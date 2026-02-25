#!/usr/bin/env bash
set -uo pipefail  # No -e to support write to canary file after cancel

. "$EXTENSION_PATH/shared.sh"

PATHS=("$@")
SINGLE_DIR_ROOT=''
if [ ${#PATHS[@]} -eq 1 ]; then
  SINGLE_DIR_ROOT=${PATHS[0]}
  PATHS=()
  cd "$SINGLE_DIR_ROOT" || exit
fi

PREFILL_QUERY=${PREFILL_QUERY:-}
SEARCH_ROOT="${SINGLE_DIR_ROOT:-.}"

# ---------- Find tags files (upward search from SEARCH_ROOT) ----------
find_tags_files() {
    local dir
    dir=$(cd "$SEARCH_ROOT" && pwd)
    local tags_files=()
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/tags" ]] && tags_files+=("$dir/tags")
        dir=$(dirname "$dir")
    done
    printf '%s\n' "${tags_files[@]}"
}

mapfile -t TAG_FILES < <(find_tags_files)

if [[ ${#TAG_FILES[@]} -eq 0 ]]; then
    echo "No tags file found. Run 'ctags -R' in your project root." >&2
    echo "1" > "$CANARY_FILE"
    exit 1
fi

# ---------- Compute total size (for fzf --algo=v1) ----------
total_size=0
for tf in "${TAG_FILES[@]}"; do
    size=$(stat -c%s "$tf" 2>/dev/null || echo 0)
    total_size=$((total_size + size))
done

fzf_extra_opts=()
[[ $total_size -gt $((200 * 1024 * 1024)) ]] && fzf_extra_opts+=(--algo=v1)

# ---------- Run fzf ----------
SELECTED=$(
    {
        for tf in "${TAG_FILES[@]}"; do
            awk -F'\t' '!/^!/ {print $1"\t"$2"\t"$3}' "$tf"
        done
    } | fzf \
        --delimiter=$'\t' \
        --nth=1,2 \
        --with-nth=1,2 \
        --tiebreak=begin \
        --prompt='Tags> ' \
        --query="$PREFILL_QUERY" \
        --history="$LAST_QUERY_FILE" \
        --preview='
            tag={1}; file={2}; loc={3}
            echo -e "\033[1;32mTag:\033[0m  $tag"
            echo -e "\033[1;34mFile:\033[0m $file"
            if [[ "$loc" =~ ^[0-9]+$ ]]; then
                echo -e "\033[1;33mLine:\033[0m $loc"
            else
                echo -ne "\033[1;33mPat:\033[0m  "
                echo "$loc" | sed -E "s:^[/?]::; s:[/?][^/?:]*$::"
            fi
        ' \
        --preview-window='up:3' \
        "${fzf_extra_opts[@]}" \
) || true

if [[ -z "$SELECTED" ]]; then
    echo canceled
    echo "1" > "$CANARY_FILE"
    exit 1
fi

# ---------- Convert location to line number (reliable) ----------
IFS=$'\t' read -r TAG FILE LOC <<< "$SELECTED"

line_number=""
if [[ "$LOC" =~ ^[0-9]+$ ]]; then
    line_number="$LOC"
else
    # Clean the ctags pattern: strip leading delimiter and trailing /;" suffix
    pattern=$(echo "$LOC" | sed -E 's:^[/?]::; s:[/?];?"?[[:space:]]*$::')

    # Resolve file path relative to its tags file's directory
    for tf in "${TAG_FILES[@]}"; do
        tags_dir=$(dirname "$tf")
        candidate="$tags_dir/$FILE"
        if [[ -f "$candidate" ]]; then
            FILE="$candidate"
            break
        fi
    done
    # Unescape ctags-escaped forward slashes
    pattern=$(echo "$pattern" | sed 's/\\\//\//g')
    if [[ "$pattern" =~ ^\^(.*)\$$ ]]; then
        inner="${BASH_REMATCH[1]}"
        line_number=$(grep -n -F -e "$inner" "$FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)
    else
        line_number=$(grep -n -F -e "$pattern" "$FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)
    fi

    # Fallback: escaped regex
    if [[ -z "$line_number" ]]; then
        escaped=$(echo "$pattern" | sed 's/[][\.|*+?(){}^$]/\\&/g')
        line_number=$(grep -n -E -e "$escaped" "$FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)
    fi
fi

if [[ -z "$line_number" || ! "$line_number" =~ ^[0-9]+$ ]]; then
    echo "Could not determine line for tag '$TAG' in $FILE" >&2
    echo "1" > "$CANARY_FILE"
    exit 1
fi

# Resolve absolute path if still relative
if [[ "$FILE" != /* ]]; then
    FILE="$(cd "$SEARCH_ROOT" && pwd)/$FILE"
fi

echo "$FILE:$line_number:1" > "$CANARY_FILE"

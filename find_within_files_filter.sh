#!/usr/bin/env bash
set -uo pipefail  # No -e to support write to canary file after cancel

# fzf.vim :Rg style — run rg once with RG_PATTERN, then fzf does client-side filtering.
# This lets you narrow results by filename, line number, or content after the initial search.

. "$EXTENSION_PATH/shared.sh"

# If we only have one directory to search, invoke commands relative to that directory
PATHS=("$@")
SINGLE_DIR_ROOT=''
if [ ${#PATHS[@]} -eq 1 ]; then
  SINGLE_DIR_ROOT=${PATHS[0]}
  PATHS=()
  cd "$SINGLE_DIR_ROOT" || exit
fi

PREVIEW_ENABLED=${FIND_WITHIN_FILES_PREVIEW_ENABLED:-1}
PREVIEW_COMMAND=${FIND_WITHIN_FILES_PREVIEW_COMMAND:-'bat --decorations=always --color=always {1} --highlight-line {2} --style=header,grid'}
PREVIEW_WINDOW=${FIND_WITHIN_FILES_PREVIEW_WINDOW_CONFIG:-'right:border-left:50%:+{2}+3/3:~3'}
LAST_QUERY_FILE=${LAST_QUERY_FILE:-'/tmp/find-it-faster-last-query'}

# Read the rg search pattern from file (written by extension's promptRgPattern)
RG_PATTERN_FILE=${RG_PATTERN_FILE:-''}
RG_PATTERN=''
if [[ -n "$RG_PATTERN_FILE" && -f "$RG_PATTERN_FILE" ]]; then
    RG_PATTERN=$(cat "$RG_PATTERN_FILE")
fi
if [[ -z "$RG_PATTERN" ]]; then
    RG_PATTERN='^(?=.)'  # match all non-empty lines
fi

# Some backwards compatibility stuff
if [[ $FZF_VER_PT1 == "0.2" && $FZF_VER_PT2 -lt 7 ]]; then
    if [[ "$PREVIEW_COMMAND" != "$FIND_WITHIN_FILES_PREVIEW_COMMAND" ]]; then
        PREVIEW_COMMAND='bat {1} --color=always --highlight-line {2} --line-range {2}:'
    fi
    if [[ "$PREVIEW_WINDOW" != "$FIND_WITHIN_FILES_PREVIEW_WINDOW_CONFIG" ]]; then
        PREVIEW_WINDOW='right:50%'
    fi
fi

PREVIEW_STR=()
if [[ "$PREVIEW_ENABLED" -eq 1 ]]; then
    PREVIEW_STR=(--preview "$PREVIEW_COMMAND" --preview-window "$PREVIEW_WINDOW")
fi

# Run rg once with the pattern, pipe to fzf for client-side filtering
IFS=: read -ra VAL < <(
  rg \
      --column \
      --hidden \
      ${USE_GITIGNORE_OPT[@]+"${USE_GITIGNORE_OPT[@]}"} \
      --line-number \
      --no-heading \
      --color=always \
      --smart-case \
      --colors 'match:fg:green' \
      --colors 'path:fg:white' \
      --colors 'path:style:nobold' \
      --glob '!**/.git/' \
      ${GLOBS[@]+"${GLOBS[@]}"} \
      ${TYPE_FILTER_ARR[@]+"${TYPE_FILTER_ARR[@]}"} \
      "$RG_PATTERN" \
      ${PATHS[@]+"${PATHS[@]}"} \
      2> /dev/null \
  | fzf \
      --ansi \
      --cycle \
      --multi \
      --delimiter : \
      --bind 'alt-a:select-all,alt-d:deselect-all' \
      --history "$LAST_QUERY_FILE" \
      --header "Rg: $RG_PATTERN (fzf filtering)" \
      ${PREVIEW_STR[@]+"${PREVIEW_STR[@]}"}
)
# Output is filename, line number, character, contents

if [[ ${#VAL[@]} -eq 0 ]]; then
    echo canceled
    echo "1" > "$CANARY_FILE"
    exit 1
else
    FILENAME=${VAL[0]}:${VAL[1]}:${VAL[2]}
    if [[ -n "$SINGLE_DIR_ROOT" ]]; then
        echo "$SINGLE_DIR_ROOT/$FILENAME" > "$CANARY_FILE"
    else
        echo "$FILENAME" > "$CANARY_FILE"
    fi
fi

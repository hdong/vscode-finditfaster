#!/bin/bash
set -uo pipefail  # No -e to support write to canary file after cancel

. "$EXTENSION_PATH/shared.sh"

PREVIEW_ENABLED=${FIND_FILES_PREVIEW_ENABLED:-1}
PREVIEW_COMMAND=${FIND_FILES_PREVIEW_COMMAND:-'bat --decorations=always --color=always --plain {}'}
PREVIEW_WINDOW=${FIND_FILES_PREVIEW_WINDOW_CONFIG:-'right:50%:border-left'}
CANARY_FILE=${CANARY_FILE:-'/tmp/canaryFile'}
BUFFERS_FILE=${BUFFERS_FILE:-''}

# Get workspace root from arguments
PATHS=("$@")
WORKSPACE_ROOT=''
if [ ${#PATHS[@]} -ge 1 ]; then
    WORKSPACE_ROOT="${PATHS[0]}"
fi

# Some backwards compatibility stuff
if [[ $FZF_VER_PT1 == "0.2" && $FZF_VER_PT2 -lt 7 ]]; then
    PREVIEW_WINDOW='right:50%'
fi

PREVIEW_STR=()
if [[ "$PREVIEW_ENABLED" -eq 1 ]]; then
    if [[ -n "$WORKSPACE_ROOT" ]]; then
        PREVIEW_STR=(--preview "bat --decorations=always --color=always --plain '$WORKSPACE_ROOT/{}'" --preview-window "$PREVIEW_WINDOW")
    else
        PREVIEW_STR=(--preview "$PREVIEW_COMMAND" --preview-window "$PREVIEW_WINDOW")
    fi
fi

if [[ -z "$BUFFERS_FILE" || ! -f "$BUFFERS_FILE" ]]; then
    echo "No buffers file found"
    echo "1" > "$CANARY_FILE"
    exit 1
fi

# Strip workspace root to show relative paths in fzf
if [[ -n "$WORKSPACE_ROOT" ]]; then
    DISPLAY_LIST=$(sed "s|^${WORKSPACE_ROOT}/||" "$BUFFERS_FILE")
else
    DISPLAY_LIST=$(cat "$BUFFERS_FILE")
fi

VAL=$(echo "$DISPLAY_LIST" \
    | fzf \
        --cycle \
        --multi \
        ${PREVIEW_STR[@]+"${PREVIEW_STR[@]}"}
)

if [[ -z "$VAL" ]]; then
    echo canceled
    echo "1" > "$CANARY_FILE"
    exit 1
else
    if [[ -n "$WORKSPACE_ROOT" ]]; then
        # Prepend workspace root back for absolute paths
        TMP=$(mktemp)
        echo "$VAL" > "$TMP"
        sed "s|^|$WORKSPACE_ROOT/|" "$TMP" > "$CANARY_FILE"
        rm "$TMP"
    else
        echo "$VAL" > "$CANARY_FILE"
    fi
fi

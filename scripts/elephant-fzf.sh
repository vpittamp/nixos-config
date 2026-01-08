#!/usr/bin/env bash
# FZF-based clipboard history selector for Elephant
# Replaces clipcat-fzf.sh - uses Elephant's clipboard provider instead of clipcat daemon
#
# Usage:
#   elephant-fzf.sh              # Interactive FZF selection
#   elephant-fzf.sh preview ID   # Preview a specific clipboard entry
#
# Features:
#   - Enter: Copy to clipboard and paste into tmux (if in tmux)
#   - Ctrl-Y: Copy to clipboard only (no paste)
#   - Ctrl-P: Toggle preview
#   - Ctrl-D: Delete entry (not yet implemented - Elephant API limitation)

set -uo pipefail

MAX_ITEMS=${ELEPHANT_FZF_MAX_ITEMS:-100}

# Generate list of clipboard entries for FZF
# Format: ID<tab>[timestamp] preview_text
generate_entries() {
  elephant query "clipboard;;${MAX_ITEMS};false" --json 2>/dev/null | \
    jq -r 'select(.item) |
      "\(.item.identifier)\t[\(.item.subtext | split(",")[1] // .item.subtext | ltrimstr(" "))] \(.item.text | gsub("\n"; " \u22ef") | gsub("\t"; " ") | .[0:100])"'
}

# Render full preview for a clipboard entry
render_preview() {
  local clip_id="$1"

  if [[ -z "$clip_id" ]]; then
    printf 'No clip selected\n'
    return
  fi

  local content
  content=$(elephant query "clipboard;;${MAX_ITEMS};false" --json 2>/dev/null | \
    jq -r --arg id "$clip_id" 'select(.item.identifier == $id) | .item.text')

  if [[ -z "$content" ]]; then
    printf 'Unable to load clip %s\n' "$clip_id"
    return
  fi

  # Get metadata
  local timestamp
  timestamp=$(elephant query "clipboard;;${MAX_ITEMS};false" --json 2>/dev/null | \
    jq -r --arg id "$clip_id" 'select(.item.identifier == $id) | .item.subtext')

  local bytes lines
  bytes=$(printf '%s' "$content" | wc -c | awk '{print $1}')
  lines=$(printf '%s' "$content" | wc -l)

  printf '\033[1mID:\033[0m %s\n' "$clip_id"
  printf '\033[1mTimestamp:\033[0m %s\n' "$timestamp"
  printf '\033[1mSize:\033[0m %s bytes, %s lines\n\n' "$bytes" "$lines"

  # Use bat for syntax highlighting if available
  if command -v bat >/dev/null 2>&1; then
    printf '%s' "$content" | bat --paging=never --style=plain --color=always --wrap=never --file-name "clipboard.txt" -
  else
    printf '%s\n' "$content"
  fi
}

# Handle subcommands
case "${1:-}" in
  preview)
    render_preview "${2:-}"
    exit 0
    ;;
  list)
    generate_entries
    exit 0
    ;;
esac

# Resolve script path for preview callback
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH=$(realpath "$0")
elif command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH=$(readlink -f "$0")
else
  SCRIPT_PATH="$0"
fi

printf -v PREVIEW_CMD '%q preview %s' "$SCRIPT_PATH" '{1}'

HEADER_MESSAGE=$'Enter\u2192paste | Ctrl-Y copy only | Ctrl-P toggle preview'

# Run FZF with clipboard entries
selected=$(generate_entries | fzf \
  --tmux=center,90%,80% \
  --ansi \
  --no-sort \
  --layout=reverse \
  --border=rounded \
  --border-label=' Elephant Clipboard ' \
  --info=inline \
  --delimiter=$'\t' \
  --with-nth=2 \
  --header="$HEADER_MESSAGE" \
  --prompt='Clipboard > ' \
  --preview="$PREVIEW_CMD" \
  --preview-label=' Clipboard entry ' \
  --preview-window=right,60%,border-top,wrap \
  --bind 'ctrl-p:toggle-preview' \
  --bind 'ctrl-y:execute-silent(elephant query "clipboard;;'"${MAX_ITEMS}"';false" --json 2>/dev/null | jq -r --arg id {1} '\''select(.item.identifier == $id) | .item.text'\'' | wl-copy)+abort' \
  --bind 'shift-up:preview-up,shift-down:preview-down' \
  --bind 'alt-up:preview-up,alt-down:preview-down' \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8) || exit 0

# If user selected something (Enter key), copy and paste
if [ -n "${selected:-}" ]; then
  clip_id=${selected%%$'\t'*}

  # Get the full text content
  text=$(elephant query "clipboard;;${MAX_ITEMS};false" --json 2>/dev/null | \
    jq -r --arg id "$clip_id" 'select(.item.identifier == $id) | .item.text')

  if [[ -z "$text" ]]; then
    exit 1
  fi

  # Copy to system clipboard via wl-copy
  printf '%s' "$text" | wl-copy

  # Paste into tmux if we're inside tmux
  if [ -n "${TMUX:-}" ]; then
    # Use send-keys -l for literal text input
    tmux send-keys -l "$text" >/dev/null 2>&1
  fi
fi

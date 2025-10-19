#!/usr/bin/env bash
# FZF-based clipboard history selector for clipcat
# Provides terminal-based clipboard history with immediate paste

# Don't exit on error - we want to handle cancellation gracefully
set -uo pipefail

# Get clipboard history and let user select
# Format: Show first 100 chars of text, keep ID in hidden column for actions
selected=$(clipcatctl list | awk -F': ' '{
  id = $1;
  $1 = "";
  text = substr($0, 2);  # Remove leading space
  # Truncate to 100 chars for list view
  if (length(text) > 100) {
    display = substr(text, 1, 100) "...";
  } else {
    display = text;
  }
  printf "%s\t%s\n", id, display;
}' | fzf \
  --tmux=center,90%,80% \
  --ansi \
  --no-sort \
  --layout=reverse \
  --border=rounded \
  --info=inline \
  --delimiter='\t' \
  --with-nth=2 \
  --header="Clipboard History - Enter to paste, Ctrl-D to delete, ESC to cancel" \
  --prompt="Search: " \
  --preview="clipcatctl get {1}" \
  --preview-window=right:50%:wrap \
  --bind="ctrl-d:execute-silent(clipcatctl remove {1})+reload(clipcatctl list | awk -F': ' '{id = \$1; \$1 = \"\"; text = substr(\$0, 2); if (length(text) > 100) {display = substr(text, 1, 100) \"...\";} else {display = text;} printf \"%s\\t%s\\n\", id, display;}')" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8) || exit 0

# If user selected something, promote to clipboard and paste it
if [ -n "${selected:-}" ]; then
  clip_id=$(echo "$selected" | cut -f1)

  # Promote to top of clipboard history (makes it the current clipboard item)
  clipcatctl promote "$clip_id"

  # Get the actual text content
  text=$(clipcatctl get "$clip_id")

  # Determine if we're in tmux and paste appropriately
  if [ -n "${TMUX:-}" ]; then
    # In tmux: send the text directly to the pane
    # Use tmux's send-keys with -l flag to send literal text
    # Redirect all output to suppress tmux's "ok" message
    tmux send-keys -l "$text" >/dev/null 2>&1
  else
    # Not in tmux: try xdotool to type the text
    if command -v xdotool &>/dev/null; then
      # Small delay to ensure focus is back on the original window
      sleep 0.1
      xdotool type --clearmodifiers -- "$text"
    else
      # Fallback: just put it in clipboard (already done by promote)
      # Suppress output to avoid "ok" message in tmux
      : # no-op
    fi
  fi
fi >/dev/null 2>&1

#!/usr/bin/env bash
# FZF-based clipboard history selector for clipcat
# Provides terminal-based clipboard history with tmux popup support

set -euo pipefail

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
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8)

# If user selected something, insert it into clipboard
if [ -n "$selected" ]; then
  clip_id=$(echo "$selected" | cut -f1)
  clipcatctl promote "$clip_id"
fi

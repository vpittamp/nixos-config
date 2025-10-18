#!/usr/bin/env bash
# FZF-based clipboard history selector for clipcat
# Provides terminal-based clipboard history with tmux popup support

set -euo pipefail

# Get clipboard history and let user select
selected=$(clipcatctl list | fzf \
  --tmux=center,90%,80% \
  --ansi \
  --no-sort \
  --layout=reverse \
  --border=rounded \
  --info=inline \
  --header="Clipboard History - Enter to insert, Ctrl-D to remove, ESC to cancel" \
  --prompt="Search: " \
  --preview="clipcatctl get {1}" \
  --preview-window=up:5:wrap \
  --bind="ctrl-d:execute-silent(clipcatctl remove {1})+reload(clipcatctl list)" \
  --bind="ctrl-y:execute-silent(clipcatctl promote {1})" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8)

# If user selected something, insert it into clipboard
if [ -n "$selected" ]; then
  clip_id=$(echo "$selected" | awk '{print $1}' | tr -d ':')
  clipcatctl promote "$clip_id"
fi

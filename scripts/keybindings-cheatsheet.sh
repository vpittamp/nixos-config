#!/usr/bin/env bash
# FZF Keybinding Cheatsheet
# Shows all keybindings from i3, tmux, bash, and other tools in a searchable fzf popup

set -euo pipefail

# Temporary file for keybindings
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# Color codes for categories
I3_COLOR="[I3]"
TMUX_COLOR="[TMUX]"
BASH_COLOR="[BASH]"
FZF_COLOR="[FZF]"

echo "# Keybinding Cheatsheet - Use arrow keys to navigate, / to search, ESC to exit" > "$TMPFILE"
echo "" >> "$TMPFILE"

# ============================================================================
# I3 WINDOW MANAGER KEYBINDINGS
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
echo "I3 WINDOW MANAGER" >> "$TMPFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"

if [ -f "$HOME/.config/i3/config" ]; then
  grep "^bindsym\|^bindcode" "$HOME/.config/i3/config" | \
    sed 's/bindsym //' | \
    sed 's/bindcode //' | \
    awk '{
      # Extract key binding and command
      key = $1;
      $1 = "";
      cmd = $0;
      gsub(/^[ \t]+/, "", cmd);  # Trim leading whitespace
      
      # Shorten common patterns
      gsub(/\/nix\/store\/[^/]*\/bin\//, "", cmd);
      gsub(/exec --no-startup-id /, "", cmd);
      gsub(/exec /, "", cmd);
      
      # Format: key -> description
      printf "%-25s %s\n", key, cmd;
    }' | sort >> "$TMPFILE"
fi

echo "" >> "$TMPFILE"

# ============================================================================
# TMUX KEYBINDINGS
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
echo "TMUX (Prefix = Ctrl+Space)" >> "$TMPFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"

if [ -f "$HOME/.config/tmux/tmux.conf" ]; then
  grep "^bind" "$HOME/.config/tmux/tmux.conf" | \
    sed 's/bind-key //' | \
    sed 's/bind //' | \
    awk '{
      flags = "";
      key = "";
      cmd = "";
      
      # Parse flags
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^-/) {
          flags = flags " " $i;
        } else if (key == "") {
          key = $i;
        } else {
          cmd = cmd " " $i;
        }
      }
      
      # Format the key
      if (flags ~ /-n/) {
        # No prefix needed
        formatted_key = key;
      } else {
        formatted_key = "Prefix " key;
      }
      
      # Clean up command
      gsub(/^[ \t]+/, "", cmd);
      
      printf "%-25s %s\n", formatted_key, cmd;
    }' | sort >> "$TMPFILE"
fi

echo "" >> "$TMPFILE"

# ============================================================================
# BASH/FZF KEYBINDINGS
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
echo "BASH / FZF / SHELL" >> "$TMPFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"

cat >> "$TMPFILE" << 'BINDINGS'
Ctrl+P                    FZF file search with preview
Alt+C                     FZF directory navigation
Ctrl+R                    FZF command history search
Ctrl+L                    Clear screen
Ctrl+C                    Cancel current command
Ctrl+D                    Exit shell / EOF
Ctrl+Z                    Suspend current process
Ctrl+A                    Move to beginning of line
Ctrl+E                    Move to end of line
Ctrl+K                    Delete from cursor to end of line
Ctrl+U                    Delete from cursor to beginning of line
Ctrl+W                    Delete word before cursor
Alt+B                     Move backward one word
Alt+F                     Move forward one word
Ctrl+T                    Transpose characters
BINDINGS

echo "" >> "$TMPFILE"

# ============================================================================
# CLIPCAT (CLIPBOARD MANAGER)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
echo "CLIPCAT (Clipboard Manager)" >> "$TMPFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"

cat >> "$TMPFILE" << 'CLIPCAT'
Mod4+v                    Show clipboard history
Mod4+Shift+v              Clear clipboard history
CLIPCAT

echo "" >> "$TMPFILE"

# ============================================================================
# SCREENSHOTS (SPECTACLE)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
echo "SCREENSHOTS (Spectacle)" >> "$TMPFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"

cat >> "$TMPFILE" << 'SCREENSHOTS'
Print                     Fullscreen screenshot to clipboard
Mod4+Print                Active window screenshot to clipboard
Mod4+Shift+s              Region screenshot to clipboard
SCREENSHOTS

echo "" >> "$TMPFILE"

# ============================================================================
# Display with FZF
# ============================================================================
cat "$TMPFILE" | fzf \
  --tmux=center,90%,80% \
  --ansi \
  --no-sort \
  --layout=reverse \
  --border=rounded \
  --info=inline \
  --header="Keybinding Cheatsheet - Press ESC to close" \
  --prompt="Search: " \
  --preview-window=hidden \
  --bind='ctrl-/:toggle-preview' \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8

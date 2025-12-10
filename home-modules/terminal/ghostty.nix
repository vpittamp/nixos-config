# Ghostty Terminal Emulator Configuration
# Modern GPU-accelerated terminal with native tabs and splits
{ config, lib, pkgs, ... }:

let
  # Tmux file path scanner using fzf (urlscan has PTY permission issues)
  # File-focused: Only shows valid file paths that exist, discards URLs
  tmux-url-scan = pkgs.writeShellScriptBin "tmux-url-scan" ''
    set -euo pipefail

    # Use a fixed temp file name
    TEMPFILE="/tmp/tmux-buffer-scan.txt"

    # Extract file paths from tmux buffer
    # Pattern matches: absolute paths, home paths, relative paths
    # Excludes: URLs (http/https), incomplete paths (just ~ or . or ..)
    # Preserves terminal order (most recent last), removes duplicates with uniq
    VALID_FILES=$(cat "$TEMPFILE" 2>/dev/null | \
      grep -oE '([~/][^[:space:]]+|\.{1,2}/[^[:space:]]+)' | \
      grep -v '^[~./]*$' | \
      grep -v '^https?://' | \
      awk '!seen[$0]++' | \
      while IFS= read -r item; do
        # Expand and validate file paths
        TARGET="$item"

        # Expand tilde
        if [[ "$TARGET" == ~* ]]; then
          TARGET="''${TARGET/#\~/$HOME}"
        fi

        # Make relative paths absolute
        if [[ ! "$TARGET" =~ ^/ ]]; then
          TARGET="$(pwd)/$TARGET"
        fi

        # Only include if file/directory exists
        if [[ -e "$TARGET" ]]; then
          echo "$item"
        fi
      done)

    # Check if we found any valid files
    if [[ -z "$VALID_FILES" ]]; then
      echo "No valid file paths found in scrollback"
      echo ""
      echo "Tip: This tool only shows files that exist on the filesystem."
      sleep 2
      exit 0
    fi

    # Use fzf with multi-select and reload capability
    # Tab=select, Enter=confirm, Ctrl-R=refresh file list
    # Full-screen layout with bat preview (matches fzf-file-search.nix UI)
    mapfile -t SELECTED < <(echo "$VALID_FILES" | \
      ${pkgs.fzf}/bin/fzf \
        --multi \
        --prompt='Open files (Tab=select, Enter=confirm, Ctrl-R=refresh): ' \
        --height=100% \
        --layout=reverse \
        --border=rounded \
        --info=inline \
        --bind='ctrl-r:reload(cat "$TEMPFILE" 2>/dev/null | grep -oE "([~/][^[:space:]]+|\.{1,2}/[^[:space:]]+)" | grep -v "^[~./]*$" | grep -v "^https?://" | awk "!seen[\$0]++" | while IFS= read -r item; do TARGET="$item"; if [[ "$TARGET" == ~* ]]; then TARGET="''${TARGET/#\~/$HOME}"; fi; if [[ ! "$TARGET" =~ ^/ ]]; then TARGET="$(pwd)/$TARGET"; fi; if [[ -e "$TARGET" ]]; then echo "$item"; fi; done)' \
        --header='Ctrl-R: Refresh list from scrollback' \
        --preview='if [[ -f {} ]]; then ${pkgs.bat}/bin/bat --color=always --style=numbers,changes {} 2>/dev/null || cat {}; elif [[ -d {} ]]; then echo "Directory: {}"; echo ""; ls -lah {}; else echo "Path: {}"; echo ""; echo "File not found"; fi' \
        --preview-window=right:60%:wrap || true)

    # Cleanup
    rm -f "$TEMPFILE"

    # Process selected files
    if [ ''${#SELECTED[@]} -gt 0 ]; then
      FILES=()

      for item in "''${SELECTED[@]}"; do
        # Expand ~ and resolve relative paths
        if [[ "$item" == ~* ]]; then
          item="''${item/#\~/$HOME}"
        fi

        # If it's a relative path, make it absolute
        if [[ ! "$item" =~ ^/ ]]; then
          item="$(pwd)/$item"
        fi

        # Normalize path
        item=$(${pkgs.coreutils}/bin/realpath -m "$item" 2>/dev/null || echo "$item")
        FILES+=("$item")
      done

      # Open files in single nvim instance (all files as buffers)
      if [ ''${#FILES[@]} -gt 0 ]; then
        # Build space-separated quoted file list for nvim
        FILE_ARGS=""
        for file in "''${FILES[@]}"; do
          FILE_ARGS="$FILE_ARGS \"$file\""
        done

        # Launch via Sway exec on workspace 4 with all files
        # Nvim will open all files as buffers (use :bn/:bp to navigate)
        ${pkgs.sway}/bin/swaymsg exec "env I3PM_APP_ID=nvim-editor-$$-$(date +%s) I3PM_APP_NAME=nvim I3PM_PROJECT_NAME=\''${I3PM_PROJECT_NAME:-} I3PM_PROJECT_DIR=\''${I3PM_PROJECT_DIR:-} I3PM_SCOPE=scoped I3PM_TARGET_WORKSPACE=4 I3PM_EXPECTED_CLASS=com.mitchellh.ghostty ${pkgs.ghostty}/bin/ghostty -e ${pkgs.neovim}/bin/nvim $FILE_ARGS" > /dev/null 2>&1
      fi
    fi
  '';

  # Tmux URL opener using fzf - extracts and opens URLs from scrollback
  # Complementary to tmux-url-scan (file paths), this extracts http/https URLs
  tmux-url-open = pkgs.writeShellScriptBin "tmux-url-open" ''
    set -euo pipefail

    # Use a fixed temp file name
    TEMPFILE="/tmp/tmux-url-buffer.txt"

    # Extract URLs from tmux buffer
    # Pattern matches: http:// and https:// URLs
    # Preserves terminal order (most recent last), removes duplicates
    # Note: Using simpler pattern to avoid escaping issues in Nix
    URLS=$(cat "$TEMPFILE" 2>/dev/null | \
      grep -oE 'https?://[^[:space:]"<>]+' | \
      sed -E 's/[.,;:!?)]+$//' | \
      sed -E 's/\]$//' | \
      awk '!seen[$0]++')

    # Check if we found any URLs
    if [[ -z "$URLS" ]]; then
      echo "No URLs found in scrollback"
      echo ""
      echo "Tip: This tool extracts http:// and https:// URLs."
      echo "For file paths, use prefix + u instead."
      sleep 2
      exit 0
    fi

    # Use fzf with multi-select
    # Tab=select, Enter=confirm
    # Full-screen layout with URL preview
    mapfile -t SELECTED < <(echo "$URLS" | \
      ${pkgs.fzf}/bin/fzf \
        --multi \
        --prompt='Open URLs (Tab=select, Enter=confirm): ' \
        --height=100% \
        --layout=reverse \
        --border=rounded \
        --info=inline \
        --header='Select URLs to open in browser/PWA' \
        --preview='echo "URL: {}"; echo ""; echo "Domain: $(echo {} | sed -E "s|https?://([^/]+).*|\1|")"; echo ""; if command -v pwa-route-test &>/dev/null; then pwa-route-test "{}" 2>/dev/null || echo "Will open in Firefox"; fi' \
        --preview-window=right:50%:wrap || true)

    # Cleanup
    rm -f "$TEMPFILE"

    # Open selected URLs
    if [ ''${#SELECTED[@]} -gt 0 ]; then
      for url in "''${SELECTED[@]}"; do
        # Use swaymsg exec to launch in detached context (survives popup close)
        # Feature 113: Explicitly call pwa-url-router for PWA domain routing
        # (pwa-url-router is NOT the default URL handler to avoid session restore loops)
        ${pkgs.sway}/bin/swaymsg exec "pwa-url-router '$url'" > /dev/null 2>&1
        sleep 0.3  # Small delay between opens to prevent overwhelming
      done
    fi
  '';

  # Smart opener for Ghostty - handles relative paths, ~, URLs
  ghostty-smart-open = pkgs.writeShellScriptBin "ghostty-smart-open" ''
    set -euo pipefail

    TARGET="''${1:-}"

    # If no argument, read from clipboard (for keybinding use)
    if [[ -z "$TARGET" ]]; then
      TARGET=$(${pkgs.wl-clipboard}/bin/wl-paste)
    fi

    # Get the current working directory from Ghostty via OSC 7
    # Ghostty sets PWD in the environment via shell integration
    CWD="''${PWD:-$HOME}"

    # Expand tilde to HOME
    if [[ "$TARGET" == ~* ]]; then
      TARGET="''${TARGET/#\~/$HOME}"
    fi

    # If it looks like a URL, open with xdg-open (browser/PWA)
    if [[ "$TARGET" =~ ^https?:// ]] || [[ "$TARGET" =~ ^www\. ]]; then
      ${pkgs.xdg-utils}/bin/xdg-open "$TARGET" &
      exit 0
    fi

    # If it's a relative path, make it absolute using CWD
    if [[ ! "$TARGET" =~ ^/ ]]; then
      TARGET="$CWD/$TARGET"
    fi

    # Normalize path (remove .., ., etc)
    TARGET=$(${pkgs.coreutils}/bin/realpath -m "$TARGET" 2>/dev/null || echo "$TARGET")

    # If file exists, open in Neovim via Sway exec on workspace 4
    # This follows the pattern from fzf-file-search.nix for reliable window creation
    if [[ -e "$TARGET" ]]; then
      ${pkgs.sway}/bin/swaymsg exec "env I3PM_APP_ID=nvim-editor-$$-$(date +%s) I3PM_APP_NAME=nvim I3PM_PROJECT_NAME=\''${I3PM_PROJECT_NAME:-} I3PM_PROJECT_DIR=\''${I3PM_PROJECT_DIR:-} I3PM_SCOPE=scoped I3PM_TARGET_WORKSPACE=4 I3PM_EXPECTED_CLASS=com.mitchellh.ghostty ${pkgs.ghostty}/bin/ghostty -e ${pkgs.neovim}/bin/nvim \"$TARGET\"" > /dev/null 2>&1
    else
      # File doesn't exist, try xdg-open as fallback
      ${pkgs.xdg-utils}/bin/xdg-open "$TARGET" &
    fi
  '';
in
{
  imports = [ ./terminal-defaults.nix ];

  programs.ghostty = {
    enable = true;

    settings = {
      # Font configuration - using centralized terminal defaults
      font-family = config.terminal.defaults.font.family;
      font-size = config.terminal.defaults.font.size;

      # Theme - Catppuccin Mocha colors (using centralized defaults)
      background = config.terminal.defaults.colors.background;
      foreground = config.terminal.defaults.colors.foreground;

      # Window configuration - using centralized defaults
      window-padding-x = config.terminal.defaults.padding.x;
      window-padding-y = config.terminal.defaults.padding.y;

      # Clipboard
      clipboard-read = "allow";
      clipboard-write = "allow";

      # Mouse
      mouse-hide-while-typing = true;

      # Scroll sensitivity - reduce for more precise scrolling
      # Default multiplier is 1.0, reduce to 0.3 for finer control
      mouse-scroll-multiplier = 0.3;

      # Shell integration (Ghostty's killer feature)
      shell-integration = "detect";

      # Cursor
      cursor-style = "block";

      # Terminal type
      term = "xterm-256color";

      # Auto-update (disable on NixOS)
      auto-update = "off";

      # Window close behavior - don't prompt when closing
      confirm-close-surface = false;

      # Allow multiple independent instances (required for i3-projects)
      # "never" = each instance is independent (needed for multiple workspaces)
      # "single-instance" = reuses existing process (default)
      # "always" = uses cgroups for isolation
      linux-cgroup = "never";

      # Make Shift+Enter send a newline (Claude CLI expects this)
      keybind = "shift+enter=text:\\x1b\\r";
    };
  };

  # Install the smart opener script and URL/path scanners
  home.packages = with pkgs; [
    ghostty-smart-open
    tmux-url-scan   # FZF-based file path scanner for tmux (prefix + u)
    tmux-url-open   # FZF-based URL opener for tmux (prefix + o)
  ];

  # Configure urlscan to use our smart opener
  xdg.configFile."urlscan/config.json".text = builtins.toJSON {
    browser = "${pkgs.xdg-utils}/bin/xdg-open";
    palettes = {
      default = [
        ["gentext" "default" "default" ""]
        ["msgtext" "default" "default" ""]
        ["msgtext:ellipses" "light gray" "default" ""]
        ["urlref:number:braces" "light gray" "default" ""]
        ["urlref:number" "yellow" "default" "standout"]
        ["urlref:url" "white,underline" "default" "standout"]
        ["url:sel" "white" "dark blue" "bold"]
      ];
    };
  };

  # Make Ghostty the default terminal globally
  home.sessionVariables = {
    TERMINAL = "ghostty";
    TERM_PROGRAM = "ghostty";
  };

  # Set Ghostty as the default terminal emulator in XDG MIME types
  # This ensures all applications that need to launch a terminal use Ghostty
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/terminal" = "ghostty.desktop";
      "application/x-terminal-emulator" = "ghostty.desktop";
    };
  };
}

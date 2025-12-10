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

  # Tmux URL opener using fzf - extracts HTTP/HTTPS URLs and routes through PWA router
  # Feature 113: URLs matching PWA domains open in PWAs, others open in Firefox
  tmux-url-open = pkgs.writeShellScriptBin "tmux-url-open" ''
    set -euo pipefail

    # Use a fixed temp file name (shared with tmux-url-scan)
    TEMPFILE="/tmp/tmux-buffer-scan.txt"
    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"

    # Extract HTTP/HTTPS URLs from tmux buffer
    # Pattern matches: http:// and https:// URLs
    # Preserves terminal order (most recent last), removes duplicates
    URLS=$(cat "$TEMPFILE" 2>/dev/null | \
      grep -oE 'https?://[^[:space:]<>"]+' | \
      sed 's/[.,;:!?\)\]]*$//' | \
      grep -v '^https\?://,$' | \
      awk '!seen[$0]++')

    # Check if we found any URLs
    if [[ -z "$URLS" ]]; then
      echo "No URLs found in scrollback"
      echo ""
      echo "Tip: This tool extracts HTTP/HTTPS URLs from terminal output."
      sleep 2
      exit 0
    fi

    # Function to check if domain has a PWA
    check_pwa() {
      local url="$1"
      local domain
      domain=$(echo "$url" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|/.*||' | ${pkgs.gnused}/bin/sed -E 's|:.*||')

      if [[ -f "$DOMAIN_REGISTRY" ]]; then
        local pwa_info
        pwa_info=$(${pkgs.jq}/bin/jq -r --arg d "$domain" '.[$d].name // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")
        if [[ -n "$pwa_info" ]]; then
          echo "🌐 $pwa_info"
        else
          echo "🦊 Firefox"
        fi
      else
        echo "🦊 Firefox"
      fi
    }

    # Build display list with PWA indicators
    DISPLAY_LIST=""
    while IFS= read -r url; do
      pwa_status=$(check_pwa "$url")
      DISPLAY_LIST="$DISPLAY_LIST$pwa_status | $url"$'\n'
    done <<< "$URLS"

    # Use fzf with multi-select
    # Tab=select, Enter=confirm
    # Full-screen layout with URL preview
    SELECTED=$(echo -n "$DISPLAY_LIST" | \
      ${pkgs.fzf}/bin/fzf \
        --multi \
        --prompt='Open URLs (Tab=select, Enter=confirm): ' \
        --height=100% \
        --layout=reverse \
        --border=rounded \
        --info=inline \
        --header='🌐 = Opens in PWA | 🦊 = Opens in Firefox' \
        --preview='url=$(echo {} | ${pkgs.gnused}/bin/sed "s/^[^|]*| //"); echo "URL: $url"; echo ""; domain=$(echo "$url" | ${pkgs.gnused}/bin/sed -E "s|^https?://||" | ${pkgs.gnused}/bin/sed -E "s|/.*||"); echo "Domain: $domain"; echo ""; if [[ -f "'"$DOMAIN_REGISTRY"'" ]]; then pwa=$(${pkgs.jq}/bin/jq -r --arg d "$domain" ".[\$d] // empty" "'"$DOMAIN_REGISTRY"'" 2>/dev/null); if [[ -n "$pwa" && "$pwa" != "null" ]]; then echo "PWA Match:"; echo "$pwa" | ${pkgs.jq}/bin/jq .; else echo "No PWA match - will open in Firefox"; fi; fi' \
        --preview-window=right:40%:wrap || true)

    # Cleanup
    rm -f "$TEMPFILE"

    # Process selected URLs
    if [[ -n "$SELECTED" ]]; then
      while IFS= read -r line; do
        # Extract URL from display format "🌐 PWA | https://..."
        url=$(echo "$line" | ${pkgs.gnused}/bin/sed 's/^[^|]*| //')

        if [[ -n "$url" ]]; then
          # Route through pwa-url-router (opens in PWA or Firefox)
          # Use setsid to detach from terminal so process survives popup close
          if command -v pwa-url-router >/dev/null 2>&1; then
            ${pkgs.util-linux}/bin/setsid pwa-url-router "$url" </dev/null >/dev/null 2>&1 &
          else
            # Fallback to xdg-open
            ${pkgs.util-linux}/bin/setsid ${pkgs.xdg-utils}/bin/xdg-open "$url" </dev/null >/dev/null 2>&1 &
          fi
        fi
      done <<< "$SELECTED"
      # Small delay to ensure processes are spawned before popup closes
      sleep 0.2
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

  # Install the smart opener script and URL scanners
  home.packages = with pkgs; [
    ghostty-smart-open
    tmux-url-scan  # FZF-based file path scanner for tmux (prefix + u)
    tmux-url-open  # FZF-based URL opener with PWA routing (prefix + o) - Feature 113
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

{ config, lib, pkgs, inputs, osConfig ? null, ... }:

let
  cfg = config.programs.walker;

  # Detect Wayland mode - if Sway is enabled, we're in Wayland mode
  isWaylandMode = config.wayland.windowManager.sway.enable or false;

  walkerOpenInNvim = pkgs.writeShellScriptBin "walker-open-in-nvim" ''
    #!/usr/bin/env bash
    # Launch an Alacritty terminal window with Neovim for a Walker-selected file path
    set -euo pipefail

    if [ $# -eq 0 ]; then
      echo "walker-open-in-nvim: missing file argument" >&2
      exit 1
    fi

    RAW_PATH="$1"

    decode_output="$(${pkgs.python3}/bin/python3 - <<'PY' "$RAW_PATH"
import sys
from urllib.parse import urlsplit, unquote

value = sys.argv[1]

if value.startswith("file://"):
    parsed = urlsplit(value)
    netloc = parsed.netloc
    path = parsed.path or ""
    if netloc and netloc not in ("", "localhost"):
        fs_path = f"/{netloc}{path}"
    else:
        fs_path = path
    fragment = parsed.fragment or ""
else:
    fs_path = value
    fragment = ""

print(unquote(fs_path))
print(fragment)
PY
    )"

    IFS=$'\n' read -r TARGET_PATH TARGET_FRAGMENT <<< "$decode_output"

    if [ -z "$TARGET_PATH" ]; then
      echo "walker-open-in-nvim: unable to parse path from '$RAW_PATH'" >&2
      exit 1
    fi

    case "$TARGET_PATH" in
      "~")
        TARGET_PATH="$HOME"
        ;;
      "~/"*)
        TARGET_PATH="$HOME/''${TARGET_PATH:2}"
        ;;
    esac

    if [[ "$TARGET_PATH" != /* ]]; then
      TARGET_PATH="$PWD/$TARGET_PATH"
    fi

    LINE_ARG=""
    if [ -n "$TARGET_FRAGMENT" ]; then
      if [[ "$TARGET_FRAGMENT" =~ ^L?([0-9]+)$ ]]; then
        LINE_ARG="+''${BASH_REMATCH[1]}"
      fi
    fi

    # Query i3pm daemon for project context (integrates with project management)
    PROJECT_JSON=$(i3pm project current --json 2>/dev/null || echo '{}')
    PROJECT_NAME=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.name // ""')
    PROJECT_DIR=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.directory // ""')
    PROJECT_DISPLAY_NAME=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.display_name // ""')
    PROJECT_ICON=$(echo "$PROJECT_JSON" | ${pkgs.jq}/bin/jq -r '.icon // ""')

    # Generate app instance ID (like app-launcher-wrapper does)
    TIMESTAMP=$(date +%s)
    APP_INSTANCE_ID="nvim-''${PROJECT_NAME:-global}-$$-$TIMESTAMP"

    # Export I3PM environment variables for window-to-project association
    export I3PM_APP_ID="$APP_INSTANCE_ID"
    export I3PM_APP_NAME="nvim"
    export I3PM_PROJECT_NAME="''${PROJECT_NAME:-}"
    export I3PM_PROJECT_DIR="''${PROJECT_DIR:-}"
    export I3PM_PROJECT_DISPLAY_NAME="''${PROJECT_DISPLAY_NAME:-}"
    export I3PM_PROJECT_ICON="''${PROJECT_ICON:-}"
    export I3PM_SCOPE="scoped"
    export I3PM_ACTIVE=$(if [[ -n "$PROJECT_NAME" ]]; then echo "true"; else echo "false"; fi)
    export I3PM_LAUNCH_TIME="$(date +%s)"
    export I3PM_LAUNCHER_PID="$$"

    # Build nvim command with line number if present
    if [ -n "$LINE_ARG" ]; then
      NVIM_CMD="${pkgs.neovim-unwrapped}/bin/nvim $LINE_ARG '$TARGET_PATH'"
    else
      NVIM_CMD="${pkgs.neovim-unwrapped}/bin/nvim '$TARGET_PATH'"
    fi

    # Use systemd-run for proper process isolation (like app-launcher-wrapper)
    if command -v systemd-run &>/dev/null; then
      exec systemd-run --user --scope \
        --setenv=I3PM_APP_ID="$I3PM_APP_ID" \
        --setenv=I3PM_APP_NAME="$I3PM_APP_NAME" \
        --setenv=I3PM_PROJECT_NAME="$I3PM_PROJECT_NAME" \
        --setenv=I3PM_PROJECT_DIR="$I3PM_PROJECT_DIR" \
        --setenv=I3PM_PROJECT_DISPLAY_NAME="$I3PM_PROJECT_DISPLAY_NAME" \
        --setenv=I3PM_PROJECT_ICON="$I3PM_PROJECT_ICON" \
        --setenv=I3PM_SCOPE="$I3PM_SCOPE" \
        --setenv=I3PM_ACTIVE="$I3PM_ACTIVE" \
        --setenv=I3PM_LAUNCH_TIME="$I3PM_LAUNCH_TIME" \
        --setenv=I3PM_LAUNCHER_PID="$I3PM_LAUNCHER_PID" \
        --setenv=DISPLAY="''${DISPLAY:-:0}" \
        --setenv=HOME="$HOME" \
        --setenv=PATH="$PATH" \
        ${pkgs.alacritty}/bin/alacritty -e bash -c "$NVIM_CMD"
    else
      # Fallback without systemd-run
      exec ${pkgs.alacritty}/bin/alacritty -e bash -c "$NVIM_CMD"
    fi
  '';

  walkerOpenInNvimCmd = lib.getExe walkerOpenInNvim;

  # Walker project list script - outputs formatted project list for Walker menu
  # Reordered to show inactive projects first, active project last with visual indicator
  # Fixed: Use .active.project_name instead of .active.name to match i3pm JSON structure
  walkerProjectList = pkgs.writeShellScriptBin "walker-project-list" ''
    #!/usr/bin/env bash
    # List projects for Walker menu
    set -euo pipefail

    I3PM="${config.home.profileDirectory}/bin/i3pm"

    # Get projects JSON
    PROJECTS_JSON=$($I3PM project list --json 2>/dev/null || echo '{"projects":[]}')

    # Check if we have projects
    PROJECT_COUNT=$(echo "$PROJECTS_JSON" | ${pkgs.jq}/bin/jq '.projects | length')
    if [ "$PROJECT_COUNT" = "0" ]; then
      exit 0
    fi

    # Get current active project name
    ACTIVE_PROJECT=$(echo "$PROJECTS_JSON" | ${pkgs.jq}/bin/jq -r '.active.project_name // ""')

    # Add "Clear Project" option if a project is active
    if [ -n "$ACTIVE_PROJECT" ] && [ "$ACTIVE_PROJECT" != "null" ]; then
      echo "∅ Clear Project (Global Mode)	__CLEAR__"
    fi

    # Output INACTIVE projects first (default selection will be first inactive project)
    echo "$PROJECTS_JSON" | ${pkgs.jq}/bin/jq -r '.projects[] | select(.name != "'"$ACTIVE_PROJECT"'") |
      ((.icon // "📁") + " " + (.display_name // .name) +
       (if .directory then " [" + (.directory | gsub("'$HOME'"; "~")) + "]" else "" end) +
       "\t" + .name)'

    # Output ACTIVE project last with prominent indicator
    if [ -n "$ACTIVE_PROJECT" ] && [ "$ACTIVE_PROJECT" != "null" ]; then
      echo "$PROJECTS_JSON" | ${pkgs.jq}/bin/jq -r '.projects[] | select(.name == "'"$ACTIVE_PROJECT"'") |
        ((.icon // "📁") + " " + (.display_name // .name) +
         (if .directory then " [" + (.directory | gsub("'$HOME'"; "~")) + "]" else "" end) +
         " 🟢 ACTIVE" +
         "\t" + .name)'
    fi
  '';

  # Walker project switch script - parses selection and switches project
  walkerProjectSwitch = pkgs.writeShellScriptBin "walker-project-switch" ''
    #!/usr/bin/env bash
    # Switch to selected project from Walker
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    I3PM="${config.home.profileDirectory}/bin/i3pm"
    SELECTED="$1"

    # Extract project name (everything after the tab character)
    PROJECT_NAME=$(echo "$SELECTED" | ${pkgs.coreutils}/bin/cut -f2)

    # Handle special cases
    if [ "$PROJECT_NAME" = "__CLEAR__" ]; then
      $I3PM project clear >/dev/null 2>&1
    else
      $I3PM project switch "$PROJECT_NAME" >/dev/null 2>&1
    fi
  '';

  walkerProjectListCmd = lib.getExe walkerProjectList;
  walkerProjectSwitchCmd = lib.getExe walkerProjectSwitch;

  # Walker window action scripts - enhanced window management via Walker
  walkerWindowClose = pkgs.writeShellScriptBin "walker-window-close" ''
    #!/usr/bin/env bash
    # Close/kill the selected window
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    # The windows provider returns the window ID
    WINDOW_ID="$1"

    # Use swaymsg to kill the focused window
    # The windows provider should have already focused it
    swaymsg kill
  '';

  walkerWindowFloat = pkgs.writeShellScriptBin "walker-window-float" ''
    #!/usr/bin/env bash
    # Toggle floating mode for the selected window
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    swaymsg floating toggle
  '';

  walkerWindowFullscreen = pkgs.writeShellScriptBin "walker-window-fullscreen" ''
    #!/usr/bin/env bash
    # Toggle fullscreen mode for the selected window
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    swaymsg fullscreen toggle
  '';

  walkerWindowScratchpad = pkgs.writeShellScriptBin "walker-window-scratchpad" ''
    #!/usr/bin/env bash
    # Move the selected window to scratchpad
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    swaymsg move scratchpad
  '';

  walkerWindowInfo = pkgs.writeShellScriptBin "walker-window-info" ''
    #!/usr/bin/env bash
    # Show detailed window information
    set -euo pipefail

    if [ $# -eq 0 ]; then
      exit 0
    fi

    # Get the focused window info from swaymsg
    WINDOW_INFO=$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.focused? == true) | {id, name, app_id, pid, window_properties, geometry, floating, fullscreen, urgent, visible, focused}')

    # Display in a notification using our terminal
    echo "$WINDOW_INFO" | ${pkgs.jq}/bin/jq '.' | ${pkgs.rofi}/bin/rofi -dmenu -p "Window Info" -theme-str 'window {width: 800px; height: 600px;}' -no-custom
  '';

  # Walker Window Manager - Two-stage dmenu-based window management
  walkerWindowManager = pkgs.writeShellScriptBin "walker-window-manager" ''
    #!/usr/bin/env bash
    # Walker-based window manager - two-stage selection
    set -euo pipefail

    # Stage 1: Select a window
    get_windows() {
        ${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '
            recurse(.nodes[]?, .floating_nodes[]?) |
            select(.type == "con" and .pid != null) |
            "\(.id)|\(.app_id // .window_properties.class // "unknown")|\(.name)"
        ' | while IFS='|' read -r id app_id name; do
            # Format: "app_id - name [id]"
            echo "''${id}|''${app_id} - ''${name}"
        done
    }

    # Get list of windows
    WINDOWS=$(get_windows)

    if [ -z "$WINDOWS" ]; then
        ${pkgs.libnotify}/bin/notify-send "No Windows" "No windows found"
        exit 0
    fi

    # Show windows in walker dmenu mode
    SELECTED_WINDOW=$(echo "$WINDOWS" | ${pkgs.coreutils}/bin/cut -d'|' -f2 | ${pkgs.walker}/bin/walker --dmenu -p "Select Window:")

    if [ -z "$SELECTED_WINDOW" ]; then
        exit 0
    fi

    # Extract window ID from the original data
    WINDOW_ID=$(echo "$WINDOWS" | ${pkgs.gnugrep}/bin/grep -F "$SELECTED_WINDOW" | ${pkgs.coreutils}/bin/cut -d'|' -f1)

    # Focus the selected window first
    ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus"

    # Stage 2: Select an action
    ACTIONS="❌ Close/Kill Window
    ⬜ Toggle Floating
    ⛶ Toggle Fullscreen
    📦 Move to Scratchpad
    ⬅️  Move Left
    ➡️  Move Right
    ⬆️  Move Up
    ⬇️  Move Down
    🔲 Split Horizontal
    ⬛ Split Vertical
    📊 Layout Stacking
    📑 Layout Tabbed
    ⚡ Layout Toggle Split"

    SELECTED_ACTION=$(echo "$ACTIONS" | ${pkgs.walker}/bin/walker --dmenu -p "Window Action:")

    if [ -z "$SELECTED_ACTION" ]; then
        exit 0
    fi

    # Execute the action
    case "$SELECTED_ACTION" in
        "❌ Close/Kill Window")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] kill"
            ;;
        "⬜ Toggle Floating")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] floating toggle"
            ;;
        "⛶ Toggle Fullscreen")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] fullscreen toggle"
            ;;
        "📦 Move to Scratchpad")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] move scratchpad"
            ;;
        "⬅️  Move Left")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] move left"
            ;;
        "➡️  Move Right")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] move right"
            ;;
        "⬆️  Move Up")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] move up"
            ;;
        "⬇️  Move Down")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] move down"
            ;;
        "🔲 Split Horizontal")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus; split h"
            ;;
        "⬛ Split Vertical")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus; split v"
            ;;
        "📊 Layout Stacking")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] layout stacking"
            ;;
        "📑 Layout Tabbed")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] layout tabbed"
            ;;
        "⚡ Layout Toggle Split")
            ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] layout toggle split"
            ;;
    esac

    ${pkgs.libnotify}/bin/notify-send "Window Action" "Executed: $SELECTED_ACTION"
  '';

  # Feature 034/035: Custom application directory for i3pm-managed apps
  # Desktop files are at ~/.local/share/i3pm-applications/applications/
  # Add to XDG_DATA_DIRS so Walker can find them
  i3pmAppsDir = "${config.home.homeDirectory}/.local/share/i3pm-applications";
in

# Walker Application Launcher
#
# Walker is a modern GTK4-based application launcher with:
# - Fast application search with fuzzy matching
# - Built-in calculator (= prefix)
# - File browser (/ prefix)
# - Clipboard history (: prefix)
# - Symbol picker (. prefix)
# - Shell command execution
# - Web search integration
# - Custom menu support
#
# Documentation: https://github.com/abenz1267/walker

{
  imports = [
    inputs.walker.homeManagerModules.default
  ];

  programs.walker = {
    enable = true;

    # Enable service mode for Wayland/Sway (plugins require GApplication service)
    # Disable for X11/XRDP due to GApplication DBus issues
    runAsService = isWaylandMode;

    # NOTE: config generation disabled - we override with xdg.configFile below to add X11 settings
    # Walker configuration with sesh plugin integration (Feature 034)
    config = lib.mkForce {};  # Disable upstream module config generation
    /*
    config = {
      # Enable default Walker/Elephant providers
      # Reference: https://github.com/abenz1267/walker#providers-implemented-by-walker-per-default
      modules = {
        applications = true;    # Desktop applications (primary launcher mode)
        calc = true;            # Calculator (= prefix)
        clipboard = true;       # Clipboard history (: prefix) - text and image support
        files = false;          # File browser (DISABLED - causes segfault in X11)
        menus = true;           # Context menus
        runner = true;          # Shell command execution
        symbols = true;         # Symbol/emoji picker (. prefix)
        websearch = true;       # Web search integration
        # bluetooth = false;    # Bluetooth (disabled - not needed)
        # providerlist = true;  # Provider list (meta-provider)
        # todo = false;         # Todo list (disabled - not configured)
        # unicode = true;       # Unicode character search
      };

      # Provider prefixes - Type these to activate specific providers
      # Reference: https://github.com/abenz1267/walker/wiki/Basic-Configuration#providersprefixes
      providers.prefixes = [
        { prefix = "="; provider = "calc"; }           # Calculator
        { prefix = ":"; provider = "clipboard"; }      # Clipboard history (text + images)
        { prefix = "."; provider = "symbols"; }        # Symbol/emoji picker
        { prefix = "@"; provider = "websearch"; }      # Web search
        { prefix = ">"; provider = "runner"; }         # Shell command execution
        # { prefix = "/"; provider = "files"; }        # File browser (disabled - segfault)
      ];

      # Custom plugins
      plugins = [
        {
          name = "sesh";
          prefix = ";s ";
          src_once = "sesh list -d -c -t -T";
          cmd = "sesh connect --switch %RESULT%";
          keep_sort = false;
          recalculate_score = true;
          show_icon_when_single = true;
          switcher_only = true;
        }
        {
          name = "projects";
          prefix = ";p ";
          src_once = lib.getExe walkerProjectList;
          cmd = "${lib.getExe walkerProjectSwitch} %RESULT%";
          keep_sort = false;
          recalculate_score = true;
          show_icon_when_single = true;
          switcher_only = true;
        }
      ];

      # Provider actions - Custom keybindings and actions for providers
      # Feature 034: Enhanced application launching with project context
      providers.actions = {
        # Desktop applications actions
        # Default action uses .desktop Exec command (already points to app-launcher-wrapper.sh)
        desktopapplications = [
          {
            action = "open";           # Default action: Launch via app-launcher-wrapper
            default = true;
            bind = "Return";
            label = "launch";
            after = "Close";
          }
        ];

        # Runner actions - Execute commands
        runner = [
          {
            action = "run";
            default = true;
            bind = "Return";
            label = "run";
            after = "Close";
          }
          {
            action = "runterminal";
            bind = "shift Return";
            label = "run in terminal";
            after = "Close";
          }
        ];

        # Fallback actions for all providers
        fallback = [
          {
            action = "menus:open";
            label = "open";
            after = "Nothing";
          }
        ];
      };
    };
    */
  };

  home.packages = [
    walkerOpenInNvim
    walkerProjectList
    walkerProjectSwitch
    walkerWindowClose
    walkerWindowFloat
    walkerWindowFullscreen
    walkerWindowScratchpad
    walkerWindowInfo
    walkerWindowManager
  ];

  # Desktop file for walker-open-in-nvim - manual creation
  xdg.dataFile."applications/walker-open-in-nvim.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Open in Neovim (Alacritty)
    Exec=${lib.getExe walkerOpenInNvim} %U
    MimeType=text/plain;text/markdown;text/x-shellscript;text/x-python;text/x-nix;application/x-shellscript;application/json;application/xml;text/x-c;text/x-c++;text/x-java;text/x-rust;text/x-go;text/x-yaml;text/x-toml;application/toml;application/x-yaml;inode/directory;
    NoDisplay=true
    Terminal=false
  '';

  # Set walker-open-in-nvim as default handler for all common file types
  xdg.mimeApps.defaultApplications = {
    "text/plain" = "walker-open-in-nvim.desktop";
    "text/markdown" = "walker-open-in-nvim.desktop";
    "text/x-shellscript" = "walker-open-in-nvim.desktop";
    "text/x-python" = "walker-open-in-nvim.desktop";
    "text/x-nix" = "walker-open-in-nvim.desktop";
    "text/x-c" = "walker-open-in-nvim.desktop";
    "text/x-c++" = "walker-open-in-nvim.desktop";
    "text/x-java" = "walker-open-in-nvim.desktop";
    "text/x-rust" = "walker-open-in-nvim.desktop";
    "text/x-go" = "walker-open-in-nvim.desktop";
    "text/x-yaml" = "walker-open-in-nvim.desktop";
    "text/x-toml" = "walker-open-in-nvim.desktop";
    "application/x-shellscript" = "walker-open-in-nvim.desktop";
    "application/json" = "walker-open-in-nvim.desktop";
    "application/xml" = "walker-open-in-nvim.desktop";
    "application/toml" = "walker-open-in-nvim.desktop";
    "application/x-yaml" = "walker-open-in-nvim.desktop";
    # Fallback for unknown text files
    "application/octet-stream" = "walker-open-in-nvim.desktop";
  };

  # Override the walker config file to add mode settings not supported by the module
  xdg.configFile."walker/config.toml" = lib.mkForce {
    text = ''
        # Walker Configuration
        # ${if isWaylandMode then "Wayland Mode (headless Sway)" else "X11 Mode (use window instead of Wayland layer shell)"}
        # Using default Walker theme
        as_window = ${if isWaylandMode then "false" else "true"}
        # Force keyboard focus when Walker opens (ensures immediate typing without clicking)
        force_keyboard_focus = true
        close_when_open = true

        [modules]
        applications = true
        calc = true
        # Clipboard: ${if isWaylandMode then "Enabled for Wayland mode" else "Disabled - Elephant's clipboard provider requires Wayland (wl-clipboard), X11 clipboard monitoring not supported"}
        clipboard = ${if isWaylandMode then "true" else "false"}
        # File provider now enabled (Walker ≥v1.5 supports X11 safely when launched as a window)
        files = true
        menus = true
        runner = true
        symbols = true
        websearch = true
        # Feature 050: Additional providers for enhanced productivity
        todo = true              # Todo list management (! prefix)
        windows = true           # Window switcher for fuzzy window navigation
        bookmarks = true         # Quick URL access via bookmarks
        snippets = true          # User-defined command shortcuts ($ prefix)
        providerlist = true      # Help menu - lists all providers and prefixes (? prefix)

        # NOTE: Projects and Sesh menus are defined as Elephant Lua menus
        # See ~/.config/elephant/menus/projects.lua and sesh.lua
        # Activated via provider prefixes below (;p and ;s)

        [[providers.prefixes]]
        prefix = "="
        provider = "calc"

        [[providers.prefixes]]
        prefix = ":"
        provider = "clipboard"

        [[providers.prefixes]]
        prefix = "."
        provider = "symbols"

        [[providers.prefixes]]
        prefix = "@"
        provider = "websearch"

        [[providers.prefixes]]
        prefix = ">"
        provider = "runner"

        [[providers.prefixes]]
        prefix = "/"
        provider = "files"

        [[providers.prefixes]]
        prefix = "//"
        provider = "menus:project-files"

        [[providers.prefixes]]
        prefix = "!"
        provider = "todo"

        [[providers.prefixes]]
        prefix = "$"
        provider = "snippets"

        [[providers.prefixes]]
        prefix = "w"
        provider = "windows"

        [[providers.prefixes]]
        prefix = "b"
        provider = "bookmarks"

        [[providers.prefixes]]
        prefix = "?"
        provider = "providerlist"

        [[providers.prefixes]]
        prefix = ";p "
        provider = "menus:projects"

        [[providers.prefixes]]
        prefix = ";s "
        provider = "menus:sesh"

        [[providers.prefixes]]
        prefix = ";w "
        provider = "menus:window-actions"

        [[providers.actions.desktopapplications]]
        action = "open"
        after = "Close"
        bind = "Return"
        default = true
        label = "launch"

        [[providers.actions.fallback]]
        action = "menus:open"
        after = "Nothing"
        label = "open"

        [[providers.actions.runner]]
        action = "run"
        after = "Close"
        bind = "Return"
        default = true
        label = "run"

        [[providers.actions.runner]]
        action = "runterminal"
        after = "Close"
        bind = "shift Return"
        label = "run in terminal"

        # File provider actions
        # Return key uses "open" action which respects MIME handlers (opens text files in Neovim)
        # Ctrl+Return opens parent directory for quick navigation
        [[providers.actions.files]]
        action = "open"
        after = "Close"
        bind = "Return"
        default = true
        label = "open"

        [[providers.actions.files]]
        action = "opendir"
        after = "Close"
        bind = "ctrl Return"
        label = "open directory"

        # Windows provider actions
        # The windows provider only supports "focus" as a built-in action
        # Use Ctrl+M to open the full window actions menu
        [[providers.actions.windows]]
        action = "focus"
        after = "Close"
        bind = "Return"
        default = true
        label = "focus window"

        [[providers.actions.windows]]
        action = "menus:window-actions"
        after = "Nothing"
        bind = "ctrl m"
        label = "window actions"
    '';
  };

  # Elephant websearch provider configuration
  # Feature 050: Enhanced with domain-specific search engines
  xdg.configFile."elephant/websearch.toml".text = ''
    # Elephant Web Search Configuration

    [[engines]]
    name = "Google"
    url = "https://www.google.com/search?q=%s"

    [[engines]]
    name = "DuckDuckGo"
    url = "https://duckduckgo.com/?q=%s"

    [[engines]]
    name = "GitHub"
    url = "https://github.com/search?q=%s"

    [[engines]]
    name = "YouTube"
    url = "https://www.youtube.com/results?search_query=%s"

    [[engines]]
    name = "Wikipedia"
    url = "https://en.wikipedia.org/wiki/Special:Search?search=%s"

    # Feature 050: Domain-specific search engines for development
    [[engines]]
    name = "Stack Overflow"
    url = "https://stackoverflow.com/search?q=%s"

    [[engines]]
    name = "Arch Wiki"
    url = "https://wiki.archlinux.org/index.php?search=%s"

    [[engines]]
    name = "Nix Packages"
    url = "https://search.nixos.org/packages?query=%s"

    [[engines]]
    name = "Rust Docs"
    url = "https://doc.rust-lang.org/std/?search=%s"

    # Default search engine
    default = "Google"
  '';

  # Providerlist configuration - native help menu
  xdg.configFile."elephant/providerlist.toml".text = ''
    # Elephant Providerlist Configuration
    # Shows all installed providers and configured menus
    # Access: Meta+D → ? → shows all providers with descriptions

    # Minimum fuzzy match score (0-100)
    min_score = 30

    # Hidden providers (exclude from list)
    # hidden = ["providerlist"]  # Hide the help menu from itself
  '';

  # Feature 050: Bookmarks provider configuration
  # Elephant bookmarks are stored in CSV format, this file only contains configuration
  xdg.configFile."elephant/bookmarks.toml".text = ''
    # Elephant Bookmarks Configuration
    # Bookmarks are stored in CSV: ~/.cache/elephant/bookmarks/bookmarks.csv
    # Use Walker to add bookmarks: Meta+D → b → <url> → Return

    # Minimum fuzzy match score (0-100)
    min_score = 30

    # Prefix for creating new bookmarks (optional)
    # If set, use: Meta+D → b → add:github.com GitHub
    # If not set, any non-matching query creates a bookmark
    # create_prefix = "add"

    # Categories for organizing bookmarks
    # Usage: Meta+D → b → dev:github.com → adds to "dev" category

    [[categories]]
    name = "docs"
    prefix = "d:"

    [[categories]]
    name = "dev"
    prefix = "dv:"

    [[categories]]
    name = "ai"
    prefix = "ai:"

    [[categories]]
    name = "nix"
    prefix = "nx:"

    [[categories]]
    name = "work"
    prefix = "w:"

    [[categories]]
    name = "personal"
    prefix = "p:"

    # Browsers for opening bookmarks
    # Usage: Set browser when adding bookmark or edit CSV later

    [[browsers]]
    name = "Firefox"
    command = "firefox"

    [[browsers]]
    name = "Firefox Private"
    command = "firefox --private-window"

    [[browsers]]
    name = "Chromium"
    command = "chromium"

    [[browsers]]
    name = "Firefox App Mode"
    command = "firefox --new-window --kiosk"
  '';

  # Files provider configuration
  # Feature 050: Configure files provider to show hidden files (dotfiles)
  # Default fd_flags: "--ignore-vcs --type file --type directory"
  # Searches from $HOME by default
  xdg.configFile."elephant/files.toml".text = ''
    # Feature 050: Files provider configuration
    # Show hidden files (dotfiles) and search from home directory
    # NOTE: Removed --follow flag - it traverses ALL symlinks (too slow, indexes too much)
    # To search /etc/nixos: Type /etc/nixos in Walker file search
    fd_flags = "--hidden --ignore-vcs --type file --type directory"

    # Ignore performance-heavy directories
    ignored_dirs = [
      "${config.home.homeDirectory}/.cache",
      "${config.home.homeDirectory}/.local/share/Trash",
      "${config.home.homeDirectory}/.npm",
      "${config.home.homeDirectory}/.cargo",
      "${config.home.homeDirectory}/node_modules",
      "${config.home.homeDirectory}/.nix-profile",
    ]
  '';

  # Windows provider configuration
  # Enhanced with additional window management actions
  xdg.configFile."elephant/windows.toml".text = ''
    # Elephant Windows Provider Configuration
    # Provides fuzzy window switching with enhanced actions

    # Minimum fuzzy match score (0-100)
    min_score = 30

    # Delay in ms before focusing to avoid potential focus issues
    delay = 100

    # Icon for the provider
    icon = "preferences-system-windows"
  '';

  # Create symlink to /etc/nixos in home directory for easy access
  # Access via: /nixos-config/ in file search
  home.file."nixos-config".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos";

  # Feature 050: Custom commands provider configuration
  # NOTE: commands.toml is now managed dynamically via walker-cmd CLI tool
  # This allows adding/removing commands without rebuilding NixOS
  # Run 'walker-cmd --help' for usage instructions
  # Initial file will be created with examples on first use

  # Feature 034/035: Isolate Walker/Elephant to show ONLY i3pm registry apps
  # By setting XDG_DATA_DIRS to ONLY the i3pm-applications directory,
  # Walker/Elephant won't see any system applications
  # NOTE: This only affects Walker/Elephant service, not the entire session
  # (Elephant service has its own isolated XDG_DATA_DIRS below)

  # Feature 035/046: Elephant service - conditional for Wayland (Sway) vs X11 (i3)
  # Uses standard Elephant binary instead of isolated wrapper
  systemd.user.services.elephant = lib.mkForce {
    Unit = {
      Description = if isWaylandMode then "Elephant launcher backend (Wayland)" else "Elephant launcher backend (X11)";
      # Wayland/Sway: Use sway-session.target (Feature 046)
      # X11/i3: Use default.target (i3 doesn't activate graphical-session.target)
      PartOf = if isWaylandMode then [ "sway-session.target" ] else [ "default.target" ];
      After = if isWaylandMode then [ "sway-session.target" ] else [ "default.target" ];
      # Note: Removed ConditionEnvironment=DISPLAY/WAYLAND_DISPLAY - PassEnvironment provides it when service runs
      # Condition check was too early (before env set), causing startup failures
    };
    Service = {
      # Feature 034/035: Elephant with isolated XDG environment
      # Set XDG_DATA_DIRS to ONLY i3pm-applications directory
      # This ensures Elephant/Walker only see our curated 21 apps
      ExecStart = "${inputs.elephant.packages.${pkgs.system}.default}/bin/elephant";
      Restart = "on-failure";
      RestartSec = 1;
      # Fix: Add PATH for program launching (GitHub issue #69)
      # Feature 034/035 (Feature 050): XDG_DATA_DIRS now includes BOTH custom and default directories
      # NOTE: XDG_DATA_HOME must NOT be overridden - apps like Firefox PWA need default location
      # IMPORTANT: Include ~/.local/bin in PATH so Elephant can find app-launcher-wrapper.sh
      Environment = [
        "PATH=${config.home.homeDirectory}/.local/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        # Feature 050: Prepend i3pm-applications directory to XDG_DATA_DIRS (doesn't suppress defaults)
        # This allows Walker to find both our custom apps AND system defaults (for bookmarks, etc.)
        "XDG_DATA_DIRS=${i3pmAppsDir}:${config.home.homeDirectory}/.local/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
        "XDG_RUNTIME_DIR=%t"
      ];
      # CRITICAL: Pass compositor environment variables
      # X11/i3: DISPLAY
      # Wayland/Sway: WAYLAND_DISPLAY (Feature 046)
      PassEnvironment = if isWaylandMode then [ "WAYLAND_DISPLAY" ] else [ "DISPLAY" ];
    };
    Install = {
      # Wayland/Sway: sway-session.target (Feature 046)
      # X11/i3: default.target
      WantedBy = if isWaylandMode then [ "sway-session.target" ] else [ "default.target" ];
    };
  };

  # Walker service disabled - using direct invocation
  # No service override needed since runAsService = false

  # Feature 034/035 (Feature 050): Add i3pm apps directory to session XDG_DATA_DIRS
  # This ensures Walker (when invoked directly, not as service) can find our apps
  # Prepends custom directory to existing defaults (doesn't suppress bookmarks)
  home.sessionVariables = {
    XDG_DATA_DIRS = "${i3pmAppsDir}:$XDG_DATA_DIRS";
  };
}

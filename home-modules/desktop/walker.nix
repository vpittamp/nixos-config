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

    if [ -n "$LINE_ARG" ]; then
      exec ${pkgs.alacritty}/bin/alacritty -e ${pkgs.neovim-unwrapped}/bin/nvim "$LINE_ARG" "$TARGET_PATH"
    else
      exec ${pkgs.alacritty}/bin/alacritty -e ${pkgs.neovim-unwrapped}/bin/nvim "$TARGET_PATH"
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

    # Disable runAsService - Walker has issues with GApplication DBus in X11/XRDP
    # Instead, invoke Walker directly which works fine
    # Plugins still work in direct mode
    runAsService = false;

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
        customcommands = true    # User-defined command shortcuts

        [[plugins]]
        # Modified to launch Alacritty with the selected tmux session
        # Original sesh docs use "sesh connect --switch %RESULT%" but that only works inside tmux
        # We launch Alacritty to attach to the selected session instead
        cmd = "alacritty -e tmux attach-session -t %RESULT%"
        keep_sort = false
        name = "sesh"
        prefix = ";s "
        recalculate_score = true
        show_icon_when_single = true
        src_once = "sesh list -d -c -t -T"
        switcher_only = true

        [[plugins]]
        # Project switcher - integrated with i3pm
        # Lists all projects with icons, display names, and directories
        # Supports clearing active project to return to global mode
        cmd = "${walkerProjectSwitchCmd} %RESULT%"
        keep_sort = false
        name = "projects"
        prefix = ";p "
        recalculate_score = true
        show_icon_when_single = true
        src_once = "${walkerProjectListCmd}"
        switcher_only = true

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
        prefix = "!"
        provider = "todo"

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

  # Feature 050: Bookmarks provider configuration
  xdg.configFile."elephant/bookmarks.toml".text = ''
    # Elephant Bookmarks Configuration
    # Quick access to frequently visited URLs

    [[bookmarks]]
    name = "NixOS Manual"
    url = "https://nixos.org/manual/nixos/stable/"
    description = "Official NixOS documentation"
    tags = ["docs", "nix"]

    [[bookmarks]]
    name = "GitHub"
    url = "https://github.com"
    description = "GitHub code hosting platform"
    tags = ["dev", "git"]

    [[bookmarks]]
    name = "Google AI Studio"
    url = "https://aistudio.google.com"
    description = "Google AI development platform"
    tags = ["ai", "dev"]

    [[bookmarks]]
    name = "Stack Overflow"
    url = "https://stackoverflow.com"
    description = "Programming Q&A community"
    tags = ["dev", "help"]

    [[bookmarks]]
    name = "Rust Documentation"
    url = "https://doc.rust-lang.org"
    description = "Official Rust programming language documentation"
    tags = ["docs", "rust", "dev"]

    [[bookmarks]]
    name = "Arch Wiki"
    url = "https://wiki.archlinux.org"
    description = "Comprehensive Linux documentation"
    tags = ["docs", "linux"]

    [[bookmarks]]
    name = "Nix Packages Search"
    url = "https://search.nixos.org/packages"
    description = "Search NixOS package repository"
    tags = ["nix", "packages"]

    [[bookmarks]]
    name = "Home Manager Options"
    url = "https://nix-community.github.io/home-manager/options.xhtml"
    description = "Home Manager configuration options reference"
    tags = ["nix", "docs", "home-manager"]
  '';

  # Feature 050: Custom commands provider configuration
  xdg.configFile."elephant/commands.toml".text = ''
    # Elephant Custom Commands Configuration
    # User-defined shortcuts for common operations

    [customcommands]
    # Sway/Window Manager Commands
    "reload sway config" = "swaymsg reload"
    "restart waybar" = "killall waybar && waybar &"
    "lock screen" = "swaylock -f"

    # System Management Commands
    "suspend system" = "systemctl suspend"
    "reboot system" = "systemctl reboot"
    "shutdown system" = "systemctl poweroff"

    # NixOS Commands
    "rebuild nixos" = "cd /etc/nixos && sudo nixos-rebuild switch --flake .#hetzner-sway"
    "update nixos" = "cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#hetzner-sway"
    "rebuild home-manager" = "home-manager switch --flake /etc/nixos#hetzner-sway"

    # Git Commands
    "git status all" = "cd /etc/nixos && git status"
    "git pull nixos" = "cd /etc/nixos && git pull"
    "git push nixos" = "cd /etc/nixos && git push"

    # Project Management Commands
    "list projects" = "i3pm project list"
    "show active project" = "i3pm project current"

    # Service Management Commands
    "restart elephant" = "systemctl --user restart elephant"
    "restart i3pm daemon" = "systemctl --user restart i3-project-event-listener"
    "check elephant status" = "systemctl --user status elephant"
    "check i3pm daemon status" = "systemctl --user status i3-project-event-listener"

    # Development Commands
    "run nixos tests" = "cd /etc/nixos/tests && pytest"
    "format nixos config" = "cd /etc/nixos && nixfmt **/*.nix"
  '';

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
      # Feature 034/035: Isolate XDG_DATA_DIRS to ONLY i3pm apps (no system apps)
      # NOTE: XDG_DATA_HOME must NOT be overridden - apps like Firefox PWA need default location
      # IMPORTANT: Include ~/.local/bin in PATH so Elephant can find app-launcher-wrapper.sh
      Environment = [
        "PATH=${config.home.homeDirectory}/.local/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        "XDG_DATA_DIRS=${i3pmAppsDir}"
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

  # Feature 034/035: Add i3pm apps directory to session XDG_DATA_DIRS
  # This ensures Walker (when invoked directly, not as service) can find our apps
  home.sessionVariables = {
    XDG_DATA_DIRS = "${i3pmAppsDir}:$XDG_DATA_DIRS";
  };
}

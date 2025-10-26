{ config, lib, pkgs, inputs, ... }:

let
  walkerOpenInNvim = pkgs.writeShellScriptBin "walker-open-in-nvim" ''
    #!/usr/bin/env bash
    # Launch a Ghostty terminal window with Neovim for a Walker-selected file path
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
      exec ${pkgs.ghostty}/bin/ghostty -e ${pkgs.neovim-unwrapped}/bin/nvim "$LINE_ARG" "$TARGET_PATH"
    else
      exec ${pkgs.ghostty}/bin/ghostty -e ${pkgs.neovim-unwrapped}/bin/nvim "$TARGET_PATH"
    fi
  '';

  walkerOpenInNvimCmd = lib.getExe walkerOpenInNvim;

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
  ];

  # Override the walker config file to add X11 settings not supported by the module
  xdg.configFile."walker/config.toml" = lib.mkForce {
    text = ''
        # Walker Configuration (X11 Mode)
        # X11 Mode - use window instead of Wayland layer shell
        as_window = true
        force_keyboard_focus = false
        close_when_open = true

        [modules]
        applications = true
        calc = true
        clipboard = true
        # File provider now enabled (Walker ≥v1.5 supports X11 safely when launched as a window)
        files = true
        menus = true
        runner = true
        symbols = true
        websearch = true

        [[plugins]]
        cmd = "sesh connect --switch %RESULT%"
        keep_sort = false
        name = "sesh"
        prefix = ";s "
        recalculate_score = true
        show_icon_when_single = true
        src_once = "sesh list -d -c -t -T"
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

        # File provider actions - open files in Ghostty + Neovim
        [[providers.actions.files]]
        action = "run ${walkerOpenInNvimCmd} %RESULT%"
        after = "Close"
        bind = "Return"
        default = true
        label = "open in ghostty (nvim)"

        [[providers.actions.files]]
        action = "open"
        after = "Close"
        bind = "ctrl Return"
        label = "open with default app"
    '';
  };

  # Elephant websearch provider configuration
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

    # Default search engine
    default = "Google"
  '';

  # Feature 034/035: Isolate Walker/Elephant to show ONLY i3pm registry apps
  # By setting XDG_DATA_DIRS to ONLY the i3pm-applications directory,
  # Walker/Elephant won't see any system applications
  # NOTE: This only affects Walker/Elephant service, not the entire session
  # (Elephant service has its own isolated XDG_DATA_DIRS below)

  # Feature 035: Elephant service without XDG isolation
  # Uses standard Elephant binary instead of isolated wrapper
  systemd.user.services.elephant = lib.mkForce {
    Unit = {
      Description = "Elephant launcher backend (X11)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      # Use DISPLAY instead of WAYLAND_DISPLAY
      ConditionEnvironment = "DISPLAY";
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
      Environment = [
        "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        "XDG_DATA_DIRS=${i3pmAppsDir}"
        "XDG_RUNTIME_DIR=%t"
      ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
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

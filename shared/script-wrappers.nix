# Script Wrappers for Portable NixOS Configuration
# Feature 106: Make NixOS Config Portable for Worktrees
#
# This module generates wrapper scripts in the Nix store that dynamically
# resolve the flake root at runtime. This allows the configuration to work
# correctly when built from git worktrees in different directories.
#
# Usage in Nix modules:
#   let
#     scriptWrappers = import ../shared/script-wrappers.nix { inherit pkgs lib; };
#   in {
#     programs.bash.shellAliases = {
#       keys = "${scriptWrappers.keybindings-cheatsheet}/bin/keybindings-cheatsheet";
#     };
#   }
#
# Or use the combined package:
#   home.packages = [ scriptWrappers.package ];
#
{ pkgs, lib }:

let
  # Common runtime inputs for all wrappers
  commonInputs = [ pkgs.git pkgs.coreutils ];

  # The flake root discovery logic (embedded in each wrapper)
  flakeRootFunction = ''
    get_flake_root() {
      # Priority 1: Environment variable (for CI/CD and manual override)
      if [[ -n "''${FLAKE_ROOT:-}" ]]; then
        echo "$FLAKE_ROOT"
        return 0
      fi

      # Priority 2: Git repository detection (works for worktrees!)
      local git_root
      git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
      if [[ -n "$git_root" ]]; then
        echo "$git_root"
        return 0
      fi

      # Priority 3: Default fallback (for deployed systems without git)
      echo "/etc/nixos"
    }
  '';

  # Generate a wrapper script for a given script path relative to flake root
  makeScriptWrapper = { name, scriptPath, extraInputs ? [], description ? "" }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = commonInputs ++ extraInputs;
      meta = lib.optionalAttrs (description != "") { inherit description; };
      text = ''
        ${flakeRootFunction}
        FLAKE_ROOT="$(get_flake_root)"
        export FLAKE_ROOT
        exec "$FLAKE_ROOT/${scriptPath}" "$@"
      '';
    };

  # Define all scripts that need wrappers
  # Format: attrName = { scriptPath, extraInputs?, description? }
  scriptDefinitions = {
    # Shell utilities
    keybindings-cheatsheet = {
      scriptPath = "scripts/keybindings-cheatsheet.sh";
      description = "Display keybinding cheatsheet";
    };
    # Elephant-based clipboard history selector (replaces clipcat)
    elephant-fzf = {
      scriptPath = "scripts/elephant-fzf.sh";
      extraInputs = [ pkgs.fzf pkgs.jq pkgs.wl-clipboard ];
      description = "FZF-based clipboard history selector (Elephant)";
    };
    # Legacy alias - points to elephant-fzf for backward compatibility
    clipcat-fzf = {
      scriptPath = "scripts/elephant-fzf.sh";
      extraInputs = [ pkgs.fzf pkgs.jq pkgs.wl-clipboard ];
      description = "FZF-based clipboard history selector (Elephant) - legacy alias";
    };
    clipboard-sync = {
      scriptPath = "scripts/clipboard-sync.sh";
      description = "Sync clipboard between tmux and system";
    };
    clipboard-paste = {
      scriptPath = "scripts/clipboard-paste.sh";
      description = "Paste from system clipboard";
    };
    view-last-bg-command = {
      scriptPath = "scripts/view-last-bg-command.sh";
      description = "View output of last background command";
    };
    fzf-history = {
      scriptPath = "scripts/fzf-history.sh";
      extraInputs = [ pkgs.fzf ];
      description = "FZF-based command history search";
    };

    # Plasma utilities
    plasma-rc2nix = {
      scriptPath = "scripts/plasma-rc2nix.sh";
      description = "Export Plasma config to Nix";
    };
    plasma-diff = {
      scriptPath = "scripts/plasma-diff.sh";
      description = "Diff Plasma configuration changes";
    };

    # Launcher scripts
    fzf-launcher = {
      scriptPath = "scripts/fzf-launcher.sh";
      extraInputs = [ pkgs.fzf ];
      description = "FZF application launcher";
    };
    fzf-send-to-window = {
      scriptPath = "scripts/fzf-send-to-window.sh";
      extraInputs = [ pkgs.fzf ];
      description = "FZF window selector for sending";
    };
    fzf-project-switcher = {
      scriptPath = "scripts/fzf-project-switcher.sh";
      extraInputs = [ pkgs.fzf ];
      description = "FZF project switcher";
    };
    sesh-switcher = {
      scriptPath = "scripts/sesh-switcher.sh";
      description = "Tmux session switcher via sesh";
    };

    # i3pm utilities
    i3pm-project-badge = {
      scriptPath = "scripts/i3pm-project-badge.sh";
      description = "Display current project badge for status bars";
    };
    i3pm-clone = {
      scriptPath = "scripts/i3pm-clone.sh";
      description = "Clone repository with i3pm integration";
    };

    # System utilities
    generate-ulid = {
      scriptPath = "scripts/generate-ulid.sh";
      description = "Generate ULID identifier";
    };
    onepassword-setup-token = {
      scriptPath = "scripts/1password-setup-token.sh";
      description = "Setup 1Password service account token";
    };

    # Tmux utilities
    tmux-supervisor-enhanced = {
      scriptPath = "scripts/tmux-supervisor/tmux-supervisor-enhanced.sh";
      extraInputs = [ pkgs.tmux ];
      description = "Enhanced tmux supervisor dashboard";
    };

    # Terminal launching
    devenv-terminal-launch = {
      scriptPath = "scripts/devenv-terminal-launch.sh";
      extraInputs = [ pkgs.tmux pkgs.sesh pkgs.devenv ];
      description = "Devenv-aware terminal launcher with tmux session and devenv up window";
    };
  };

  # Generate wrapper packages from definitions
  wrappers = lib.mapAttrs (name: def:
    makeScriptWrapper {
      inherit name;
      scriptPath = def.scriptPath;
      extraInputs = def.extraInputs or [];
      description = def.description or "";
    }
  ) scriptDefinitions;

in {
  # Individual wrapper packages (for targeted use)
  inherit wrappers;

  # Convenience accessors for common scripts
  inherit (wrappers)
    keybindings-cheatsheet
    elephant-fzf
    clipcat-fzf
    clipboard-sync
    clipboard-paste
    view-last-bg-command
    fzf-history
    plasma-rc2nix
    plasma-diff
    fzf-launcher
    fzf-send-to-window
    fzf-project-switcher
    sesh-switcher
    i3pm-project-badge
    i3pm-clone
    generate-ulid
    onepassword-setup-token
    tmux-supervisor-enhanced
    devenv-terminal-launch;

  # Combined package with all wrappers (for home.packages)
  package = pkgs.symlinkJoin {
    name = "nixos-script-wrappers";
    paths = lib.attrValues wrappers;
    meta.description = "Wrapper scripts for portable NixOS configuration";
  };

  # Helper to get the bin path for a wrapper
  # Usage: scriptWrappers.binPath "clipcat-fzf"
  # Returns: "/nix/store/.../bin/clipcat-fzf"
  binPath = name: "${wrappers.${name}}/bin/${name}";

  # Export the flake root function for use in other scripts
  inherit flakeRootFunction;
}

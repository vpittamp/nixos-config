{ config, lib, pkgs, ... }:

let
  # Feature 035 + Feature 037: Window visibility commands
  # Feature 048: Monitor detection for multi-display VNC setup
  # Feature 053: Enhanced event logging with decision tree visualization - table layout
  # PID support: Added window PID display to all i3pm windows commands
  # Fix: Use flags parameter directly instead of re-parsing args in windowsCommand
  # Feature 058: Columnar output formatting + comprehensive help menu
  # Feature 059: Unified window view - show all windows including scratchpad by default
  # Feature 060: Project-centric tree view - group windows by project
  # Feature 061: Unified mark format - only project:NAME:ID
  version = "2.17.0";  # Feature 108: Enhanced worktree status fields

  # i3pm Deno CLI - Runtime wrapper (Feature 035 registry-centric rewrite)
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm-feature035";
    inherit version;

    src = ./i3pm;

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/share/i3pm
      cp -r * $out/share/i3pm/

      # Ensure remote worktree command sources are packaged.
      if [ ! -f "$out/share/i3pm/src/commands/worktree/remote.ts" ]; then
        echo "ERROR: missing src/commands/worktree/remote.ts in i3pm package output" >&2
        exit 1
      fi

      mkdir -p $out/bin

      # Main i3pm CLI (v2.7.1 - fixed app_id nullable validation)
      cat > $out/bin/i3pm <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \\
  --no-lock \\
  -A \\
  $out/share/i3pm/src/main.ts "\$@"
EOF
      chmod +x $out/bin/i3pm

      # Feature 048: Monitor detection for multi-display VNC setup
      cp ${./i3pm/i3pm-monitors} $out/bin/i3pm-monitors
      chmod +x $out/bin/i3pm-monitors
    '';

    meta = with lib; {
      description = "i3pm - Registry-Centric Project & Workspace Management";
      longDescription = ''
        Feature 035: Complete rewrite using environment-based window filtering.
        Type-safe, compiled CLI for i3 project management with registry-centric architecture.

        Key Features:
        - Environment variable injection (I3PM_*) for project context
        - Process environment reading via /proc/<pid>/environ
        - Deterministic window matching with unique instance IDs
        - Auto-generated window rules from app-registry.nix
        - Layout capture and restore with exact window identification
        - JSON-RPC 2.0 communication with daemon

        Commands:
        - i3pm apps list/show - Query application registry
        - i3pm project create/switch/list/current - Project management
        - i3pm layout save/restore/delete - Window layout persistence
        - i3pm daemon status/events - Monitoring and debugging
        - i3pm windows - Real-time window state visualization

        Replaces tag-based system with simpler environment-based filtering.
      '';
      homepage = "https://github.com/user/nixos-config";
      license = licenses.mit;
      platforms = platforms.linux;
      maintainers = [ ];
    };
  };
  # Wrapper scripts for Sway keybindings (aliases don't work with exec)
  i3-project-switch = pkgs.writeShellScriptBin "i3-project-switch" ''
    # Cancel workspace mode preview if active, then launch project switcher
    i3pm-workspace-mode cancel 2>/dev/null || true
    # Launch Walker with the projects provider for fuzzy selection
    exec ${pkgs.walker}/bin/walker -m projects
  '';

  i3-project-clear = pkgs.writeShellScriptBin "i3-project-clear" ''
    exec i3pm project clear "$@"
  '';
in
{
  config = {
    # Install i3pm binary and wrapper scripts
    home.packages = [
      i3pm
      i3-project-switch  # For Win+P keybinding (sway-keybindings.nix)
      i3-project-clear   # For Win+Shift+P keybinding (sway-keybindings.nix)
    ];

    # Feature 109: Declarative GitHub accounts configuration
    # This eliminates the need to manually run `i3pm account add` on each system
    # The paths use ${config.home.homeDirectory} so they work on any system
    xdg.configFile."i3/accounts.json".text = builtins.toJSON {
      version = 1;
      accounts = [
        {
          name = "PittampalliOrg";
          path = "${config.home.homeDirectory}/repos/PittampalliOrg";
          is_default = true;
          ssh_host = "github.com";
        }
        {
          name = "vpittamp";
          path = "${config.home.homeDirectory}/repos/vpittamp";
          is_default = false;
          ssh_host = "github.com";
        }
      ];
    };

    # Note: Shell aliases are managed in home-modules/shell/bash.nix
    # to avoid conflicts. The bash.nix file should be updated to use
    # the new i3pm commands instead of the old shell scripts.
  };
}

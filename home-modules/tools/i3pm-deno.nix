{ config, lib, pkgs, ... }:

let
  # Feature 035 + Feature 037: Window visibility commands
  # Feature 048: Monitor detection for multi-display VNC setup
  # Feature 053: Enhanced event logging with decision tree visualization - table layout
  # PID support: Added window PID display to all i3pm windows commands
  # Fix: Use flags parameter directly instead of re-parsing args in windowsCommand
  version = "2.5.4";

  # i3pm Deno CLI - Runtime wrapper (Feature 035 registry-centric rewrite)
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm-feature035";
    inherit version;

    src = ./i3pm;

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/share/i3pm
      cp -r * $out/share/i3pm/

      mkdir -p $out/bin

      # Main i3pm CLI
      cat > $out/bin/i3pm <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \\
  --no-lock \\
  -A \\
  $out/share/i3pm/src/main.ts "\$@"
EOF
      chmod +x $out/bin/i3pm

      # Feature 048: Monitor detection for multi-display VNC setup
      cp ${./i3pm-deno/i3pm-monitors} $out/bin/i3pm-monitors
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
in
{
  config = {
    # Install i3pm binary
    home.packages = [ i3pm ];

    # Note: Shell aliases are managed in home-modules/shell/bash.nix
    # to avoid conflicts. The bash.nix file should be updated to use
    # the new i3pm commands instead of the old shell scripts.
  };
}

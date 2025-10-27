{ config, lib, pkgs, ... }:

# Feature 034: Unified Application Launcher - Deno CLI Tool & Wrapper Script
#
# This module:
# - Builds the Deno CLI tool (i3pm apps subcommand)
# - Installs the launcher wrapper script
# - Provides runtime command for application launching

let
  # Build Deno CLI tool using runtime wrapper pattern (not deno compile)
  # See: /etc/nixos/specs/034-create-a-feature/DENO_PACKAGING_RESEARCH.md
  app-launcher-cli = pkgs.stdenv.mkDerivation {
    name = "app-launcher-cli";
    src = ./app-launcher;

    installPhase = ''
      mkdir -p $out/bin $out/share/app-launcher

      # Copy source files
      cp -r src $out/share/app-launcher/ 2>/dev/null || true
      cp main.ts $out/share/app-launcher/ 2>/dev/null || true
      cp mod.ts $out/share/app-launcher/ 2>/dev/null || true
      cp deno.json $out/share/app-launcher/ 2>/dev/null || true

      # Create runtime wrapper script
      cat > $out/bin/i3pm-apps <<'EOF'
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \
  --allow-read=/run/user,$HOME \
  --allow-net=unix \
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \
  --no-lock \
  $out/share/app-launcher/main.ts "$@"
EOF

      chmod +x $out/bin/i3pm-apps
    '';

    meta = {
      description = "Application launcher CLI for unified project-aware launching";
      mainProgram = "i3pm-apps";
    };
  };

  # Launcher wrapper script (bash)
  # Feature 037: Socket path for system service daemon
  # Single source of truth - matches modules/services/i3-project-daemon.nix
  daemonSocketPath = "/run/i3-project-daemon/ipc.sock";

  wrapper-script = pkgs.writeScriptBin "app-launcher-wrapper" (
    let
      scriptContent = builtins.readFile ../../scripts/app-launcher-wrapper.sh;
    in
    # Substitute @DAEMON_SOCKET@ placeholder with actual path
    builtins.replaceStrings
      [ "@DAEMON_SOCKET@" ]
      [ daemonSocketPath ]
      scriptContent
  );

in
{
  # Install CLI tool
  home.packages = [
    app-launcher-cli
    wrapper-script
  ];

  # Install wrapper script to standard location
  # This ensures it's accessible from desktop files
  home.file.".local/bin/app-launcher-wrapper.sh" = {
    source = "${wrapper-script}/bin/app-launcher-wrapper";
    executable = true;
  };

  # Note: .local/state directory is created by other modules
}

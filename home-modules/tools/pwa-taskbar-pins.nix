# Optional PWA Taskbar Pinning Module
# This module can be imported separately to add taskbar pinning functionality
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.pwa-taskbar-pins;

  # Script to pin PWAs to taskbar
  pinScript = pkgs.writeShellScriptBin "pwa-pin-taskbar" ''
    ${builtins.readFile ../../scripts/pwa-taskbar-pin.sh}
  '';
in
{
  options.programs.pwa-taskbar-pins = {
    enable = mkEnableOption "PWA taskbar pinning";

    autoPin = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically pin PWAs after installation";
    };

    pwaOrder = mkOption {
      type = types.listOf types.str;
      default = [
        "Google"
        "YouTube"
        "Claude"
        "ChatGPT"
        "Google Gemini"
        "GitHub"
        "Gmail"
        "Gitea"
        "Backstage"
        "Kargo"
        "ArgoCD"
        "Headlamp"
      ];
      description = "Order of PWAs in taskbar";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pinScript ];

    # Add alias for convenience
    home.shellAliases = {
      "pwa-pin" = "pwa-pin-taskbar";
      "pwa-pins" = "pwa-pin-taskbar";
    };

    # Optional: Run after PWA installation
    home.activation.pinPWAsToTaskbar = mkIf cfg.autoPin (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        if command -v pwa-pin-taskbar >/dev/null 2>&1; then
          echo "Pinning PWAs to taskbar..."
          $DRY_RUN_CMD pwa-pin-taskbar
        fi
      ''
    );
  };
}
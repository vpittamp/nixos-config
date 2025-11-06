# M1 Module Imports Contract
# Feature: M1 Configuration Alignment with Hetzner-Sway
# This file defines the required module imports to add to configurations/m1.nix

# INSTRUCTION: Add these imports to configurations/m1.nix in the imports = [ ... ] block

{
  # Priority 1: CRITICAL - i3 Project Management Daemon
  # This system service is REQUIRED for Features 037, 049 (project switching, window filtering, workspace intelligence)
  # Location to add: After ../modules/services/onepassword.nix
  critical_imports = [
    ../modules/services/i3-project-daemon.nix
  ];

  # Priority 2: HIGH - 1Password Automation
  # Enables service account automation for Git/CI operations
  # Location to add: After i3-project-daemon.nix
  high_priority_imports = [
    ../modules/services/onepassword-automation.nix
  ];

  # Priority 3: OPTIONAL - Keyboard Remapping
  # CapsLock → F9 for workspace mode (Feature 050)
  # Location to add: After onepassword-automation.nix
  # Note: Currently disabled in hetzner-sway, consider enabling on both platforms
  optional_imports = [
    # ../modules/services/keyd.nix  # Uncomment to enable
  ];

  # Configuration Template for m1.nix
  #
  # Current imports section (lines 6-37):
  #   imports = [
  #     ./base.nix
  #     ../modules/assertions/m1-check.nix
  #     ../hardware/m1.nix
  #     inputs.nixos-apple-silicon.nixosModules.default
  #     ../modules/desktop/sway.nix
  #     ../modules/services/development.nix
  #     ../modules/services/networking.nix
  #     ../modules/services/onepassword.nix
  #     ../modules/services/onepassword-password-management.nix
  #     ../modules/services/speech-to-text-safe.nix
  #     ../modules/desktop/firefox-1password.nix
  #     ../modules/desktop/firefox-pwa-1password.nix
  #   ];
  #
  # ADD AFTER onepassword.nix, BEFORE onepassword-password-management.nix:
  #
  #     ../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon
  #     ../modules/services/onepassword-automation.nix  # Service account automation
  #     # ../modules/services/keyd.nix                  # Optional: CapsLock→F9 workspace mode
  #
  # Final imports section should look like:
  #   imports = [
  #     # Base configuration
  #     ./base.nix
  #
  #     # Environment check
  #     ../modules/assertions/m1-check.nix
  #
  #     # Hardware
  #     ../hardware/m1.nix
  #
  #     # Apple Silicon support - CRITICAL for hardware functionality
  #     inputs.nixos-apple-silicon.nixosModules.default
  #
  #     # Desktop environment (Sway - Feature 045 migration from KDE Plasma)
  #     # Sway Wayland compositor for keyboard-driven productivity with i3pm integration
  #     ../modules/desktop/sway.nix
  #
  #     # Services
  #     ../modules/services/development.nix
  #     ../modules/services/networking.nix
  #     ../modules/services/onepassword.nix
  #     ../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon
  #     ../modules/services/onepassword-automation.nix  # Service account automation
  #     ../modules/services/onepassword-password-management.nix
  #     ../modules/services/speech-to-text-safe.nix
  #
  #     # Browser integrations with 1Password
  #     ../modules/desktop/firefox-1password.nix
  #     ../modules/desktop/firefox-pwa-1password.nix
  #   ];

  # Service Configuration (ADD after imports, around line 60 after services.sway.enable)
  #
  # i3 Project Daemon configuration:
  #   services.i3ProjectDaemon = {
  #     enable = true;
  #     user = "vpittamp";
  #     logLevel = "INFO";  # Or "DEBUG" for troubleshooting
  #   };

  # 1Password Automation configuration (ADD after onepassword-password-management block):
  #   services.onepassword-automation = {
  #     enable = true;
  #     user = "vpittamp";
  #     tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  #   };

  # Note: If adding keyd.nix, no additional configuration needed - it's self-contained
}

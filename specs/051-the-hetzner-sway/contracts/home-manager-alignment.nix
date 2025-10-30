# Home Manager Alignment Contract
# Feature: M1 Configuration Alignment with Hetzner-Sway
# This file defines the home-manager structure changes for M1

# CURRENT STATE: M1 uses base-home.nix with 45+ nested imports
# TARGET STATE: Match hetzner-sway's clean 10-import structure in home-vpittamp.nix

{
  # Reference: hetzner-sway home-manager structure
  # File: home-manager/home-vpittamp.nix (hetzner-sway-specific)
  #
  # Key characteristics:
  # - Explicit imports (no nested base-home.nix structure)
  # - Clear separation: desktop apps only, no system services
  # - Easy to identify platform-specific additions
  hetzner_sway_structure = {
    file = "home-manager/home-vpittamp.nix";
    imports = [
      # Desktop applications
      ../home-modules/desktop/sway.nix
      ../home-modules/desktop/walker.nix
      ../home-modules/desktop/sway-config-manager.nix
      ../home-modules/desktop/declarative-cleanup.nix
      ../home-modules/tools/i3pm
      ../home-modules/terminal/tmux.nix
      ../home-modules/shell/bash.nix
      ../home-modules/editors/neovim.nix
      # ... (other explicit imports)
    ];
  };

  # Issue: M1 incorrectly imports i3-project-daemon.nix in home-manager
  # This is a SYSTEM service requiring root access, should NOT be in user configuration
  incorrect_m1_imports = [
    # REMOVE from base-home.nix or M1-specific home-manager:
    # ../modules/services/i3-project-daemon.nix  # This goes in configurations/m1.nix, not home-manager!
  ];

  # Missing from M1 that should be added
  missing_m1_imports = [
    ../home-modules/desktop/declarative-cleanup.nix  # Automatic XDG cleanup
  ];

  # Recommended approach: Simplify M1 home-manager structure
  # Option 1 (RECOMMENDED): Create home-modules/profiles/base.nix with shared imports
  # Option 2: Duplicate hetzner-sway structure with M1-specific additions documented
  # Option 3: Keep base-home.nix but remove incorrect system service imports

  # Implementation Template for Option 1 (Recommended)
  #
  # Step 1: Create home-modules/profiles/base.nix (NEW FILE):
  #
  #   # home-modules/profiles/base.nix
  #   { config, lib, pkgs, ... }:
  #   {
  #     imports = [
  #       # Shell environment
  #       ../shell/bash.nix
  #
  #       # Editors
  #       ../editors/neovim.nix
  #
  #       # Terminal tools
  #       ../terminal/tmux.nix
  #
  #       # Desktop applications (when on Sway/Wayland)
  #       ../desktop/sway.nix
  #       ../desktop/walker.nix
  #       ../desktop/sway-config-manager.nix
  #       ../desktop/declarative-cleanup.nix
  #
  #       # Developer tools
  #       ../tools/i3pm
  #       ../tools/git
  #
  #       # AI assistants
  #       ../ai-assistants/claude.nix
  #       # ... (other shared modules)
  #     ];
  #   }
  #
  # Step 2: Update home-manager/base-home.nix to import profile:
  #
  #   { config, lib, pkgs, ... }:
  #   {
  #     imports = [
  #       ../home-modules/profiles/base.nix  # All shared configuration
  #     ];
  #
  #     # M1-specific overrides (if any)
  #     # ... M1 customizations only
  #   }
  #
  # Step 3: Ensure system services are in configurations/m1.nix, not home-manager
  #
  # Benefits:
  # - Single source of truth for shared home-manager configuration
  # - Clear separation: profiles/base.nix = shared, home-manager/base-home.nix = M1 overrides
  # - Matches hetzner-sway pattern (explicit imports in home-vpittamp.nix)
  # - Easy to identify what's truly M1-specific

  # Implementation Template for Option 3 (Minimal Change)
  #
  # Step 1: Edit home-manager/base-home.nix
  #
  # FIND this line (if it exists):
  #   ../modules/services/i3-project-daemon.nix
  #
  # REMOVE IT - this is a system service, belongs in configurations/m1.nix
  #
  # ADD this import (if missing):
  #   ../home-modules/desktop/declarative-cleanup.nix
  #
  # Verification:
  # - Ensure NO modules/services/* imports in home-manager configuration
  # - Ensure ALL home-modules/* imports are present
  # - Ensure system services (i3-project-daemon) are in configurations/m1.nix

  # Service Configuration Notes:
  #
  # User services (systemd --user) like walker, sway-config-manager are CORRECTLY
  # configured in home-modules/ - these don't need changes.
  #
  # System services (systemd --system) like i3-project-daemon MUST be in
  # configurations/m1.nix because they require:
  # - Root privileges for /proc namespace traversal
  # - System-wide socket access
  # - Integration with system boot sequence
}

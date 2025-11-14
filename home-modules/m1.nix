# Home-manager configuration for M1 MacBook Pro (Feature 051)
# Physical Retina display with Sway, i3pm daemon, walker launcher
{ pkgs, ... }:
{
  imports = [
    # Base home configuration (shell, editors, tools)
    ./profiles/base-home.nix

    # Declarative cleanup (removes backups and stale files before activation)
    ./profiles/declarative-cleanup.nix

    # Desktop Environment: Sway (Wayland)
    ./desktop/python-environment.nix  # Shared Python environment for all modules
    ./desktop/sway.nix         # Sway window manager with HiDPI support
    # sway-easyfocus now provided by home-manager upstream
    ./desktop/unified-bar-theme.nix  # Feature 057: Unified bar theme (Catppuccin Mocha)
    ./desktop/swaybar.nix      # Swaybar with event-driven status
    ./desktop/swaybar-enhanced.nix  # Feature 052: Enhanced swaybar status (battery, network, volume, bluetooth)
    ./desktop/eww-workspace-bar.nix  # SVG workspace bar with icons
    ./desktop/eww-quick-panel.nix     # Feature 057: Quick settings panel (brightness, network, apps)
    ./desktop/eww-top-bar.nix   # Feature 060: Eww top bar with system metrics
    ./desktop/swaync.nix       # Feature 057: SwayNC notification center
    ./desktop/sway-config-manager.nix  # Feature 047: Dynamic configuration management

    # Project management (works with Sway via IPC)
    # NOTE: i3-project-daemon runs as system service (configurations/m1.nix line 29)
    # Home-manager module removed to prevent Python environment conflicts
    ./tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./tools/i3pm-diagnostic.nix       # Feature 039: Diagnostic CLI for troubleshooting
    ./tools/i3pm-workspace-mode-wrapper.nix  # Feature 042: Workspace mode IPC wrapper (temp until TS CLI integration)

    # Application launcher and registry
    ./desktop/walker.nix        # Feature 043: Walker/Elephant launcher (works with Wayland)
    ./desktop/app-registry.nix  # Feature 034: Application registry with desktop files
    ./tools/app-launcher.nix    # Feature 034: Launcher wrapper script and CLI
    ./tools/pwa-launcher.nix    # Dynamic PWA launcher (queries IDs at runtime)

    # Feature 056: Declarative PWA Installation
    ./tools/firefox-pwas-declarative.nix  # TDD-driven declarative PWA management with ULIDs
    ./tools/pwa-helpers.nix               # Helper CLI commands for PWA management
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Feature 046: i3-msg → swaymsg compatibility symlink
  # i3pm CLI uses i3-msg, but Sway uses swaymsg (compatible CLI)
  home.file.".local/bin/i3-msg" = {
    source = "${pkgs.sway}/bin/swaymsg";
    executable = true;
  };

  # Feature 015: i3 project event listener daemon
  # NOTE: Runs as system service (configurations/m1.nix: services.i3ProjectDaemon.enable)
  # Home-manager module removed to prevent Python environment conflicts

  # Feature 047: Sway Dynamic Configuration Management
  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;  # Auto-reload on file changes
    debounceMs = 500;  # Wait 500ms after last change before reloading
  };

  # Feature 052: Enhanced Swaybar Status
  programs.swaybar-enhanced = {
    enable = true;
    # Uses default Catppuccin Mocha theme and standard update intervals
    # Bluetooth status block enabled with click handler to open Blueman Manager
    detectBluetooth = true;
  };

  # Feature 056: Declarative PWA Installation
  programs.firefoxpwa-declarative = {
    enable = true;
  };

  # eww workspace bar with SVG icons
  programs.eww-workspace-bar.enable = true;

  # eww quick settings panel (Feature 057)
  programs.eww-quick-panel.enable = true;

  # eww top bar with system metrics (Feature 060)
  programs.eww-top-bar.enable = true;

  # sway-easyfocus - Keyboard-driven window hints
  programs.sway-easyfocus = {
    enable = true;
    settings = {
      # Hint characters (home row optimized)
      chars = "fjghdkslaemuvitywoqpcbnxz";

      # Catppuccin Mocha theme colors (rrggbb format, no # prefix)
      window_background_color = "1e1e2e";  # Base
      window_background_opacity = 0.3;
      label_background_color = "313244";   # Surface0
      label_text_color = "cdd6f4";         # Text
      focused_background_color = "89b4fa"; # Blue
      focused_text_color = "1e1e2e";       # Base

      # Font settings
      font_family = "monospace";
      font_weight = "bold";
      font_size = "18pt";

      # Spacing
      label_padding_x = 8;
      label_padding_y = 4;
      label_margin_x = 4;
      label_margin_y = 4;

      # No confirmation window
      show_confirmation = false;
    };
  };
}

# Home-manager configuration for Acer Swift Go 16
# Physical laptop display with Sway, i3pm daemon, walker launcher
{ pkgs, ... }:
{
  imports = [
    # Base home configuration (shell, editors, tools)
    ./profiles/base-home.nix

    # Declarative cleanup (removes backups and stale files before activation)
    ./profiles/declarative-cleanup.nix

    # Desktop Environment: Sway (Wayland)
    ./desktop/python-environment.nix
    ./desktop/sway.nix
    ./desktop/unified-bar-theme.nix
    ./desktop/eww-workspace-bar.nix
    ./desktop/eww-quick-panel.nix
    ./desktop/eww-top-bar.nix
    ./desktop/eww-monitoring-panel.nix
    ./desktop/swaync.nix
    ./desktop/sway-config-manager.nix

    # Project management (works with Sway via IPC)
    ./tools/i3pm-deno.nix
    ./tools/i3pm-diagnostic.nix
    ./tools/i3pm-workspace-mode-wrapper.nix

    # Application launcher and registry
    ./desktop/walker.nix
    ./desktop/app-registry.nix
    ./tools/app-launcher.nix
    ./tools/pwa-launcher.nix

    # Declarative PWA Installation
    ./tools/firefox-pwas-declarative.nix
    ./tools/pwa-helpers.nix
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # i3-msg → swaymsg compatibility symlink
  home.file.".local/bin/i3-msg" = {
    source = "${pkgs.sway}/bin/swaymsg";
    executable = true;
  };

  # Sway Dynamic Configuration Management
  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;
    debounceMs = 500;
  };

  # Declarative PWA Installation
  programs.firefoxpwa-declarative = {
    enable = true;
  };

  # eww workspace bar with SVG icons
  programs.eww-workspace-bar.enable = true;

  # eww quick settings panel
  programs.eww-quick-panel.enable = true;

  # eww top bar with system metrics
  programs.eww-top-bar.enable = true;

  # eww monitoring panel
  programs.eww-monitoring-panel.enable = true;

  # sway-easyfocus - Keyboard-driven window hints
  programs.sway-easyfocus = {
    enable = true;
    settings = {
      # Hint characters (home row optimized)
      chars = "fjghdkslaemuvitywoqpcbnxz";

      # Catppuccin Mocha theme colors
      window_background_color = "1e1e2e";
      window_background_opacity = 0.3;
      label_background_color = "313244";
      label_text_color = "cdd6f4";
      focused_background_color = "89b4fa";
      focused_text_color = "1e1e2e";

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

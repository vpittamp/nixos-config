# Home-manager configuration for AMD Ryzen Desktop
# Desktop with Sway, i3pm daemon, walker launcher
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

  # WayVNC configuration for remote access over Tailscale
  # Desktop typically uses DP-1 or HDMI-A-1 - adjust based on your setup
  xdg.configFile."wayvnc/config".text = ''
    # WayVNC configuration for Ryzen Desktop
    # Access via: vnc://<tailscale-ip>:5900 (Tailscale IP)
    address=0.0.0.0
    enable_auth=false
  '';

  # WayVNC systemd user service
  # Note: Adjust output (-o flag) based on your monitor setup
  # Common NVIDIA outputs: DP-1, HDMI-A-1, DP-2
  # Run 'swaymsg -t get_outputs' to see available outputs
  systemd.user.services.wayvnc = {
    Unit = {
      Description = "WayVNC - VNC server for Wayland (Ryzen Desktop)";
      Documentation = "man:wayvnc(1)";
      After = [ "sway-session.target" ];
      BindsTo = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      # Dynamically detect primary output (DP-1 preferred, fallback to first available)
      ExecStart = "${pkgs.writeShellScript "wayvnc-start" ''
        OUTPUT=$(${pkgs.sway}/bin/swaymsg -t get_outputs -r | ${pkgs.jq}/bin/jq -r '.[0].name // "DP-1"')
        exec ${pkgs.wayvnc}/bin/wayvnc -o "$OUTPUT" 0.0.0.0 5900
      ''}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}

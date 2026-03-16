# Home-manager configuration for Lenovo ThinkPad
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
    ./desktop/quickshell-runtime-shell.nix
    ./desktop/quickshell-worktree-app.nix
    ./desktop/swaync.nix
    ./desktop/sway-config-manager.nix

    # Project management (works with Sway via IPC)
    # Feature 117: i3-project-daemon now runs as user service
    ./services/i3-project-daemon.nix
    ./services/otel-ai-monitor.nix    # Feature 123: OTEL-based AI session monitoring
    ./tools/i3pm-deno.nix
    ./tools/i3pm-diagnostic.nix
    # Application launcher and registry
    ./desktop/walker.nix
    ./desktop/app-registry.nix
    ./tools/pwa-launcher.nix

    # Declarative PWA Installation

    ./tools/pwa-helpers.nix
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # i3-msg → swaymsg compatibility symlink
  home.file.".local/bin/i3-msg" = {
    source = "${pkgs.sway}/bin/swaymsg";
    executable = true;
  };

  # Feature 117: i3 project event listener daemon (user service)
  programs.i3-project-daemon = {
    enable = true;
    logLevel = "DEBUG";  # Temporary for testing
  };

  # Feature 123: OTEL AI assistant monitor service
  # Receives forwarded telemetry from OTEL Collector on port 4320
  # Collector receives from Claude Code on 4318, forwards here for session aggregation
  services.otel-ai-monitor = {
    enable = true;
    port = 4320;  # Non-standard port (collector uses 4318)
    verbose = true;  # Enable debug logging to trace event parsing
    enableNotifications = false;  # Suppress "Claude Code Ready" alerts
    remoteSink.enable = true;
    remotePush = {
      enable = true;
      url = "http://ryzen:4320/v1/i3pm/remote-sessions";
      connectionKey = "vpittamp@thinkpad:22";
      hostName = "thinkpad";
    };
  };

  # Sway Dynamic Configuration Management
  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;
    debounceMs = 500;
  };

  # Declarative PWA Installation


  programs.quickshell-runtime-shell = {
    enable = true;
  };

  programs.quickshell-worktree-app.enable = true;

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
  xdg.configFile."wayvnc/config".text = ''
    # WayVNC configuration for ThinkPad
    # Access via: vnc://<tailscale-ip>:5900 (Tailscale IP)
    address=0.0.0.0
    enable_auth=false
  '';

  # WayVNC systemd user service
  systemd.user.services.wayvnc = {
    Unit = {
      Description = "WayVNC - VNC server for Wayland (ThinkPad eDP-1)";
      Documentation = "man:wayvnc(1)";
      After = [ "sway-session.target" ];
      BindsTo = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o eDP-1 0.0.0.0 5900";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}

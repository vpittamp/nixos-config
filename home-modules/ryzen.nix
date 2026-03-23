# Home-manager configuration for AMD Ryzen Desktop
# 4-monitor bare-metal setup with NVIDIA RTX 5070
# Desktop with Sway, i3pm daemon, walker launcher
{ pkgs, ... }:
let
  rustdeskStop = pkgs.writeShellScript "rustdesk-stop" ''
    ${pkgs.procps}/bin/pkill -f 'rustdesk --tray' >/dev/null 2>&1 || true
    ${pkgs.procps}/bin/pkill -f 'rustdesk --server' >/dev/null 2>&1 || true
  '';
  sunshineWebUi = pkgs.writeShellScriptBin "sunshine-web-ui" ''
    set -euo pipefail

    profile_dir="$HOME/.local/share/webapps/SunshineWebUI"
    mkdir -p "$profile_dir"

    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --user-data-dir="$profile_dir" \
      --class=SunshineWebUI \
      --app=https://localhost:47990 \
      --new-window \
      --no-first-run \
      --no-default-browser-check \
      --password-store=basic \
      --allow-insecure-localhost
  '';
in
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
    ./tools/disk-guardrails.nix
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

  home.packages = [ sunshineWebUi ];

  # Feature 117: i3 project event listener daemon (user service)
  programs.i3-project-daemon = {
    enable = true;
    logLevel = "DEBUG";  # Temporary for testing
  };

  programs.disk-guardrails.enable = true;

  # Feature 123: OTEL AI assistant monitor service
  # Receives forwarded telemetry from OTEL Collector on port 4320
  # Collector receives from Claude Code on 4318, forwards here for session aggregation
  services.otel-ai-monitor = {
    enable = true;
    port = 4320;  # Non-standard port (collector uses 4318)
    enableNotifications = false;
    remoteSink.enable = true;
    remotePush = {
      enable = true;
      url = "http://thinkpad:4320/v1/i3pm/remote-sessions";
      connectionKey = "vpittamp@ryzen:22";
      hostName = "ryzen";
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
    accentColor = "#c4b5fd";
    accentBg = "#241b43";
    accentMuted = "#8b7bb5";
    accentWash = "#1e1639";
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

  # Sunshine NVENC drop-in configuration
  # Adds NVIDIA library path for CUDA/NVENC hardware encoding
  xdg.configFile."systemd/user/sunshine.service.d/nvidia.conf".text = ''
    [Service]
    Environment="LD_LIBRARY_PATH=/run/opengl-driver/lib"
  '';

  # RustDesk direct-access host for the logged-in Sway session.
  systemd.user.services.rustdesk = {
    Unit = {
      Description = "RustDesk host session";
      Documentation = "https://rustdesk.com/docs/";
      After = [ "sway-session.target" "network.target" ];
      BindsTo = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.rustdesk}/bin/rustdesk --server";
      ExecStop = rustdeskStop;
      Restart = "on-failure";
      RestartSec = "5s";
      KillMode = "mixed";
      Environment = [
        "PULSE_LATENCY_MSEC=60"
        "PIPEWIRE_LATENCY=1024/48000"
      ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}

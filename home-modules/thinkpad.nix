# Home-manager configuration for Lenovo ThinkPad
# Physical laptop display with Sway, i3pm daemon, walker launcher
{ lib, pkgs, ... }:
let
  gameStreaming = import ../shared/game-streaming.nix;
  ryzenSunshineHost = gameStreaming.sunshineHosts.ryzen;
  qSettingsByteArray = value:
    "\"@ByteArray(${lib.replaceStrings [ "\\" "\n" "\"" ] [ "\\\\" "\\n" "\\\"" ] value})\"";
  ryzenMoonlightServerCert = qSettingsByteArray ryzenSunshineHost.certificate;
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

  home.activation.ensureMoonlightRyzenHost = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_dir="$HOME/.config/Moonlight Game Streaming Project"
    config_file="$config_dir/Moonlight.conf"
    tmp_file="$(mktemp)"

    mkdir -p "$config_dir"

    if [ -f "$config_file" ]; then
      ${pkgs.gawk}/bin/awk '
        BEGIN {
          general_seen = 0
        }
        /^\[hosts\]$/ {
          if (!general_seen) {
            print "[General]"
            print "abstouchmode=false"
          }
          exit
        }
        /^\[General\]$/ {
          general_seen = 1
          print
          print "abstouchmode=false"
          next
        }
        /^abstouchmode=/ {
          next
        }
        { print }
      ' "$config_file" > "$tmp_file"
    else
      cat > "$tmp_file" <<'EOF'
[General]
abstouchmode=false
EOF
    fi

    cat >> "$tmp_file" <<'EOF'

[hosts]
1\customname=false
1\hostname=ryzen
1\ipv6address=
1\ipv6port=0
1\localaddress=ryzen
1\localport=47989
1\mac=@ByteArray()
1\manualaddress=ryzen
1\manualport=47989
1\nvidiasw=false
1\remoteaddress=
1\remoteport=0
1\srvcert=${ryzenMoonlightServerCert}
1\uuid=${ryzenSunshineHost.uniqueId}
size=1
EOF

    if [ ! -f "$config_file" ] || ! ${pkgs.diffutils}/bin/cmp -s "$tmp_file" "$config_file"; then
      mv "$tmp_file" "$config_file"
      chmod 600 "$config_file"
    else
      rm -f "$tmp_file"
    fi
  '';

  # Feature 117: i3 project event listener daemon (user service)
  programs.i3-project-daemon = {
    enable = true;
    logLevel = "DEBUG";  # Temporary for testing
  };

  # Use the shared hybrid display path so the ThinkPad can expose a virtual second monitor.
  programs.sway-profile.mode = "hybrid";

  programs.disk-guardrails.enable = true;

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

  wayland.windowManager.sway.config.window.commands = lib.mkAfter [
    {
      criteria = { app_id = "com.moonlight_stream.Moonlight"; };
      command = "border pixel 0, fullscreen enable";
    }
  ];

  # Mod+Escape exits Moonlight fullscreen even with capture-system-keys
  wayland.windowManager.sway.extraConfig = ''
    bindsym --inhibited Mod4+Escape [app_id="com.moonlight_stream.Moonlight"] fullscreen disable
  '';

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

}

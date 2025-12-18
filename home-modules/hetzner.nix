# Home-manager configuration for Hetzner Cloud Sway (Feature 046)
# Headless Wayland with Sway, VNC remote access, i3pm daemon, walker launcher
{ pkgs, lib, ... }:
let
  # Custom package: Google Antigravity (Linux x86_64)
  antigravity = pkgs.stdenv.mkDerivation rec {
    pname = "antigravity";
    version = "1.11.2-6251250307170304";

    src = pkgs.fetchurl {
      url = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${version}/linux-x64/Antigravity.tar.gz";
      sha256 = "1dv4bx598nshjsq0d8nnf8zfn86wsbjf2q56dqvmq9vcwxd13cfi";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.wrapGAppsHook3 ];
    buildInputs = [
      pkgs.atk pkgs.glib pkgs.gtk3 pkgs.nss pkgs.cups pkgs.alsa-lib
      pkgs.libsecret pkgs.libdrm pkgs.libxkbcommon pkgs.pango
      pkgs.libxkbfile pkgs.mesa
      pkgs.xorg.libX11 pkgs.xorg.libxcb pkgs.xorg.libXcomposite
      pkgs.xorg.libXdamage pkgs.xorg.libXext pkgs.xorg.libXfixes
      pkgs.xorg.libXi pkgs.xorg.libXtst pkgs.xorg.libXScrnSaver
    ];

    unpackPhase = ''mkdir source; tar xzf $src --strip-components=1 -C source'';

    installPhase = ''
      mkdir -p $out/opt/antigravity $out/bin \
               $out/share/applications $out/share/icons/hicolor/512x512/apps

      cp -r source/* $out/opt/antigravity

      cat > $out/bin/antigravity <<EOF
      #!${pkgs.runtimeShell}
      # Use Firefox for OAuth - handles custom URL schemes better than Chromium
      export BROWSER=${pkgs.firefox}/bin/firefox
      exec "$out/opt/antigravity/antigravity" --no-sandbox "\$@"
      EOF
      chmod +x $out/bin/antigravity

      cat > $out/share/applications/antigravity.desktop <<'EOF'
      [Desktop Entry]
      Name=Antigravity
      Exec=antigravity %U
      Terminal=false
      Type=Application
      Icon=antigravity
      Categories=Development;IDE;
      MimeType=x-scheme-handler/antigravity;
      EOF

      # URL handler for OAuth callbacks
      cat > $out/share/applications/antigravity-url-handler.desktop <<'EOF'
      [Desktop Entry]
      Name=Antigravity - URL Handler
      Exec=antigravity %U
      Terminal=false
      Type=Application
      Icon=antigravity
      NoDisplay=true
      MimeType=x-scheme-handler/antigravity;
      StartupWMClass=Antigravity
      EOF

      cp source/resources/app/resources/linux/code.png \
         $out/share/icons/hicolor/512x512/apps/antigravity.png
    '';
  };
in
{
  imports = [
    # Base home configuration (shell, editors, tools)
    ./profiles/base-home.nix

    # Declarative cleanup (removes backups and stale files before activation)
    ./profiles/declarative-cleanup.nix

    # Desktop Environment: Sway (Wayland)
    ./desktop/python-environment.nix  # Shared Python environment for all modules
    ./desktop/sway.nix         # Sway window manager with headless support
    # sway-easyfocus now provided by home-manager upstream
    ./desktop/unified-bar-theme.nix  # Feature 057: Unified bar theme (Catppuccin Mocha)
    # ./desktop/swaybar.nix      # Swaybar with event-driven status (DISABLED: replaced by eww-top-bar Feature 060)
    # ./desktop/swaybar-enhanced.nix  # Feature 052: Enhanced swaybar status (DISABLED: replaced by eww-top-bar Feature 060)
    ./desktop/eww-workspace-bar.nix  # SVG workspace bar replacing bottom swaybar
    ./desktop/eww-quick-panel.nix     # Feature 057: Quick settings panel (network, apps, system controls)
    ./desktop/eww-top-bar.nix  # Feature 060: Eww top bar with system metrics
    ./desktop/eww-monitoring-panel.nix  # Feature 085: Live window/project monitoring panel
    ./desktop/swaync.nix       # Feature 057: SwayNC notification center
    ./desktop/sway-config-manager.nix  # Feature 047: Dynamic configuration management

    # Project management (works with Sway via IPC)
    # Feature 117: i3-project-daemon now runs as user service
    ./services/i3-project-daemon.nix  # Feature 117: User-level daemon service
    ./services/otel-ai-monitor.nix    # Feature 123: OTEL-based AI session monitoring
    ./tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./tools/i3pm-diagnostic.nix       # Feature 039: Diagnostic CLI for troubleshooting
    ./tools/i3pm-workspace-mode-wrapper.nix  # Feature 042: Workspace mode IPC wrapper (temp until TS CLI integration)

    # Application launcher and registry
    ./desktop/walker.nix        # Feature 043: Walker/Elephant launcher (works with software rendering)
    ./desktop/app-registry.nix  # Feature 034: Application registry with desktop files
    ./tools/app-launcher.nix    # Feature 034: Launcher wrapper script and CLI
    ./tools/pwa-launcher.nix    # Dynamic PWA launcher (queries IDs at runtime)

    # Feature 056: Declarative PWA Installation
    ./tools/firefox-pwas-declarative.nix  # TDD-driven declarative PWA management with ULIDs
    ./tools/pwa-helpers.nix               # Helper CLI commands for PWA management

    # Feature 121: Stale socket cleanup
    ./tools/sway-socket-cleanup           # Automatic cleanup of orphaned Sway IPC sockets
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Add gnome-keyring for D-Bus secrets service (needed for Goose auth)
  home.packages = with pkgs; [
    gnome-keyring
    libsecret  # For secret-tool CLI
    antigravity
  ];

  # Enable gnome-keyring service for org.freedesktop.secrets
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];  # Only secrets, not ssh/pkcs11
  };

  # Feature 046: i3-msg → swaymsg compatibility symlink
  # i3pm CLI uses i3-msg, but Sway uses swaymsg (compatible CLI)
  home.file.".local/bin/i3-msg" = {
    source = "${pkgs.sway}/bin/swaymsg";
    executable = true;
  };

  # Provide a swaymsg wrapper that auto-discovers the IPC socket when run over SSH
  home.file.".local/bin/swaymsg" = {
    text = ''
      #!/usr/bin/env bash
      if [ -z "$SWAYSOCK" ]; then
        socket="$(${pkgs.sway}/bin/sway --get-socketpath 2>/dev/null || true)"
        if [ -n "$socket" ]; then
          export SWAYSOCK="$socket"
        fi
      fi
      exec ${pkgs.sway}/bin/swaymsg "$@"
    '';
    executable = true;
  };

  # Feature 117: i3 project event listener daemon (user service)
  # Converted from system service (Feature 037) to user service for better session integration
  programs.i3-project-daemon = {
    enable = true;
    logLevel = "DEBUG";  # Temporary for testing
  };

  # Feature 121: Automatic cleanup of stale Sway IPC sockets every 5 minutes
  programs.sway-socket-cleanup.enable = true;

  # Feature 123: OTEL AI assistant monitor service
  # Receives OTLP telemetry from Claude Code and Codex CLI
  # (services.otel-ai-monitor.enable = true is set below)

  # Feature 047: Sway Dynamic Configuration Management
  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;  # Auto-reload on file changes
    debounceMs = 500;  # Wait 500ms after last change before reloading
  };

  # Feature 052: Enhanced Swaybar Status (DISABLED: replaced by eww-top-bar Feature 060)
  # programs.swaybar-enhanced = {
  #   enable = true;
  #   # Uses default Catppuccin Mocha theme and standard update intervals
  # };

  programs.eww-workspace-bar.enable = true;

  # eww quick settings panel (Feature 057)
  programs.eww-quick-panel.enable = true;

  # Eww top bar with system metrics (Feature 060)
  programs.eww-top-bar.enable = true;

  # Live window/project monitoring panel (Feature 085)
  programs.eww-monitoring-panel.enable = true;  # Toggle with Mod+m

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

  # Feature 056: Declarative PWA Installation
  programs.firefoxpwa-declarative = {
    enable = true;
  };

  # Override default browser to Chromium for better OAuth/authentication support
  # (Goose and other apps that need browser auth work better with Chromium)
  home.sessionVariables = {
    BROWSER = lib.mkForce "chromium";
  };

  # Feature 123: OTEL AI assistant monitor service
  # Receives forwarded telemetry from OTEL Collector on port 4320
  # Collector receives from Claude Code on 4318, forwards here for session aggregation
  services.otel-ai-monitor = {
    enable = true;
    port = 4320;  # Non-standard port (collector uses 4318)
  };
}

# Home-manager configuration for Microsoft Surface Laptop 2
# Physical laptop display with Sway, i3pm daemon, walker launcher.
# Mirrors home-modules/thinkpad.nix, minus the Ryzen-streaming client bits
# (Moonlight config seeding, Moonlight window rules). The herdr-ryzen remote
# target is configured like the thinkpad (daemon aggregation + registry app).
{ lib, pkgs, ... }:

{
  imports = [
    # Base home configuration (shell, editors, tools)
    ./profiles/base-home.nix

    # Declarative cleanup (removes backups and stale files before activation)
    ./profiles/declarative-cleanup.nix

    # Desktop Environment: Sway (Wayland)
    ./desktop/python-environment.nix
    ./desktop/sway.nix
    ./desktop/casting.nix
    ./desktop/quickshell-runtime-shell.nix

    # Project management (works with Sway via IPC)
    # Feature 117: i3-project-daemon now runs as user service
    ./services/i3-project-daemon.nix
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

  # Feature 117: i3 project event listener daemon (user service)
  programs.i3-project-daemon = {
    enable = true;
    logLevel = "INFO";
    # Same remote herdr aggregation as the thinkpad: ryzen rows map to the
    # herdr-ryzen registry app (Ghostty window with app-id com.herdr.ryzen).
    herdrRemoteTargets = [
      {
        host = "ryzen";
        ssh_target = "ryzen";
        connection_key = "vpittamp@ryzen:22";
      }
      {
        host = "surface-pro3";
        ssh_target = "surface-pro";  # Tailscale MagicDNS name; "surface-pro3" does not resolve
        connection_key = "vpittamp@surface-pro3:22";
      }
      {
        host = "thinkpad";
        ssh_target = "thinkpad";
        connection_key = "vpittamp@thinkpad:22";
      }
    ];
  };

  # Plain laptop profile: the built-in panel plus EDID-recognized physical
  # externals (managed by lid-clamshell).
  programs.sway-profile.mode = "laptop";

  programs.disk-guardrails.enable = true;

  # Declarative PWA Installation

  programs.quickshell-runtime-shell = {
    # Evaluating the Omarchy palettes here first (see themes.nix); the other
    # hosts stay on zinc-dark until this is rolled out.
    theme = "tokyo-night";
    enable = true;
    # Overlay toasts re-enabled 2026-08: the redesigned toast stack (hover-pause,
    # swipe-dismiss, animated, per-id stable) replaced the old static cards whose
    # timers reset on every feed change. Default limit is 4 per output.
  };

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

# Home-manager configuration for Microsoft Surface Pro 3
# Trimmed sibling of home-modules/surface.nix: keeps the Sway + Quickshell
# desktop, drops the PWA tooling (the system config omits Chrome and its four
# policy modules, so there is nothing for pwa-install-all to install into).
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
    ./desktop/quickshell-runtime-shell.nix

    # Project management (works with Sway via IPC)
    ./services/i3-project-daemon.nix
    ./tools/i3pm-deno.nix
    ./tools/i3pm-diagnostic.nix
    ./tools/disk-guardrails.nix

    # Application launcher and registry
    ./desktop/walker.nix
    ./desktop/app-registry.nix

    # Declarative PWA installation. Restored alongside the chrome-* policy
    # modules in configurations/surface-pro3.nix — without these, those modules
    # would push managed bookmarks for PWAs that have no launcher.
    ./tools/pwa-launcher.nix
    ./tools/pwa-helpers.nix
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # i3-msg → swaymsg compatibility symlink
  home.file.".local/bin/i3-msg" = {
    source = "${pkgs.sway}/bin/swaymsg";
    executable = true;
  };

  # i3 project event listener daemon (user service). Same remote herdr
  # aggregation as the thinkpad and Laptop 2: ryzen rows map to the herdr-ryzen
  # registry app.
  programs.i3-project-daemon = {
    enable = true;
    logLevel = "INFO";
    herdrRemoteTargets = [
      {
        host = "ryzen";
        ssh_target = "ryzen";
        connection_key = "vpittamp@ryzen:22";
      }
      {
        host = "thinkpad";
        ssh_target = "thinkpad";
        connection_key = "vpittamp@thinkpad:22";
      }
    ];
  };

  # Laptop profile with clamshell-default policy (lid-clamshell): this host is
  # permanently docked, so a connected, enabled external display is always the
  # sole monitor and the built-in panel never displays output. The panel only
  # comes on when no external is connected.
  programs.sway-profile.mode = "laptop";

  programs.disk-guardrails.enable = true;

  programs.quickshell-runtime-shell = {
    enable = true;
    notifications.toastMaxPerOutput = 0;
  };

  # sway-easyfocus - Keyboard-driven window hints
  programs.sway-easyfocus = {
    enable = true;
    settings = {
      chars = "fjghdkslaemuvitywoqpcbnxz";

      # Catppuccin Mocha theme colors
      window_background_color = "1e1e2e";
      window_background_opacity = 0.3;
      label_background_color = "313244";
      label_text_color = "cdd6f4";
      focused_background_color = "89b4fa";
      focused_text_color = "1e1e2e";

      font_family = "monospace";
      font_weight = "bold";
      font_size = "18pt";

      label_padding_x = 8;
      label_padding_y = 4;
      label_margin_x = 4;
      label_margin_y = 4;

      show_confirmation = false;
    };
  };
}

# Home-manager configuration for Hetzner Cloud Sway (Feature 046)
# Headless Wayland with Sway, VNC remote access, i3pm daemon, Walker launcher
{ pkgs, ... }:
{
  imports = [
    # Base home configuration (shell, editors, tools)
    ./profiles/base-home.nix

    # Desktop Environment: Sway (Wayland)
    ./desktop/sway.nix         # Sway window manager with headless support
    ./desktop/swaybar.nix      # Swaybar with event-driven status

    # Project management (works with Sway via IPC)
    ./desktop/i3-project-daemon.nix   # Feature 015: Event-driven daemon (Sway-compatible)
    ./tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./tools/i3pm-diagnostic.nix       # Feature 039: Diagnostic CLI for troubleshooting

    # Application launcher and registry (Wayland-native)
    ./desktop/walker.nix        # Feature 043: Walker/Elephant launcher (Wayland-compatible)
    ./desktop/app-registry.nix  # Feature 034: Application registry with desktop files
    ./tools/app-launcher.nix    # Feature 034: Launcher wrapper script and CLI
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
  # NOTE: Disabled in favor of system service (Feature 037 - cross-namespace /proc access)
  # System service configured in configurations/hetzner-sway.nix: services.i3ProjectDaemon.enable
  services.i3ProjectEventListener = {
    enable = false;  # Disabled - using system service instead
  };
}

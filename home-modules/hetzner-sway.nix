# Home-manager configuration for Hetzner Cloud Sway (Feature 046)
# Headless Wayland with Sway, VNC remote access, i3pm daemon, walker launcher
{ pkgs, ... }:
{
  imports = [
    # Base home configuration (shell, editors, tools)
    ./profiles/base-home.nix

    # Declarative cleanup (removes backups and stale files before activation)
    ./profiles/declarative-cleanup.nix

    # Desktop Environment: Sway (Wayland)
    ./desktop/python-environment.nix  # Shared Python environment for all modules
    ./desktop/sway.nix         # Sway window manager with headless support
    ./desktop/swaybar.nix      # Swaybar with event-driven status
    ./desktop/swaybar-enhanced.nix  # Feature 052: Enhanced swaybar status (system monitoring + rich indicators)
    ./desktop/sway-config-manager.nix  # Feature 047: Dynamic configuration management

    # Project management (works with Sway via IPC)
    # NOTE: i3-project-daemon runs as system service (configurations/hetzner-sway.nix line 126)
    # Home-manager module removed to prevent Python environment conflicts
    ./tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./tools/i3pm-diagnostic.nix       # Feature 039: Diagnostic CLI for troubleshooting
    ./tools/i3pm-workspace-mode-wrapper.nix  # Feature 042: Workspace mode IPC wrapper (temp until TS CLI integration)

    # Application launcher and registry
    ./desktop/walker.nix        # Feature 043: Walker/Elephant launcher (works with software rendering)
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
  # NOTE: Runs as system service (configurations/hetzner-sway.nix: services.i3ProjectDaemon.enable)
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
  };
}

# Sway Wayland Compositor Home Manager Configuration
# Parallel to i3.nix - adapted for Wayland on M1 MacBook Pro
# Works with Sway native Wayland session (no XRDP)
#
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                  CONFIGURATION MANAGEMENT ARCHITECTURE                       ║
# ║                    (Feature 047 - User Story 2)                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This module provides NIX-MANAGED (static) Sway configuration.
# For runtime-managed (hot-reloadable) settings, use the dynamic config system.
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ CONFIGURATION PRECEDENCE (from lowest to highest priority):                 │
# │                                                                              │
# │  1. Nix Config (this file)         → System defaults, stable settings       │
# │  2. Runtime Config                  → ~/.config/sway/*.{toml,json}          │
# │  3. Project Overrides               → ~/.config/sway/projects/<name>.json   │
# │                                                                              │
# │ Higher precedence levels override lower ones. Runtime changes take effect   │
# │ via `i3pm config reload` without NixOS rebuild.                             │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ DECISION TREE: Where should I put my configuration?                         │
# │                                                                              │
# │ ┌─ Is this setting system-wide and STABLE (rarely changes)?                 │
# │ │                                                                            │
# │ ├─ YES → Use this Nix file                                                  │
# │ │  Examples:                                                                │
# │ │    • Package installation (pkgs.sway, pkgs.terminal)                      │
# │ │    • Service configuration (systemd units, startup commands)              │
# │ │    • Display/output configuration (resolution, scaling)                   │
# │ │    • Base keybindings that never change (Mod+Return for terminal)         │
# │ │                                                                            │
# │ └─ NO → Does it CHANGE FREQUENTLY during development/testing?               │
# │    │                                                                         │
# │    ├─ YES → Use runtime config (hot-reloadable)                             │
# │    │  Location: ~/.config/sway/keybindings.toml or window-rules.json        │
# │    │  Command: i3pm config reload (no rebuild needed!)                      │
# │    │  Examples:                                                             │
# │    │    • Custom keybindings you're experimenting with                      │
# │    │    • Window rules for floating/sizing/positioning                      │
# │    │    • Workspace-to-output assignments (if you have multiple monitors)   │
# │    │                                                                         │
# │    └─ NO → Does it apply ONLY to specific projects?                         │
# │       │                                                                      │
# │       └─ YES → Use project overrides                                        │
# │          Location: ~/.config/sway/projects/<project-name>.json              │
# │          Command: pswitch <project> (auto-applies overrides)                │
# │          Examples:                                                          │
# │            • Project-specific keybindings (Mod+n → edit project file)       │
# │            • Project-aware window rules (calculator bigger in data-science) │
# │            • Workspace layouts for specific workflows                       │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ WHAT'S IN THIS FILE (Nix-managed):                                          │
# │                                                                              │
# │  ✓ Package installation (sway, terminal emulator, compositor packages)      │
# │  ✓ System services (daemon startup, systemd units)                          │
# │  ✓ Display configuration (resolution, scaling, output setup)                │
# │  ✓ Input devices (touchpad, keyboard base settings)                         │
# │  ✓ Base keybindings (stable shortcuts that never change)                    │
# │  ✓ Essential window rules (for system UI like walker, fzf)                  │
# │  ✓ Startup commands (service initialization)                                │
# │  ✓ Bar configuration (swaybar via separate module)                          │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ WHAT'S NOT IN THIS FILE (Runtime-managed via Feature 047):                  │
# │                                                                              │
# │  ✗ Custom user keybindings         → ~/.config/sway/keybindings.toml        │
# │  ✗ User window rules                → ~/.config/sway/window-rules.json      │
# │  ✗ Workspace assignments            → ~/.config/sway/workspace-assignments. │
# │  ✗ Project-specific overrides       → ~/.config/sway/projects/*.json        │
# │  ✗ Color schemes (user preference)  → Runtime config                        │
# │  ✗ Font size tweaks                 → Runtime config                        │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ HOW TO MODIFY SETTINGS:                                                      │
# │                                                                              │
# │ For Nix-managed settings (this file):                                       │
# │   1. Edit this file: nvim /etc/nixos/home-modules/desktop/sway.nix          │
# │   2. Test: sudo nixos-rebuild dry-build --flake .#m1                         │
# │   3. Apply: sudo nixos-rebuild switch --flake .#m1 --impure                  │
# │   4. Restart Sway (Mod+Shift+r) to apply changes                             │
# │                                                                              │
# │ For runtime-managed settings (Feature 047):                                 │
# │   1. Edit config: i3pm config edit keybindings  (or manual)                 │
# │   2. Validate: i3pm config validate                                          │
# │   3. Apply: i3pm config reload  (changes take effect immediately!)           │
# │   4. Rollback if needed: i3pm config rollback <commit-hash>                  │
# │                                                                              │
# │ See documentation: /etc/nixos/specs/047-create-a-new/quickstart.md          │
# └─────────────────────────────────────────────────────────────────────────────┘
#
{ config, lib, pkgs, osConfig ? null, ... }:

let
  # Detect headless Sway configuration (Feature 046)
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";
in
{
  # Sway window manager configuration via home-manager
  wayland.windowManager.sway = {
    enable = true;
    package = pkgs.sway;

    # Sway uses identical config syntax to i3 (FR-023)
    config = {
      # Modifier key (Mod4 = Super/Command key on Mac)
      modifier = "Mod4";

      # Terminal (Meta+Return) - using app-launcher-wrapper for project context (Feature 046)
      terminal = "~/.local/bin/app-launcher-wrapper.sh terminal";

      # Application menu (Meta+D) - walker works with software rendering (GSK_RENDERER=cairo)
      menu = "walker";

      # Font with Font Awesome icons
      fonts = {
        names = [ "monospace" "Font Awesome 6 Free" ];
        size = 10.0;
      };

      # Border settings - no borders for clean appearance
      window = {
        border = 0;
        titlebar = false;
      };

      floating = {
        border = 0;
        titlebar = false;
      };

      # Output configuration (FR-005, FR-006)
      # Conditional configuration for headless vs physical displays
      output = if isHeadless then {
        # Headless Wayland - SINGLE output for VNC (Feature 046)
        # VNC can only show one output at a time, so use single HEADLESS-1
        # Resolution: 1920x1080 for better picture quality (sharper text, less VNC scaling blur)
        # Note: Multi-monitor VNC setup requires running multiple wayvnc instances on different ports
        "HEADLESS-1" = {
          resolution = "1920x1080@60Hz";
          position = "0,0";
          scale = "1.0";
        };
      } else {
        # M1 MacBook Pro physical displays
        "eDP-1" = {
          scale = "2.0";                    # 2x scaling for Retina
          resolution = "2560x1600@60Hz";    # Native resolution
          position = "0,0";
        };

        # External monitor (auto-detect, 1:1 scaling)
        "HDMI-A-1" = {
          scale = "1.0";
          mode = "1920x1080@60Hz";
          position = "1280,0";  # Right of built-in (1280 = 2560/2)
        };
      };

      # Input configuration (FR-006)
      input = {
        # Touchpad configuration for M1 MacBook Pro
        "type:touchpad" = {
          natural_scroll = "enabled";   # Natural scrolling
          tap = "enabled";               # Tap-to-click
          tap_button_map = "lrm";        # Two-finger right-click
          dwt = "enabled";               # Disable while typing
          middle_emulation = "enabled";  # Three-finger middle-click
        };

        # Keyboard configuration
        "type:keyboard" = {
          xkb_layout = "us";
          repeat_delay = "300";
          repeat_rate = "50";
        };
      };

      # Workspace definitions with Font Awesome icons (parallel to i3 config)
      workspaceOutputAssign = if isHeadless then [
        # Headless mode: All workspaces on single HEADLESS-1 output (Feature 046)
        # VNC can only show one output at a time
        { workspace = "1"; output = "HEADLESS-1"; }
        { workspace = "2"; output = "HEADLESS-1"; }
        { workspace = "3"; output = "HEADLESS-1"; }
        { workspace = "4"; output = "HEADLESS-1"; }
        { workspace = "5"; output = "HEADLESS-1"; }
        { workspace = "6"; output = "HEADLESS-1"; }
        { workspace = "7"; output = "HEADLESS-1"; }
        { workspace = "8"; output = "HEADLESS-1"; }
        { workspace = "9"; output = "HEADLESS-1"; }
      ] else [
        # M1 MacBook Pro: default assignments (overridden by i3pm monitors reassign)
        { workspace = "1"; output = "eDP-1"; }
        { workspace = "2"; output = "eDP-1"; }
        { workspace = "3"; output = "HDMI-A-1"; }
      ];

      # ═══════════════════════════════════════════════════════════════════════════
      # KEYBINDINGS (Feature 047: Fully Dynamic via sway-config-manager)
      # ═══════════════════════════════════════════════════════════════════════════
      #
      # Feature 047: ALL keybindings are now managed dynamically through
      # sway-config-manager to prevent conflicts with home-manager's static generation.
      #
      # To edit keybindings:
      #   • Edit: ~/.config/sway/keybindings.toml
      #   • Validate: i3pm config validate
      #   • Reload: swayconfig reload (or i3pm config reload)
      #   • No NixOS rebuild required!
      #
      # The dynamically generated keybindings file is included via extraConfig below.
      # ═══════════════════════════════════════════════════════════════════════════
      keybindings = lib.mkForce {
        # Empty - all keybindings managed by sway-config-manager (Feature 047)
        # Default keybindings are in: ~/.local/share/sway-config-manager/templates/keybindings.toml
      };

      # ORIGINAL home-manager keybindings (commented out for Feature 047):
      # All keybindings below have been moved to ~/.local/share/sway-config-manager/templates/keybindings.toml
      # and are now managed dynamically. To restore static keybindings, remove lib.mkForce above.
      #
      # keybindings = let
      #   mod = config.wayland.windowManager.sway.config.modifier;
      # in lib.mkOptionDefault {
      #   # Terminal (uses config.terminal which calls app-launcher-wrapper)
      #   "${mod}+Return" = "exec $terminal";

      #   # Application launcher (rofi for headless, walker for M1)
      #   "${mod}+d" = "exec $menu";
      #   "Mod1+space" = "exec $menu";  # Alternative: Alt+Space

      #         # Window management
      #         "${mod}+Shift+q" = "kill";
      #         "${mod}+Escape" = "kill";  # Alternative kill binding
      # 
      #         # Focus movement (arrow keys)
      #         "${mod}+Left" = "focus left";
      #         "${mod}+Down" = "focus down";
      #         "${mod}+Up" = "focus up";
      #         "${mod}+Right" = "focus right";
      # 
      #         # Move focused window (arrow keys)
      #         "${mod}+Shift+Left" = "move left";
      #         "${mod}+Shift+Down" = "move down";
      #         "${mod}+Shift+Up" = "move up";
      #         "${mod}+Shift+Right" = "move right";
      # 
      #         # Split orientation
      #         "${mod}+h" = "split h";
      #         "${mod}+Shift+bar" = "split v";
      # 
      #         # Fullscreen
      #         "${mod}+f" = "fullscreen toggle";
      # 
      #         # Container layout
      #         "${mod}+s" = "layout stacking";
      #         "${mod}+w" = "layout tabbed";
      #         "${mod}+e" = "layout toggle split";
      # 
      #         # Toggle floating
      #         "${mod}+Shift+space" = "floating toggle";
      #         "${mod}+space" = "focus mode_toggle";
      # 
      #         # Scratchpad
      #         "${mod}+Shift+minus" = "move scratchpad";
      #         "${mod}+minus" = "scratchpad show";
      # 
      #         # Workspace switching (Ctrl+1-9) - parallel to Hetzner
      #         "Control+1" = "workspace number 1";
      #         "Control+2" = "workspace number 2";
      #         "Control+3" = "workspace number 3";
      #         "Control+4" = "workspace number 4";
      #         "Control+5" = "workspace number 5";
      #         "Control+6" = "workspace number 6";
      #         "Control+7" = "workspace number 7";
      #         "Control+8" = "workspace number 8";
      #         "Control+9" = "workspace number 9";
      # 
      #         # Move container to workspace
      #         "${mod}+Shift+1" = "move container to workspace number 1";
      #         "${mod}+Shift+2" = "move container to workspace number 2";
      #         "${mod}+Shift+3" = "move container to workspace number 3";
      #         "${mod}+Shift+4" = "move container to workspace number 4";
      #         "${mod}+Shift+5" = "move container to workspace number 5";
      #         "${mod}+Shift+6" = "move container to workspace number 6";
      #         "${mod}+Shift+7" = "move container to workspace number 7";
      #         "${mod}+Shift+8" = "move container to workspace number 8";
      #         "${mod}+Shift+9" = "move container to workspace number 9";
      # 
      #         # Project management keybindings (parallel to i3 config)
      #         "${mod}+p" = "exec ${pkgs.xterm}/bin/xterm -name fzf-launcher -geometry 80x24 -e /etc/nixos/scripts/fzf-project-switcher.sh";
      #         "${mod}+Shift+p" = "exec i3pm project clear";
      # 
      #         # Project-aware application launchers (Feature 035: Registry-based)
      #         "${mod}+c" = "exec ~/.local/bin/app-launcher-wrapper.sh vscode";
      #         "${mod}+g" = "exec ~/.local/bin/app-launcher-wrapper.sh lazygit";
      #         "${mod}+y" = "exec ~/.local/bin/app-launcher-wrapper.sh yazi";
      #         "${mod}+b" = "exec ~/.local/bin/app-launcher-wrapper.sh btop";
      #         "${mod}+k" = "exec ~/.local/bin/app-launcher-wrapper.sh k9s";
      #         "${mod}+Shift+Return" = "exec ~/.local/bin/app-launcher-wrapper.sh terminal";
      # 
      #         # Monitor detection/workspace reassignment
      #         "${mod}+Shift+m" = "exec ~/.config/i3/scripts/reassign-workspaces.sh";
      # 
      #         # Reload/restart
      #         "${mod}+Shift+c" = "reload";
      #         "${mod}+Shift+r" = "restart";
      #         "${mod}+Shift+e" = "exec swaymsg exit";
      # 
      #         # Screenshots (grim + slurp for Wayland)
      #         "Print" = "exec grim -o $(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name') - | wl-copy";
      #         "${mod}+Print" = "exec grim -g \"$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.focused?) | .rect | \"\\(.x),\\(.y) \\(.width)x\\(.height)\"')\" - | wl-copy";
      #         "${mod}+Shift+x" = "exec grim -g \"$(slurp)\" - | wl-copy";
      #       };

      # ═══════════════════════════════════════════════════════════════════════════
      # WINDOW RULES (Nix-Managed - Essential System UI Only)
      # ═══════════════════════════════════════════════════════════════════════════
      #
      # NOTE: Only SYSTEM UI window rules belong here (launcher, system dialogs).
      # These are essential for the window manager to function correctly.
      #
      # For USER-DEFINED window rules (floating, sizing, positioning), use runtime config:
      #   • Edit: ~/.config/sway/window-rules.json
      #   • Reload: i3pm config reload
      #   • Examples: Calculator floating, Firefox on workspace 3, etc.
      #
      # ═══════════════════════════════════════════════════════════════════════════
      window.commands = [
        # Walker launcher - floating, centered, no border
        {
          criteria = { app_id = "walker"; };
          command = "floating enable, border pixel 0, move position center, mark _global_ui";
        }

        # Floating terminal
        {
          criteria = { app_id = "floating_terminal"; };
          command = "floating enable";
        }

        # FZF launcher - floating, centered, no border
        {
          criteria = { instance = "fzf-launcher"; };
          command = "floating enable, border pixel 0, move position center, mark _global_ui";
        }
      ];

      # Startup commands (FR-015)
      startup = [
        # D-Bus activation environment
        { command = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all"; }

        # Import DISPLAY for systemd services
        { command = "systemctl --user import-environment WAYLAND_DISPLAY DISPLAY"; }

        # i3pm daemon (systemd service)
        { command = "systemctl --user start i3-project-event-listener"; }

        # Monitor workspace distribution (wait for daemon)
        { command = "sleep 2 && ~/.config/i3/scripts/reassign-workspaces.sh"; }
      ];

      # Bar configuration will be provided by swaybar.nix
      bars = [];
    };

    # Extra Sway config for features not exposed by home-manager
    extraConfig = ''
      ${lib.optionalString (!isHeadless) ''
        # Disable laptop lid close action (keep running when closed)
        # Only for M1 MacBook Pro, not headless mode
        bindswitch lid:on output eDP-1 disable
        bindswitch lid:off output eDP-1 enable
      ''}

      # Application menu launcher - walker works with software rendering (GSK_RENDERER=cairo)
      set $menu walker

      # Define modifier key for dynamic keybindings (Feature 047)
      set $mod Mod4

      # Gaps (optional - clean appearance)
      gaps inner 5
      gaps outer 0

      # Workspace names with icons
      set $ws1 "1: terminal "
      set $ws2 "2: code "
      set $ws3 "3: firefox "
      set $ws4 "4: youtube "
      set $ws5 "5: files "
      set $ws6 "6: k8s "
      set $ws7 "7: git "
      set $ws8 "8: ai "
      set $ws9 "9 "

      # Feature 047: Include dynamically generated keybindings from sway-config-manager
      include ~/.config/sway/keybindings-generated.conf
    '';
  };

  # Install Wayland-specific utilities
  home.packages = with pkgs; [
    wl-clipboard     # Clipboard utilities (wl-copy, wl-paste)
    grim             # Screenshot tool
    slurp            # Screen area selection
    mako             # Notification daemon
    swaylock         # Screen locker
    swayidle         # Idle management
  ] ++ lib.optionals isHeadless [
    # wayvnc for headless mode (Feature 046)
    pkgs.wayvnc
  ];

  # wayvnc configuration for headless Sway (Feature 046)
  xdg.configFile."wayvnc/config" = lib.mkIf isHeadless {
    text = ''
      address=0.0.0.0
      port=5900
      enable_auth=false
    '';
  };

  # wayvnc systemd service for headless mode (Feature 046)
  systemd.user.services.wayvnc = lib.mkIf isHeadless {
    Unit = {
      Description = "wayvnc - VNC server for wlroots compositors";
      Documentation = "https://github.com/any1/wayvnc";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc";
      Restart = "on-failure";
      RestartSec = "1";
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Sway session target (synchronization point for Sway-dependent services)
  # Contract: /etc/nixos/specs/046-revise-my-spec/contracts/systemd-dependencies.md lines 132-149
  # This target represents that Sway compositor is fully initialized with IPC socket available
  systemd.user.targets.sway-session = {
    Unit = {
      Description = "sway compositor session";
      Documentation = "man:systemd.special(7)";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };
}

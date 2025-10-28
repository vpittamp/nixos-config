# Sway Wayland Compositor Home Manager Configuration
# Parallel to i3.nix - adapted for Wayland on M1 MacBook Pro
# Works with Sway native Wayland session (no XRDP)
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

      # Application menu (Meta+D) - rofi for headless (GPU-less), walker for M1
      menu = if isHeadless then "rofi -show drun" else "walker";

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
        # Headless Wayland - THREE separate outputs for multi-monitor VNC (Feature 046)
        # Each output maps to one physical monitor on the client
        "HEADLESS-1" = {
          resolution = "1920x1080@60Hz";
          position = "0,0";
          scale = "1.0";
        };
        "HEADLESS-2" = {
          resolution = "1920x1080@60Hz";
          position = "1920,0";
          scale = "1.0";
        };
        "HEADLESS-3" = {
          resolution = "1920x1080@60Hz";
          position = "3840,0";
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
        # Headless mode: Workspaces distributed across 3 monitors (Feature 046)
        { workspace = "1"; output = "HEADLESS-1"; }
        { workspace = "2"; output = "HEADLESS-1"; }
        { workspace = "3"; output = "HEADLESS-2"; }
        { workspace = "4"; output = "HEADLESS-2"; }
        { workspace = "5"; output = "HEADLESS-2"; }
        { workspace = "6"; output = "HEADLESS-3"; }
        { workspace = "7"; output = "HEADLESS-3"; }
        { workspace = "8"; output = "HEADLESS-3"; }
        { workspace = "9"; output = "HEADLESS-3"; }
      ] else [
        # M1 MacBook Pro: default assignments (overridden by i3pm monitors reassign)
        { workspace = "1"; output = "eDP-1"; }
        { workspace = "2"; output = "eDP-1"; }
        { workspace = "3"; output = "HDMI-A-1"; }
      ];

      # Keybindings (FR-002 - identical to Hetzner i3)
      keybindings = let
        mod = config.wayland.windowManager.sway.config.modifier;
      in lib.mkOptionDefault {
        # Terminal (uses config.terminal which calls app-launcher-wrapper)
        "${mod}+Return" = "exec $terminal";

        # Application launcher (rofi for headless, walker for M1)
        "${mod}+d" = "exec $menu";
        "Mod1+space" = "exec $menu";  # Alternative: Alt+Space

        # Window management
        "${mod}+Shift+q" = "kill";
        "${mod}+Escape" = "kill";  # Alternative kill binding

        # Focus movement (arrow keys)
        "${mod}+Left" = "focus left";
        "${mod}+Down" = "focus down";
        "${mod}+Up" = "focus up";
        "${mod}+Right" = "focus right";

        # Move focused window (arrow keys)
        "${mod}+Shift+Left" = "move left";
        "${mod}+Shift+Down" = "move down";
        "${mod}+Shift+Up" = "move up";
        "${mod}+Shift+Right" = "move right";

        # Split orientation
        "${mod}+h" = "split h";
        "${mod}+Shift+bar" = "split v";

        # Fullscreen
        "${mod}+f" = "fullscreen toggle";

        # Container layout
        "${mod}+s" = "layout stacking";
        "${mod}+w" = "layout tabbed";
        "${mod}+e" = "layout toggle split";

        # Toggle floating
        "${mod}+Shift+space" = "floating toggle";
        "${mod}+space" = "focus mode_toggle";

        # Scratchpad
        "${mod}+Shift+minus" = "move scratchpad";
        "${mod}+minus" = "scratchpad show";

        # Workspace switching (Ctrl+1-9) - parallel to Hetzner
        "Control+1" = "workspace number 1";
        "Control+2" = "workspace number 2";
        "Control+3" = "workspace number 3";
        "Control+4" = "workspace number 4";
        "Control+5" = "workspace number 5";
        "Control+6" = "workspace number 6";
        "Control+7" = "workspace number 7";
        "Control+8" = "workspace number 8";
        "Control+9" = "workspace number 9";

        # Move container to workspace
        "${mod}+Shift+1" = "move container to workspace number 1";
        "${mod}+Shift+2" = "move container to workspace number 2";
        "${mod}+Shift+3" = "move container to workspace number 3";
        "${mod}+Shift+4" = "move container to workspace number 4";
        "${mod}+Shift+5" = "move container to workspace number 5";
        "${mod}+Shift+6" = "move container to workspace number 6";
        "${mod}+Shift+7" = "move container to workspace number 7";
        "${mod}+Shift+8" = "move container to workspace number 8";
        "${mod}+Shift+9" = "move container to workspace number 9";

        # Project management keybindings (parallel to i3 config)
        "${mod}+p" = "exec ${pkgs.xterm}/bin/xterm -name fzf-launcher -geometry 80x24 -e /etc/nixos/scripts/fzf-project-switcher.sh";
        "${mod}+Shift+p" = "exec i3pm project clear";

        # Project-aware application launchers (Feature 035: Registry-based)
        "${mod}+c" = "exec ~/.local/bin/app-launcher-wrapper.sh vscode";
        "${mod}+g" = "exec ~/.local/bin/app-launcher-wrapper.sh lazygit";
        "${mod}+y" = "exec ~/.local/bin/app-launcher-wrapper.sh yazi";
        "${mod}+b" = "exec ~/.local/bin/app-launcher-wrapper.sh btop";
        "${mod}+k" = "exec ~/.local/bin/app-launcher-wrapper.sh k9s";
        "${mod}+Shift+Return" = "exec ~/.local/bin/app-launcher-wrapper.sh terminal";

        # Monitor detection/workspace reassignment
        "${mod}+Shift+m" = "exec ~/.config/i3/scripts/reassign-workspaces.sh";

        # Reload/restart
        "${mod}+Shift+c" = "reload";
        "${mod}+Shift+r" = "restart";
        "${mod}+Shift+e" = "exec swaymsg exit";

        # Screenshots (grim + slurp for Wayland)
        "Print" = "exec grim -o $(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name') - | wl-copy";
        "${mod}+Print" = "exec grim -g \"$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.focused?) | .rect | \"\\(.x),\\(.y) \\(.width)x\\(.height)\"')\" - | wl-copy";
        "${mod}+Shift+x" = "exec grim -g \"$(slurp)\" - | wl-copy";
      };

      # Window rules (FR-023 - parallel to i3 config)
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

        # Import DISPLAY for systemd services (Elephant needs this)
        { command = "systemctl --user import-environment WAYLAND_DISPLAY DISPLAY"; }

        # Restart Elephant after environment import
        { command = "systemctl --user restart elephant"; }

        # i3pm daemon (systemd service)
        { command = "systemctl --user start i3-project-event-listener"; }

        # Monitor workspace distribution (wait for daemon)
        { command = "sleep 2 && ~/.config/i3/scripts/reassign-workspaces.sh"; }
      ] ++ (if isHeadless then [
        # Create additional headless outputs for multi-monitor VNC (Feature 046)
        { command = "swaymsg create_output"; }
        { command = "swaymsg create_output"; }
      ] else []);

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
    # RustDesk 1.4.3 with Wayland multi-monitor support (Feature 046)
    pkgs.rustdesk
    # rofi-wayland for application launching (Walker requires GPU) (Feature 046)
    pkgs.rofi-wayland
  ];

  # wayvnc configuration for headless Sway (Feature 046)
  xdg.configFile."wayvnc/config" = lib.mkIf isHeadless {
    text = ''
      # wayvnc configuration for headless Sway on Hetzner Cloud
      # VNC server for remote access to Wayland compositor

      address=0.0.0.0
      port=5900
      enable_auth=false

      # To enable authentication:
      # 1. Set enable_auth=true and username=vnc
      # 2. Rebuild: nixos-rebuild switch --flake .#hetzner-sway
      # 3. After Sway starts, set password: wayvncctl set-password vnc <your-password>

      # Performance settings for remote access
      # max_rate=60  # FPS limit (default: 60, can reduce to 30 for lower bandwidth)

      # Output selection (auto-detect HEADLESS-1)
      # output=HEADLESS-1
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

  # RustDesk systemd service for headless mode (Feature 046)
  # Alternative to wayvnc with multi-monitor support
  # After service starts, set password: rustdesk --password <your-password>
  # Get connection ID: rustdesk --get-id
  systemd.user.services.rustdesk = lib.mkIf isHeadless {
    Unit = {
      Description = "RustDesk - Remote Desktop Client Service";
      Documentation = "https://rustdesk.com/docs/en/client/linux/";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      # Run RustDesk client in service mode for headless access
      # It will auto-detect Wayland and use native support (1.4.3+)
      ExecStart = "${pkgs.rustdesk}/bin/rustdesk";
      Restart = "on-failure";
      RestartSec = "3";
      # Wayland environment variables for 1.4.3 multi-monitor support
      Environment = [
        "XDG_SESSION_TYPE=wayland"
        "WAYLAND_DISPLAY=wayland-1"
      ];
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}

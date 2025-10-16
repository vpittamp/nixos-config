{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.mangowc;

  # Generate keybinding configuration lines
  keybindingsConfig = concatStringsSep "\n" (
    mapAttrsToList (key: action: "bind=${key},${action}") cfg.keybindings
  );

  # Generate workspace/tag rules
  workspaceRules = concatStringsSep "\n" (
    map (ws: "tagrule=id:${toString ws.id},layout_name:${ws.layout}") cfg.workspaces
  );

  # Default keybindings (can be overridden)
  defaultKeybindings = {
    # System
    "SUPER,r" = "reload_config";
    "SUPER,m" = "quit";
    "ALT,q" = "killclient,";

    # Application launching
    "Alt,space" = "spawn,rofi -show drun";
    "Alt,Return" = "spawn,foot";

    # Window focus
    "ALT,Left" = "focusdir,left";
    "ALT,Right" = "focusdir,right";
    "ALT,Up" = "focusdir,up";
    "ALT,Down" = "focusdir,down";

    # Workspace switching (Ctrl+1-9)
    "Ctrl,1" = "view,1,0";
    "Ctrl,2" = "view,2,0";
    "Ctrl,3" = "view,3,0";
    "Ctrl,4" = "view,4,0";
    "Ctrl,5" = "view,5,0";
    "Ctrl,6" = "view,6,0";
    "Ctrl,7" = "view,7,0";
    "Ctrl,8" = "view,8,0";
    "Ctrl,9" = "view,9,0";

    # Move window to workspace (Alt+1-9)
    "Alt,1" = "tag,1,0";
    "Alt,2" = "tag,2,0";
    "Alt,3" = "tag,3,0";
    "Alt,4" = "tag,4,0";
    "Alt,5" = "tag,5,0";
    "Alt,6" = "tag,6,0";
    "Alt,7" = "tag,7,0";
    "Alt,8" = "tag,8,0";
    "Alt,9" = "tag,9,0";

    # Layout management
    "SUPER,n" = "switch_layout";

    # Window management
    "ALT,backslash" = "togglefloating,";
    "ALT,f" = "togglefullscreen,";
    "SUPER,i" = "minimized,";
    "SUPER+SHIFT,I" = "restore_minimized";
  };

  # Merge default and custom keybindings (custom overrides default)
  allKeybindings = defaultKeybindings // cfg.keybindings;

  # Generate complete MangoWC config
  mangoConfig = if cfg.config != "" then cfg.config else ''
    # Window Effects
    blur=0
    shadows=0
    border_radius=${toString cfg.appearance.borderRadius}
    focused_opacity=1.0
    unfocused_opacity=1.0

    # Animation Configuration
    animations=1
    animation_duration_open=400
    animation_duration_close=800
    animation_curve_open=0.46,1.0,0.29,1

    # Layout Settings
    new_is_master=1
    default_mfact=0.55
    default_nmaster=1
    smartgaps=0

    # Scroller Layout
    scroller_structs=20
    scroller_default_proportion=0.8
    scroller_focus_center=0

    # Overview
    hotarea_size=10
    enable_hotarea=1
    overviewgappi=5
    overviewgappo=30

    # Misc
    focus_on_activate=1
    sloppyfocus=1
    warpcursor=1
    focus_cross_monitor=0
    cursor_size=24

    # Keyboard
    repeat_rate=25
    repeat_delay=600
    numlockon=1
    xkb_rules_layout=us

    # Appearance
    gappih=5
    gappiv=5
    gappoh=10
    gappov=10
    borderpx=${toString cfg.appearance.borderWidth}
    rootcolor=${cfg.appearance.rootColor}
    bordercolor=${cfg.appearance.unfocusedColor}
    focuscolor=${cfg.appearance.focusColor}

    # Tag/Workspace Rules
    ${workspaceRules}

    # Key Bindings
    ${keybindingsConfig}

    # Mouse bindings
    mousebind=SUPER,btn_left,moveresize,curmove
    mousebind=SUPER,btn_right,moveresize,curresize
  '';

in {
  options.services.mangowc = {
    enable = mkEnableOption "MangoWC Wayland compositor";

    package = mkOption {
      type = types.package;
      default = inputs.mangowc.packages.${pkgs.system}.mango or pkgs.mangowc;
      description = "MangoWC package to use";
    };

    user = mkOption {
      type = types.str;
      default = "vpittamp";
      description = "System user to run MangoWC compositor";
    };

    resolution = mkOption {
      type = types.str;
      default = "1920x1080";
      description = "Virtual display resolution for headless mode";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for MangoWC compositor";
      example = {
        WLR_NO_HARDWARE_CURSORS = "1";
        WLR_RENDERER = "pixman";
      };
    };

    config = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Complete MangoWC configuration (config.conf content).
        If provided, replaces default configuration entirely.
      '';
    };

    autostart = mkOption {
      type = types.lines;
      default = "";
      description = "Shell commands to execute when MangoWC session starts";
    };

    workspaces = mkOption {
      type = types.listOf (types.submodule {
        options = {
          id = mkOption {
            type = types.ints.between 1 9;
            description = "Workspace/tag ID (1-9)";
          };
          layout = mkOption {
            type = types.enum [
              "tile" "scroller" "monocle" "grid"
              "deck" "center_tile" "vertical_tile"
              "vertical_grid" "vertical_scroller"
            ];
            default = "tile";
            description = "Default layout for this workspace";
          };
          name = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional workspace name";
          };
        };
      });
      default = [
        { id = 1; layout = "tile"; }
        { id = 2; layout = "scroller"; }
        { id = 3; layout = "monocle"; }
        { id = 4; layout = "tile"; }
        { id = 5; layout = "tile"; }
        { id = 6; layout = "tile"; }
        { id = 7; layout = "tile"; }
        { id = 8; layout = "tile"; }
        { id = 9; layout = "tile"; }
      ];
      description = "Workspace/tag configuration";
    };

    keybindings = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = ''
        Custom keybindings to add or override.
        Format: { "SUPER,Return" = "spawn,foot"; }
      '';
      example = {
        "SUPER,Return" = "spawn,alacritty";
        "SUPER,d" = "spawn,wofi --show drun";
      };
    };

    appearance = mkOption {
      type = types.submodule {
        options = {
          borderWidth = mkOption {
            type = types.ints.unsigned;
            default = 4;
            description = "Window border width in pixels";
          };
          borderRadius = mkOption {
            type = types.ints.unsigned;
            default = 6;
            description = "Window corner radius in pixels";
          };
          rootColor = mkOption {
            type = types.str;
            default = "0x201b14ff";
            description = "Root/background color (hex RGBA)";
          };
          focusColor = mkOption {
            type = types.str;
            default = "0xc9b890ff";
            description = "Focused window border color (hex RGBA)";
          };
          unfocusedColor = mkOption {
            type = types.str;
            default = "0x444444ff";
            description = "Unfocused window border color (hex RGBA)";
          };
        };
      };
      default = {};
      description = "Visual appearance settings";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "MangoWC should not run as root";
      }
      {
        assertion = all (ws: ws.id >= 1 && ws.id <= 9) cfg.workspaces;
        message = "Workspace IDs must be between 1 and 9";
      }
    ];

    # Disable X11 (Wayland only)
    services.xserver.enable = lib.mkForce false;

    # Essential Wayland packages
    environment.systemPackages = with pkgs; [
      cfg.package  # MangoWC compositor
      foot         # Terminal
      rofi         # Application launcher (Wayland support built-in)
      swaybg       # Wallpaper
      grim         # Screenshot
      slurp        # Region selection
      wl-clipboard # Clipboard utilities
      wlroots      # Wayland compositor library
    ];

    # Enable loginctl linger for session persistence
    systemd.user.services."enable-linger-${cfg.user}" = {
      description = "Enable loginctl linger for ${cfg.user}";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger ${cfg.user}";
        RemainAfterExit = true;
      };
    };

    # MangoWC configuration files
    environment.etc."mangowc/config.conf" = {
      text = mangoConfig;
      mode = "0644";
    };

    environment.etc."mangowc/autostart.sh" = {
      text = ''
        #!/bin/sh
        ${cfg.autostart}
      '';
      mode = "0755";
    };

    # User systemd service for MangoWC
    systemd.user.services.mangowc = {
      description = "MangoWC Wayland Compositor";
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];

      environment = {
        # Headless backend configuration
        WLR_BACKENDS = "headless";
        WLR_LIBINPUT_NO_DEVICES = "1";
        WLR_HEADLESS_OUTPUTS = "1";
        WLR_OUTPUT_MODE = cfg.resolution;

        # Force software rendering (no GPU in QEMU)
        WLR_RENDERER = "pixman";
        WLR_NO_HARDWARE_CURSORS = "1";

        # Wayland display
        WAYLAND_DISPLAY = "wayland-1";

        # XDG directories
        XDG_RUNTIME_DIR = "/run/user/%U";
        XDG_CONFIG_HOME = "$HOME/.config";

        # MangoWC config path
        MANGOWC_CONFIG_DIR = "/etc/mangowc";
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/mango";
        Restart = "on-failure";
        RestartSec = "5s";

        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";

        # Allow writing to runtime directory
        ReadWritePaths = [ "/run/user/%U" ];
      };

      wantedBy = [ "default.target" ];
    };
  };
}

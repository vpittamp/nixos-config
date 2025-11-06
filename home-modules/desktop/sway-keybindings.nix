{ config, lib, pkgs, ... }:

let
  modifier = config.wayland.windowManager.sway.config.modifier;
in
{
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    # ========== WORKSPACE NAVIGATION ==========
    # Mode-based system with visual feedback in status bar
    # Platform-specific workspace mode entry keybindings are managed in sway.nix:
    #   - M1 (physical): CapsLock / Shift+CapsLock
    #   - Hetzner (VNC): Control+0 / Control+Shift+0
    # Once in mode: type digits, press Enter to execute
    # See workspace number appear in status bar as you type

    # Toggle between current and last workspace
    "${modifier}+Tab" = "workspace back_and_forth";

    # Next/previous workspace
    "${modifier}+n" = "workspace next";
    "${modifier}+Shift+n" = "workspace prev";

    # ========== APPLICATION LAUNCHERS ==========
    "${modifier}+Return" = "exec i3pm scratchpad toggle";
    "${modifier}+Shift+Return" = "exec alacritty";
    "${modifier}+d" = "exec walker";

    # ========== WINDOW MANAGEMENT ==========
    # Focus windows (vim-style)
    "${modifier}+h" = "focus left";
    "${modifier}+j" = "focus down";
    "${modifier}+k" = "focus up";
    "${modifier}+l" = "focus right";

    # Focus windows (arrow keys)
    "${modifier}+Left" = "focus left";
    "${modifier}+Down" = "focus down";
    "${modifier}+Up" = "focus up";
    "${modifier}+Right" = "focus right";

    # Easy focus - keyboard hints for quick window selection
    "${modifier}+slash" = "exec sway-easyfocus";
    "${modifier}+Shift+slash" = "exec sway-easyfocus swap";

    # Move windows (vim-style)
    "${modifier}+Shift+h" = "move left";
    "${modifier}+Shift+j" = "move down";
    "${modifier}+Shift+k" = "move up";
    "${modifier}+Shift+l" = "move right";

    # Move windows (arrow keys)
    "${modifier}+Shift+Left" = "move left";
    "${modifier}+Shift+Down" = "move down";
    "${modifier}+Shift+Up" = "move up";
    "${modifier}+Shift+Right" = "move right";

    # Window actions
    "${modifier}+x" = "kill";
    "${modifier}+f" = "fullscreen toggle";
    "${modifier}+Shift+space" = "floating toggle";
    "${modifier}+space" = "focus mode_toggle";

    # Layout
    "${modifier}+s" = "layout stacking";
    "${modifier}+w" = "layout tabbed";
    "${modifier}+e" = "layout toggle split";
    "${modifier}+v" = "splitv";
    "${modifier}+b" = "splith";

    # ========== SYSTEM ==========
    "${modifier}+Shift+c" = "reload";
    "${modifier}+Shift+e" = "exec swaymsg exit";
    "${modifier}+Shift+r" = "mode resize";

    # ========== SCRATCHPAD ==========
    "${modifier}+Shift+minus" = "move scratchpad";
    "${modifier}+minus" = "scratchpad show";

    # ========== PROJECT MANAGEMENT (i3pm) ==========
    "${modifier}+p" = "exec i3-project-switch";
    "${modifier}+Shift+p" = "exec i3-project-clear";

    # ========== ADDITIONAL UTILITIES ==========
    # Screenshots (Wayland with grim + slurp)
    "Print" = "exec grim -o $(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name') - | wl-copy";
    "Shift+Print" = "exec grim -g \"$(slurp)\" - | wl-copy";
    "Control+Print" = "exec grim ~/Pictures/screenshot-$(date +%Y%m%d_%H%M%S).png";

    # Clipboard history
    "${modifier}+c" = "exec clipman pick -t wofi";

    # Brightness control
    "XF86MonBrightnessUp" = "exec light -A 5";
    "XF86MonBrightnessDown" = "exec light -U 5";

    # Volume control
    "XF86AudioRaiseVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ +5%";
    "XF86AudioLowerVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ -5%";
    "XF86AudioMute" = "exec pactl set-sink-mute @DEFAULT_SINK@ toggle";
    "XF86AudioMicMute" = "exec pactl set-source-mute @DEFAULT_SOURCE@ toggle";

    # Media playback control
    "XF86AudioPlay" = "exec playerctl play-pause";
    "XF86AudioNext" = "exec playerctl next";
    "XF86AudioPrev" = "exec playerctl previous";

    # System monitor
    "${modifier}+Shift+t" = "exec btop";
  };
}

{ config, lib, pkgs, ... }:

let
  modifier = config.wayland.windowManager.sway.config.modifier;
  topBarCfg = config.programs.eww-top-bar or null;
  hasTopBar = topBarCfg != null && (topBarCfg.enable or false);
  runtimeShellCfg = config.programs.quickshell-runtime-shell or null;
  hasRuntimeShell = runtimeShellCfg != null && (runtimeShellCfg.enable or false);
  nativeNotifications =
    hasRuntimeShell
    && ((lib.attrByPath [ "notifications" "backend" ] "native" runtimeShellCfg) == "native");
  rawToggleKey = if hasRuntimeShell then runtimeShellCfg.toggleKey else "$mod+m";
  toggleKeyList =
    let keys = if lib.isList rawToggleKey then rawToggleKey else [ rawToggleKey ];
    in map (key: lib.replaceStrings ["$mod"] [modifier] key) keys;
  monitoringPanelBindings =
    if hasRuntimeShell
    then lib.listToAttrs (map (key: lib.nameValuePair key "exec toggle-monitoring-panel") (lib.unique toggleKeyList))
    else {};
  primaryLauncherCommand = if hasRuntimeShell then "exec toggle-app-launcher" else "exec walker";
in
{
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault (
    {
    # ========== WORKSPACE NAVIGATION ==========
    # Mode-based system with visual feedback in status bar
    # Platform-specific workspace mode entry keybindings are managed in sway.nix:
    #   - M1 (physical): CapsLock / Shift+CapsLock
    #   - Hetzner (VNC): Control+0 / Control+Shift+0
    # Once in mode: type digits, press Enter to execute
    # See workspace number appear in status bar as you type

    # Force-close stuck workspace preview (emergency exit)
    "${modifier}+Shift+Escape" = "exec i3pm-workspace-mode cancel";

    # AI session switcher in launcher style
    "${modifier}+Tab" = "exec show-ai-mru-switcher-action next";
    "${modifier}+Shift+Tab" = "exec show-ai-mru-switcher-action prev";

    # Next/previous workspace
    "${modifier}+n" = "workspace next";
    "${modifier}+Shift+n" = "workspace prev";

    # ========== APPLICATION LAUNCHERS ==========
    "${modifier}+Return" = "exec i3pm scratchpad toggle";
    "${modifier}+Shift+Return" = "exec i3pm launch open terminal";
    "${modifier}+d" = primaryLauncherCommand;
    "Mod1+space" = "exec walker";
    "${modifier}+Shift+f" = "exec i3pm run fzf-file-search --force";

    # ========== 1PASSWORD ==========
    # Chrome's extension popup shortcut (Ctrl+Shift+X) is inconsistent in standalone
    # PWA windows. Bind the desktop app's global entry points at the compositor level
    # so they work in both browser windows and Chrome PWAs.
    "Ctrl+Shift+space" = "exec 1password --quick-access";
    "Ctrl+backslash" = "exec 1password --fill";

    # Run-raise-hide launcher (Feature 051) - example keybindings
    # Uncomment and customize based on your most-used applications
    # Toggle mode (default): Launch if not running, focus if visible, summon to current workspace
    # "${modifier}+b" = "exec i3pm run firefox";          # Toggle Firefox
    # "${modifier}+Shift+c" = "exec i3pm run code";       # Toggle VS Code
    # "${modifier}+t" = "exec i3pm run ghostty";          # Toggle terminal
    #
    # Hide mode: Toggle visibility (hide focused window to scratchpad)
    # "${modifier}+Ctrl+b" = "exec i3pm run firefox --hide";
    # "${modifier}+Ctrl+c" = "exec i3pm run code --hide";
    #
    # Force new instance:
    # "${modifier}+Alt+t" = "exec i3pm run ghostty --force";

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
    "F11" = "fullscreen toggle";  # F11 is standard, avoids VNC client Mod+F conflict
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
    "${modifier}+Shift+e" =
      if hasRuntimeShell then "exec toggle-runtime-power-menu"
      else if hasTopBar then "exec toggle-topbar-powermenu"
      else "exec swaymsg exit";
    "${modifier}+Ctrl+Shift+e" = "exec swaymsg exit";
    "${modifier}+Shift+r" = "mode resize";

    # ========== SCRATCHPAD ==========
    "${modifier}+Shift+minus" = "move scratchpad";
    "${modifier}+minus" = "scratchpad show";

    # ========== PROJECT MANAGEMENT (i3pm) ==========
    "${modifier}+p" = "exec i3-project-switch";
    "${modifier}+Shift+p" = "exec i3-project-clear";

    # ========== APP SHORTCUTS (via i3pm app registry) ==========
    "${modifier}+y" = "exec i3pm run yazi";

    # ========== NOTIFICATIONS (SwayNC) ==========
    "${modifier}+i" = "exec toggle-quick-panel";  # Toggle Eww quick settings panel
    "${modifier}+Shift+i" = if nativeNotifications then "exec toggle-runtime-notifications" else "exec toggle-swaync";
    "${modifier}+Ctrl+Shift+i" = if nativeNotifications then "exec toggle-runtime-notification-dnd" else "exec swaync-client -d -sw";

    # ========== ADDITIONAL UTILITIES ==========
    # Screenshots (Wayland with grim + slurp)
    "Print" = "exec grim -o $(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name') - | wl-copy";
    "Shift+Print" = "exec grim -g \"$(slurp)\" - | wl-copy";
    "Control+Print" = "exec grim ~/Pictures/screenshot-$(date +%Y%m%d_%H%M%S).png";

    # Clipboard history
    "${modifier}+c" = "exec clipman pick -t wofi";

    # Open selected text/path/URL (select text, copy, then press keybinding)
    "${modifier}+o" = "exec ghostty-smart-open";

    # Extract URLs/paths from terminal with urlscan (like VSCode's link detection)
    "${modifier}+u" = "exec urlscan";

    # Cycle daemon-backed display layouts
    "${modifier}+Control+m" = "exec cycle-display-layout";

    "${modifier}+Shift+m" = "exec toggle-panel-dock-mode";
    "F10" = "exec toggle-panel-dock-mode";

    # Runtime shell view switching
    "Alt+1" = "exec monitor-panel-tab 0";
    "Alt+2" = "exec monitor-panel-tab 1";
    "Alt+3" = "exec monitor-panel-tab 2";
    "Alt+bracketright" = "exec cycle-active-ai-session-action next";
    "Alt+bracketleft" = "exec cycle-active-ai-session-action prev";
    "Alt+grave" = "exec toggle-last-ai-session-action";

    # Internal display brightness
    "XF86MonBrightnessUp" = "exec brightnessctl set +5%";
    "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";

    # Keyboard backlight (ThinkPad: tpacpi::kbd_backlight, Apple Silicon: kbd_backlight)
    "XF86KbdBrightnessUp" = "exec brightnessctl -d '*kbd_backlight*' -n 5 set +10%";
    "XF86KbdBrightnessDown" = "exec brightnessctl -d '*kbd_backlight*' -n 5 set 10%-";

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

    # ========== WORKSPACE MODE (Feature 042 + 058 + 059) ==========
    # Platform-specific entry keybindings for workspace mode navigation
    # Visual feedback now via workspace bar (Feature 058), no more notifications
    # Hetzner (VNC): F9 (easy to press over VNC), Control+0 (standard)
    # M1 (Physical): CapsLock is handled via bindcode in sway.nix extraConfig
    # Note: keyd remapping doesn't work over VNC (WayVNC bypasses evdev)
    # Feature 072: Must call 'i3pm-workspace-mode enter' to trigger all-windows preview
    "Control+0" = "exec i3pm-workspace-mode enter; exec swaymsg 'mode \"→ WS\"'";
    "Control+Shift+0" = "exec swaymsg 'mode \"⇒ WS\"'";

    # F9 keybindings for VNC users (ergonomic alternative to Control+0)
    "F9" = "exec i3pm-workspace-mode enter; exec swaymsg 'mode \"→ WS\"'";
    "Shift+F9" = "exec swaymsg 'mode \"⇒ WS\"'";

    # ========== FEATURE 059: Interactive Workspace Menu Keybindings ==========
    # Arrow key navigation for workspace preview card (navigate through workspace list)
    # These keybindings need to be added to sway.nix in the workspace mode definitions:
    #
    # In mode "→ WS" (goto mode) - add after line ~676:
    #   bindsym Down exec i3pm-workspace-mode nav down
    #   bindsym Up exec i3pm-workspace-mode nav up
    #   bindsym Delete exec i3pm-workspace-mode delete
    #
    # In mode "⇒ WS" (move mode) - add at equivalent location:
    #   bindsym Down exec i3pm-workspace-mode nav down
    #   bindsym Up exec i3pm-workspace-mode nav up
    #   bindsym Delete exec i3pm-workspace-mode delete
    #
    # Note: Return and Escape are already defined in workspace modes
    # Return executes navigation to selected workspace/window (US2)
    # Delete closes selected window (US3)
    # Escape cancels and exits mode
  }
  // monitoringPanelBindings);
}

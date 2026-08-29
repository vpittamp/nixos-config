# Structured source of truth for the sway keybindings.
#
# Each binding is { key; cmd; desc; hidden ? false } inside a named group.
# `sway-keybindings.nix` flattens this into the `bindsym` attrset sway needs;
# `quickshell-runtime-shell/default.nix` turns the same list into the JSON the
# launcher's Keys mode renders. Keeping both derived from one list is what
# lets the cheat sheet stay correct by construction — a binding that is not
# described here does not exist, and one described here cannot drift from
# what sway actually runs.
#
# `hidden` marks bindings that are implementation detail (modifier-release
# commits for the hold-to-switch rings) and should not appear in the viewer.
{ lib, modifier, hasRuntimeShell }:

let
  mod = modifier;
  bind = key: cmd: desc: { inherit key cmd desc; hidden = false; };
  hiddenBind = key: cmd: desc: { inherit key cmd desc; hidden = true; };

  primaryLauncherCommand =
    if hasRuntimeShell then "exec toggle-app-launcher" else "exec walker";

  groups = [
    {
      name = "Switching";
      bindings = [
        (bind "${mod}+Tab" "exec show-ai-mru-switcher-action next"
          "AI session switcher — hold Super, Tab steps, release commits")
        (bind "${mod}+Shift+Tab" "exec show-ai-mru-switcher-action prev"
          "AI session switcher, backwards")
        (bind "Alt+Tab" "exec show-app-switcher-action next"
          "Running-app switcher, most recent first — hold Alt, Tab steps, release commits")
        (bind "Alt+Shift+Tab" "exec show-app-switcher-action prev"
          "Running-app switcher, backwards")
        (bind "Alt+Ctrl+Tab" "exec show-window-switcher-action next"
          "Window exposé grouped by monitor (also 3-finger swipe up)")
        (bind "Alt+Ctrl+Shift+Tab" "exec show-window-switcher-action prev"
          "Window exposé, backwards")
        # Commit the hold-to-switch rings on the compositor's own modifier-release
        # event: the overlay may not hold the keyboard yet when a quick tap ends,
        # so its own key-release handler is only a fallback. Both actions are
        # no-ops when no switcher is open.
        (hiddenBind "--release Alt_L" "exec commit-window-switch-action"
          "Commit the Alt-held window switcher")
        (hiddenBind "--release Super_L" "exec commit-ai-session-switch-action"
          "Commit the Super-held AI session switcher")
        (bind "${mod}+grave" "exec cycle-app-windows-action next"
          "Cycle the focused app's windows (no UI)")
        (bind "${mod}+Shift+grave" "exec cycle-app-windows-action prev"
          "Cycle the focused app's windows, backwards (no UI)")
        (bind "${mod}+Escape" "exec toggle-last-window-action"
          "Toggle to the last focused window (no UI)")
        (bind "${mod}+n" "workspace next" "Next workspace")
        (bind "${mod}+Shift+n" "workspace prev" "Previous workspace")
      ];
    }
    {
      name = "Launch";
      bindings = [
        (bind "${mod}+Shift+Return" "exec i3pm launch open terminal" "Open a terminal")
        (bind "${mod}+d" primaryLauncherCommand "App launcher")
        (bind "Mod1+space" "exec walker" "Walker launcher")
        (bind "${mod}+Shift+f" "exec i3pm run fzf-file-search --force" "fzf file search")
        # Chrome's extension popup shortcut (Ctrl+Shift+X) is inconsistent in
        # standalone PWA windows. Bind the desktop app's global entry points at
        # the compositor level so they work in both browser windows and PWAs.
        (bind "Ctrl+Shift+space" "exec 1password --quick-access" "1Password quick access")
        (bind "Ctrl+backslash" "exec 1password --fill" "1Password autofill")
        (bind "${mod}+y" "exec i3pm run yazi" "Yazi file manager")
        (bind "${mod}+Shift+t" "exec btop" "System monitor (btop)")
      ];
    }
    {
      name = "Focus";
      bindings = [
        (bind "${mod}+h" "focus left" "Focus window left")
        (bind "${mod}+j" "focus down" "Focus window down")
        (bind "${mod}+k" "focus up" "Focus window up")
        (bind "${mod}+l" "focus right" "Focus window right")
        (bind "${mod}+Left" "focus left" "Focus window left")
        (bind "${mod}+Down" "focus down" "Focus window down")
        (bind "${mod}+Up" "focus up" "Focus window up")
        (bind "${mod}+Right" "focus right" "Focus window right")
        (bind "${mod}+slash" "exec sway-easyfocus" "Easy focus — keyboard hints to pick a window")
        (bind "${mod}+Shift+slash" "exec sway-easyfocus swap" "Easy focus — swap with a hinted window")
      ];
    }
    {
      name = "Move";
      bindings = [
        (bind "${mod}+Shift+h" "move workspace to output left" "Move workspace to the output on the left")
        (bind "${mod}+Shift+j" "move workspace to output down" "Move workspace to the output below")
        (bind "${mod}+Shift+k" "move workspace to output up" "Move workspace to the output above")
        (bind "${mod}+Shift+l" "move workspace to output right" "Move workspace to the output on the right")
        (bind "${mod}+Shift+Left" "move workspace to output left" "Move workspace to the output on the left")
        (bind "${mod}+Shift+Down" "move workspace to output down" "Move workspace to the output below")
        (bind "${mod}+Shift+Up" "move workspace to output up" "Move workspace to the output above")
        (bind "${mod}+Shift+Right" "move workspace to output right" "Move workspace to the output on the right")
        (bind "${mod}+Ctrl+Shift+h" "move left" "Move window left")
        (bind "${mod}+Ctrl+Shift+j" "move down" "Move window down")
        (bind "${mod}+Ctrl+Shift+k" "move up" "Move window up")
        (bind "${mod}+Ctrl+Shift+l" "move right" "Move window right")
        (bind "${mod}+Ctrl+Shift+Left" "move left" "Move window left")
        (bind "${mod}+Ctrl+Shift+Down" "move down" "Move window down")
        (bind "${mod}+Ctrl+Shift+Up" "move up" "Move window up")
        (bind "${mod}+Ctrl+Shift+Right" "move right" "Move window right")
      ];
    }
    {
      name = "Windows";
      bindings = [
        (bind "${mod}+x" "kill" "Close window")
        # F11 is standard and avoids the VNC client's Mod+F conflict
        (bind "F11" "fullscreen toggle" "Toggle fullscreen")
        (bind "${mod}+Shift+space" "floating toggle" "Toggle floating")
        (bind "${mod}+space" "focus mode_toggle" "Focus between tiling and floating")
        (bind "${mod}+s" "layout stacking" "Stacking layout")
        (bind "${mod}+w" "layout tabbed" "Tabbed layout")
        (bind "${mod}+e" "layout toggle split" "Toggle split layout")
        (bind "${mod}+v" "splitv" "Split vertically")
        (bind "${mod}+b" "splith" "Split horizontally")
        (bind "${mod}+Shift+minus" "move scratchpad" "Move window to scratchpad")
        (bind "${mod}+minus" "scratchpad show" "Show scratchpad")
      ];
    }
    {
      name = "Shell";
      bindings = [
        (bind "${mod}+i" "exec show-runtime-devices" "Devices settings (audio, brightness, power)")
        (bind "${mod}+Shift+i" "exec toggle-runtime-notifications" "Toggle the notification center")
        (bind "${mod}+Ctrl+Shift+i" "exec toggle-runtime-notification-dnd" "Toggle do-not-disturb")
        (bind "${mod}+Control+m" "exec cycle-display-layout" "Cycle daemon-backed display layouts")
        (bind "${mod}+Shift+m" "exec toggle-panel-dock-mode" "Toggle panel dock mode (overlay ↔ docked)")
        (bind "F10" "exec toggle-panel-dock-mode" "Toggle panel dock mode (overlay ↔ docked)")
        (bind "Alt+1" "exec monitor-panel-tab 0" "Runtime panel: first tab")
        (bind "Alt+2" "exec monitor-panel-tab 1" "Runtime panel: second tab")
        (bind "Alt+3" "exec monitor-panel-tab 2" "Runtime panel: third tab")
        (bind "Alt+bracketright" "exec cycle-active-ai-session-action next" "Next AI session (no UI)")
        (bind "Alt+bracketleft" "exec cycle-active-ai-session-action prev" "Previous AI session (no UI)")
        (bind "Alt+grave" "exec toggle-last-ai-session-action" "Toggle to the last AI session (no UI)")
      ] ++ lib.optionals hasRuntimeShell [
        (bind "${mod}+Ctrl+k" "exec toggle-keybindings-help" "This keybinding cheat sheet")
      ];
    }
    {
      name = "Session";
      bindings = [
        (bind "${mod}+Ctrl+l"
          (if hasRuntimeShell then "exec lock-session" else "exec swaylock -f")
          "Lock the session")
      ];
    }
    {
      name = "System";
      bindings = [
        (bind "${mod}+Shift+c" "reload" "Reload sway config")
        (bind "${mod}+Shift+e"
          (if hasRuntimeShell then "exec toggle-runtime-power-menu" else "exec swaymsg exit")
          (if hasRuntimeShell then "Power menu" else "Exit sway"))
        (bind "${mod}+Ctrl+Shift+e" "exec swaymsg exit" "Exit sway")
        (bind "${mod}+Shift+r" "mode resize" "Resize mode")
      ];
    }
    {
      name = "Capture & clipboard";
      bindings = [
        # With the runtime shell the `capture` CLI saves to ~/Pictures/Screenshots,
        # copies to the clipboard and notifies; recordings show a REC chip.
        (bind "Print"
          (if hasRuntimeShell then "exec capture screenshot output"
           else "exec grim -o $(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name') - | wl-copy")
          "Screenshot the focused output")
        (bind "Shift+Print"
          (if hasRuntimeShell then "exec capture screenshot region" else "exec grim -g \"$(slurp)\" - | wl-copy")
          "Screenshot a region")
        (bind "Control+Print"
          (if hasRuntimeShell then "exec capture screenshot window" else "exec grim ~/Pictures/screenshot-$(date +%Y%m%d_%H%M%S).png")
          "Screenshot the focused window")
      ] ++ lib.optionals hasRuntimeShell [
        (bind "Alt+Print" "exec capture record toggle" "Start / stop a screen recording of a region")
        (bind "${mod}+Print" "exec capture color" "Pick a colour from the screen (copies #rrggbb)")
        (bind "${mod}+Ctrl+Print" "exec capture ocr" "Recognise text in a region and copy it")
        (bind "${mod}+Shift+Print" "exec capture qr" "Decode a QR code on screen and copy it")
      ] ++ [
        (bind "${mod}+c" "exec clipman pick -t wofi" "Clipboard history")
        (bind "${mod}+o" "exec ghostty-smart-open" "Open selected text / path / URL")
        (bind "${mod}+u" "exec urlscan" "Extract URLs and paths from the terminal")
      ];
    }
    {
      name = "Hardware";
      bindings = [
        # With the runtime shell the keys go through quickshell-brightness-key,
        # which runs the same brightnessctl step and then shows the OSD.
        (bind "XF86MonBrightnessUp"
          (if hasRuntimeShell then "exec quickshell-brightness-key display up" else "exec brightnessctl set +5%")
          "Screen brightness up")
        (bind "XF86MonBrightnessDown"
          (if hasRuntimeShell then "exec quickshell-brightness-key display down" else "exec brightnessctl set 5%-")
          "Screen brightness down")
        # ThinkPad: tpacpi::kbd_backlight, Apple Silicon: kbd_backlight
        (bind "XF86KbdBrightnessUp"
          (if hasRuntimeShell then "exec quickshell-brightness-key keyboard up" else "exec brightnessctl -d '*kbd_backlight*' -n 5 set +10%")
          "Keyboard backlight up")
        (bind "XF86KbdBrightnessDown"
          (if hasRuntimeShell then "exec quickshell-brightness-key keyboard down" else "exec brightnessctl -d '*kbd_backlight*' -n 5 set 10%-")
          "Keyboard backlight down")
        # wpctl, not pactl: PipeWire ships wpctl on every host; pactl was never installed.
        (bind "XF86AudioRaiseVolume" "exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+" "Volume up")
        (bind "XF86AudioLowerVolume" "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" "Volume down")
        (bind "XF86AudioMute" "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" "Mute / unmute")
        (bind "XF86AudioMicMute" "exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" "Mute / unmute microphone")
        (bind "XF86AudioPlay" "exec playerctl play-pause" "Play / pause")
        (bind "XF86AudioNext" "exec playerctl next" "Next track")
        (bind "XF86AudioPrev" "exec playerctl previous" "Previous track")
      ];
    }
  ];

  bindings = lib.concatMap
    (group: map (binding: binding // { group = group.name; }) group.bindings)
    groups;
in
{
  inherit groups bindings;

  # The `bindsym` attrset sway consumes. Later entries win on a duplicate key,
  # matching how the old flat attrset behaved.
  attrs = lib.listToAttrs (map (b: lib.nameValuePair b.key b.cmd) bindings);
}

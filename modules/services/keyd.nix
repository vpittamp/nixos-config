{ config, lib, pkgs, ... }:

{
  # keyd - Kernel-level key remapper for Wayland
  # Keep only explicit non-destructive remaps at the evdev/uinput layer.
  # Workspace-mode entry now stays on deliberate Sway bindings instead of CapsLock.

  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];  # Apply to all keyboards
        settings = {
          main = {
            # ThinkPad Copilot key sends Meta+Shift+F23 as a firmware chord.
            # Remap F23 → Compose so voxtype sees EVTEST_127 (KEY_COMPOSE)
            # on both ThinkPad and Ryzen (which has a physical Compose key).
            # F23 is unused otherwise, so this is harmless on other machines.
            f23 = "compose";

            # CapsLock opens the natural-language command bar. Sway cannot
            # bind a lock key at all, so the remap has to happen below the
            # compositor, and the carrier has to be a key xkb leaves alone.
            #
            # NOT f20: xkeyboard-config's symbols/inet maps <FK20> to
            # XF86AudioMicMute ("historical mappings that must not be
            # removed" — the X drivers remap the unroutable evdev mic-mute
            # code onto F20). Sending f20 therefore reached our own
            # XF86AudioMicMute binding and toggled the microphone; the
            # `bindsym F20` never fired at all. F21-F24 are the touchpad
            # keys and F13-F18 are XF86Tools/Launch5-9 for the same reason.
            #
            # <FK19> is the one key in that range that resolves to a plain
            # F19 — in the base inet block and in every vendor file.
            # Caps-locking itself is gone, which is the point: it was the
            # largest key on the keyboard doing the least work.
            #
            # A plain remap, both edges passed through: sway binds F19 on
            # press AND on release, and the shell decides what a tap and a
            # hold mean (commandKeyPress/commandKeyRelease in shell.qml).
            #
            # This was briefly `timeout(f19, 250, S-f19)`, which let keyd do
            # the discrimination. That is the wrong layer for it. Push-to-talk
            # needs the mic to close when the key comes up, so it needs a real
            # release event for the whole duration of the press — and whether
            # keyd's hold action stays held or fires once is not something the
            # config can state. A straight remap makes the press and release
            # the hardware's own, which is a guarantee. It also keeps the
            # tap/hold threshold next to the behaviour it governs instead of
            # in a different module.
            capslock = "f19";
          };
        };
      };
    };
  };

  # Helps libinput treat keyd's virtual device as internal
  # Avoids palm-rejection bugs on touch devices
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Serial Keyboards]
    MatchUdevType=keyboard
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
  '';
}

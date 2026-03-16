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

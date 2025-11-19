{ config, lib, pkgs, ... }:

{
  # keyd - Kernel-level key remapper for Wayland
  # Maps CapsLock -> Control+0 for ergonomic workspace mode access
  # Works at evdev/uinput layer, so applies before Sway sees events
  # Perfect for VNC/remote scenarios

  services.keyd = {
    enable = true;  # Enabled for CapsLock -> Control+0 remapping
    keyboards = {
      default = {
        ids = [ "*" ];  # Apply to all keyboards
        settings = {
          main = {
            # CapsLock becomes Control+0 (workspace mode trigger)
            # Matches the Sway keybinding in sway-keybindings.nix
            capslock = "C-0";
          };
          # Shift layer: CapsLock becomes Control+Shift+0 (move mode)
          "main:S" = {
            capslock = "C-S-0";
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

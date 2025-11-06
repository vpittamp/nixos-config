{ config, lib, pkgs, ... }:

{
  # keyd - Kernel-level key remapper for Wayland
  # Maps CapsLock -> F9 for ergonomic workspace mode access
  # Works at evdev/uinput layer, so applies before Sway sees events
  # Perfect for VNC/remote scenarios

  services.keyd = {
    enable = true;  # Enabled for CapsLock -> F9 remapping
    keyboards = {
      default = {
        ids = [ "*" ];  # Apply to all keyboards
        settings = {
          main = {
            # CapsLock becomes F9 (workspace mode trigger)
            # F9 works reliably through VNC
            capslock = "f9";

            # Optional: Make Shift+CapsLock actual CapsLock for rare usage
            # Uncomment if needed:
            # shift+capslock = "capslock";
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

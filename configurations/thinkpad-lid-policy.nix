{
  services.bare-metal.lidPolicy = {
    battery = "suspend";
    # Clamshell mode: never suspend or lock on lid close while on AC power.
    # logind's "docked" detection depends on the external monitor being
    # connected, and this monitor's USB chain flaps (see the USB_DENYLIST
    # comment in configurations/thinkpad.nix) — every drop re-evaluates the
    # lid as undocked, so HandleLidSwitchExternalPower is the policy that
    # actually fires. "ignore" keeps the external display alive regardless.
    externalPower = "ignore";
    docked = "ignore";
  };
}

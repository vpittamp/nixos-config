{ config, lib, pkgs, ... }:

{
  programs.chromium = {
    enable = true;
    # Enterprise policies: disable built-in password manager and pin 1Password
    extraOpts = {
      "PasswordManagerEnabled" = false;
      "ExtensionSettings" = {
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
          "toolbar_pin" = "force_pinned";
        };
      };
    };
    # Also set initial preferences to turn off password saving UI on first run
    initialPrefs = {
      "credentials_enable_service" = false;
    };
  };
}

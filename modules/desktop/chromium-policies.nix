{ config, lib, pkgs, ... }:

{
  programs.chromium = {
    enable = true;
    # Force-install 1Password – Password Manager
    extensions = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    ];
    # Disable built-in password manager to avoid conflicts with 1Password
    extraOpts = {
      "PasswordManagerEnabled" = false;
    };
  };
}

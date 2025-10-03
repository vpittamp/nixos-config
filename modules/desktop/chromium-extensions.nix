{ config, lib, pkgs, ... }:

{
  # System-level Chromium configuration to force-install extensions
  # Note: There's a known issue where Chromium doesn't always auto-install from ExtensionInstallForcelist
  # Extensions may need to be manually installed on first run, but will persist after that
  programs.chromium = {
    enable = true;

    # Extensions list - NixOS will automatically create ExtensionInstallForcelist policy
    extensions = [
      { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; }  # 1Password - Password Manager
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }  # uBlock Origin
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }  # Dark Reader
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }  # Vimium
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; }  # Privacy Badger
      { id = "fcoeoabgfenejglbffodgkkbkcdhcgfn"; }  # Claude - AI Assistant
    ];

    # Additional enterprise policies
    extraOpts = {
      # Toolbar pinning for specific extensions
      "ExtensionSettings" = {
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa;https://clients2.google.com/service/update2/crx"  # 1Password
        "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx"  # uBlock Origin
        "eimadpbcbfnmbkopoojfekhnkhdbieeh;https://clients2.google.com/service/update2/crx"  # Dark Reader
        "dbepggeogbaibhgnhhndojpepiihcmeb;https://clients2.google.com/service/update2/crx"  # Vimium
        "pkehgijcmpdhfbdbbnkijodmdjhbjlgp;https://clients2.google.com/service/update2/crx"  # Privacy Badger
        "fcoeoabgfenejglbffodgkkbkcdhcgfn;https://clients2.google.com/service/update2/crx"  # Claude
      ];

      # Configure extension settings and toolbar pinning
      "ExtensionSettings" = {
        # 1Password - force pinned to toolbar
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
          "installation_mode" = "force_installed";
          "update_url" = "https://clients2.google.com/service/update2/crx";
          "toolbar_pin" = "force_pinned";
        };

        # Claude - force pinned to toolbar
        "fcoeoabgfenejglbffodgkkbkcdhcgfn" = {
          "installation_mode" = "force_installed";
          "update_url" = "https://clients2.google.com/service/update2/crx";
          "toolbar_pin" = "force_pinned";
        };

        # uBlock Origin
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" = {
          "installation_mode" = "force_installed";
          "update_url" = "https://clients2.google.com/service/update2/crx";
        };

        # Dark Reader
        "eimadpbcbfnmbkopoojfekhnkhdbieeh" = {
          "installation_mode" = "force_installed";
          "update_url" = "https://clients2.google.com/service/update2/crx";
        };

        # Vimium
        "dbepggeogbaibhgnhhndojpepiihcmeb" = {
          "installation_mode" = "force_installed";
          "update_url" = "https://clients2.google.com/service/update2/crx";
        };

        # Privacy Badger
        "pkehgijcmpdhfbdbbnkijodmdjhbjlgp" = {
          "installation_mode" = "force_installed";
          "update_url" = "https://clients2.google.com/service/update2/crx";
        };
      };

      # Disable Chrome's built-in password manager since we use 1Password
      "PasswordManagerEnabled" = false;
      "CredentialsEnableService" = false;

      # Allow native messaging for 1Password
      "NativeMessagingAllowlist" = [
        "com.1password.1password"
        "com.1password.browser_support"
      ];
    };
  };
}
{ config, pkgs, lib, ... }:

let
  # Detect if we're on M1 or Hetzner based on hostname
  isM1 = config.networking.hostName or "" == "nixos-m1";
  # Use Nix package reference for 1Password browser support
  onePasswordBrowserSupport = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";
  chromiumBin = "${pkgs.chromium}/bin/chromium";
in
{
  # Chromium browser configuration with 1Password and other extensions
  # This is installed as a secondary browser for specific use cases:
  # - Playwright MCP server for browser automation
  # - Testing and development
  # Firefox remains the default system browser for general use
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;
    
    # Extension IDs - These are installed declaratively by Nix
    extensions = [
      { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; }  # 1Password - Password Manager
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }  # uBlock Origin
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }  # Dark Reader
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }  # Vimium
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; }  # Privacy Badger
      { id = "fcoeoabgfenejglbffodgkkbkcdhcgfn"; }  # Claude - Anthropic AI assistant
    ];
    
    # Command line arguments for better performance and privacy
    commandLineArgs = (if isM1 then [
      # M1-specific: Force scaling to compensate for GDK_SCALE=2
      "--force-device-scale-factor=0.75"
    ] else []) ++ [
      # Disable KDE Wallet to prevent errors - use basic password store
      "--password-store=basic"
      
      # Enable hardware acceleration
      "--enable-features=VaapiVideoDecoder"
      "--use-gl=desktop"
      "--enable-gpu-rasterization"
      "--enable-zero-copy"
      
      # Wayland support (auto-detect)
      "--ozone-platform-hint=auto"
      
      # Enable native messaging for 1Password
      "--enable-native-messaging"
      
      # Enable password import features
      "--enable-features=PasswordImport"
      
      # Note: Removed --load-extension flag that was causing "Manifest file missing" error
      # External Extensions are handled automatically by Chromium from the JSON files
      
      # Privacy enhancements
      "--disable-reading-from-canvas"
      "--disable-background-networking"
      
      # Note: Certificate bypass flags moved to chromium-dev profile
      # Use 'chromium-dev' or 'clb' for cluster development
    ];
    
    # Enable spell checking
    dictionaries = [
      pkgs.hunspellDictsChromium.en_US
    ];
  };

  # Chromium is installed as a secondary browser alongside Firefox
  # Extensions are managed declaratively by home-manager
  # No complex scripts or manual installation needed

  # Native messaging host manifest for 1Password
  # This allows the browser extension to communicate with the desktop app
  home.file.".config/chromium/NativeMessagingHosts/com.1password.1password.json" = {
    text = builtins.toJSON {
      name = "com.1password.1password";
      description = "1Password Native Messaging Host";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      # Path to the 1Password browser support binary
      path = onePasswordBrowserSupport;
    };
  };

  # Additional native messaging host for browser support
  home.file.".config/chromium/NativeMessagingHosts/com.1password.browser_support.json" = {
    text = builtins.toJSON {
      name = "com.1password.browser_support";
      description = "1Password Browser Support";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      path = onePasswordBrowserSupport;
    };
  };

  # Configure 1Password browser integration settings
  home.file.".config/1Password/settings/browser-support.json" = {
    text = builtins.toJSON {
      "browser.autoFillShortcut" = {
        "enabled" = true;
        "shortcut" = "Ctrl+Shift+L";
      };
      "browser.showSavePrompts" = true;
      "browser.theme" = "system";
      "security.authenticatedUnlock.enabled" = true;
      "security.authenticatedUnlock.method" = "system";  # Use system authentication
      "security.autolock.minutes" = 10;
      "security.clipboardClearAfterSeconds" = 90;
    };
  };

  # Environment variables for default browser
  # Commented out to avoid conflict with Firefox settings
  # home.sessionVariables = {
  #   DEFAULT_BROWSER = "chromium";
  #   BROWSER = "chromium";
  # };

  # Shell aliases for convenience
  home.shellAliases = {
    chrome = "chromium";
    browser = "chromium";
  };

  # Home-manager handles extension installation automatically
  # No activation scripts needed - this is the proper NixOS way
}
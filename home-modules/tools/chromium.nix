{ config, pkgs, lib, ... }:

{
  # Chromium browser configuration with 1Password and other extensions
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;
    
    # Declaratively install extensions using Chrome Web Store IDs
    extensions = [
      # 1Password - Password Manager
      { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; }
      
      # uBlock Origin - Ad blocker
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }
      
      # Dark Reader - Dark mode for websites
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }
      
      # Vimium - Vim keybindings for navigation
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }
      
      # Privacy Badger - Privacy protection
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; }
    ];
    
    # Command line arguments for better performance and privacy
    commandLineArgs = [
      # Enable hardware acceleration
      "--enable-features=VaapiVideoDecoder"
      "--use-gl=desktop"
      "--enable-gpu-rasterization"
      "--enable-zero-copy"
      
      # Wayland support (auto-detect)
      "--ozone-platform-hint=auto"
      
      # Enable native messaging for 1Password
      "--enable-native-messaging"
      
      # Privacy enhancements
      "--disable-reading-from-canvas"
      "--disable-background-networking"
    ];
    
    # Enable spell checking
    dictionaries = [
      pkgs.hunspellDictsChromium.en_US
    ];
  };
}
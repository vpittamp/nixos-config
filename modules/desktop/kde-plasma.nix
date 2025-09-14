# KDE Plasma 6 Desktop Environment Configuration
{ config, lib, pkgs, ... }:

{
  # Enable X11 and KDE Plasma 6
  services.xserver = {
    enable = true;
    
    # Configure for headless operation with virtual display (for cloud servers)
    videoDrivers = lib.mkDefault [ "modesetting" "fbdev" ];
    
    # Enable DRI for better performance
    deviceSection = ''
      Option "DRI" "3"
      Option "AccelMethod" "glamor"
    '';
  };

  # Display manager
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = false;  # Disable Wayland due to Mesa/GPU issues on Apple Silicon
      
      # Workaround for black screen on logout on Apple Silicon
      settings = {
        General = {
          # Don't halt the X server on logout - helps prevent black screen
          HaltCommand = "";
          RebootCommand = "";
        };
      };
    };
    defaultSession = lib.mkForce "plasmax11";  # Force X11 session (stable on Apple Silicon)
  };
  
  # Desktop environment
  services.desktopManager.plasma6.enable = true;

  # Sound system
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable hardware acceleration
  hardware.graphics.enable = true;

  # Desktop packages
  environment.systemPackages = with pkgs; [
    # KDE applications
    kdePackages.kate
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.spectacle
    kdePackages.okular
    kdePackages.gwenview
    
    # Clipboard management - using native Klipper instead of CopyQ
    # copyq  # Advanced clipboard manager with history (disabled - using Klipper)
    wl-clipboard  # Wayland clipboard utilities
    xclip  # X11 clipboard utilities (fallback)
    xorg.libxcb  # XCB library for Qt
    libxkbcommon  # Keyboard handling for Qt
    
    # Browsers
    chromium  # Default browser with 1Password integration
    # firefox  # Disabled - using Chromium as default
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ pkgs.gitkraken ];

  # Enable flatpak for additional apps
  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  # Enable CUPS for printing
  services.printing.enable = true;

  # Enable bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Set system-wide default browser to Chromium
  environment.sessionVariables = {
    DEFAULT_BROWSER = "chromium";
    BROWSER = "chromium";
  };

}
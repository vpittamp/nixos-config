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
      wayland.enable = true;
    };
    defaultSession = lib.mkDefault "plasma";  # Use Wayland by default
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
    
    # Browsers
    firefox
    chromium
  ];

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
}
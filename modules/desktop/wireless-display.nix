# Wireless Display Support (AirPlay/Miracast)
{ config, lib, pkgs, ... }:

{
  # Install wireless display tools
  environment.systemPackages = with pkgs; [
    # AirPlay server - receive AirPlay streams from iOS/macOS
    uxplay
    
    # Miracast sender - send to TVs/displays (GNOME app works in KDE)
    gnome-network-displays
  ];
  
  # Open firewall for AirPlay
  networking.firewall = {
    allowedTCPPorts = [ 
      7000 7001 7100  # AirPlay audio/video
      5353             # mDNS/Bonjour
    ];
    allowedUDPPorts = [ 
      5353 6000 6001 7011  # AirPlay discovery and data
    ];
  };
  
  # Enable Avahi for AirPlay discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };
  };
}
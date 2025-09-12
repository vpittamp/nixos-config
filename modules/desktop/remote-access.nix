# Remote Desktop Access Configuration (RDP)
{ config, lib, pkgs, ... }:

{
  # Enable RDP for remote desktop access
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startplasma-x11";
    openFirewall = true;
    port = 3389;
  };

  # Firewall configuration for remote access
  networking.firewall.allowedTCPPorts = [
    3389   # RDP
  ];
  
  networking.firewall.allowedUDPPorts = [
    3389   # RDP
  ];

  # Remote access tools
  environment.systemPackages = with pkgs; [
    remmina
    freerdp
    xorg.xauth      # X authentication
  ];

  # Ensure X11 forwarding is enabled for SSH
  services.openssh.settings.X11Forwarding = lib.mkForce true;
}

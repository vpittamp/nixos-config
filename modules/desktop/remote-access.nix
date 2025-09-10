# Remote Desktop Access Configuration (RDP, VNC)
{ config, lib, pkgs, ... }:

{
  # Enable RDP for remote desktop access
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startplasma-x11";
    openFirewall = true;
    port = 3389;
  };

  # Optional: Enable VNC server
  # Uncomment to enable TigerVNC server
  # services.x11vnc = {
  #   enable = true;
  #   auth = "/home/vpittamp/.Xauthority";
  #   password = "vnc_password";  # Change this!
  #   display = 0;
  # };

  # Firewall configuration for remote access
  networking.firewall.allowedTCPPorts = [
    3389   # RDP
    # 5900   # VNC (uncomment if using VNC)
  ];
  
  networking.firewall.allowedUDPPorts = [
    3389   # RDP
  ];

  # Remote access tools
  environment.systemPackages = with pkgs; [
    remmina
    tigervnc
    freerdp
    kdePackages.krdc  # KDE Remote Desktop Client for RDP/VNC connections
  ];

  # Ensure X11 forwarding is enabled for SSH
  services.openssh.settings.X11Forwarding = lib.mkForce true;
}
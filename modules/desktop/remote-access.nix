# Remote Desktop Access Configuration (RDP, VNC)
{ config, lib, pkgs, ... }:

{
  imports = [
    ./vnc-setup.nix  # VNC server configuration
  ];
  # Enable RDP for remote desktop access
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startplasma-x11";
    openFirewall = true;
    port = 3389;
  };

  # Enable TigerVNC server for better Linux-to-Linux remote access
  # Use x0vncserver to share the existing display instead of creating a new one
  systemd.services.vncserver = {
    description = "TigerVNC Server (x0vncserver)";
    after = [ "graphical.target" "display-manager.service" ];
    wantedBy = [ "graphical.target" ];
    
    environment = {
      DISPLAY = ":0";
      XAUTHORITY = "/run/sddm/xauth_session";
    };
    
    serviceConfig = {
      Type = "simple";
      User = "vpittamp";
      Group = "users";
      
      # Use x0vncserver to share the existing display :0
      # This shares the actual desktop session instead of creating a virtual one
      ExecStart = "${pkgs.tigervnc}/bin/x0vncserver -display :0 -rfbport 5901 -passwordfile /home/vpittamp/.vnc/passwd -AlwaysShared";
      
      # Restart on failure
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  # Firewall configuration for remote access
  networking.firewall.allowedTCPPorts = [
    3389   # RDP
    5901   # VNC display :1
  ];
  
  networking.firewall.allowedUDPPorts = [
    3389   # RDP
  ];

  # Remote access tools
  environment.systemPackages = with pkgs; [
    remmina
    tigervnc
    freerdp
    xorg.xinit      # Required for VNC server
    xorg.xauth      # X authentication
  ];

  # Ensure X11 forwarding is enabled for SSH
  services.openssh.settings.X11Forwarding = lib.mkForce true;
}
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
  # Creates a persistent virtual desktop session
  systemd.services.vncserver = {
    description = "TigerVNC Server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    path = [ 
      pkgs.xorg.xinit 
      pkgs.xorg.xauth 
      pkgs.dbus 
      pkgs.kdePackages.plasma-workspace
    ];
    
    environment = {
      HOME = "/home/vpittamp";
    };
    
    serviceConfig = {
      Type = "forking";
      User = "vpittamp";
      Group = "users";
      WorkingDirectory = "/home/vpittamp";
      
      # Create a virtual desktop on display :1
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.tigervnc}/bin/vncserver -kill :1 > /dev/null 2>&1 || true'";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.tigervnc}/bin/vncserver :1 -geometry 1920x1080 -depth 24 -localhost no -fg'";
      ExecStop = "${pkgs.tigervnc}/bin/vncserver -kill :1";
      
      # Don't restart too quickly
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
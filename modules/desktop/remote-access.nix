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

  # Enable TigerVNC server using Xvnc directly
  # This bypasses vncserver wrapper which has issues on NixOS
  systemd.services.vncserver = {
    description = "TigerVNC Xvnc Server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    path = with pkgs; [ 
      xorg.xinit 
      xorg.xauth 
      dbus 
      kdePackages.plasma-workspace
      bash
      coreutils
    ];
    
    environment = {
      HOME = "/home/vpittamp";
      USER = "vpittamp";
    };
    
    serviceConfig = {
      Type = "simple";
      User = "vpittamp";
      Group = "users";
      WorkingDirectory = "/home/vpittamp";
      
      # Start Xvnc with M1 MacBook Pro Retina resolution
      # 2560x1600 is the native resolution for 14" M1 MacBook Pro
      ExecStart = "${pkgs.tigervnc}/bin/Xvnc :1 -geometry 2560x1600 -depth 24 -rfbport 5901 -rfbauth /home/vpittamp/.vnc/passwd -AlwaysShared -dpi 144";
      
      # Start the desktop session after Xvnc is running
      ExecStartPost = "${pkgs.bash}/bin/bash -c 'sleep 2; DISPLAY=:1 /home/vpittamp/.vnc/xstartup &'";
      
      # Clean shutdown
      ExecStop = "${pkgs.procps}/bin/pkill -u vpittamp -f 'Xvnc :1'";
      
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
    x2goclient      # X2Go client for better remote desktop
    xorg.xinit      # Required for VNC server
    xorg.xauth      # X authentication
  ];

  # Ensure X11 forwarding is enabled for SSH
  services.openssh.settings.X11Forwarding = lib.mkForce true;
}
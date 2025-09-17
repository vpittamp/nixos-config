# Remote Desktop Access Configuration (RDP)
{ config, lib, pkgs, ... }:

{
  # Enable RDP for remote desktop access
  services.xrdp = {
    enable = true;
    audio.enable = true;  # Enable audio redirection support
    defaultWindowManager = "startplasma-x11";
    openFirewall = true;
    port = 3389;
  };

  # Configure xrdp settings via configuration file
  environment.etc."xrdp/xrdp.ini".text = lib.mkAfter ''
    # Device redirection settings
    [Channels]
    rdpdr=true
    rdpsnd=true
    drdynvc=true
    cliprdr=true
    rail=true
    xrdpvr=true

    [Sessions]
    # Enable all redirection features
    use_fastpath=both
    require_credentials=yes
    bulk_compression=yes
    new_cursors=yes
    use_bitmap_cache=yes
    use_bitmap_compression=yes
  '';

  # Configure sesman for better session management
  environment.etc."xrdp/sesman.ini".text = lib.mkAfter ''
    [Globals]
    EnableSyslog=yes
    SyslogLevel=INFO

    [Security]
    AllowRootLogin=no
    MaxLoginRetry=4

    [Sessions]
    X11DisplayOffset=10
    MaxSessions=50
    KillDisconnected=no
    DisconnectedTimeLimit=0
    IdleTimeLimit=0

    [Xorg]
    param=Xorg
    param=-config
    param=xrdp/xorg.conf
    param=-noreset
    param=-nolisten
    param=tcp
    param=-logfile
    param=/var/log/xrdp-sesman.log
  '';

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

  # Enable USB/IP kernel modules for potential USB redirection
  # Note: USB/IP tools need to be installed separately if needed
  boot.kernelModules = [ "vhci-hcd" ];

  # Ensure X11 forwarding is enabled for SSH
  services.openssh.settings.X11Forwarding = lib.mkForce true;
}
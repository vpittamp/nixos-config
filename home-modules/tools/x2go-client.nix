# X2Go Client Configuration for M1 MacBook Pro
{ config, lib, pkgs, ... }:

{
  # Create X2Go session configuration
  home.file.".x2goclient/sessions".text = ''
    [nixos-hetzner]
    name=Hetzner KDE Desktop (X2Go)
    host=nixos-hetzner
    user=vpittamp
    sshport=22
    autologin=false
    command=PLASMA
    session=kde-plasma
    speed=4
    pack=16m-jpeg
    quality=9
    type=pc
    geometry=2560x1600
    setdpi=1
    dpi=180
    clipboard=both
    sound=0
    soundsystem=pulse
    startsoundsystem=1
    soundtunnel=1
    useiconv=1
    iconvfrom=UTF-8
    iconvto=UTF-8
    usekbd=1
    fullscreen=1
    multidisp=0
    xinerama=1
    maxdim=1
    usemimebox=1
    mimeboxextensions=
    mimeboxaction=OPEN
    export=
    directrdp=0
    directrdpsettings=
    rdpport=3389
    rdpclient=rdesktop
    print=0
  '';
  
  # Shell aliases for X2Go connections
  programs.bash.shellAliases = {
    # Launch X2Go with proper scaling for HiDPI
    x2go-hetzner = "GDK_SCALE=1 QT_SCALE_FACTOR=1 x2goclient --session=nixos-hetzner";
    
    # Alternative with session selection dialog
    x2go = "GDK_SCALE=1 QT_SCALE_FACTOR=1 x2goclient";
  };
  
  # Create desktop entry for properly scaled X2Go
  home.file.".local/share/applications/x2go-scaled.desktop".text = ''
    [Desktop Entry]
    Name=X2Go Client (Scaled)
    GenericName=Remote Desktop Client
    Comment=Connect to remote desktops using X2Go
    Exec=env GDK_SCALE=1 QT_SCALE_FACTOR=1 ${pkgs.x2goclient}/bin/x2goclient
    Icon=x2goclient
    Terminal=false
    Type=Application
    Categories=Network;RemoteAccess;
    StartupNotify=true
  '';
}
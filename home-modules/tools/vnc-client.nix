# VNC Client Configuration for M1 MacBook Pro
{ config, lib, pkgs, ... }:

{
  # TigerVNC viewer configuration optimized for Retina display
  home.file.".vnc/default.tigervnc" = {
    text = ''
      # TigerVNC Viewer Settings for M1 MacBook Pro
      # Connection settings
      FullScreen=1
      FullScreenMode=all
      FullScreenSelectedMonitors=1
      FullColour=1
      LowColourLevel=0
      PreferredEncoding=Tight
      AutoSelect=1
      Shared=0
      ViewOnly=0
      AcceptClipboard=1
      SendClipboard=1
      SendPrimary=1
      SetPrimary=1
      
      # Display settings for Retina
      DesktopSize=2560x1600
      RemoteResize=1
      QualityLevel=9
      CompressLevel=1
      JPEG=1
      
      # UI Settings
      MenuKey=F8
      FullscreenSystemKeys=1
      PassAllKeys=0
      EmulateMB=1
      Maximize=0
      ToolbarVisible=0
      
      # Performance
      DotWhenNoCursor=0
      PointerEventInterval=0
      Render=opengl
    '';
  };
  
  # Remmina configuration for VNC
  home.file.".config/remmina/remmina.pref" = {
    text = ''
      [remmina]
      # Fullscreen toolbar settings
      fullscreen_toolbar_visibility=0
      floating_toolbar_placement=0
      toolbar_placement=3
      prevent_snap_welcome_message=1
      
      # Display settings
      auto_scroll_step=10
      scale_quality=3
      ssh_tunnel_loopback=1
      prefer_ipv6=0
      
      # Performance
      use_master_password=0
      unlock_timeout=0
      audit=0
      trust_all=0
    '';
  };
  
  # Create a Remmina connection profile for Hetzner VNC
  home.file.".local/share/remmina/hetzner-vnc.remmina".text = ''
    [remmina]
    password=hetzner123
    gateway_usage=0
    colordepth=32
    quality=9
    viewmode=4
    scale=1
    aspectscale=1
    fullscreen=1
    viewonly=0
    disableclipboard=0
    disableencryption=0
    showcursor=1
    disableserverinput=0
    disablesmoothing=0
    enableaudio=0
    protocol=VNC
    server=nixos-hetzner:5901
    resolution_mode=2
    resolution_width=2560
    resolution_height=1600
    name=Hetzner KDE Desktop (VNC)
    group=NixOS
  '';
  
  # Shell aliases for quick connection
  programs.bash.shellAliases = {
    # Fullscreen with proper HiDPI scaling
    vnc-hetzner = "FLTK_SCALING_FACTOR=1 XAUTHORITY=$HOME/.Xauthority vncviewer -FullScreen -DesktopSize=2560x1600 -RemoteResize=1 -QualityLevel=9 nixos-hetzner:5901";
    
    # Windowed mode with scaling
    vnc-hetzner-windowed = "FLTK_SCALING_FACTOR=1 XAUTHORITY=$HOME/.Xauthority vncviewer -DesktopSize=2560x1600 nixos-hetzner:5901";
    
    # Alternative scaled mode (if FLTK scaling doesn't work)
    vnc-hetzner-scaled = "FLTK_SCALING_FACTOR=0.5 XAUTHORITY=$HOME/.Xauthority vncviewer -FullScreen -DesktopSize=2560x1600 nixos-hetzner:5901";
    
    # No scaling - let system handle it
    vnc-hetzner-native = "XAUTHORITY=$HOME/.Xauthority vncviewer -FullScreen -AutoSelect=0 -FullColour -PreferredEncoding=Tight -QualityLevel=9 nixos-hetzner:5901";
  };
}
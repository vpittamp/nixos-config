# M1-specific fixes for WiFi and display issues
{ config, lib, pkgs, ... }:

{
  # Service to reload WiFi module after boot
  # The brcmfmac module sometimes fails to load properly on first boot
  systemd.services.reload-wifi = {
    description = "Reload WiFi module for M1";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "reload-wifi" ''
        # Wait a moment for system to settle
        sleep 5
        
        # Reload WiFi module if it's not working
        if ! ${pkgs.iproute2}/bin/ip link show | grep -q "wlp1s0f0"; then
          echo "WiFi interface not found, reloading brcmfmac module..."
          ${pkgs.kmod}/bin/modprobe -r brcmfmac || true
          sleep 1
          ${pkgs.kmod}/bin/modprobe brcmfmac
          sleep 2
          
          # Enable WiFi in NetworkManager
          ${pkgs.networkmanager}/bin/nmcli device set wlp1s0f0 managed yes || true
        fi
      '';
    };
  };
  
  # Fix for KDE forceFontDPI being reset to 100
  # This ensures the correct DPI is always set for the Retina display
  systemd.user.services.fix-kde-dpi = {
    description = "Fix KDE DPI for Retina display";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "fix-kde-dpi" ''
        # Wait for KDE to start
        sleep 3
        
        # Force correct DPI in KDE config
        echo -e "[General]\nforceFontDPI=180" > ~/.config/kcmfonts
        
        # Also set via xrdb
        echo "Xft.dpi: 180" | ${pkgs.xorg.xrdb}/bin/xrdb -merge
      '';
    };
  };
}
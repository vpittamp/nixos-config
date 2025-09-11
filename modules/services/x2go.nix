# X2Go Remote Desktop Server Configuration
# Alternative to VNC with better performance over slow connections
{ config, lib, pkgs, ... }:

{
  # Enable X2Go server
  services.x2goserver = {
    enable = true;
    
    # Renice suspended sessions for better performance
    superenicer = {
      enable = true;
    };
  };
  
  # X2Go requires SSH with X11 forwarding
  services.openssh.settings = {
    X11Forwarding = lib.mkForce true;
  };
  
  # No additional firewall ports needed - X2Go uses SSH (port 22)
  # Port 22 is already open from base configuration
  
  # System packages for X2Go
  environment.systemPackages = with pkgs; [
    x2goserver
  ];
}
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
    
    # Configure X2Go agent options for proper display
    nxagentDefaultOptions = [
      "-extension GLX"
      "-nolisten tcp" 
      "-dpi 180"
      "-geometry 2560x1600"
    ];
  };
  
  # X2Go requires SSH with X11 forwarding
  services.openssh.settings = {
    X11Forwarding = lib.mkForce true;
  };
  
  # Add user to x2go groups
  users.users.vpittamp = {
    extraGroups = [ "x2go" "x2gouser" ];
  };
  
  # No additional firewall ports needed - X2Go uses SSH (port 22)
  # Port 22 is already open from base configuration
  
  # System packages for X2Go
  environment.systemPackages = with pkgs; [
    x2goserver
  ];
}
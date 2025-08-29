# Tailscale configuration for NixOS
{ config, pkgs, lib, ... }:

{
  # Enable Tailscale service
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";  # or "server" if you want to be an exit node
  };

  # Open the Tailscale port
  networking.firewall = {
    # Required for Tailscale to work
    checkReversePath = "loose";
    # Allow Tailscale UDP port
    allowedUDPPorts = [ config.services.tailscale.port ];
    # Trust the tailscale interface
    trustedInterfaces = [ "tailscale0" ];
  };

  # Optional: Enable SSH through Tailscale
  services.openssh = {
    enable = true;
    settings = {
      # Only allow SSH through Tailscale interface
      # ListenAddress = "100.x.x.x";  # Your Tailscale IP
    };
  };

  # Make sure tailscale is in system packages (already done in our overlay)
  # environment.systemPackages = [ pkgs.tailscale ];
}
# WSL-specific Docker Desktop Integration Module
# This module contains all WSL-specific Docker configurations
# Only imported by the WSL configuration, not by Hetzner or M1
{ config, lib, pkgs, ... }:

{
  # WSL Docker Desktop environment variables
  environment.sessionVariables = {
    # Point to Docker Desktop's socket in WSL
    DOCKER_HOST = "unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock";
  };
  
  # System-wide shell aliases for WSL Docker Desktop
  environment.shellAliases = {
    # Use the wrapper script that handles Docker Desktop integration
    docker = "/etc/nixos/docker-wrapper.sh";
  };
  
  # Ensure the docker wrapper script has correct permissions
  system.activationScripts.dockerWrapper = ''
    if [ -f /etc/nixos/docker-wrapper.sh ]; then
      chmod +x /etc/nixos/docker-wrapper.sh
    fi
  '';
  
  # Add user to docker group (even though we're using Docker Desktop)
  # This ensures compatibility with tools expecting the group
  users.users.vpittamp.extraGroups = [ "docker" ];
  
  # Create docker group if it doesn't exist
  users.groups.docker = {};
  
  # Note: We don't enable virtualisation.docker here because
  # Docker Desktop provides the Docker daemon from Windows side
  virtualisation.docker.enable = lib.mkForce false;
}
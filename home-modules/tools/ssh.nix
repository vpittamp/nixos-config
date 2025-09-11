{ config, pkgs, lib, ... }:

let
  # Detect if we're on a server (Hetzner)
  isServer = config.networking.hostName or "" == "nixos-hetzner";
  
  # Use 1Password agent on workstations, regular SSH agent on servers
  sshAuthSock = if isServer then "$SSH_AUTH_SOCK" else "~/.1password/agent.sock";
in
{
  # SSH configuration with conditional 1Password integration and DevSpace support
  # Using a writable config approach for DevSpace compatibility
  
  # Don't let home-manager manage the SSH config directly
  # Instead, we'll create it via onChange hook to make it writable
  home.file.".ssh/config_source" = {
    text = ''
      Include ~/.ssh/devspace_config
      
      Host *
        ${lib.optionalString (!isServer) "IdentityAgent ${sshAuthSock}"}
        AddKeysToAgent yes
        IdentitiesOnly yes
      
      Host github.com
        User git
        ${lib.optionalString (!isServer) "IdentityAgent ${sshAuthSock}"}
      
      Host gitlab.com
        User git
        ${lib.optionalString (!isServer) "IdentityAgent ${sshAuthSock}"}
      
      Host *.hetzner.cloud
        User root
        ${lib.optionalString (!isServer) "IdentityAgent ${sshAuthSock}"}
        ForwardAgent yes
    '';
    onChange = ''
      # Create a writable SSH config from the source
      cp -f ~/.ssh/config_source ~/.ssh/config
      chmod 600 ~/.ssh/config
      
      # Ensure DevSpace config file exists and is writable
      touch ~/.ssh/devspace_config
      chmod 600 ~/.ssh/devspace_config
    '';
  };
}
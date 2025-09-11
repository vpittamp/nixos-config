{ config, pkgs, lib, ... }:

{
  # SSH configuration with 1Password integration and DevSpace support
  # Using a writable config approach for DevSpace compatibility
  
  # Don't let home-manager manage the SSH config directly
  # Instead, we'll create it via onChange hook to make it writable
  home.file.".ssh/config_source" = {
    text = ''
      Include ~/.ssh/devspace_config
      
      Host *
        IdentityAgent ~/.1password/agent.sock
        AddKeysToAgent yes
        IdentitiesOnly yes
      
      Host github.com
        User git
        IdentityAgent ~/.1password/agent.sock
      
      Host gitlab.com
        User git
        IdentityAgent ~/.1password/agent.sock
      
      Host *.hetzner.cloud
        User root
        IdentityAgent ~/.1password/agent.sock
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
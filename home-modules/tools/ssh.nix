{ config, pkgs, lib, ... }:

let
  # 1Password SSH agent path differs between Linux and macOS
  onePasswordAgentPath = if pkgs.stdenv.isDarwin
    then "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else "~/.1password/agent.sock";
in
{
  # SSH configuration with 1Password integration and DevSpace support
  # Using a writable config approach for DevSpace compatibility

  # Don't let home-manager manage the SSH config directly
  # Instead, we'll create it via onChange hook to make it writable
  home.file.".ssh/config_source" = {
    text = ''
      Include ~/.ssh/devspace_config

      Match exec "test -n \"$SSH_AUTH_SOCK\""
        IdentityAgent $SSH_AUTH_SOCK

      Match exec "test -z \"$SSH_AUTH_SOCK\""
        IdentityAgent ${onePasswordAgentPath}

      Host *
        AddKeysToAgent yes
      
      Host github.com
        User git
        IdentitiesOnly yes
        IdentityFile ~/.ssh/git_signing_key.pub

      Host gitlab.com
        User git
        IdentitiesOnly yes
        IdentityFile ~/.ssh/git_signing_key.pub

      Host *.hetzner.cloud
        User root
        ForwardAgent yes

      # Tailscale hosts - generic pattern
      Host ryzen thinkpad
        HostName %h.tail286401.ts.net
        User vpittamp
        ForwardAgent yes
        StrictHostKeyChecking accept-new
        ControlMaster auto
        ControlPersist 10m
        ControlPath ~/.ssh/controlmasters/%C

      Host nixos-* *.tail*.ts.net
        User vpittamp
        ForwardAgent yes
        StrictHostKeyChecking accept-new
        ControlMaster auto
        ControlPersist 10m
        ControlPath ~/.ssh/controlmasters/%C

      # Specific Tailscale machines for better compatibility
      Host nixos-hetzner
        HostName nixos-hetzner
        User vpittamp
        ForwardAgent yes

      Host nixos-wsl
        HostName nixos-wsl
        User vpittamp
        ForwardAgent yes
    '';
    onChange = ''
      # Create a writable SSH config from the source
      cp -f ~/.ssh/config_source ~/.ssh/config
      chmod 600 ~/.ssh/config

      mkdir -p ~/.ssh/controlmasters
      chmod 700 ~/.ssh/controlmasters
      
      # Ensure DevSpace config file exists and is writable
      touch ~/.ssh/devspace_config
      chmod 600 ~/.ssh/devspace_config
    '';
  };
}

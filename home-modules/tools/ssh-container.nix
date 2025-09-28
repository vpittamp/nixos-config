{ pkgs, ... }:

{
  # Basic SSH configuration for containers without 1Password
  home.file.".ssh/config_source".text = ''
    # SSH client configuration for containers

    Host *
      AddKeysToAgent yes
      IdentitiesOnly no
      StrictHostKeyChecking accept-new
      ServerAliveInterval 120
      ServerAliveCountMax 3

    Host github.com
      User git
      IdentitiesOnly no

    Host gitlab.com
      User git
      IdentitiesOnly no

    Host *.hetzner.cloud
      User root
      ForwardAgent yes
      IdentitiesOnly no

    # Tailscale network hosts
    Host nixos-* *.tail*.ts.net
      User vpittamp
      ForwardAgent yes
      IdentitiesOnly no

    # DevSpace SSH configuration
    Host *.devspace
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
      IdentitiesOnly no

    # Include any user-specific config at the end
    Include ~/.ssh/config.d/*
  '';

  # Create the config directory for additional configs
  home.file.".ssh/config.d/.keep".text = "";

  # Install SSH packages
  home.packages = with pkgs; [
    openssh
    sshpass
    ssh-copy-id
  ];

  # SSH agent configuration (using system SSH agent instead of 1Password)
  programs.ssh = {
    enable = true;

    # Use the system SSH agent
    extraConfig = ''
      AddKeysToAgent yes
      IdentitiesOnly no
    '';
  };

  # Set up SSH config management script
  home.file.".local/bin/update-ssh-config" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Update SSH config from source
      if [ -f ~/.ssh/config_source ]; then
        cp ~/.ssh/config_source ~/.ssh/config
        chmod 600 ~/.ssh/config
        echo "SSH config updated from source"
      fi
    '';
  };

  # Activation script to set up SSH config on first run
  home.activation.setupSshConfig = ''
    # Ensure SSH directory exists with correct permissions
    mkdir -p ~/.ssh/config.d
    chmod 700 ~/.ssh
    chmod 700 ~/.ssh/config.d

    # Copy the source config to the actual config if it doesn't exist
    if [ ! -f ~/.ssh/config ] && [ -f ~/.ssh/config_source ]; then
      cp ~/.ssh/config_source ~/.ssh/config
      chmod 600 ~/.ssh/config
    fi
  '';
}
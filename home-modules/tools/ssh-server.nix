{ config, pkgs, lib, ... }:

let
  # Detect if we're on a server (Hetzner)
  isServer = config.networking.hostName or "" == "nixos-hetzner";
in
{
  # SSH key management for servers without 1Password desktop
  config = lib.mkIf isServer {
    # SSH client configuration for servers
    programs.ssh = {
      enable = true;
      extraConfig = ''
        AddKeysToAgent yes
        IdentityFile ~/.ssh/id_ed25519
        IdentityFile ~/.ssh/id_rsa
      '';
    };
    
    # Create SSH keys for server authentication
    # These should be added to GitHub/GitLab manually or via gh/glab CLI
    home.file.".ssh/README-server.md" = {
      text = ''
        # SSH Key Setup for Servers
        
        Since this is a headless server without 1Password desktop app,
        you need to manually set up SSH keys for GitHub/GitLab access:
        
        ## Option 1: Generate new SSH key
        ```bash
        ssh-keygen -t ed25519 -C "$(hostname)@$(date +%Y-%m-%d)"
        ```
        
        ## Option 2: Copy from 1Password (if you have CLI access)
        ```bash
        # Login to 1Password CLI
        op signin
        
        # List SSH keys
        op item list --categories "SSH Key"
        
        # Get a specific key
        op item get "GitHub SSH Key" --fields "private key" > ~/.ssh/id_ed25519
        op item get "GitHub SSH Key" --fields "public key" > ~/.ssh/id_ed25519.pub
        chmod 600 ~/.ssh/id_ed25519
        chmod 644 ~/.ssh/id_ed25519.pub
        ```
        
        ## Add to GitHub
        ```bash
        # Using GitHub CLI (recommended)
        gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
        
        # Or manually copy and add via web UI
        cat ~/.ssh/id_ed25519.pub
        ```
        
        ## Git Configuration for Servers
        
        Git commits won't be signed on this server since 1Password desktop
        is not available. Use personal access tokens or OAuth for authentication:
        
        ```bash
        # GitHub CLI authentication (recommended)
        gh auth login
        
        # Use HTTPS with token caching
        git config --global credential.helper cache
        ```
      '';
    };
  };
}
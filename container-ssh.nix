# SSH configuration module for containers
# Enables SSH server with secure defaults for development containers
{ config, lib, pkgs, ... }:

let
  # SSH configuration can be controlled via environment variables
  sshEnabled = builtins.getEnv "CONTAINER_SSH_ENABLED" == "true";
  sshPort = let
    port = builtins.getEnv "CONTAINER_SSH_PORT";
  in if port == "" then 2222 else lib.toInt port;
in
{
  # Only enable SSH if explicitly requested
  config = lib.mkIf sshEnabled {
    # Enable OpenSSH server
    services.openssh = {
      enable = true;
      ports = [ sshPort ];
      
      settings = {
        # Security settings
        PermitRootLogin = "yes";  # Required for container access
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
        ChallengeResponseAuthentication = false;
        UsePAM = false;
        
        # Performance settings
        X11Forwarding = false;
        PrintMotd = false;
        PrintLastLog = false;
        TCPKeepAlive = true;
        ClientAliveInterval = 60;
        ClientAliveCountMax = 3;
        
        # Allow specific users
        AllowUsers = [ "root" "code" "vpittamp" ];
        
        # Use only strong ciphers
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
        ];
        
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };
      
      # Extra configuration
      extraConfig = ''
        # Allow SSH agent forwarding for git operations
        AllowAgentForwarding yes
        
        # Custom SFTP settings for VS Code
        Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
        
        # Host key algorithms
        HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
      '';
    };
    
    # Ensure SSH host keys persist (will be mounted from ConfigMap)
    environment.etc = {
      "ssh/ssh_host_ed25519_key" = {
        mode = "0600";
        source = "/ssh-host-keys/ssh_host_ed25519_key";
      };
      "ssh/ssh_host_ed25519_key.pub" = {
        mode = "0644";
        source = "/ssh-host-keys/ssh_host_ed25519_key.pub";
      };
      "ssh/ssh_host_rsa_key" = {
        mode = "0600";
        source = "/ssh-host-keys/ssh_host_rsa_key";
      };
      "ssh/ssh_host_rsa_key.pub" = {
        mode = "0644";
        source = "/ssh-host-keys/ssh_host_rsa_key.pub";
      };
    } // lib.optionalAttrs (builtins.pathExists "/ssh-host-keys") {};
    
    # Create SSH directories for users
    system.activationScripts.ssh-setup = ''
      # Setup SSH for root user (required for container access)
      mkdir -p /root/.ssh
      touch /root/.ssh/authorized_keys
      chmod 700 /root/.ssh
      chmod 600 /root/.ssh/authorized_keys
      
      # Copy authorized keys from mounted secret if available
      if [ -f /ssh-keys/authorized_keys ]; then
        cp /ssh-keys/authorized_keys /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
      fi
      
      # Setup SSH for code user
      if id -u code >/dev/null 2>&1; then
        mkdir -p /home/code/.ssh
        touch /home/code/.ssh/authorized_keys
        chown -R code:users /home/code/.ssh
        chmod 700 /home/code/.ssh
        chmod 600 /home/code/.ssh/authorized_keys
        
        # Copy authorized keys from mounted secret if available
        if [ -f /ssh-keys/authorized_keys ]; then
          cp /ssh-keys/authorized_keys /home/code/.ssh/authorized_keys
          chown code:users /home/code/.ssh/authorized_keys
          chmod 600 /home/code/.ssh/authorized_keys
        fi
      fi
      
      # Setup SSH for vpittamp user if exists
      if id -u vpittamp >/dev/null 2>&1; then
        mkdir -p /home/vpittamp/.ssh
        touch /home/vpittamp/.ssh/authorized_keys
        chown -R vpittamp:users /home/vpittamp/.ssh
        chmod 700 /home/vpittamp/.ssh
        chmod 600 /home/vpittamp/.ssh/authorized_keys
        
        # Copy authorized keys from mounted secret if available
        if [ -f /ssh-keys/authorized_keys ]; then
          cp /ssh-keys/authorized_keys /home/vpittamp/.ssh/authorized_keys
          chown vpittamp:users /home/vpittamp/.ssh/authorized_keys
          chmod 600 /home/vpittamp/.ssh/authorized_keys
        fi
      fi
    '';
    
    # Open firewall for SSH (container environments usually don't have firewall)
    networking.firewall.allowedTCPPorts = lib.mkIf config.networking.firewall.enable [ sshPort ];
    
    # Ensure SSH service starts automatically
    systemd.services.sshd = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
    };
  };
}
{ config, pkgs, lib, ... }:

{
  # KDE Wallet declarative configuration for 1Password integration
  
  # Install required packages
  home.packages = with pkgs; [
    libsecret
    kdePackages.kwallet
    kdePackages.kwallet-pam
    kdePackages.kwalletmanager
  ];
  
  # Simple wallet initialization with empty password for automation
  # Since 1Password handles actual secrets, the wallet just needs to exist
  home.activation.initializeKdeWallet = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Ensure KDE Wallet directory exists
    mkdir -p $HOME/.local/share/kwalletd
    
    # Check if wallet already exists
    if [ ! -f "$HOME/.local/share/kwalletd/kdewallet.kwl" ] && [ ! -f "$HOME/.local/share/kwalletd/kdewallet.salt" ]; then
      echo "Initializing KDE Wallet with empty password for automation..."
      
      # Start wallet daemon if not running
      if ! pgrep -f kwalletd6 > /dev/null 2>&1; then
        ${pkgs.kdePackages.kwallet}/bin/kwalletd6 &
        sleep 2
      fi
      
      # Create wallet with empty password using kwallet-query
      # This creates the wallet without any password prompt
      echo "" | ${pkgs.kdePackages.kwallet}/bin/kwallet-query kdewallet -f Passwords -w 1password-init 2>/dev/null || true
      
      echo "KDE Wallet initialized with empty password"
    fi
  '';
  
  # KDE Wallet settings are configured in plasma-config.nix
  # Additional wallet-specific configurations can be added here
  
  # Create systemd service to ensure wallet is unlocked on login
  systemd.user.services.kwallet-unlock = {
    Unit = {
      Description = "Unlock KDE Wallet on login";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      
      # Script to unlock wallet using 1Password CLI
      ExecStart = pkgs.writeShellScript "kwallet-unlock" ''
        #!/usr/bin/env bash
        
        # Wait for wallet daemon
        for i in {1..10}; do
          if pgrep -f kwalletd6 > /dev/null; then
            break
          fi
          sleep 1
        done
        
        # Check if wallet exists and needs unlocking
        if [ -f "$HOME/.local/share/kwalletd/kdewallet.salt" ]; then
          # Try to open wallet with empty password first (for auto-unlock)
          ${pkgs.kdePackages.kwallet}/bin/kwallet-query kdewallet -l >/dev/null 2>&1 || {
            echo "Wallet needs password - should be configured for auto-unlock"
          }
        else
          echo "Wallet not yet created - will be created on first use"
        fi
      '';
    };
    
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
  
  # Environment variables for Secret Service API
  home.sessionVariables = {
    # Use KDE Wallet for Secret Service
    SECRET_SERVICE_PROVIDER = "kwallet";
    
    # Tell applications to use KDE Wallet
    KWALLET_FORCE_ENABLE = "1";
  };
  
}
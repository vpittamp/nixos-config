{ config, pkgs, lib, osConfig, ... }:

{
  # Add convenience script to check 1Password status
  home.packages = with pkgs; [
    (writeShellScriptBin "1password-check" ''
      #!/usr/bin/env bash
      echo "=== 1Password Status Check ==="
      echo ""
      
      # Check if desktop app is running
      if pgrep -f "1password" > /dev/null; then
        echo "✅ 1Password desktop app is running"
      else
        echo "❌ 1Password desktop app is not running"
        echo "   Starting it now..."
        1password --silent &
        sleep 3
      fi
      
      # Check CLI version
      echo ""
      echo "CLI Version:"
      op --version || echo "❌ CLI not found"
      
      # Check CLI integration
      echo ""
      echo "CLI Integration Status:"
      if op whoami 2>/dev/null; then
        echo "✅ CLI is connected to desktop app"
      else
        echo "❌ CLI cannot connect to desktop app"
        echo ""
        echo "Note: CLI integration has been configured."
        echo "If still not working, try:"
        echo "1. Run: 1p-restart"
        echo "2. Sign in to 1Password app"
        echo "3. Try again"
      fi
      
      # Check SSH agent
      echo ""
      echo "SSH Agent Status:"
      if [ -S "$HOME/.1password/agent.sock" ]; then
        echo "✅ 1Password SSH agent socket exists"
        SSH_AUTH_SOCK="$HOME/.1password/agent.sock" ssh-add -l 2>/dev/null && \
          echo "✅ SSH agent is working" || \
          echo "⚠️  SSH agent socket exists but not responding"
      else
        echo "❌ 1Password SSH agent not configured"
      fi
      
      # Check KDE Wallet (native keyring)
      echo ""
      echo "Keyring Status:"
      if pgrep -f "kwalletd" > /dev/null; then
        echo "✅ KDE Wallet is running (native keyring)"
      else
        echo "⚠️  KDE Wallet not running, starting it..."
        kwalletd6 &
      fi
    '')
  ];
  
  # Auto-start 1Password desktop app on login with proper environment
  # Using single autostart mechanism (XDG desktop entry) to avoid duplicate system tray icons
  home.file.".config/autostart/1password.desktop" = {
    text = ''
      [Desktop Entry]
      Name=1Password
      GenericName=Password Manager
      Comment=1Password - Password Manager
      Exec=${pkgs._1password-gui}/bin/1password --silent --enable-features=UseOzonePlatform --ozone-platform=x11
      Terminal=false
      Type=Application
      Icon=1password
      StartupNotify=true
      Categories=Utility;Security;
      X-GNOME-Autostart-enabled=true
      X-KDE-autostart-after=panel
      Hidden=false
    '';
  };
  
  # Note: 1Password settings are managed by onepassword.nix
  # The CLI integration is already enabled in the existing settings
  
  # Create environment file for 1Password with current display
  home.file.".config/1password/env" = {
    text = ''
      # This file is sourced by 1Password systemd service
      DISPLAY=:10.0
    '';
  };
  
  
  # Shell alias for quick checks
  home.shellAliases = {
    "1p-check" = "1password-check";
    "1p-start" = "1password --silent &";
    "1p-restart" = "pkill -f 1password; sleep 2; 1password --silent &";
  };
  
  # Environment variables for 1Password with KDE Wallet
  home.sessionVariables = {
    # 1Password specific
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
    OP_DEVICE = "Linux";
    
    # Use KDE's native Secret Service implementation
    LIBSECRET_BACKEND = "kwallet";
  };
}
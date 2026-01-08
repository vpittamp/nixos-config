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
  # Using systemd user service for reliable autostart that works even after nixos-rebuild
  # Optimized for Sway/i3 window manager with system tray support
  #
  # 1Password System Tray Behavior:
  # - Starts minimized to system tray (--silent flag)
  # - Persists in tray even when main window is closed
  # - Uses system authentication (polkit) for biometric-like unlock
  # - Click tray icon to open, close window to minimize back to tray
  systemd.user.services.onepassword-gui = {
    Unit = {
      Description = "1Password Desktop Application";
      After = [ "graphical-session.target" "tray.target" ];
      PartOf = [ "graphical-session.target" ];
      # Ensure we wait for system tray to be ready
      Wants = [ "tray.target" ];
      # Don't start before tray is available
      Requires = [ "tray.target" ];
    };

    Service = {
      Type = "simple";
      # Launch 1Password in background with system tray support
      # --silent: Start minimized to system tray (persists in tray)
      # --enable-features=UseOzonePlatform: Use Ozone platform for better Wayland/X11 support
      # --ozone-platform-hint=auto: Auto-detect X11/Wayland
      ExecStart = "${pkgs._1password-gui}/bin/1password --silent --ozone-platform-hint=auto --enable-features=UseOzonePlatform";
      Restart = "on-failure";
      RestartSec = 5;
      # Ensure 1Password stays running
      TimeoutStopSec = 10;

      # Environment for better integration
      Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
        # Enable biometric unlock via polkit
        "OP_BIOMETRIC_UNLOCK_ENABLED=true"
      ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
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

  # Ensure 1Password tray settings are enabled (merged with existing settings)
  # This runs on every home-manager activation to ensure tray icon works
  home.activation.onepasswordTraySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS_FILE="$HOME/.config/1Password/settings/settings.json"
    if [ -f "$SETTINGS_FILE" ]; then
      # Merge tray settings into existing settings (preserves user settings)
      ${pkgs.jq}/bin/jq '. + {
        "app.keepInTray": true,
        "app.minimizeToTray": true,
        "app.useHardwareAcceleration": true
      }' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    fi
  '';
  
  
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
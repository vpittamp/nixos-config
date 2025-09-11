{ config, pkgs, lib, ... }:

{
  # Ensure 1Password environment variables are set in user sessions
  programs.bash.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
  };
  
  # Also set in profile for non-interactive shells
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
  };
  
  # Create initialization script for 1Password
  home.file.".config/1Password/init.sh" = {
    text = ''
      #!/usr/bin/env bash
      # 1Password initialization script
      
      # Ensure 1Password agent socket is available
      export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
      
      # Check if 1Password is running
      if ! pgrep -x "1password" > /dev/null; then
        echo "Starting 1Password in background..."
        1password --silent &
        sleep 2
      fi
      
      # Verify agent is working
      if [ -S "$SSH_AUTH_SOCK" ]; then
        echo "1Password SSH agent is ready at $SSH_AUTH_SOCK"
      else
        echo "Warning: 1Password SSH agent socket not found"
      fi
    '';
    executable = true;
  };
  
  # Source it in bashrc
  programs.bash.initExtra = ''
    # Initialize 1Password environment
    if [ -f "$HOME/.config/1Password/init.sh" ]; then
      source "$HOME/.config/1Password/init.sh" 2>/dev/null
    fi
  '';
}
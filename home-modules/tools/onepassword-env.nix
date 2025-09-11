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
      export OP_BIOMETRIC_UNLOCK_ENABLED="true"
      
      # Check if 1Password is running (only start if we have DISPLAY)
      if [ -n "$DISPLAY" ] && ! pgrep -x "1password" > /dev/null; then
        echo "Starting 1Password in background..."
        1password --silent &
        sleep 2
      fi
      
      # Verify agent is working
      if [ -S "$SSH_AUTH_SOCK" ]; then
        # Test the agent silently
        ssh-add -l &>/dev/null
        if [ $? -eq 0 ] || [ $? -eq 1 ]; then
          # Exit code 0 = has keys, 1 = no keys, 2 = agent not running
          :  # Agent is working
        else
          echo "Warning: 1Password SSH agent not responding"
        fi
      else
        echo "Warning: 1Password SSH agent socket not found at $SSH_AUTH_SOCK"
      fi
    '';
    executable = true;
  };
  
  # Enhanced bash configuration
  programs.bash.initExtra = ''
    # Set SSH_AUTH_SOCK for 1Password
    export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
    
    # Initialize 1Password environment
    if [ -f "$HOME/.config/1Password/init.sh" ]; then
      source "$HOME/.config/1Password/init.sh" 2>/dev/null
    fi
    
    # Source 1Password plugins if available
    if [ -f "$HOME/.config/op/plugins.sh" ]; then
      source "$HOME/.config/op/plugins.sh"
    fi
  '';
}
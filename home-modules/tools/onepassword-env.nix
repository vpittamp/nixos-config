{ config, pkgs, lib, ... }:

let
  # 1Password SSH agent path differs between Linux and macOS
  onePasswordAgentPath = if pkgs.stdenv.isDarwin
    then "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else "$HOME/.1password/agent.sock";
in
{
  # Ensure 1Password environment variables are set in user sessions
  programs.bash.sessionVariables = {
    SSH_AUTH_SOCK = onePasswordAgentPath;
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
  };

  # Also set in profile for non-interactive shells
  home.sessionVariables = {
    SSH_AUTH_SOCK = onePasswordAgentPath;
    OP_BIOMETRIC_UNLOCK_ENABLED = "true";
  };
  
  # Create initialization script for 1Password
  home.file.".config/1Password/init.sh" = {
    text = ''
      #!/usr/bin/env bash
      # 1Password initialization script

      # Ensure 1Password agent socket is available
      # Only set if not already set by SSH agent forwarding
      if [ -z "$SSH_AUTH_SOCK" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
        export SSH_AUTH_SOCK="${onePasswordAgentPath}"
      fi
      export OP_BIOMETRIC_UNLOCK_ENABLED="true"

      # Don't auto-start 1Password - it should be started by the desktop environment
      # or manually by the user when needed. Auto-starting causes segfaults.
      # if [ -n "$DISPLAY" ] && ! pgrep -x "1password" > /dev/null; then
      #   echo "Starting 1Password in background..."
      #   1password --silent &
      #   sleep 2
      # fi

      # Verify agent is working (silently)
      if [ -S "$SSH_AUTH_SOCK" ]; then
        # Test the agent silently
        ssh-add -l &>/dev/null
        # Exit code 0 = has keys, 1 = no keys, 2 = agent not running
        # We don't need to notify the user unless there's a real problem
      fi
    '';
    executable = true;
  };

  # Enhanced bash configuration
  programs.bash.initExtra = ''
    # Set SSH_AUTH_SOCK for 1Password
    # IMPORTANT: Only set if not already set by SSH agent forwarding
    # When SSH'ing in with -A, SSH_AUTH_SOCK will be set to forwarded agent
    if [ -z "$SSH_AUTH_SOCK" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
      export SSH_AUTH_SOCK="${onePasswordAgentPath}"
    fi

    # Initialize 1Password environment
    if [ -f "$HOME/.config/1Password/init.sh" ]; then
      source "$HOME/.config/1Password/init.sh" 2>/dev/null
    fi
  '';
}
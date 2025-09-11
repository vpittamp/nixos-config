# 1Password Shell Plugins Configuration
# Enables biometric authentication for CLI tools
{ config, pkgs, lib, ... }:

{
  # Enable 1Password shell plugins
  programs._1password-shell-plugins = {
    enable = true;
    
    # Enable plugins for specific tools
    plugins = with pkgs; [
      gh          # GitHub CLI
      awscli2     # AWS CLI
      # Add more as needed:
      # glab      # GitLab CLI
      # stripe    # Stripe CLI
      # doctl     # DigitalOcean CLI
    ];
  };

  # Additional shell configuration for 1Password
  programs.bash.initExtra = ''
    # 1Password CLI authentication helper
    source <(op completion bash) 2>/dev/null || true
    
    # Helper functions for 1Password operations
    op-signin() {
      eval $(op signin)
    }
    
    # Use GitHub without 1Password plugin wrapper for non-interactive operations
    gh-direct() {
      command gh "$@"
    }
    
    # Use GitHub with 1Password plugin for interactive operations
    gh-auth() {
      op plugin run -- gh auth login --git-protocol https
    }
    
    # AWS authentication using 1Password
    aws-auth() {
      op plugin run -- aws configure
    }
    
    # For non-interactive git operations, use direct gh command
    export GIT_CREDENTIAL_HELPER_GITHUB="command gh auth git-credential"
  '';

  # Git configuration is now handled in git.nix module
}
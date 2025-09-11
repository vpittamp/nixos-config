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
    
    # Helper to signin to 1Password
    op-signin() {
      eval $(op signin)
    }
    
    # GitHub authentication using 1Password
    gh-auth() {
      op plugin run -- gh auth login --git-protocol ssh
    }
    
    # AWS authentication using 1Password
    aws-auth() {
      op plugin run -- aws configure
    }
  '';

  # Git configuration is now handled in git.nix module
}
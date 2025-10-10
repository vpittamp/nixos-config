# 1Password Shell Plugins Configuration
# Enables biometric authentication for CLI tools using the official 1Password module
{ config, pkgs, lib, inputs, ... }:

{
  # Official 1Password Shell Plugins configuration
  # This module is imported from the onepassword-shell-plugins flake in flake.nix
  # The module automatically creates shell integration for biometric authentication

  programs._1password-shell-plugins = {
    enable = true;

    # Configure plugins for tools we use
    # Each plugin will automatically wrap the CLI command with 1Password authentication
    plugins = with pkgs; [
      gh          # GitHub CLI - authenticate with 1Password
      cachix      # Cachix binary cache - authenticate with 1Password
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

    # Helper function to list configured plugins
    op-list() {
      echo "🔐 1Password Shell Plugins Status:"
      echo "=================================="
      echo "Configured plugins:"
      echo "  - gh (GitHub CLI)"
      echo "  - cachix (Cachix)"
      echo ""
      echo "Active plugins from shell-plugins module:"
      type gh 2>/dev/null | head -1
      type cachix 2>/dev/null | head -1
      echo ""
      echo "All available 1Password plugins:"
      op plugin list 2>/dev/null || echo "Please authenticate with 1Password first"
    }

    # For non-interactive git operations, use direct gh command
    export GIT_CREDENTIAL_HELPER_GITHUB="command gh auth git-credential"
  '';

  # Shell aliases for convenience
  programs.bash.shellAliases = {
    # Quick plugin management
    opl = "op-list";

    # Short aliases for commonly used tools
    argo = "argocd";
    hc = "hcloud";
  };

  # Git configuration is now handled in git.nix module
}

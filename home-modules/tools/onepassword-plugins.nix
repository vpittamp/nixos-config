# 1Password Shell Plugins Configuration
# Enables biometric authentication for CLI tools
{ config, pkgs, lib, inputs, ... }:

{
  # Note: The 1Password shell plugins module is imported in flake.nix
  # This file configures the plugins
  # The module AUTOMATICALLY creates shell functions for each plugin

  # Enable 1Password shell plugins
  programs._1password-shell-plugins = {
    enable = true;
    
    # Enable plugins for specific tools
    # The module will automatically create wrapper functions for these
    plugins = with pkgs; [
      gh          # GitHub CLI - creates gh() function
      # awscli2     # AWS CLI - creates aws() function (commented out - slow to build)
      cachix      # Cachix binary cache - creates cachix() function
      openai      # OpenAI CLI - creates openai() function
      # hcloud requires app integration (biometric unlock) which may not be available
      # We'll use a manual wrapper instead
      # Note: Only packages that have 1Password plugins can be added here
      # Check available plugins with: op plugin list
    ];
  };

  # Additional shell configuration for 1Password
  programs.bash.initExtra = ''
    # 1Password CLI authentication helper
    source <(op completion bash) 2>/dev/null || true

    # Source 1Password shell plugins configuration (managed by op plugin init)
    # This file contains aliases for plugins initialized with: op plugin init <plugin-name>
    # These aliases work ALONGSIDE the functions created by programs._1password-shell-plugins
    #
    # Why both?
    # - programs._1password-shell-plugins: Creates functions for packages in nixpkgs
    # - op plugin init: Creates aliases for plugins that need interactive configuration
    #   (e.g., hcloud, which requires selecting specific credentials during init)
    #
    # Functions take precedence over aliases, so plugins in both places will use the function
    if [ -f "$HOME/.config/op/plugins.sh" ]; then
      source "$HOME/.config/op/plugins.sh"
    fi
    
    # Helper functions for 1Password operations
    op-signin() {
      eval $(op signin)
    }

    # Note: gh and argocd functions removed - they're now handled by
    # 1Password shell plugins (aliases in ~/.config/op/plugins.sh)
    
    # 1Password Shell Plugins
    # Plugins are initialized with: op plugin init <name>
    # They create aliases in ~/.config/op/plugins.sh which is sourced above
    #
    # Currently configured plugins (check ~/.config/op/plugins.sh):
    # - hcloud: Hetzner Cloud CLI
    # - gh: GitHub CLI (to be initialized)
    # - argocd: Argo CD CLI (to be initialized)
    #
    # Note: These don't need function wrappers - the plugin system
    # creates aliases automatically in ~/.config/op/plugins.sh
    
    # Helper function to initialize a plugin interactively
    op-init() {
      local plugin="$1"
      if [ -z "$plugin" ]; then
        echo "Usage: op-init <plugin-name>"
        echo "Available plugins: gh, aws, cachix, openai, hcloud, psql, argocd"
        echo ""
        echo "Examples:"
        echo "  op-init gh       # Initialize GitHub CLI"
        echo "  op-init openai   # Initialize OpenAI CLI"
        echo "  op-init hcloud   # Initialize Hetzner Cloud CLI"
        echo "  op-init argocd   # Initialize Argo CD CLI"
        echo ""
        echo "Note: Use exact plugin names from 'op plugin list'"
        return 1
      fi
      op plugin init "$plugin"
    }
    
    # Helper function to list configured plugins
    op-list() {
      echo "🔐 1Password Shell Plugins Status:"
      echo "=================================="
      op plugin list 2>/dev/null || echo "Please authenticate with 1Password first (op signin)"
    }
    
    # Helper function to inspect a plugin configuration
    op-inspect() {
      local plugin="$1"
      if [ -z "$plugin" ]; then
        echo "Select a plugin to inspect:"
        op plugin inspect
      else
        op plugin inspect "$plugin"
      fi
    }
    
    # Helper function to clear plugin credentials
    op-clear() {
      local plugin="$1"
      if [ -z "$plugin" ]; then
        echo "Usage: op-clear <plugin-name> [--all]"
        echo "Example: op-clear gh --all"
        return 1
      fi
      shift
      op plugin clear "$plugin" "$@"
    }

    # OpenAI CLI with 1Password authentication
    # The API key will be securely retrieved from 1Password
    openai-init() {
      echo "Initializing OpenAI CLI with 1Password..."
      op plugin init openai
    }

    # Use OpenAI without 1Password plugin wrapper for non-interactive operations
    openai-direct() {
      command openai "$@"
    }

    # Helper to test OpenAI connection
    openai-test() {
      op plugin run -- openai api models.list 2>/dev/null | head -5
    }
    # For non-interactive git operations, use direct gh command
    export GIT_CREDENTIAL_HELPER_GITHUB="command gh auth git-credential"
  '';

  # Shell aliases for convenience
  programs.bash.shellAliases = {
    # Quick plugin management
    opl = "op-list";
    opinit = "op-init";  # Changed from opi to avoid conflict with existing alias
    opc = "op-clear";
    opx = "op-inspect";
    
    # Short aliases for commonly used tools
    argo = "argocd";
    hc = "hcloud";
  };

  # Git configuration is now handled in git.nix module
}
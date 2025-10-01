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
      awscli2     # AWS CLI - creates aws() function
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
    
    # Manual plugin wrappers for tools not in the plugins list
    # These need to be initialized with: op plugin init <name>

    # Hetzner Cloud CLI wrapper - using direct token retrieval
    # Note: Shell plugins require app integration, so we use direct token access
    hcloud() {
      # Check if signed into 1Password CLI first
      if ! op whoami &>/dev/null; then
        echo "Error: Not signed into 1Password. Run: eval \$(op signin)" >&2
        return 1
      fi

      # Get token with timeout to prevent hanging
      local token
      if ! token=$(timeout 2s op read 'op://CLI/Hetzner Cloud API/token' 2>/dev/null); then
        echo "Error: Failed to retrieve Hetzner token from 1Password" >&2
        echo "Make sure the 'Hetzner Cloud API' item exists in the CLI vault with a 'token' field" >&2
        return 1
      fi

      HCLOUD_TOKEN="$token" command hcloud "$@"
    }
    
    # PostgreSQL wrappers (initialize with: op plugin init psql)
    psql() {
      op plugin run -- psql "$@"
    }
    
    # Argo CD wrapper (initialize with: op plugin init argocd)
    argocd() {
      op plugin run -- argocd "$@"
    }
    
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
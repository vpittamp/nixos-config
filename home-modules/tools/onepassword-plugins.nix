# 1Password Shell Plugins Configuration
# Enables biometric authentication for CLI tools
{ config, pkgs, lib, inputs, ... }:

{
  # Import the 1Password shell plugins module
  imports = [ inputs.onepassword-shell-plugins.hmModules.default ];

  # Enable 1Password shell plugins
  programs._1password-shell-plugins = {
    enable = true;
    
    # Enable plugins for specific tools
    plugins = with pkgs; [
      gh          # GitHub CLI
      awscli2     # AWS CLI
      cachix      # Cachix binary cache
      tea         # Gitea CLI
      hcloud      # Hetzner Cloud CLI
      postgresql  # PostgreSQL tools (psql, pg_dump, pg_restore)
      argocd      # Argo CD CLI
      # Additional plugins available:
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
    
    # Cachix wrapper function
    cachix() {
      op plugin run -- cachix "$@"
    }
    
    # Gitea CLI wrapper (tea)
    tea() {
      op plugin run -- tea "$@"
    }
    
    # Hetzner Cloud CLI wrapper
    hcloud() {
      op plugin run -- hcloud "$@"
    }
    
    # PostgreSQL wrappers
    psql() {
      op plugin run -- psql "$@"
    }
    
    pg_dump() {
      op plugin run -- pg_dump "$@"
    }
    
    pg_restore() {
      op plugin run -- pg_restore "$@"
    }
    
    pgcli() {
      op plugin run -- pgcli "$@"
    }
    
    # Argo CD wrapper
    argocd() {
      op plugin run -- argocd "$@"
    }
    
    # Helper function to initialize a plugin interactively
    op-init() {
      local plugin="$1"
      if [ -z "$plugin" ]; then
        echo "Usage: op-init <plugin-name>"
        echo "Available plugins: gh, aws, cachix, tea, hcloud, psql, argocd"
        echo ""
        echo "Examples:"
        echo "  op-init gh       # Initialize GitHub CLI"
        echo "  op-init hcloud   # Initialize Hetzner Cloud CLI"
        echo "  op-init argocd   # Initialize Argo CD CLI"
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
    
    # For non-interactive git operations, use direct gh command
    export GIT_CREDENTIAL_HELPER_GITHUB="command gh auth git-credential"
  '';

  # Shell aliases for convenience
  programs.bash.shellAliases = {
    # Quick plugin management
    opl = "op-list";
    opi = "op-init";
    opc = "op-clear";
    opx = "op-inspect";
    
    # Short aliases for commonly used tools
    argo = "argocd";
    hc = "hcloud";
  };

  # Git configuration is now handled in git.nix module
}
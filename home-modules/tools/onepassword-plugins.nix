# 1Password CLI Tools Configuration
# Uses `op run` for secure credential injection without service accounts
{ config, pkgs, lib, inputs, ... }:

{
  # Additional shell configuration for 1Password
  programs.bash.initExtra = ''
    # 1Password CLI authentication helper
    source <(op completion bash) 2>/dev/null || true

    # Helper functions for 1Password operations
    op-signin() {
      eval $(op signin)
    }

    # Wrapper functions for CLI tools that use 1Password credentials
    # These use `op run` to inject credentials securely

    gh() {
      # Create temporary env file for GitHub token
      local env_file=$(mktemp)
      echo 'GH_TOKEN="op://Employee/Github Personal Access Token/token"' > "$env_file"

      # Run command with injected credentials
      op run --env-file="$env_file" -- ${pkgs.gh}/bin/gh "$@"
      local exit_code=$?

      # Clean up
      rm -f "$env_file"
      return $exit_code
    }

    hcloud() {
      # Create temporary env file for Hetzner Cloud token
      local env_file=$(mktemp)
      echo 'HCLOUD_TOKEN="op://CLI/Hetzner Cloud API/token"' > "$env_file"

      # Run command with injected credentials
      op run --env-file="$env_file" -- ${pkgs.hcloud}/bin/hcloud "$@"
      local exit_code=$?

      # Clean up
      rm -f "$env_file"
      return $exit_code
    }

    openai() {
      # Create temporary env file for OpenAI API key
      local env_file=$(mktemp)
      echo 'OPENAI_API_KEY="op://CLI/OPENAI_API_KEY/credential"' > "$env_file"

      # Run command with injected credentials
      op run --env-file="$env_file" -- ${pkgs.openai-whisper-cpp}/bin/openai "$@"
      local exit_code=$?

      # Clean up
      rm -f "$env_file"
      return $exit_code
    }

    argocd() {
      # Run without special credentials for now
      ${pkgs.argocd}/bin/argocd "$@"
    }

    cachix() {
      # Run without special credentials for now
      ${pkgs.cachix}/bin/cachix "$@"
    }

    # Helper: Show authentication status
    op-status() {
      echo "🔐 1Password CLI Tools Status"
      echo "===================================="
      echo ""
      echo "Authentication: Personal account with op run"
      echo "Method: Desktop app integration"
      echo ""

      # Test if we can access vaults
      if op vault list &> /dev/null; then
        echo "✅ Successfully authenticated with 1Password"
        echo ""
        echo "Available vaults:"
        op vault list | head -5
      else
        echo "❌ Not authenticated with 1Password"
        echo "Run: op-signin"
      fi

      echo ""
      echo "Wrapped CLI tools (using op run):"
      echo "  ✅ gh - GitHub CLI"
      echo "  ✅ hcloud - Hetzner Cloud CLI"
      echo "  ✅ openai - OpenAI CLI"
      echo "  ✅ argocd - Argo CD CLI"
      echo "  ✅ cachix - Cachix binary cache"
    }

    # Helper: Test CLI tool authentication
    op-test() {
      echo "🧪 Testing 1Password CLI tool authentication..."
      echo ""

      echo "Testing 1Password CLI access..."
      if op vault list &> /dev/null; then
        echo "✅ 1Password CLI working"
      else
        echo "❌ 1Password CLI not authenticated"
        echo "Run: op-signin"
        return 1
      fi

      echo ""
      echo "Testing GitHub CLI authentication..."
      if gh auth status &> /dev/null; then
        echo "✅ GitHub CLI authenticated"
        gh auth status 2>&1 | grep "Logged in"
      else
        echo "⚠️  GitHub CLI test - check credentials in 1Password"
      fi
    }

    # Helper: List configured plugins/tools
    op-list() {
      echo "🔐 1Password CLI Tools Status"
      echo "=============================="
      echo ""
      echo "Authentication: Personal account (desktop app)"
      echo "Credential injection: op run command"
      echo ""
      echo "Wrapped CLI tools:"
      echo "  ✅ gh - GitHub CLI (op://Employee/Github Personal Access Token/token)"
      echo "  ✅ hcloud - Hetzner Cloud CLI (op://CLI/Hetzner Cloud API/credential)"
      echo "  ✅ openai - OpenAI CLI (op://CLI/OPENAI_API_KEY/credential)"
      echo "  ✅ argocd - Argo CD CLI"
      echo "  ✅ cachix - Cachix binary cache"
      echo ""
      echo "Management commands:"
      echo "  op-signin  Sign in to 1Password"
      echo "  op-status  Show authentication status"
      echo "  op-test    Test CLI tool authentication"
      echo "  op-list    Show this help"
    }

    # For non-interactive git operations, use GitHub CLI credential helper
    export GIT_CREDENTIAL_HELPER_GITHUB="command gh auth git-credential"
  '';

  # Shell aliases for convenience
  programs.bash.shellAliases = {
    # Quick service account management
    opl = "op-list";
    ops = "op-status";
    opt = "op-test";

    # Short aliases for commonly used tools
    argo = "argocd";
    hc = "hcloud";
  };

  # Git configuration is now handled in git.nix module
}

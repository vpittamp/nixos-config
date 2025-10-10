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
      echo 'OPENAI_API_KEY="op://CLI/OPENAI_API_KEY/api key"' > "$env_file"

      # Run command with injected credentials
      op run --env-file="$env_file" -- ${pkgs.python3Packages.openai}/bin/openai "$@"
      local exit_code=$?

      # Clean up
      rm -f "$env_file"
      return $exit_code
    }

    argocd() {
      # Create temporary env file for Argo CD auth token
      local env_file=$(mktemp)
      echo 'ARGOCD_AUTH_TOKEN="op://CLI/Argo CD (localdev)/auth token"' > "$env_file"
      echo 'ARGOCD_SERVER="op://CLI/Argo CD (localdev)/address"' >> "$env_file"

      # Run command with injected credentials
      op run --env-file="$env_file" -- ${pkgs.argocd}/bin/argocd "$@"
      local exit_code=$?

      # Clean up
      rm -f "$env_file"
      return $exit_code
    }

    cachix() {
      # Run without special credentials for now
      ${pkgs.cachix}/bin/cachix "$@"
    }

    # Azure CLI wrapper
    az() {
      # Note: Azure CLI uses interactive login by default
      # Service Principal auth requires: az login --service-principal -u CLIENT_ID -p PASSWORD --tenant TENANT_ID
      # For now, pass through to the actual command
      ${pkgs.azure-cli}/bin/az "$@"
    }

    # MySQL CLI wrapper
    mysql() {
      # Create temporary env file for MySQL credentials
      local env_file=$(mktemp)
      echo 'MYSQL_PWD="op://Employee/rqa74rt2b4meswwvutf2dqwy5q/password"' > "$env_file"

      # Run command with injected credentials
      op run --env-file="$env_file" -- ${pkgs.mariadb}/bin/mysql "$@"
      local exit_code=$?

      # Clean up
      rm -f "$env_file"
      return $exit_code
    }

    # PostgreSQL CLI wrappers
    psql() {
      # Note: PostgreSQL credentials would need to be added to 1Password
      # For now, pass through to the actual command
      ${pkgs.postgresql}/bin/psql "$@"
    }

    pg_dump() {
      # Note: PostgreSQL credentials would need to be added to 1Password
      # For now, pass through to the actual command
      ${pkgs.postgresql}/bin/pg_dump "$@"
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
      echo "  ✅ mysql - MySQL CLI"
      echo "  ⚪ az - Azure CLI (passthrough, uses interactive login)"
      echo "  ⚪ psql - PostgreSQL CLI (passthrough)"
      echo "  ⚪ pg_dump - PostgreSQL dump (passthrough)"
      echo "  ⚪ cachix - Cachix binary cache (no credentials)"
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
      echo "  ✅ hcloud - Hetzner Cloud CLI (op://CLI/Hetzner Cloud API/token)"
      echo "  ✅ openai - OpenAI CLI (op://CLI/OPENAI_API_KEY/api key)"
      echo "  ✅ argocd - Argo CD CLI (op://CLI/Argo CD (localdev)/auth token)"
      echo "  ✅ mysql - MySQL CLI (op://Employee/.../password)"
      echo "  ⚪ az - Azure CLI (passthrough, uses interactive login)"
      echo "  ⚪ psql - PostgreSQL CLI (passthrough, no 1Password integration yet)"
      echo "  ⚪ pg_dump - PostgreSQL dump (passthrough, no 1Password integration yet)"
      echo "  ⚪ cachix - Cachix binary cache (no credentials configured)"
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

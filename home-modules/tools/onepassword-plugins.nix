# 1Password CLI Tools Configuration
# Uses `op run` for secure credential injection
#
# Note: The official 1Password shell-plugins flake has a known bug (#485)
# with IFD and socket files. Using manual `op run` wrappers instead.
#
# Updated: 2026-01-06 with Cachix integration
{ config, pkgs, lib, inputs, ... }:

{
  programs.bash.initExtra = ''
    # 1Password CLI completion
    if command -v op >/dev/null 2>&1; then
      source <(op completion bash) 2>/dev/null || true
    fi

    # Helper to sign in
    op-signin() {
      eval $(op signin)
    }

    # =============================================================
    # CLI Tool Wrappers using op run
    # =============================================================

    # GitHub CLI with 1Password token injection
    gh() {
      if [ "$1" = "auth" ]; then
        ${pkgs.gh}/bin/gh "$@"
        return $?
      fi

      if op account list &> /dev/null 2>&1; then
        local env_file=$(mktemp)
        echo 'GH_TOKEN="op://Employee/Github Personal Access Token/token"' > "$env_file"
        op run --env-file="$env_file" -- ${pkgs.gh}/bin/gh "$@"
        local exit_code=$?
        rm -f "$env_file"
        return $exit_code
      else
        ${pkgs.gh}/bin/gh "$@"
      fi
    }

    # Hetzner Cloud CLI
    hcloud() {
      local env_file=$(mktemp)
      echo 'HCLOUD_TOKEN="op://CLI/Hetzner Cloud API/token"' > "$env_file"
      op run --env-file="$env_file" -- ${pkgs.hcloud}/bin/hcloud "$@"
      local exit_code=$?
      rm -f "$env_file"
      return $exit_code
    }

    # OpenAI CLI
    openai() {
      local env_file=$(mktemp)
      echo 'OPENAI_API_KEY="op://CLI/OPENAI_API_KEY/api key"' > "$env_file"
      op run --env-file="$env_file" -- ${pkgs.python3Packages.openai}/bin/openai "$@"
      local exit_code=$?
      rm -f "$env_file"
      return $exit_code
    }

    # Argo CD CLI
    argocd() {
      local env_file=$(mktemp)
      echo 'ARGOCD_AUTH_TOKEN="op://CLI/shdhimokibw653iy5gkyzay4qy/auth token"' > "$env_file"
      echo 'ARGOCD_SERVER="op://CLI/shdhimokibw653iy5gkyzay4qy/address"' >> "$env_file"
      op run --env-file="$env_file" -- ${pkgs.argocd}/bin/argocd "$@"
      local exit_code=$?
      rm -f "$env_file"
      return $exit_code
    }

    # Cachix binary cache
    cachix() {
      # Only inject token for commands that require auth
      local auth_commands="push|authtoken|generate-keypair|pin|remove"

      if [[ "$1" =~ ^($auth_commands)$ ]] && op account list &> /dev/null 2>&1; then
        local env_file=$(mktemp)
        echo 'CACHIX_AUTH_TOKEN="op://CLI/Cachix Auth Token/token"' > "$env_file"
        op run --env-file="$env_file" -- ${pkgs.cachix}/bin/cachix "$@"
        local exit_code=$?
        rm -f "$env_file"
        return $exit_code
      else
        ${pkgs.cachix}/bin/cachix "$@"
      fi
    }

    # MySQL CLI
    mysql() {
      local env_file=$(mktemp)
      echo 'MYSQL_PWD="op://Employee/rqa74rt2b4meswwvutf2dqwy5q/password"' > "$env_file"
      op run --env-file="$env_file" -- ${pkgs.mariadb}/bin/mysql "$@"
      local exit_code=$?
      rm -f "$env_file"
      return $exit_code
    }

    # =============================================================
    # Passthrough wrappers (no 1Password plugin available)
    # =============================================================

    az() {
      command az "$@"
    }

    psql() {
      ${pkgs.postgresql}/bin/psql "$@"
    }

    pg_dump() {
      ${pkgs.postgresql}/bin/pg_dump "$@"
    }

    # =============================================================
    # Helper functions
    # =============================================================

    op-status() {
      echo "🔐 1Password CLI Tools Status"
      echo "===================================="
      echo ""

      if op vault list &> /dev/null; then
        echo "✅ Authenticated with 1Password"
        echo ""
        echo "Available vaults:"
        op vault list | head -5
      else
        echo "❌ Not authenticated - run: op-signin"
        return 1
      fi

      echo ""
      echo "Configured tools (op run):"
      echo "  ✅ gh      - GitHub CLI"
      echo "  ✅ hcloud  - Hetzner Cloud CLI"
      echo "  ✅ openai  - OpenAI CLI"
      echo "  ✅ argocd  - Argo CD CLI"
      echo "  ✅ cachix  - Cachix binary cache"
      echo "  ✅ mysql   - MySQL CLI"
      echo ""
      echo "Passthrough (no 1Password plugin):"
      echo "  ⚪ az      - Azure CLI (use: az login)"
      echo "  ⚪ psql    - PostgreSQL CLI"
      echo "  ⚪ pg_dump - PostgreSQL dump"
    }

    op-test() {
      echo "🧪 Testing 1Password CLI tools..."
      echo ""

      if ! op vault list &> /dev/null; then
        echo "❌ Not authenticated - run: op-signin"
        return 1
      fi
      echo "✅ 1Password CLI working"

      echo ""
      echo "Testing GitHub CLI..."
      if gh auth status &> /dev/null 2>&1; then
        echo "✅ GitHub CLI authenticated"
      else
        echo "⚠️  GitHub CLI needs token in 1Password"
      fi

      echo ""
      echo "Testing Cachix..."
      if op item get "Cachix Auth Token" --vault CLI &> /dev/null 2>&1; then
        echo "✅ Cachix token found"
      else
        echo "⚠️  Cachix token not found in CLI vault"
      fi
    }

    op-list() {
      echo "🔐 1Password CLI Tools"
      echo "======================"
      echo ""
      echo "Configured tools (credentials via op run):"
      echo "  gh      - op://Employee/Github Personal Access Token/token"
      echo "  hcloud  - op://CLI/Hetzner Cloud API/token"
      echo "  openai  - op://CLI/OPENAI_API_KEY/api key"
      echo "  argocd  - op://CLI/.../auth token"
      echo "  cachix  - op://CLI/Cachix Auth Token/token"
      echo "  mysql   - op://Employee/.../password"
      echo ""
      echo "Passthrough (no 1Password integration):"
      echo "  az, psql, pg_dump"
      echo ""
      echo "Commands: op-signin | op-status | op-test | op-list"
    }

    export GIT_CREDENTIAL_HELPER_GITHUB="command gh auth git-credential"
  '';

  programs.bash.shellAliases = {
    opl = "op-list";
    ops = "op-status";
    opt = "op-test";
    argo = "argocd";
    hc = "hcloud";
    reboot = "hcloud server reboot nixos-hetzner";
  };
}

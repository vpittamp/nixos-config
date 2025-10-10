{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    modules.tools.docker = {
      enable = mkEnableOption "Docker with 1Password integration";

      onePasswordItem = mkOption {
        type = types.str;
        default = "DOCKER_PERSONAL_ACCESS_TOKEN";
        description = "Name of the 1Password item containing Docker Hub credentials";
      };

      onePasswordVault = mkOption {
        type = types.str;
        default = "CLI";
        description = "1Password vault containing Docker credentials";
      };

      autoLogin = mkOption {
        type = types.bool;
        default = false;
        description = "Automatically login to Docker Hub on shell startup";
      };
    };
  };

  config = mkIf config.modules.tools.docker.enable (
    let
      item = config.modules.tools.docker.onePasswordItem;
      vault = config.modules.tools.docker.onePasswordVault;
    in
    {
      # Docker configuration with 1Password integration
      # Provides automatic authentication to Docker Hub using 1Password CLI

      # Docker CLI configuration
      # NOTE: Changed from home.file to activation script to allow docker login to write credentials
      # The file must be writable for docker login to work
      home.activation.dockerConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p $HOME/.docker
        if [ ! -f $HOME/.docker/config.json ] || [ -L $HOME/.docker/config.json ]; then
          $DRY_RUN_CMD rm -f $HOME/.docker/config.json
          $DRY_RUN_CMD cat > $HOME/.docker/config.json <<'EOF'
{
  "cliPluginsExtraDirs": ["$HOME/.docker/cli-plugins"],
  "auths": {}
}
EOF
        fi
      '';


      # Shell functions for Docker + 1Password integration
      programs.bash.initExtra = ''
        # Docker Hub login using 1Password CLI
        docker-login() {
          echo "🔐 Authenticating to Docker Hub via 1Password..."

          local username=$(op read "op://${vault}/${item}/username" 2>/dev/null)
          local token=$(op read "op://${vault}/${item}/password" 2>/dev/null)

          if [ -n "$username" ] && [ -n "$token" ]; then
            if echo "$token" | docker login -u "$username" --password-stdin 2>/dev/null; then
              echo "✅ Successfully logged in to Docker Hub as $username"
              return 0
            else
              echo "❌ Docker login failed"
              return 1
            fi
          else
            echo "❌ Failed to retrieve credentials from 1Password"
            echo "   Vault: ${vault}, Item: ${item}"
            echo "   Ensure item has 'username' and 'password' fields"
            return 1
          fi
        }

        # Docker push with automatic authentication
        docker-push() {
          [ -z "$1" ] && { echo "Usage: docker-push <image:tag>"; return 1; }
          docker-login && docker push "$1"
        }

        # Docker pull with automatic authentication
        docker-pull-auth() {
          [ -z "$1" ] && { echo "Usage: docker-pull-auth <image:tag>"; return 1; }
          docker-login && docker pull "$1"
        }

        # Check Docker authentication status
        docker-auth-status() {
          if docker info 2>/dev/null | grep -q "Username:"; then
            local username=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
            echo "✅ Logged in to Docker Hub as: $username"
          else
            echo "❌ Not logged in to Docker Hub (run: docker-login)"
          fi

          if op read "op://${vault}/${item}/username" >/dev/null 2>&1; then
            echo "✅ 1Password credentials available"
          else
            echo "⚠️  1Password credentials not found: op://${vault}/${item}"
          fi
        }

        alias docker-whoami='docker-auth-status'
      '' + optionalString config.modules.tools.docker.autoLogin ''
      
      # Auto-login on shell startup (if enabled)
      if command -v docker >/dev/null 2>&1 && command -v op >/dev/null 2>&1; then
        docker-login 2>/dev/null >/dev/null || true
      fi
    '';

      # Convenience aliases
      programs.bash.shellAliases = {
        "docker-config" = "cat ~/.docker/config.json | ${pkgs.jq}/bin/jq .";
        "docker-logout" = "docker logout";
      };
    }
  );
}

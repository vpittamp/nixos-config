{ pkgs, lib, config, ... }:

{
  # Git credential helper using 1Password CLI with service account
  # This works in containers without the desktop app

  programs.git.extraConfig = {
    # Use 1Password CLI as credential helper
    credential.helper = "${pkgs.writeShellScript "git-credential-1password-sa" ''
      #!/usr/bin/env bash
      # Git credential helper using 1Password CLI with service account token

      # Check if OP_SERVICE_ACCOUNT_TOKEN is set
      if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
        echo "Error: OP_SERVICE_ACCOUNT_TOKEN not set" >&2
        exit 1
      fi

      # Read git credential input
      input=$(cat)

      # Parse the input to get host
      host=$(echo "$input" | grep "^host=" | cut -d= -f2)
      protocol=$(echo "$input" | grep "^protocol=" | cut -d= -f2)

      case "$1" in
        get)
          # Fetch credentials from 1Password based on host
          case "$host" in
            github.com)
              # Get GitHub PAT from 1Password
              username=$(${pkgs._1password}/bin/op item get "Github Personal Access Token" --fields username --format json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.value // empty')
              password=$(${pkgs._1password}/bin/op item get "Github Personal Access Token" --fields token --format json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.value // empty')
              ;;
            gitlab.com)
              # Get GitLab PAT from 1Password if you have one
              username=$(${pkgs._1password}/bin/op item get "GitLab Personal Access Token" --fields username --format json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.value // empty')
              password=$(${pkgs._1password}/bin/op item get "GitLab Personal Access Token" --fields token --format json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.value // empty')
              ;;
            *)
              # Fallback to github for unknown hosts
              username=$(${pkgs._1password}/bin/op item get "Github Personal Access Token" --fields username --format json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.value // empty')
              password=$(${pkgs._1password}/bin/op item get "Github Personal Access Token" --fields token --format json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.value // empty')
              ;;
          esac

          if [ -n "$username" ] && [ -n "$password" ]; then
            echo "username=$username"
            echo "password=$password"
          fi
          ;;
        store)
          # We don't store credentials (1Password is the source of truth)
          :
          ;;
        erase)
          # We don't erase credentials (1Password is the source of truth)
          :
          ;;
      esac
    ''}";
  };

  # Add helper script to initialize 1Password service account
  home.packages = with pkgs; [
    _1password  # 1Password CLI

    (writeShellScriptBin "op-sa-init" ''
      #!/usr/bin/env bash
      # Initialize 1Password service account for container use

      echo "🔐 1Password Service Account Setup for Containers"
      echo "=================================================="
      echo ""

      if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
        echo "❌ OP_SERVICE_ACCOUNT_TOKEN environment variable not set"
        echo ""
        echo "To set it up:"
        echo "1. Go to https://pittampalli.1password.com/developer/infrastructure/serviceaccounts"
        echo "2. Create a new service account with 'Read' access to the vaults you need"
        echo "3. Copy the token (starts with 'ops_')"
        echo "4. Add to your environment:"
        echo "   export OP_SERVICE_ACCOUNT_TOKEN='ops_...'"
        echo ""
        echo "For containers, pass it when running:"
        echo "   docker run -e OP_SERVICE_ACCOUNT_TOKEN='ops_...' ..."
        echo ""
        exit 1
      fi

      echo "✅ OP_SERVICE_ACCOUNT_TOKEN is set"
      echo ""

      # Test the token
      echo "Testing 1Password CLI connection..."
      if ${_1password}/bin/op whoami >/dev/null 2>&1; then
        echo "✅ Successfully authenticated with 1Password"
        ${_1password}/bin/op whoami
        echo ""
        echo "Git credential helper is configured and ready to use!"
        echo ""
        echo "Try:"
        echo "  git clone git@github.com:vpittamp/nixos-config.git"
        echo "  # or"
        echo "  git clone https://github.com/vpittamp/nixos-config.git"
        echo ""
      else
        echo "❌ Failed to authenticate with 1Password"
        echo "Please check your token is valid"
        exit 1
      fi
    '')

    (writeShellScriptBin "op-sa-test" ''
      #!/usr/bin/env bash
      # Test 1Password service account access to Git credentials

      echo "Testing 1Password service account access..."
      echo ""

      if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
        echo "❌ OP_SERVICE_ACCOUNT_TOKEN not set"
        exit 1
      fi

      echo "Fetching GitHub token..."
      TOKEN=$(${_1password}/bin/op item get "Github Personal Access Token" --fields token 2>&1)

      if [ $? -eq 0 ]; then
        echo "✅ Successfully retrieved GitHub token"
        echo "Token: ''${TOKEN:0:10}..." # Show first 10 chars
      else
        echo "❌ Failed to retrieve GitHub token"
        echo "$TOKEN"
        exit 1
      fi
    '')
  ];

  # Environment setup instructions
  home.file.".config/op-container-setup.md".text = ''
    # 1Password Service Account Setup for Containers

    ## Quick Start

    1. Create a service account token:
       https://pittampalli.1password.com/developer/infrastructure/serviceaccounts

    2. Grant read access to the "Employee" vault (or vaults with Git credentials)

    3. Set the environment variable:
       ```bash
       export OP_SERVICE_ACCOUNT_TOKEN='ops_...'
       ```

    4. Test the connection:
       ```bash
       op-sa-init
       ```

    5. Git will now automatically use 1Password for credentials!

    ## For Docker Containers

    ```bash
    docker run -e OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" myimage
    ```

    ## For Kubernetes

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: op-service-account
    type: Opaque
    stringData:
      token: ops_...
    ---
    apiVersion: v1
    kind: Pod
    spec:
      containers:
      - name: app
        env:
        - name: OP_SERVICE_ACCOUNT_TOKEN
          valueFrom:
            secretKeyRef:
              name: op-service-account
              key: token
    ```

    ## Security Notes

    - Service account tokens should have minimal permissions (read-only)
    - Scope to specific vaults only
    - Rotate tokens regularly
    - Never commit tokens to git
    - Use secrets management for production (Kubernetes Secrets, AWS Secrets Manager, etc.)
  '';
}

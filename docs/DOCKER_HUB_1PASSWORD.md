# Docker Hub Authentication with 1Password in VS Code

## Overview

This guide shows how to authenticate to Docker Hub using your 1Password Docker token in VS Code. The authentication works automatically through the Docker extension and 1Password CLI integration.

## Prerequisites

✅ Already configured in your NixOS setup:

- 1Password desktop app with CLI integration enabled
- 1Password VS Code extension (`1Password.op-vscode`)
- Docker extension (`ms-azuretools.vscode-docker`)
- Docker CLI installed

## Setup Methods

### Method 1: Docker Credential Helper (Recommended)

This method uses 1Password as a Docker credential helper, providing automatic authentication for all Docker operations in VS Code and the terminal.

#### Step 1: Store Docker Hub Token in 1Password

```bash
# Using 1Password CLI
op item create \
  --category="API Credential" \
  --title="Docker Hub Token" \
  --vault="Personal" \
  username="<your-docker-username>" \
  credential[password]="<your-docker-token>" \
  url="https://hub.docker.com"

# Or use the 1Password desktop app:
# 1. Open 1Password
# 2. Create new item → API Credential
# 3. Title: "Docker Hub Token"
# 4. Username: your Docker Hub username
# 5. Credential: your Docker Hub token
# 6. Website: https://hub.docker.com
```

#### Step 2: Configure Docker to Use 1Password CLI

Add this to your NixOS configuration to automatically configure Docker credential helper:

```nix
# In home-modules/tools/docker.nix (create if it doesn't exist)
{ config, pkgs, lib, ... }:

{
  # Docker credential helper using 1Password CLI
  home.file.".docker/config.json".text = builtins.toJSON {
    # Use 1Password CLI as credential helper
    credsStore = "1password-cli";

    # Registry-specific helpers
    credHelpers = {
      "docker.io" = "1password-cli";
      "index.docker.io" = "1password-cli";
    };

    # Additional Docker settings
    auths = {}; # Empty - credentials managed by 1Password
  };

  # Install Docker credential helper for 1Password
  home.packages = with pkgs; [
    docker-credential-helpers
  ];

  # Shell alias for Docker login using 1Password
  programs.bash.shellAliases = {
    "docker-login" = ''
      op item get "Docker Hub Token" --format json | \
      jq -r '.fields[] | select(.label=="credential") | .value' | \
      docker login --username $(op item get "Docker Hub Token" --fields username) --password-stdin
    '';
  };
}
```

#### Step 3: Alternative - Use Docker Credential Helper Script

If the credential helper doesn't work automatically, create a custom helper script:

```bash
# Create credential helper script
mkdir -p ~/.docker/cli-plugins

cat > ~/.docker/docker-credential-1password-cli << 'EOF'
#!/usr/bin/env bash
set -e

# Docker credential helper using 1Password CLI
# Usage: This is called by Docker automatically when needed

case "$1" in
  get)
    # Read server URL from stdin
    read -r server

    # Default to Docker Hub if no server specified
    if [ -z "$server" ] || [ "$server" = "https://index.docker.io/v1/" ]; then
      server="hub.docker.com"
    fi

    # Fetch credentials from 1Password
    username=$(op item get "Docker Hub Token" --fields username 2>/dev/null || echo "")
    secret=$(op item get "Docker Hub Token" --fields credential 2>/dev/null || echo "")

    if [ -n "$username" ] && [ -n "$secret" ]; then
      cat <<JSON
{
  "ServerURL": "$server",
  "Username": "$username",
  "Secret": "$secret"
}
JSON
    else
      echo "Error: Could not retrieve Docker Hub credentials from 1Password" >&2
      exit 1
    fi
    ;;

  store)
    # Not implemented - use 1Password app to store credentials
    exit 0
    ;;

  erase)
    # Not implemented - use 1Password app to manage credentials
    exit 0
    ;;

  list)
    echo '{"https://index.docker.io/v1/": "docker"}'
    ;;

  *)
    echo "Unknown credential action: $1" >&2
    exit 1
    ;;
esac
EOF

chmod +x ~/.docker/docker-credential-1password-cli
```

### Method 2: Environment Variable with Secret Reference

This method uses 1Password secret references in a `.env` file that VS Code can automatically detect and resolve.

#### Step 1: Create `.env` file with Secret Reference

```bash
# In your project directory, create .env.docker
DOCKER_USERNAME="op://Personal/Docker Hub Token/username"
DOCKER_TOKEN="op://Personal/Docker Hub Token/credential"
```

#### Step 2: Use in VS Code Tasks

Create or update `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Docker Login",
      "type": "shell",
      "command": "op",
      "args": [
        "run",
        "--env-file=.env.docker",
        "--",
        "bash",
        "-c",
        "echo $DOCKER_TOKEN | docker login -u $DOCKER_USERNAME --password-stdin"
      ],
      "problemMatcher": []
    },
    {
      "label": "Docker Build & Push",
      "type": "shell",
      "dependsOn": "Docker Login",
      "command": "op",
      "args": [
        "run",
        "--env-file=.env.docker",
        "--",
        "bash",
        "-c",
        "docker build -t ${input:imageName} . && docker push ${input:imageName}"
      ],
      "problemMatcher": []
    }
  ],
  "inputs": [
    {
      "id": "imageName",
      "type": "promptString",
      "description": "Docker image name (e.g., username/repo:tag)"
    }
  ]
}
```

### Method 3: VS Code Terminal Integration

Use the 1Password integration in VS Code's integrated terminal:

#### Step 1: Configure VS Code Settings

This is already configured in your `vscode.nix`:

```nix
# Terminal environment with 1Password SSH agent
"terminal.integrated.profiles.linux" = {
  "bash" = {
    "env" = {
      "SSH_AUTH_SOCK" = "$HOME/.1password/agent.sock";
    };
  };
};
```

#### Step 2: Use in Terminal

```bash
# In VS Code integrated terminal
# Login using 1Password CLI
op item get "Docker Hub Token" --format json | \
  jq -r '.fields[] | select(.label=="credential") | .value' | \
  docker login -u $(op item get "Docker Hub Token" --fields username) --password-stdin

# Or use the alias (if configured in Method 1)
docker-login
```

### Method 4: Docker Extension Settings

Configure the Docker extension to use custom authentication:

#### Add to VS Code settings (vscode.nix)

```nix
# In baseUserSettings
"docker.dockerPath" = "${pkgs.docker}/bin/docker";
"docker.dockerComposePath" = "${pkgs.docker-compose}/bin/docker-compose";

# Environment for Docker extension
"docker.environment" = {
  "DOCKER_CONFIG" = "$HOME/.docker";
};

# Commands to run before Docker operations
"docker.commands.build" = [
  "op run --env-file=.env.docker -- docker build"
];

"docker.commands.push" = [
  "op run --env-file=.env.docker -- docker push"
];
```

## Complete NixOS Integration

### Create a New Home Module

Create `/etc/nixos/home-modules/tools/docker.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  # Docker CLI configuration
  home.file.".docker/config.json".text = builtins.toJSON {
    # Try to use 1Password CLI credential helper
    # Falls back to manual login if not available
    credHelpers = {
      "docker.io" = "1password-cli";
      "index.docker.io" = "1password-cli";
    };

    # Enable BuildKit
    features = {
      buildkit = true;
    };

    # CLI plugins
    cliPluginsExtraDirs = [
      "$HOME/.docker/cli-plugins"
    ];
  };

  # Shell functions for Docker + 1Password
  programs.bash.initExtra = ''
    # Docker Hub login using 1Password
    docker-login() {
      echo "🔐 Authenticating to Docker Hub via 1Password..."
      local username=$(op item get "Docker Hub Token" --fields username 2>/dev/null)
      local token=$(op item get "Docker Hub Token" --fields credential 2>/dev/null)

      if [ -n "$username" ] && [ -n "$token" ]; then
        echo "$token" | docker login -u "$username" --password-stdin
        echo "✅ Successfully logged in to Docker Hub"
      else
        echo "❌ Failed to retrieve credentials from 1Password"
        echo "Please ensure 'Docker Hub Token' item exists in your Personal vault"
        return 1
      fi
    }

    # Docker build and push with automatic authentication
    docker-push() {
      local image="$1"
      if [ -z "$image" ]; then
        echo "Usage: docker-push <image:tag>"
        return 1
      fi

      echo "🔐 Ensuring Docker Hub authentication..."
      docker-login || return 1

      echo "📤 Pushing $image..."
      docker push "$image"
    }

    # Docker pull with automatic authentication
    docker-pull-auth() {
      local image="$1"
      if [ -z "$image" ]; then
        echo "Usage: docker-pull-auth <image:tag>"
        return 1
      fi

      echo "🔐 Ensuring Docker Hub authentication..."
      docker-login || return 1

      echo "📥 Pulling $image..."
      docker pull "$image"
    }
  '';

  # Aliases for convenience
  programs.bash.shellAliases = {
    "docker-status" = "cat ~/.docker/config.json | jq .";
    "docker-whoami" = "docker info | grep -i username || echo 'Not logged in'";
  };
}
```

### Include in Your Home Configuration

Add to `/etc/nixos/home-vpittamp.nix` or your active home configuration:

```nix
{
  imports = [
    # ... existing imports
    ./home-modules/tools/docker.nix
  ];
}
```

## VS Code Docker Extension Integration

### Update vscode.nix

Add these settings to `baseUserSettings` in `/etc/nixos/home-modules/tools/vscode.nix`:

```nix
# Docker extension configuration
"docker.dockerPath" = "${pkgs.docker}/bin/docker";
"docker.dockerComposePath" = "${pkgs.docker-compose}/bin/docker-compose";
"docker.enableDockerComposeLanguageService" = true;

# Show Docker view in Activity Bar
"docker.showStartPage" = false;

# Automatically refresh Docker view
"docker.autoRefreshInterval" = 5000;

# Environment for Docker operations
"docker.environment" = {
  "DOCKER_CONFIG" = "$HOME/.docker";
};

# Add docker-compose.yml to secret detection
"1password.detection.filePatterns" = [
  # ... existing patterns
  "**/docker-compose.yml"
  "**/docker-compose.yaml"
  "**/.dockerconfigjson"
  "**/config.json"  # Docker config
];
```

## Usage Workflows

### Workflow 1: Manual Login (Simplest)

1. Open VS Code integrated terminal
2. Run: `docker-login`
3. Use Docker normally in VS Code

### Workflow 2: Automatic with Tasks

1. Open Command Palette (`Ctrl+Shift+P`)
2. Select "Tasks: Run Task"
3. Choose "Docker Login"
4. Now use Docker extension normally

### Workflow 3: Secret References in docker-compose.yml

```yaml
# docker-compose.yml
version: "3.8"
services:
  app:
    image: ${DOCKER_USERNAME}/myapp:latest
    build:
      context: .
      args:
        - REGISTRY_TOKEN=${DOCKER_TOKEN}
```

Run with: `op run --env-file=.env.docker -- docker-compose up`

### Workflow 4: Dockerfile with Secrets

```dockerfile
# Dockerfile
FROM alpine

# Use BuildKit secret mount (most secure)
RUN --mount=type=secret,id=docker_token \
    DOCKER_TOKEN=$(cat /run/secrets/docker_token) && \
    echo "Authenticated build step"
```

Build with:

```bash
op item get "Docker Hub Token" --fields credential | \
  docker build --secret id=docker_token,src=- -t myimage .
```

## Security Best Practices

1. **Never commit credentials**: Use `.gitignore`:

   ```gitignore
   .env.docker
   .env*.local
   .docker/config.json
   ```

2. **Use secret references**: Always use `op://` format in committed files:

   ```bash
   # ✅ Commit this (.env.docker.example)
   DOCKER_USERNAME="op://Personal/Docker Hub Token/username"
   DOCKER_TOKEN="op://Personal/Docker Hub Token/credential"

   # ❌ Never commit this (.env.docker)
   DOCKER_USERNAME="actualusername"
   DOCKER_TOKEN="dckr_pat_actual_token_here"
   ```

3. **Rotate tokens regularly**: Update in 1Password, refresh automatically everywhere

4. **Use scoped tokens**: Create Docker Hub tokens with minimal required permissions

5. **Audit access**: Review Docker Hub access logs regularly

## Troubleshooting

### Issue: "credential helper not found"

```bash
# Check if credential helper is in PATH
which docker-credential-1password-cli

# If not, ensure it's executable
chmod +x ~/.docker/docker-credential-1password-cli
```

### Issue: "error getting credentials"

```bash
# Verify 1Password CLI is working
op whoami

# Check if the item exists
op item get "Docker Hub Token"

# Re-authenticate to 1Password
eval $(op signin)
```

### Issue: VS Code Docker extension not authenticated

1. Use integrated terminal to run `docker-login`
2. Restart Docker extension: `Ctrl+Shift+P` → "Docker: Restart"
3. Check Docker config: `cat ~/.docker/config.json`

### Issue: "unauthorized: incorrect username or password"

```bash
# Verify credentials in 1Password
op item get "Docker Hub Token" --fields username
op item get "Docker Hub Token" --fields credential

# Test manual login
echo "token_here" | docker login -u username --password-stdin
```

## Verification

Test your setup:

```bash
# 1. Verify 1Password integration
op item get "Docker Hub Token"

# 2. Test Docker login
docker-login

# 3. Verify authentication
docker info | grep Username

# 4. Test pull/push (if you have a test repo)
docker pull yourusername/test:latest
docker tag yourusername/test:latest yourusername/test:v2
docker push yourusername/test:v2

# 5. Test in VS Code
# Open Docker extension view (Ctrl+Shift+D)
# Should see your repositories without login prompts
```

## Additional Resources

- [1Password Docker Integration](https://developer.1password.com/docs/cli/secrets-docker)
- [Docker Credential Helpers](https://docs.docker.com/engine/reference/commandline/login/#credential-helpers)
- [VS Code Docker Extension](https://code.visualstudio.com/docs/containers/overview)
- [Docker Hub Access Tokens](https://docs.docker.com/docker-hub/access-tokens/)

---

_Last updated: 2025-10 with comprehensive 1Password + Docker Hub integration_

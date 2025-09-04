# Container Installation Guide for AI Development Tools

This guide explains how to install home-manager with AI assistants (claude-code, gemini-cli, codex, aichat) in containers.

## Quick Start

### For Containers WITH Nix Pre-installed

Use these images that have Nix already installed:

```bash
# Recommended: nixos/nix (latest Nix version, well-maintained)
docker run -it nixos/nix:latest bash
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash

# Alternative: nixpkgs/nix-flakes (smaller, flakes enabled)
docker run -it nixpkgs/nix-flakes:latest sh
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash

# Alternative: xtruder/nix-devcontainer (development-focused)
docker run -it xtruder/nix-devcontainer:latest bash
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash
```

### For Containers WITHOUT Nix (like Backstage)

If your container doesn't have Nix (common in Kubernetes with security restrictions), you have several options:

## Solution 1: Build Custom Container Image

### Option A: Add Nix to Existing Image

Create this Dockerfile to add Nix to any existing image:

```dockerfile
# Dockerfile.add-nix
ARG BASE_IMAGE=backstage:latest
FROM nixos/nix:latest AS nix-env
FROM ${BASE_IMAGE}

# Copy Nix from the nix image
COPY --from=nix-env /nix /nix
COPY --from=nix-env /root/.nix-profile /root/.nix-profile

# Set up Nix environment
ENV PATH="/root/.nix-profile/bin:${PATH}"
ENV NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"

# Install dependencies
RUN apt-get update && apt-get install -y git curl || \
    yum install -y git curl || \
    apk add --no-cache git curl || true

# Install home-manager on startup
RUN curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash
```

Build and use:
```bash
docker build -f Dockerfile.add-nix --build-arg BASE_IMAGE=backstage:latest -t backstage-with-ai .
docker run -it backstage-with-ai
```

### Option B: Pre-built Image with AI Tools

Use the pre-built image with everything installed:

```dockerfile
# Dockerfile.backstage-nix
FROM nixos/nix:latest AS builder
WORKDIR /build

# Clone and build configuration
RUN git clone -b container-ssh https://github.com/vpittamp/nixos-config.git .
RUN nix build ./user#homeConfigurations.container-essential.activationPackage \
    --extra-experimental-features "nix-command flakes"

FROM backstage:latest
COPY --from=builder /nix /nix
COPY --from=builder /root/.nix-profile /opt/nix-profile
COPY --from=builder /build/result /opt/home-manager

ENV PATH="/opt/nix-profile/bin:${PATH}"
USER code
RUN /opt/home-manager/activate
```

## Solution 2: Kubernetes Sidecar Pattern

Add a sidecar container to your pod that provides the AI tools:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: backstage-with-ai
spec:
  containers:
  - name: backstage
    image: backstage:latest
    volumeMounts:
    - name: ai-tools
      mountPath: /opt/ai-tools
    env:
    - name: PATH
      value: "/opt/ai-tools/bin:$(PATH)"
      
  - name: ai-tools-provider
    image: nixos/nix:latest
    command: ["/bin/sh"]
    args:
    - -c
    - |
      curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash -s essential
      cp -r /root/.nix-profile/* /opt/ai-tools/
      sleep infinity
    volumeMounts:
    - name: ai-tools
      mountPath: /opt/ai-tools
      
  volumes:
  - name: ai-tools
    emptyDir: {}
```

## Solution 3: Init Container Pattern

Use an init container to install tools before the main container starts:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: backstage-with-ai
spec:
  initContainers:
  - name: install-ai-tools
    image: nixos/nix:latest
    command: ["/bin/sh"]
    args:
    - -c
    - |
      curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash
      cp -r /root/.nix-profile /shared/nix-profile
      cp -r /nix /shared/nix
    volumeMounts:
    - name: shared-tools
      mountPath: /shared
      
  containers:
  - name: backstage
    image: backstage:latest
    volumeMounts:
    - name: shared-tools
      mountPath: /opt
    env:
    - name: PATH
      value: "/opt/nix-profile/bin:$(PATH)"
      
  volumes:
  - name: shared-tools
    emptyDir: {}
```

## Available Profiles

The installation script supports different profiles:

- **minimal**: Basic tools only (no AI assistants)
- **essential** (default): Includes all AI assistants + development tools
- **development**: Full development environment with AI assistants
- **ai**: Focused on AI assistants with minimal other tools

Usage:
```bash
# Install essential profile (default)
curl -L .../install-container.sh | bash

# Install specific profile
curl -L .../install-container.sh | bash -s minimal
curl -L .../install-container.sh | bash -s development
curl -L .../install-container.sh | bash -s ai
```

## Installed AI Tools

After installation, you'll have:

- **claude** - Claude Code CLI (OAuth: `claude login`)
- **gemini** - Gemini CLI (OAuth: run `gemini` and select login)
- **codex** - OpenAI Codex (OAuth: `codex auth`)
- **aichat** - Multi-model chat interface

## Container Compatibility

| Container Image | Nix Location | User | Tested | Notes |
|---|---|---|---|---|
| nixos/nix:latest | /root/.nix-profile/bin/nix | root | ✅ | Recommended, latest Nix |
| nixpkgs/nix:latest | /usr/bin/nix | root | ✅ | Smaller, minimal |
| nixpkgs/nix-flakes:latest | /usr/bin/nix | root | ✅ | Flakes pre-enabled |
| xtruder/nix-devcontainer | /home/code/.nix-profile/bin/nix | code | ✅ | Dev-focused |
| ubuntu/debian/alpine | N/A | varies | ✅ | Requires Nix installation |
| backstage | N/A | node | ⚠️ | Needs custom image or sidecar |

## Troubleshooting

### "nix: command not found"
- The container doesn't have Nix installed
- Use one of the recommended images or build a custom image

### "no new privileges" error
- Container has security restrictions (common in Kubernetes)
- Use the sidecar or init container pattern
- Or build a custom image with tools pre-installed

### "Operation not permitted" during build
- Container lacks permissions for certain operations
- Use a less restrictive security context or pre-built image

### Installation seems frozen
- Building packages can take 5-10 minutes on first run
- Subsequent runs use cached packages and are much faster

## OAuth Authentication

All AI tools use OAuth (no API keys needed):

1. **Claude**: Run `claude login` and follow the browser flow
2. **Gemini**: Run `gemini` and select "Login with Google"
3. **Codex**: Run `codex auth` for authentication

## Support

For issues or questions:
- Check the [main README](../README.md)
- Report issues at: https://github.com/vpittamp/nixos-config/issues
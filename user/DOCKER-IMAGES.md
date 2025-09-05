# Docker Images for Nix-enabled Containers

This directory contains Docker images for different container deployment scenarios with Nix package manager and home-manager configurations.

## Available Dockerfiles

### 1. Dockerfile.add-nix
**Purpose**: Generic solution to add Nix to ANY existing container image

**Use Case**: 
- When you have an existing container (e.g., official Backstage, Node.js app)
- Want to add Nix capabilities without rebuilding the entire image
- Quick prototyping with Nix tools

**How it works**:
- Multi-stage build copying Nix from `nixos/nix:latest`
- Preserves your base image while adding Nix environment
- Minimal changes to existing containers

**Build Example**:
```bash
docker build -f Dockerfile.add-nix \
  --build-arg BASE_IMAGE=backstage:latest \
  -t backstage-with-nix .
```

---

### 2. Dockerfile.backstage-nix
**Purpose**: Complete Backstage + Nix + AI tools production image

**Use Case**:
- Production deployments where everything should be pre-installed
- When you want fastest container startup (no runtime installation)
- CI/CD pipelines that need consistent, immutable images

**How it works**:
- Multi-stage build that pre-builds home-manager configuration
- Includes all AI tools (claude, gemini, codex, aichat)
- Everything baked into the image layers

**Build Example**:
```bash
docker build -f Dockerfile.backstage-nix -t backstage-ai:latest .
```

**Trade-offs**:
- ✅ Fastest startup time
- ✅ Immutable and reproducible
- ❌ Larger image size
- ❌ Longer build times

---

### 3. Dockerfile.ubuntu-nix-v4
**Purpose**: Ubuntu-based image with Nix pre-installed for Kubernetes deployments

**Use Case**:
- Kubernetes deployments with persistent volumes
- Development containers that need runtime configuration
- When using PVC for /nix storage persistence

**How it works**:
- Ubuntu 24.04 base with 'code' user (UID 1001)
- Single-user Nix installation (works as non-root)
- Compatible with Kubernetes security contexts
- Designed to work with PersistentVolumeClaims

**Build Example**:
```bash
docker build -f Dockerfile.ubuntu-nix-v4 -t ubuntu-nix-nonroot:v4 .
docker push docker.io/yourrepo/ubuntu-nix-nonroot:v4
```

**Key Features**:
- Non-root user 'code' (UID 1001)
- Pre-installed Nix in single-user mode
- Entrypoint script ensures Nix environment
- Works with restricted Kubernetes pods

**Trade-offs**:
- ✅ Works with Kubernetes PVCs
- ✅ Non-root security compliance
- ✅ Flexible runtime configuration
- ❌ Requires runtime setup for home-manager

---

## Choosing the Right Image

### Decision Matrix

| Scenario | Recommended Dockerfile | Why |
|----------|----------------------|-----|
| Adding Nix to existing app | `Dockerfile.add-nix` | Minimal changes, preserves base |
| Production Backstage + AI | `Dockerfile.backstage-nix` | Everything pre-installed |
| Kubernetes with PVC | `Dockerfile.ubuntu-nix-v4` | PVC-compatible, non-root |
| Quick development | `Dockerfile.ubuntu-nix-v4` | Fast rebuild, runtime config |
| CI/CD pipelines | `Dockerfile.backstage-nix` | Reproducible, immutable |

## Container Setup Commands

### For ubuntu-nix-v4 in Kubernetes

After container starts, run:
```bash
# Install Nix (if not persisted in PVC)
curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --yes

# Source Nix environment
. /home/code/.nix-profile/etc/profile.d/nix.sh

# Install home-manager configuration
nix run 'github:vpittamp/nixos-config/container-ssh?dir=user#homeConfigurations.container-essential.activationPackage' \
  --extra-experimental-features 'nix-command flakes' \
  --accept-flake-config --refresh
```

### Available Home-Manager Profiles

- `container-minimal` - Basic development tools (git, vim, curl, jq, htop)
- `container-essential` - Includes AI assistants (claude, gemini, codex, aichat)
- `container-development` - Development tools + AI assistants
- `container-ai` - Full AI-assisted development environment

## Known Issues & Solutions

### chmod Permission Errors
**Problem**: Building claude-code from NPM fails with chmod errors in restricted containers

**Solution**: Use npm-package wrapper (already configured in container-essential profile)

### PVC Volume Overwrites
**Problem**: Empty PVC mounts overwrite pre-installed /nix directory

**Solution**: InitContainer copies Nix to PVC on first run (see CDK8s configuration)

### Multiple Dockerfile Versions
**Problem**: Historical versions (v1, v2, v3) created during problem-solving

**Solution**: Kept only working versions, removed intermediate attempts

## Maintenance Notes

- **ubuntu-nix-v4** is the current production image for Kubernetes
- **backstage-nix** needs updating when AI tools change
- **add-nix** is stable and rarely needs changes
- All images should use 'code' user (UID 1001) for Kubernetes compatibility

## Related Files

- `entrypoint.sh` - Runtime Nix environment setup script
- `install-container.sh` - Home-manager installation helper
- `ai-assistants/` - Individual AI tool configurations
- `/home/vpittamp/stacks/cdk8s/charts/apps/backstage-parameterized-chart.ts` - Kubernetes deployment configuration
# Installing Home-Manager in Containers

## Quick Start (One-liner)

When you've exec'd into a nix-based container (like `xtruder/nix-devcontainer`), run:

```bash
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-home-manager.sh | bash
```

## Manual Installation Steps

### 1. First, check your environment:

```bash
# Verify nix is available
nix --version

# Check if you're in a container
echo "Container: ${KUBERNETES_SERVICE_HOST:+Yes}"
```

### 2. Set up Home Manager:

```bash
# Add home-manager channel
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update

# Install home-manager
nix-shell '<home-manager>' -A install
```

### 3. Create a minimal configuration:

```bash
mkdir -p ~/.config/home-manager

cat > ~/.config/home-manager/home.nix << 'EOF'
{ config, pkgs, lib, ... }:

let
  # Fetch user packages from GitHub
  nixosConfig = builtins.fetchGit {
    url = "https://github.com/vpittamp/nixos-config.git";
    ref = "container-ssh";
  };
  
  userPackages = import "${nixosConfig}/user/packages.nix" { inherit pkgs lib; };
in
{
  home.username = builtins.getEnv "USER";
  home.homeDirectory = builtins.getEnv "HOME";
  home.stateVersion = "24.05";
  
  # Use minimal packages for containers
  home.packages = userPackages.minimal;
  
  # Enable basic programs
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.vim.enable = true;
  programs.bash = {
    enable = true;
    enableCompletion = true;
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
EOF
```

### 4. Apply the configuration:

```bash
# Set container environment flag
export NIXOS_CONTAINER=1

# Apply configuration
home-manager switch
```

## For Specific Container Types

### xtruder/nix-devcontainer

This container already has nix installed. Just run:

```bash
# Install home-manager
nix-env -iA nixpkgs.home-manager

# Create config and switch
mkdir -p ~/.config/home-manager
# (create home.nix as shown above)
home-manager switch
```

### devcontainer with Nix feature

If using VS Code devcontainer with nix feature:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/nix:1": {}
  },
  "postCreateCommand": "curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-home-manager.sh | bash"
}
```

### Kubernetes Pod with Nix

For a running pod:

```bash
# Exec into pod
kubectl exec -it <pod-name> -- bash

# Run installation
curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-home-manager.sh | bash
```

## Package Profiles

The user packages are organized into profiles:

- **minimal**: Basic tools (git, vim, tmux, curl, jq, fzf, ripgrep)
- **essential**: Common dev tools (includes terminal utilities)
- **development**: Full development environment (language servers, etc.)

Set the profile before running home-manager:

```bash
export CONTAINER_PROFILE=minimal  # or essential, development
home-manager switch
```

## Troubleshooting

### Permission Errors

If you get permission errors, you're likely hitting the container restrictions we solved. Use only the user packages, not system packages.

### SSL Certificate Errors

If you encounter SSL issues:

```bash
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export NIX_SSL_CERT_FILE=$SSL_CERT_FILE
```

### Nix Channel Issues

If channels aren't working:

```bash
# Use flakes instead
nix run nixpkgs#home-manager -- switch
```

## Testing Installation

After installation, verify packages:

```bash
# Check installed packages
which git vim tmux fzf ripgrep

# List all home-manager packages
home-manager packages
```
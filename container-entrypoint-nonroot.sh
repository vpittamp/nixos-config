#!/bin/bash
# Simplified entrypoint for running as non-root user
set -e

echo "[entrypoint] Container starting at $(date)"

# Export marker to prevent recursive shell invocations
export IN_NIX_SHELL=""

# Set user information
USER_ID=$(id -u 2>/dev/null || echo "1000")
GROUP_ID=$(id -g 2>/dev/null || echo "100")
USER_NAME="code"

echo "[entrypoint] Running as user: $USER_NAME (UID: $USER_ID, GID: $GROUP_ID)"

# Set up basic environment
export PATH="/nix/var/nix/profiles/default/bin:/bin:/usr/bin:$PATH"
export NIX_REMOTE=""
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"
export USER=$USER_NAME
export HOME="/home/$USER_NAME"

# SSL Certificate configuration for Node.js/Yarn
# Check if ca-certificates.crt exists, otherwise use ca-bundle.crt from cacert package
if [ -f "/etc/ssl/certs/ca-certificates.crt" ]; then
    export NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-certificates.crt"
    export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
    export REQUESTS_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
elif [ -f "/etc/ssl/certs/ca-bundle.crt" ]; then
    export NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-bundle.crt"
    export SSL_CERT_FILE="/etc/ssl/certs/ca-bundle.crt"
    export REQUESTS_CA_BUNDLE="/etc/ssl/certs/ca-bundle.crt"
fi
# Development-only: Allow self-signed certificates (with warning)
if [ "$ALLOW_INSECURE_SSL" = "true" ]; then
    export NODE_TLS_REJECT_UNAUTHORIZED=0
    echo "[entrypoint] WARNING: SSL certificate verification disabled (NODE_TLS_REJECT_UNAUTHORIZED=0)"
    echo "[entrypoint] This should only be used in development environments!"
fi

# Set proper terminal type for tmux compatibility
export TERM="xterm-256color"
# Disable terminal color queries that cause escape sequence issues
export COLORTERM="truecolor"

# Configure Nix for container usage
export NIX_CONF_DIR="$HOME/.config/nix"
mkdir -p "$NIX_CONF_DIR" 2>/dev/null || true

# Set up user profile directory for nix profile commands
export NIX_USER_PROFILE_DIR="$HOME/.nix-profile"
mkdir -p "$HOME/.nix-defexpr" 2>/dev/null || true

# Nix configuration is handled by the system
# We don't override it in the entrypoint to avoid conflicts

# Native Nix setup with environment preservation

# Initialize user nix profile if it doesn't exist
if [ -w "$HOME" ] && [ ! -L "$HOME/.nix-profile" ]; then
    echo "[entrypoint] Initializing user Nix profile..."
    # Create the profile link
    nix-env --switch-profile "$HOME/.nix-profile" 2>/dev/null || true
fi

# Ensure nix is in PATH
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

# Helper functions are now provided by /etc/profile.d/flake-helpers.sh
# Source it if not already done
if [ -f /etc/profile.d/flake-helpers.sh ]; then
    source /etc/profile.d/flake-helpers.sh 2>/dev/null || true
fi

# Set up direnv hook for automatic environment loading (if available)
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)" 2>/dev/null || true
fi

# Ensure home directory exists and is not a symlink
# This is critical for nix shell to work properly
if [ -L "$HOME" ]; then
    echo "[entrypoint] ERROR: $HOME is a symlink, which breaks nix shell"
    echo "[entrypoint] This should be a volume mount, not a symlink to nix store"
    exit 1
fi

if [ ! -d "$HOME" ]; then
    echo "[entrypoint] ERROR: Home directory $HOME does not exist"
    echo "[entrypoint] Ensure the container has a proper volume mount for /home/code"
    exit 1
fi

# Ensure home directory is writable
if [ ! -w "$HOME" ]; then
    echo "[entrypoint] WARNING: Home directory $HOME is not writable"
    # Try to use /tmp as a fallback for VS Code Server
    export VSCODE_SERVER_DATA_DIR="/tmp/.vscode-server"
    mkdir -p "$VSCODE_SERVER_DATA_DIR" 2>/dev/null || true
fi

# Source user profile if it exists
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi

# Create user directories if needed and we have permissions
if [ -w "$HOME" ]; then
    mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.cache" 2>/dev/null || true
fi

# Set up NIX_LD for dynamic binaries (needed for VS Code)
if [ -z "$NIX_LD" ]; then
    # Find the glibc loader
    LOADER=$(find /nix/store -maxdepth 2 -name 'ld-linux-x86-64.so.2' -type f 2>/dev/null | head -1)
    if [ -n "$LOADER" ]; then
        export NIX_LD="$LOADER"
        # Find library directories
        LIBDIRS=$(find /nix/store -maxdepth 2 -name lib -type d 2>/dev/null | head -20 | tr '\n' ':')
        export NIX_LD_LIBRARY_PATH="${LIBDIRS}${NIX_LD_LIBRARY_PATH}"
        export LD_LIBRARY_PATH="/lib:/usr/lib:/lib64:${LD_LIBRARY_PATH}"
        echo "[entrypoint] NIX_LD configured: $NIX_LD"
    fi
fi

# Create .envrc for automatic nix develop activation (optional)
if [ -w "$HOME" ] && [ ! -f "$HOME/.envrc" ]; then
    cat > "$HOME/.envrc" << 'ENVRC_EOF'
# Auto-activate nix develop if flake.nix exists
if [ -f "flake.nix" ]; then
    use flake
fi
ENVRC_EOF
    # Note: User needs to run 'direnv allow' to activate
fi

# Home-manager activation
echo "[entrypoint] Setting up home-manager environment..."

# First check if we have pre-staged configs in /etc/skel
if [ -d "/etc/skel" ] && [ "$(ls -A /etc/skel 2>/dev/null)" ]; then
    echo "[entrypoint] Found pre-staged home-manager configs in /etc/skel"
    
    if [ -w "$HOME" ]; then
        echo "[entrypoint] Copying pre-staged configs to home directory..."
        cp -r /etc/skel/. "$HOME/" 2>/dev/null || true
        
        # Fix permissions on copied files - make them writable by the user
        # This is necessary because files from Nix store are read-only
        echo "[entrypoint] Fixing permissions on home directory files..."
        find "$HOME" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$HOME" -type f -exec chmod 644 {} \; 2>/dev/null || true
        # Make .ssh directory more restrictive if it exists
        [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh" 2>/dev/null || true
        [ -f "$HOME/.ssh/config" ] && chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
        
        echo "[entrypoint] Home-manager configuration copied and permissions fixed"
    else
        echo "[entrypoint] ERROR: Cannot copy configs - home directory not writable"
        exit 1
    fi
else
    # Fallback to finding home-manager generation in /nix/store
    echo "[entrypoint] No pre-staged configs found, looking for home-manager generation..."
    HM_GENERATION=$(find /nix/store -maxdepth 1 -type d -name "*-home-manager-generation" 2>/dev/null | head -1)

    if [ -n "$HM_GENERATION" ]; then
        echo "[entrypoint] Found home-manager generation at: $HM_GENERATION"
    
    # Use GNU Stow to manage symlinks from home-manager generation to HOME
    # Stow is designed exactly for this use case - managing dotfiles and config directories
    if [ -d "$HM_GENERATION/home-files" ] && [ -w "$HOME" ]; then
        echo "[entrypoint] Using GNU Stow to link home-manager configuration..."
        
        # Check if stow is available
        if ! command -v stow >/dev/null 2>&1; then
            echo "[entrypoint] ERROR: GNU Stow not found in PATH"
            echo "[entrypoint] Falling back to direct symlink method..."
            
            # Direct symlink fallback (simpler version)
            cd "$HOME"
            # Use stow-like approach manually - create symlinks for everything in home-files
            find "$HM_GENERATION/home-files" -mindepth 1 -maxdepth 1 | while read -r item; do
                item_name=$(basename "$item")
                ln -sfn "$item" "$HOME/$item_name"
                echo "[entrypoint]   Linked $item_name"
            done
        else
            # Stow needs the package to be in a directory adjacent to target
            # Create a temporary stow directory
            STOW_DIR="/tmp/hm-stow-$$"
            mkdir -p "$STOW_DIR/hm-configs"
            
            # Create symlinks in the stow package directory pointing to actual files
            cd "$HM_GENERATION/home-files"
            find . -type f -o -type l | while read -r file; do
                # Skip the . directory itself
                [ "$file" = "." ] && continue
                
                # Create parent directory if needed
                dir=$(dirname "$file")
                [ "$dir" != "." ] && mkdir -p "$STOW_DIR/hm-configs/$dir"
                
                # Create absolute symlink to the actual file
                ln -sf "$HM_GENERATION/home-files/$file" "$STOW_DIR/hm-configs/$file"
            done
            
            # Now use stow to create the links in HOME
            cd "$STOW_DIR"
            # -v = verbose, -t = target directory, -S = stow (default), --no-folding = don't fold directories
            stow -v -t "$HOME" -S --no-folding hm-configs 2>&1 | while read -r line; do
                echo "[entrypoint]   $line"
            done
            
            # Check stow exit code
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                echo "[entrypoint] Home-manager configuration linked successfully with Stow"
            else
                echo "[entrypoint] WARNING: Stow reported some conflicts or errors"
            fi
            
            # Clean up
            cd /
            rm -rf "$STOW_DIR"
        fi
        
        else
            echo "[entrypoint] ERROR: Cannot link home-manager files - either generation not found or home not writable"
            exit 1
        fi
    else
        echo "[entrypoint] ERROR: No home-manager generation found in /nix/store"
        echo "[entrypoint] This indicates the container was not built with home-manager properly included"
        exit 1
    fi
fi

# Auto-approve direnv if .envrc exists
if [ -f "$HOME/.envrc" ] && command -v direnv >/dev/null 2>&1; then
    direnv allow "$HOME/.envrc" 2>/dev/null || true
fi

echo "[entrypoint] User environment ready"
echo "[entrypoint] Container ready with Nix flake support"
echo "[entrypoint] Type 'nix-dev' or 'nd' to enter a development shell"
echo "[entrypoint] Type 'nix-add <package>' or 'na <package>' to add packages"

# Execute the original command
if [ $# -eq 0 ]; then
    echo "[entrypoint] No command specified, running sleep infinity"
    exec sleep infinity
else
    echo "[entrypoint] Executing command: $@"
    exec "$@"
fi
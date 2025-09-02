#!/bin/bash
# Simplified entrypoint for running as non-root user
set -e

echo "[entrypoint] Container starting at $(date)"

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

# Home-manager activation using GNU Stow
echo "[entrypoint] Setting up home-manager environment with GNU Stow..."

# Look for home-manager generation files
# The activationPackage from the build should be in the container
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

echo "[entrypoint] User environment ready"

# Execute the original command
if [ $# -eq 0 ]; then
    echo "[entrypoint] No command specified, running sleep infinity"
    exec sleep infinity
else
    echo "[entrypoint] Executing command: $@"
    exec "$@"
fi
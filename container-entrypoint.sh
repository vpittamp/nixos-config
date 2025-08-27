#!/bin/bash
# Container entrypoint script that starts SSH daemon and executes the main command
# This script ensures SSH is available for development access and VS Code compatibility

set -e

# Function to setup SSH environment
setup_ssh() {
    echo "[entrypoint] Setting up SSH environment..."
    
    # Create necessary directories (including runtime directories for sshd)
    mkdir -p /etc/ssh /var/empty /root/.ssh /home/code/.ssh /var/run /var/log
    
    # Initialize user database files if missing
    if [ ! -f /etc/passwd ]; then
        echo "[entrypoint] Creating /etc/passwd for user database..."
        cat > /etc/passwd << 'EOF'
root:x:0:0:System administrator:/root:/bin/bash
code:x:1000:100:Development user:/home/code:/bin/bash
vpittamp:x:1001:100:VPittamp user:/home/vpittamp:/bin/bash
sshd:x:74:74:SSH Privilege Separation:/var/empty:/sbin/nologin
nobody:x:65534:65534:Nobody:/var/empty:/bin/false
EOF
    fi
    
    if [ ! -f /etc/group ]; then
        echo "[entrypoint] Creating /etc/group..."
        cat > /etc/group << 'EOF'
root:x:0:
wheel:x:1:code,vpittamp
users:x:100:code,vpittamp
sshd:x:74:
nogroup:x:65534:
EOF
    fi
    
    if [ ! -f /etc/shadow ]; then
        echo "[entrypoint] Creating /etc/shadow..."
        touch /etc/shadow
        chmod 640 /etc/shadow
        cat > /etc/shadow << 'EOF'
root:!:19000:0:99999:7:::
code:!:19000:0:99999:7:::
vpittamp:!:19000:0:99999:7:::
sshd:!:19000:0:99999:7:::
nobody:!:19000:0:99999:7:::
EOF
    fi
    
    # Ensure NSS is properly configured for user lookups
    if [ ! -f /etc/nsswitch.conf ]; then
        echo "[entrypoint] Creating nsswitch.conf for user lookups..."
        cat > /etc/nsswitch.conf << 'EOF'
passwd:    files systemd
group:     files systemd
shadow:    files
hosts:     files dns
networks:  files
ethers:    files
services:  files
protocols: files
EOF
    fi
    
    # Generate SSH host keys if they don't exist
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        echo "[entrypoint] Generating SSH host keys..."
        # Suppress the "No user exists" warning which is harmless
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q < /dev/null 2>/dev/null || true
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" -q < /dev/null 2>/dev/null || true
        
        # Ensure keys were created
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            echo "[entrypoint] Warning: Failed to generate SSH host keys"
        fi
    fi
    
    # Copy mounted host keys if available (for persistent keys across restarts)
    if [ -d /ssh-host-keys ] && [ "$(ls -A /ssh-host-keys 2>/dev/null)" ]; then
        echo "[entrypoint] Using mounted SSH host keys..."
        
        # Copy both private keys and public keys if they exist
        for keyfile in /ssh-host-keys/ssh_host_*; do
            if [ -f "$keyfile" ]; then
                keyname=$(basename "$keyfile")
                
                # Public keys (.pub files) are never base64-encoded, they're plain text
                if [[ "$keyname" == *.pub ]]; then
                    echo "[entrypoint] Copying public key: $keyname"
                    cp -f "$keyfile" "/etc/ssh/$keyname"
                # Private keys might be base64-encoded
                elif ! grep -q "BEGIN" "$keyfile" 2>/dev/null; then
                    echo "[entrypoint] Private key appears to be base64-encoded: $keyname"
                    
                    # Ensure temp directory exists
                    mkdir -p /tmp
                    
                    # Decode once and check if it's still base64
                    base64 -d < "$keyfile" > "/tmp/${keyname}.tmp"
                    
                    # Check if decoded content is STILL base64 (double encoding from External Secrets)
                    if ! grep -q "BEGIN" "/tmp/${keyname}.tmp" 2>/dev/null; then
                        echo "[entrypoint] Key was double base64-encoded, decoding again..."
                        base64 -d < "/tmp/${keyname}.tmp" > "/etc/ssh/$keyname"
                    else
                        # Single base64 encoding
                        mv "/tmp/${keyname}.tmp" "/etc/ssh/$keyname"
                    fi
                else
                    echo "[entrypoint] Copying plain text private key: $keyname"
                    cp -f "$keyfile" "/etc/ssh/$keyname"
                fi
                
                # Set appropriate permissions based on file type
                if [[ "$keyname" == *.pub ]]; then
                    chmod 644 "/etc/ssh/$keyname" 2>/dev/null || true
                else
                    chmod 600 "/etc/ssh/$keyname" 2>/dev/null || true
                fi
            fi
        done
        
        # Generate public keys from private keys if .pub files don't exist
        if [ -f /etc/ssh/ssh_host_ed25519_key ] && [ ! -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
            echo "[entrypoint] Generating ED25519 public key from private key..."
            ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key > /etc/ssh/ssh_host_ed25519_key.pub
        fi
        
        if [ -f /etc/ssh/ssh_host_rsa_key ] && [ ! -f /etc/ssh/ssh_host_rsa_key.pub ]; then
            echo "[entrypoint] Generating RSA public key from private key..."
            ssh-keygen -y -f /etc/ssh/ssh_host_rsa_key > /etc/ssh/ssh_host_rsa_key.pub
        fi
        
        chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
    fi
    
    # Create SSH config
    cat > /etc/ssh/sshd_config << 'EOF'
Port 2222
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
StrictModes no
UsePAM no
UsePrivilegeSeparation no
AllowUsers code root
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
AuthorizedKeysFile .ssh/authorized_keys /ssh-keys/authorized_keys
Subsystem sftp /bin/sftp-server
LogLevel INFO
PidFile /var/run/sshd.pid
EOF
    
    # Note: authorized_keys copying is handled by container-ssh.nix activation script
    # This ensures proper ownership and permissions
    
    # Create home directories if they don't exist
    mkdir -p /home/code /root
    
    echo "[entrypoint] SSH setup complete"
}

# VS Code tunnel functionality has been removed
# The tunnel had compatibility issues with NixOS container structure
# Use SSH on port 2222 for remote development access

# Function to start SSH daemon
start_sshd() {
    if [ "${CONTAINER_SSH_ENABLED}" = "true" ]; then
        echo "[entrypoint] Starting SSH daemon on port ${CONTAINER_SSH_PORT:-2222}..."
        setup_ssh
        
        # Ensure privilege separation directory has correct permissions
        chmod 755 /var/empty
        
        # Start sshd in the background
        echo "[entrypoint] Starting sshd..."
        
        # First test the configuration
        if /bin/sshd -t -f /etc/ssh/sshd_config 2>/dev/null; then
            # Configuration is valid, start the daemon
            /bin/sshd -D -f /etc/ssh/sshd_config &
            SSHD_PID=$!
            
            # Wait a moment to ensure it starts
            sleep 2
            
            # Check if the process is still running
            if kill -0 $SSHD_PID 2>/dev/null; then
                echo "[entrypoint] SSH daemon started successfully (PID: $SSHD_PID)"
            else
                echo "[entrypoint] Warning: SSH daemon exited, will retry without strict config"
                # Try with minimal config
                /bin/sshd -D &
                SSHD_PID=$!
                sleep 1
                if kill -0 $SSHD_PID 2>/dev/null; then
                    echo "[entrypoint] SSH daemon started with default config (PID: $SSHD_PID)"
                else
                    echo "[entrypoint] Warning: SSH daemon failed to start"
                fi
            fi
        else
            echo "[entrypoint] Warning: SSH config validation failed, trying with defaults"
            /bin/sshd -D &
            echo "[entrypoint] SSH daemon started with default config"
        fi
    else
        echo "[entrypoint] SSH is disabled (CONTAINER_SSH_ENABLED != true)"
    fi
}

# Function to setup VS Code compatibility
setup_vscode_compat() {
    echo "[entrypoint] Setting up VS Code compatibility..."
    
    # Create /usr/bin with essential symlinks
    mkdir -p /usr/bin
    for cmd in env bash sh uname ps find grep sed hostname which curl wget git cat ls cp mv rm mkdir touch; do
        if command -v $cmd >/dev/null 2>&1; then
            ln -sf $(command -v $cmd) /usr/bin/$cmd 2>/dev/null || true
        fi
    done
    
    # Create /lib64 for dynamic linker
    mkdir -p /lib64
    GLIBC_LD=$(ls /nix/store/*/glibc*/lib/ld-linux-x86-64.so.2 2>/dev/null | head -1)
    if [ -n "$GLIBC_LD" ]; then
        ln -sf "$GLIBC_LD" /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    fi
    
    # Link essential libraries
    mkdir -p /lib /usr/lib
    
    # Find and link glibc libraries
    for lib in /nix/store/*/glibc*/lib/*.so*; do
        if [ -f "$lib" ]; then
            basename_lib=$(basename "$lib")
            [ ! -e "/lib/$basename_lib" ] && ln -sf "$lib" "/lib/$basename_lib" 2>/dev/null || true
            [ ! -e "/usr/lib/$basename_lib" ] && ln -sf "$lib" "/usr/lib/$basename_lib" 2>/dev/null || true
        fi
    done
    
    # Find and link gcc libraries (libstdc++, libgcc_s)
    for lib in /nix/store/*/gcc*/lib/libstdc++.so* /nix/store/*/gcc*/lib/libgcc_s.so*; do
        if [ -f "$lib" ]; then
            basename_lib=$(basename "$lib")
            [ ! -e "/lib/$basename_lib" ] && ln -sf "$lib" "/lib/$basename_lib" 2>/dev/null || true
            [ ! -e "/usr/lib/$basename_lib" ] && ln -sf "$lib" "/usr/lib/$basename_lib" 2>/dev/null || true
        fi
    done
    
    # Create ldconfig stub (some tools may expect it)
    if [ ! -f /usr/bin/ldconfig ]; then
        cat > /usr/bin/ldconfig << 'LDCONFIG'
#!/bin/sh
# Basic ldconfig stub for compatibility
exit 0
LDCONFIG
        chmod +x /usr/bin/ldconfig 2>/dev/null || true
    fi
    
    # Create /etc/os-release if missing
    if [ ! -f /etc/os-release ]; then
        cat > /etc/os-release << 'OSRELEASE'
NAME="NixOS"
ID=nixos
VERSION="24.11"
VERSION_ID="24.11"
PRETTY_NAME="NixOS 24.11"
HOME_URL="https://nixos.org/"
SUPPORT_URL="https://nixos.org/community/"
BUG_REPORT_URL="https://github.com/NixOS/nixpkgs/issues"
OSRELEASE
    fi
    
    # Export library paths
    export LD_LIBRARY_PATH="/lib:/usr/lib:/lib64:${LD_LIBRARY_PATH}"
    for dir in /nix/store/*/gcc*/lib /nix/store/*/glibc*/lib; do
        if [ -d "$dir" ]; then
            export LD_LIBRARY_PATH="${dir}:${LD_LIBRARY_PATH}"
        fi
    done
    
    echo "[entrypoint] VS Code compatibility setup complete"
}

# Function to ensure dynamic loader is available for VS Code
fix_vscode_node() {
    echo "[entrypoint] Setting up dynamic loader for VS Code compatibility..."
    
    # Always recreate the symlink to ensure it's correct
    mkdir -p /lib64 /lib
    
    # Find the glibc loader
    LOADER=$(ls /nix/store/*/lib/ld-linux-x86-64.so.2 2>/dev/null | grep glibc | head -1)
    
    if [ -n "$LOADER" ]; then
        ln -sf "$LOADER" /lib64/ld-linux-x86-64.so.2
        ln -sf "$LOADER" /lib/ld-linux-x86-64.so.2
        echo "[entrypoint] Created dynamic loader symlinks:"
        echo "  /lib64/ld-linux-x86-64.so.2 -> $LOADER"
        echo "  /lib/ld-linux-x86-64.so.2 -> $LOADER"
        
        # Set up NIX_LD environment variables for VS Code
        export NIX_LD="$LOADER"
        # Find actual library directories
        LIBDIRS=$(find /nix/store -maxdepth 2 -name lib -type d 2>/dev/null | head -20 | tr '\n' ':')
        export NIX_LD_LIBRARY_PATH="${LIBDIRS}${NIX_LD_LIBRARY_PATH}"
        
        # Write to profile for SSH sessions and VS Code
        mkdir -p /etc/profile.d
        cat > /etc/profile.d/nix-ld.sh << EOF
export NIX_LD="$LOADER"
export NIX_LD_LIBRARY_PATH="${LIBDIRS}\${NIX_LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="/lib:/usr/lib:/lib64:\${LD_LIBRARY_PATH}"
EOF
        chmod +x /etc/profile.d/nix-ld.sh 2>/dev/null || true
        
        # Test if it works
        if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
            echo "[entrypoint] Dynamic loader setup successful"
            echo "[entrypoint] NIX_LD=$NIX_LD"
        else
            echo "[entrypoint] Warning: Dynamic loader symlink creation may have failed"
        fi
    else
        echo "[entrypoint] Warning: Could not find glibc loader in /nix/store"
    fi
    
    return 0
}

# Legacy function kept for compatibility
fix_vscode_node_legacy() {
    echo "[entrypoint] Checking for VS Code server installations..."
    
    # Find the NixOS interpreter path
    local INTERPRETER=$(ls /nix/store/*/glibc*/lib/ld-linux-x86-64.so.2 2>/dev/null | head -1)
    if [ -z "$INTERPRETER" ]; then
        INTERPRETER="/lib64/ld-linux-x86-64.so.2"
    fi
    
    # Function to patch a VS Code installation
    patch_vscode_dir() {
        local vscode_dir="$1"
        echo "[entrypoint] Patching VS Code server at: $vscode_dir"
        
        # Replace node binary with wrapper script
        if [ -f "$vscode_dir/node" ]; then
            # Check if already fixed
            if ! grep -q "exec /bin/node" "$vscode_dir/node" 2>/dev/null; then
                mv "$vscode_dir/node" "$vscode_dir/node.orig" 2>/dev/null || true
                
                # Create wrapper script that uses system node
                cat > "$vscode_dir/node" << 'NODEWRAPPER'
#!/bin/bash
exec /bin/node "$@"
NODEWRAPPER
                chmod +x "$vscode_dir/node"
                echo "[entrypoint] Replaced node with wrapper script"
            fi
        fi
        
        # Fix ripgrep if present
        if [ -f "$vscode_dir/node_modules/@vscode/ripgrep/bin/rg" ] && command -v rg >/dev/null 2>&1; then
            rm -f "$vscode_dir/node_modules/@vscode/ripgrep/bin/rg" 2>/dev/null || true
            ln -sf $(command -v rg) "$vscode_dir/node_modules/@vscode/ripgrep/bin/rg"
            echo "[entrypoint] Replaced ripgrep with system version"
        fi
        
        # Use patchelf to fix binary interpreters if available
        if command -v patchelf >/dev/null 2>&1 && [ -n "$INTERPRETER" ]; then
            # Patch node_modules binaries
            for binary in "$vscode_dir"/node_modules/**/bin/*; do
                if [ -f "$binary" ] && [ ! -L "$binary" ] && file "$binary" 2>/dev/null | grep -q "ELF"; then
                    echo "[entrypoint] Patching binary: $(basename $binary)"
                    patchelf --set-interpreter "$INTERPRETER" "$binary" 2>/dev/null || true
                fi
            done
            
            # Patch extensions binaries
            for ext_binary in "$vscode_dir"/extensions/*/server/bin/*; do
                if [ -f "$ext_binary" ] && [ ! -L "$ext_binary" ] && file "$ext_binary" 2>/dev/null | grep -q "ELF"; then
                    echo "[entrypoint] Patching extension binary: $(basename $ext_binary)"
                    patchelf --set-interpreter "$INTERPRETER" "$ext_binary" 2>/dev/null || true
                fi
            done
        fi
        
        # Fix helpers/check-requirements.sh to bypass GLIBC check
        if [ -f "$vscode_dir/bin/helpers/check-requirements.sh" ]; then
            if ! grep -q "NixOS detected" "$vscode_dir/bin/helpers/check-requirements.sh" 2>/dev/null; then
                echo "[entrypoint] Patching check-requirements.sh for NixOS"
                sed -i '1a echo "Warning: NixOS detected, skipping GLIBC check"; exit 0' "$vscode_dir/bin/helpers/check-requirements.sh" 2>/dev/null || true
            fi
        fi
        
        # Also fix the bin/remote-cli directory if it exists
        if [ -f "$vscode_dir/bin/remote-cli/node" ]; then
            if ! grep -q "exec /bin/node" "$vscode_dir/bin/remote-cli/node" 2>/dev/null; then
                mv "$vscode_dir/bin/remote-cli/node" "$vscode_dir/bin/remote-cli/node.orig" 2>/dev/null || true
                cat > "$vscode_dir/bin/remote-cli/node" << 'NODEWRAPPER'
#!/bin/bash
exec /bin/node "$@"
NODEWRAPPER
                chmod +x "$vscode_dir/bin/remote-cli/node"
            fi
        fi
    }
    
    # Check common VS Code server locations (both bin and cli/servers)
    for vscode_dir in /root/.vscode-server/bin/* /root/.vscode-server/cli/servers/*/server /home/*/.vscode-server/bin/* /home/*/.vscode-server/cli/servers/*/server; do
        if [ -d "$vscode_dir" ]; then
            patch_vscode_dir "$vscode_dir"
        fi
    done
    
    # Monitor for new VS Code installations using inotify if available
    if command -v inotifywait >/dev/null 2>&1; then
        # Run in background to watch for new installations
        (
            # Create directories if they don't exist yet
            mkdir -p /root/.vscode-server/bin 2>/dev/null || true
            
            while true; do
                # Watch for new VS Code server installations
                inotifywait -q -r -e create,close_write --include "node$" /root/.vscode-server 2>/dev/null
                
                # Immediately patch any node binaries found
                for node_file in /root/.vscode-server/bin/*/node /root/.vscode-server/cli/servers/*/server/node; do
                    if [ -f "$node_file" ] && ! grep -q "exec /bin/node" "$node_file" 2>/dev/null; then
                        echo "[entrypoint-monitor] Found new node binary: $node_file"
                        dir=$(dirname "$node_file")
                        patch_vscode_dir "$dir"
                    fi
                done
            done
        ) >> /var/log/vscode-monitor.log 2>&1 &
        echo "[entrypoint] Started VS Code monitor (PID: $!)"
    fi
    
    # Create a wrapper script that fixes node on demand
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/fix-vscode-node << 'FIXSCRIPT'
#!/bin/bash
echo "Fixing VS Code server node binaries..."

for vscode_dir in /root/.vscode-server/bin/* /root/.vscode-server/cli/servers/*/server /home/*/.vscode-server/bin/* /home/*/.vscode-server/cli/servers/*/server; do
    if [ -d "$vscode_dir" ] && [ -f "$vscode_dir/node" ]; then
        # Check if not already fixed
        if ! grep -q "exec /bin/node" "$vscode_dir/node" 2>/dev/null; then
            echo "Fixing node at: $vscode_dir"
            mv "$vscode_dir/node" "$vscode_dir/node.orig" 2>/dev/null || true
            cat > "$vscode_dir/node" << 'NODEWRAPPER'
#!/bin/bash
exec /bin/node "$@"
NODEWRAPPER
            chmod +x "$vscode_dir/node"
        fi
        
        # Fix remote-cli node
        if [ -f "$vscode_dir/bin/remote-cli/node" ]; then
            if ! grep -q "exec /bin/node" "$vscode_dir/bin/remote-cli/node" 2>/dev/null; then
                mv "$vscode_dir/bin/remote-cli/node" "$vscode_dir/bin/remote-cli/node.orig" 2>/dev/null || true
                cat > "$vscode_dir/bin/remote-cli/node" << 'NODEWRAPPER2'
#!/bin/bash
exec /bin/node "$@"
NODEWRAPPER2
                chmod +x "$vscode_dir/bin/remote-cli/node"
            fi
        fi
        
        # Fix ripgrep
        if [ -f "$vscode_dir/node_modules/@vscode/ripgrep/bin/rg" ] && command -v rg >/dev/null 2>&1; then
            rm -f "$vscode_dir/node_modules/@vscode/ripgrep/bin/rg"
            ln -sf $(command -v rg) "$vscode_dir/node_modules/@vscode/ripgrep/bin/rg"
        fi
    fi
done

echo "VS Code node fix complete"
FIXSCRIPT
    chmod +x /usr/local/bin/fix-vscode-node 2>/dev/null || true
}

# Main execution
main() {
    echo "[entrypoint] Container starting at $(date)"
    
    # Setup VS Code compatibility first
    setup_vscode_compat
    
    # Ensure nix-ld is properly configured
    fix_vscode_node
    
    # Export NIX_LD variables to current shell and all child processes
    if [ -f /etc/profile.d/nix-ld.sh ]; then
        . /etc/profile.d/nix-ld.sh
        echo "[entrypoint] NIX_LD environment variables loaded"
    fi
    
    # Setup SSL/TLS certificates
    echo "[entrypoint] Setting up SSL certificates..."
    # Find NixOS CA bundle
    CA_BUNDLE=$(find /nix/store -name ca-bundle.crt 2>/dev/null | head -1)
    if [ -n "$CA_BUNDLE" ]; then
        export SSL_CERT_FILE="$CA_BUNDLE"
        export NIX_SSL_CERT_FILE="$CA_BUNDLE"
        export CURL_CA_BUNDLE="$CA_BUNDLE"
        echo "[entrypoint] SSL certificates configured: $CA_BUNDLE"
    elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
        export NIX_SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
        export CURL_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
        echo "[entrypoint] SSL certificates configured: /etc/ssl/certs/ca-certificates.crt"
    fi
    
    # Add idpbuilder certificate if available
    if [ -f /etc/ssl/certs/idpbuilder-ca.crt ]; then
        export NODE_EXTRA_CA_CERTS="/etc/ssl/certs/idpbuilder-ca.crt"
        echo "[entrypoint] IdpBuilder CA configured for Node.js"
    fi
    
    # Run NixOS system activation which includes home-manager
    echo "[entrypoint] Skipping NixOS system activation (not needed in container)..."
    # In containers, the activation script tries to mount filesystems which fails
    # The packages are already available in /bin from the container build
    echo "[entrypoint] Packages are available in /bin from container build"
    
    # Set up PATH to include per-user profiles
    if [ -d "/etc/profiles/per-user/$USER/bin" ]; then
        export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
    fi
    echo "[entrypoint] Using container PATH: $PATH"
    
    # Set locale environment variables to C.UTF-8 (minimal UTF-8 locale)
    # C.UTF-8 is built into glibc, no need for locale-archive
    export LANG="C.UTF-8"
    export LC_ALL="C.UTF-8"
    
    echo "[entrypoint] Locale configured: LANG=$LANG"
    
    # Link home-manager configuration files for users
    echo "[entrypoint] Setting up home-manager configuration files..."
    setup_home_manager_files() {
        local user="$1"
        local home="$2"
        
        # Create home directory if it doesn't exist
        if [ ! -d "$home" ]; then
            mkdir -p "$home"
            chown "$user:$user" "$home" 2>/dev/null || true
        fi
        
        # Find home-manager-files directory (they're all the same for our users)
        local HM_FILES=$(ls -d /nix/store/*-home-manager-files 2>/dev/null | head -1)
        
        if [ -n "$HM_FILES" ] && [ -d "$HM_FILES" ]; then
            echo "[entrypoint] Linking home-manager files from $HM_FILES to $home"
            
            # Use cp -rsf to create symlinks for all files
            # -r: recursive, -s: symbolic links, -f: force overwrite
            cp -rsf "$HM_FILES"/. "$home"/
            
            # Fix ownership
            chown -R "$user:$user" "$home" 2>/dev/null || true
            
            echo "[entrypoint] Home-manager files linked for $user"
        else
            echo "[entrypoint] Warning: home-manager-files not found in /nix/store"
        fi
        
        # Also try to run home-manager activation if available
        local HM_GEN=$(ls -d /nix/store/*-home-manager-generation 2>/dev/null | head -1)
        if [ -n "$HM_GEN" ] && [ -f "$HM_GEN/activate" ]; then
            echo "[entrypoint] Running home-manager activation for $user"
            # Run activation with modern driver (doesn't update profile)
            HOME="$home" USER="$user" "$HM_GEN/activate" --driver-version 1 2>/dev/null || true
        fi
    }
    
    # Setup for root
    setup_home_manager_files "root" "/root"
    
    # Setup for other users if they exist
    if id -u vpittamp >/dev/null 2>&1; then
        setup_home_manager_files "vpittamp" "/home/vpittamp"
    fi
    if id -u code >/dev/null 2>&1; then
        setup_home_manager_files "code" "/home/code"
    fi
    
    echo "[entrypoint] Home-manager configuration files setup complete"
    
    # Start SSH if enabled
    start_sshd
    
    # VS Code tunnel removed - use SSH on port 2222 for remote access
    
    # Execute the original command
    if [ $# -eq 0 ]; then
        echo "[entrypoint] No command specified, running sleep infinity"
        exec sleep infinity
    else
        echo "[entrypoint] Executing command: $@"
        exec "$@"
    fi
}

# Run main function with all arguments
main "$@"
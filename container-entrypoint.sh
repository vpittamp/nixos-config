#!/bin/bash
# Container entrypoint script that starts SSH daemon and executes the main command
# This script ensures SSH is available for development access and VS Code compatibility

set -e

# Function to setup SSH environment
setup_ssh() {
    echo "[entrypoint] Setting up SSH environment..."
    
    # Create necessary directories (including runtime directories for sshd)
    mkdir -p /etc/ssh /var/empty /root/.ssh /home/code/.ssh /var/run /var/log
    
    # NixOS manages users, no need to create /etc/passwd
    
    # Generate SSH host keys if they don't exist
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        echo "[entrypoint] Generating SSH host keys..."
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q < /dev/null
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" -q < /dev/null
    fi
    
    # Copy mounted host keys if available (for persistent keys across restarts)
    if [ -d /ssh-host-keys ] && [ "$(ls -A /ssh-host-keys 2>/dev/null)" ]; then
        echo "[entrypoint] Using mounted SSH host keys..."
        cp -f /ssh-host-keys/ssh_host_* /etc/ssh/ 2>/dev/null || true
        chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
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

# Function to start SSH daemon
start_sshd() {
    if [ "${CONTAINER_SSH_ENABLED}" = "true" ]; then
        echo "[entrypoint] Starting SSH daemon on port ${CONTAINER_SSH_PORT:-2222}..."
        setup_ssh
        
        # Ensure privilege separation directory has correct permissions
        chmod 755 /var/empty
        
        # Start sshd in debug mode in the background
        # Using -D (no detach) with & to keep it running in background
        # This ensures the process doesn't exit immediately
        echo "[entrypoint] Starting sshd with command: /bin/sshd -D -f /etc/ssh/sshd_config &"
        /bin/sshd -D -f /etc/ssh/sshd_config &
        SSHD_PID=$!
        
        # Wait a moment to ensure it starts
        sleep 2
        
        # Check if the process is still running
        if kill -0 $SSHD_PID 2>/dev/null; then
            echo "[entrypoint] SSH daemon started successfully (PID: $SSHD_PID)"
        else
            echo "[entrypoint] Warning: SSH daemon failed to start or exited"
            # Try to get any error output
            /bin/sshd -t -f /etc/ssh/sshd_config 2>&1
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
    
    # Create ldconfig stub
    if [ ! -f /usr/bin/ldconfig ]; then
        cat > /usr/bin/ldconfig << 'LDCONFIG'
#!/bin/sh
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

# Function to fix VS Code server node binaries
fix_vscode_node() {
    echo "[entrypoint] Checking for VS Code server installations..."
    
    # Check common VS Code server locations
    for vscode_dir in /root/.vscode-server/bin/* /home/*/.vscode-server/bin/*; do
        if [ -d "$vscode_dir" ] && [ -f "$vscode_dir/node" ]; then
            # Check if it's already a symlink to our node
            if [ ! -L "$vscode_dir/node" ] || [ "$(readlink "$vscode_dir/node")" != "/bin/node" ]; then
                echo "[entrypoint] Fixing VS Code node at: $vscode_dir"
                
                # Backup original if not already done
                if [ ! -f "$vscode_dir/node.microsoft" ]; then
                    mv "$vscode_dir/node" "$vscode_dir/node.microsoft" 2>/dev/null || true
                fi
                
                # Create symlink to NixOS node
                ln -sf /bin/node "$vscode_dir/node"
                echo "[entrypoint] Replaced with NixOS node $(node --version)"
            fi
        fi
    done
}

# Main execution
main() {
    echo "[entrypoint] Container starting at $(date)"
    
    # Setup VS Code compatibility first
    setup_vscode_compat
    
    # Fix any VS Code server installations
    fix_vscode_node
    
    # Also run the fix periodically in background
    (
        while true; do
            sleep 60
            fix_vscode_node >/dev/null 2>&1
        done
    ) &
    
    # Start SSH if enabled
    start_sshd
    
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
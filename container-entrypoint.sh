#!/bin/bash
# Container entrypoint script that starts SSH daemon and executes the main command
# This script ensures SSH is available for development access

set -e

# Function to setup SSH environment
setup_ssh() {
    echo "[entrypoint] Setting up SSH environment..."
    
    # Create necessary directories
    mkdir -p /etc/ssh /var/empty /root/.ssh /home/code/.ssh
    
    # Create basic user system if not exists
    if [ ! -f /etc/passwd ]; then
        cat > /etc/passwd << 'EOF'
root:x:0:0:root:/root:/bin/bash
sshd:x:74:74:SSH daemon:/var/empty:/sbin/nologin
code:x:1000:1000:code:/home/code:/bin/bash
EOF
    fi
    
    if [ ! -f /etc/group ]; then
        cat > /etc/group << 'EOF'
root:x:0:
sshd:x:74:
users:x:100:code
wheel:x:10:code
EOF
    fi
    
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
PermitRootLogin no
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
    
    # Setup authorized keys for code user
    if [ -f /ssh-keys/authorized_keys ]; then
        echo "[entrypoint] Copying authorized keys for code user..."
        cp /ssh-keys/authorized_keys /home/code/.ssh/authorized_keys
        chmod 700 /home/code/.ssh
        chmod 600 /home/code/.ssh/authorized_keys
        # Also copy for root for emergency access
        cp /ssh-keys/authorized_keys /root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        chmod 600 /root/.ssh/authorized_keys
    fi
    
    # Create home directories if they don't exist
    mkdir -p /home/code /root
    
    echo "[entrypoint] SSH setup complete"
}

# Function to start SSH daemon
start_sshd() {
    if [ "${CONTAINER_SSH_ENABLED}" = "true" ]; then
        echo "[entrypoint] Starting SSH daemon on port ${CONTAINER_SSH_PORT:-2222}..."
        setup_ssh
        /bin/sshd -f /etc/ssh/sshd_config
        echo "[entrypoint] SSH daemon started successfully"
    else
        echo "[entrypoint] SSH is disabled (CONTAINER_SSH_ENABLED != true)"
    fi
}

# Main execution
main() {
    echo "[entrypoint] Container starting at $(date)"
    
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
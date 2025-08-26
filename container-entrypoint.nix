# Container entrypoint configuration
{ config, lib, pkgs, ... }:

{
  # Create an entrypoint script that runs activation
  environment.etc."container-entrypoint.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      echo "Starting NixOS container..."
      
      # Run VS Code compatibility setup
      echo "Setting up VS Code compatibility..."
      
      # Create /usr/bin with essential symlinks
      mkdir -p /usr/bin
      for cmd in env bash sh uname ps find grep sed hostname which curl wget git; do
        if command -v $cmd >/dev/null 2>&1; then
          ln -sf $(command -v $cmd) /usr/bin/$cmd 2>/dev/null || true
        fi
      done
      
      # Create /lib64 for dynamic linker
      mkdir -p /lib64
      GLIBC_PATH=$(ldd /bin/bash 2>/dev/null | grep ld-linux | awk '{print $1}')
      if [ -n "$GLIBC_PATH" ]; then
        ln -sf "$GLIBC_PATH" /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
      fi
      
      # Link essential libraries
      mkdir -p /lib /usr/lib
      for lib in /nix/store/*/lib/libc.so* /nix/store/*/lib/libstdc++.so* /nix/store/*/lib/libgcc_s.so*; do
        if [ -f "$lib" ]; then
          ln -sf "$lib" /lib/$(basename "$lib") 2>/dev/null || true
          ln -sf "$lib" /usr/lib/$(basename "$lib") 2>/dev/null || true
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
      
      # Handle idpbuilder certificate if mounted
      if [ -f /etc/ssl/certs/idpbuilder-ca.crt ]; then
        echo "Using idpbuilder certificate"
        export SSL_CERT_FILE=/etc/ssl/certs/idpbuilder-ca.crt
        export CURL_CA_BUNDLE=/etc/ssl/certs/idpbuilder-ca.crt
        export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/idpbuilder-ca.crt
      fi
      
      echo "Container setup complete"
      
      # If SSH is enabled, ensure it's running
      if [ "${CONTAINER_SSH_ENABLED}" = "true" ]; then
        echo "Starting SSH service..."
        /nix/store/*/bin/sshd -D &
      fi
      
      # Execute the command passed to the container
      if [ $# -eq 0 ]; then
        # No command specified, run sleep infinity for devcontainer
        exec sleep infinity
      else
        # Run the specified command
        exec "$@"
      fi
    '';
  };
}
# VS Code Remote compatibility module for NixOS containers
# Ensures containers work with VS Code Remote-SSH and Kubernetes extensions
{ config, lib, pkgs, ... }:

{
  # Essential packages for VS Code compatibility
  environment.systemPackages = with pkgs; [
    # Core utilities VS Code expects
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    procps
    hostname
    which
    curl
    wget
    
    # SSL certificates for downloading VS Code server
    cacert
    
    # Libraries needed by VS Code server
    glibc
    gcc-unwrapped.lib
    
    # Shell utilities
    bash
    
    # Optional but helpful
    less
    tree
    file
    
    # VS Code CLI for tunneling support
    # Note: We'll download the CLI directly in activation script since
    # the NixOS package might not include the CLI separately
  ];
  
  # Environment variables for SSL certificates
  environment.variables = {
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    # Library path for VS Code node binary
    LD_LIBRARY_PATH = "/lib:/usr/lib:/lib64:${pkgs.gcc-unwrapped.lib}/lib:${pkgs.glibc}/lib";
  };
  
  # Create standard Unix paths that VS Code expects
  system.activationScripts.vscode-compat = ''
    echo "Setting up VS Code compatibility..."
    
    # Create /usr/bin with essential symlinks
    mkdir -p /usr/bin
    ln -sf ${pkgs.coreutils}/bin/env /usr/bin/env 2>/dev/null || true
    ln -sf ${pkgs.bash}/bin/bash /usr/bin/bash 2>/dev/null || true
    ln -sf ${pkgs.bash}/bin/sh /usr/bin/sh 2>/dev/null || true
    ln -sf ${pkgs.coreutils}/bin/uname /usr/bin/uname 2>/dev/null || true
    ln -sf ${pkgs.procps}/bin/ps /usr/bin/ps 2>/dev/null || true
    ln -sf ${pkgs.findutils}/bin/find /usr/bin/find 2>/dev/null || true
    ln -sf ${pkgs.gnugrep}/bin/grep /usr/bin/grep 2>/dev/null || true
    ln -sf ${pkgs.gnused}/bin/sed /usr/bin/sed 2>/dev/null || true
    ln -sf ${pkgs.hostname}/bin/hostname /usr/bin/hostname 2>/dev/null || true
    ln -sf ${pkgs.which}/bin/which /usr/bin/which 2>/dev/null || true
    
    # Create /lib64 for ELF interpreter (required by VS Code's node binary)
    mkdir -p /lib64
    if [ -f ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 ]; then
      ln -sf ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    fi
    
    # Create /lib and /usr/lib with essential libraries
    mkdir -p /lib /usr/lib
    
    # Link essential libraries
    for lib in ${pkgs.glibc}/lib/*.so*; do
      if [ -f "$lib" ]; then
        ln -sf "$lib" /lib/$(basename "$lib") 2>/dev/null || true
        ln -sf "$lib" /usr/lib/$(basename "$lib") 2>/dev/null || true
      fi
    done
    
    for lib in ${pkgs.gcc-unwrapped.lib}/lib/*.so*; do
      if [ -f "$lib" ]; then
        ln -sf "$lib" /lib/$(basename "$lib") 2>/dev/null || true
        ln -sf "$lib" /usr/lib/$(basename "$lib") 2>/dev/null || true
      fi
    done
    
    # Create stub for ldconfig (VS Code checks for it)
    cat > /usr/bin/ldconfig << 'EOF'
    #!/bin/sh
    # Stub ldconfig for VS Code compatibility
    exit 0
    EOF
    chmod +x /usr/bin/ldconfig
    
    # Create /etc/os-release if it doesn't exist
    if [ ! -f /etc/os-release ]; then
      cat > /etc/os-release << 'EOF'
    NAME="NixOS"
    ID=nixos
    VERSION="24.11"
    VERSION_ID="24.11"
    PRETTY_NAME="NixOS 24.11"
    HOME_URL="https://nixos.org/"
    SUPPORT_URL="https://nixos.org/community/"
    BUG_REPORT_URL="https://github.com/NixOS/nixpkgs/issues"
    EOF
    fi
    
    echo "VS Code compatibility setup complete"
  '';
  
  # Pre-install VS Code server if requested
  system.activationScripts.vscode-server-preinstall = lib.mkIf (builtins.getEnv "VSCODE_SERVER_PREINSTALL" == "true") ''
    echo "Pre-installing VS Code server..."
    
    # VS Code server commit hash (update this when VS Code updates)
    COMMIT_HASH="${if builtins.getEnv "VSCODE_SERVER_COMMIT" != "" then builtins.getEnv "VSCODE_SERVER_COMMIT" else "6f17636121051a53c88d3e605c491d22af2ba755"}"
    SERVER_DIR="/root/.vscode-server/bin/$COMMIT_HASH"
    
    if [ ! -d "$SERVER_DIR" ]; then
      echo "Downloading VS Code server for commit $COMMIT_HASH..."
      mkdir -p /tmp/vscode-download
      cd /tmp/vscode-download
      
      if ${pkgs.curl}/bin/curl -L \
        "https://update.code.visualstudio.com/commit:$COMMIT_HASH/server-linux-x64/stable" \
        -o vscode-server.tar.gz; then
        
        mkdir -p "$SERVER_DIR"
        ${pkgs.gnutar}/bin/tar -xzf vscode-server.tar.gz -C "$SERVER_DIR" --strip-components=1
        
        # Create a wrapper for the node binary with proper library paths
        if [ -f "$SERVER_DIR/node" ]; then
          mv "$SERVER_DIR/node" "$SERVER_DIR/node.real"
          cat > "$SERVER_DIR/node" << 'WRAPPER'
    #!/bin/sh
    export LD_LIBRARY_PATH="${pkgs.gcc-unwrapped.lib}/lib:${pkgs.glibc}/lib:/lib:/usr/lib:/lib64:$LD_LIBRARY_PATH"
    exec "$SERVER_DIR/node.real" "$@"
    WRAPPER
          sed -i "s|\$SERVER_DIR|$SERVER_DIR|g" "$SERVER_DIR/node"
          chmod +x "$SERVER_DIR/node"
        fi
        
        # Bypass requirements check
        if [ -f "$SERVER_DIR/bin/helpers/check-requirements.sh" ]; then
          cat > "$SERVER_DIR/bin/helpers/check-requirements.sh" << 'CHECK'
    #!/usr/bin/env sh
    # Requirements check bypassed for NixOS container
    echo "Requirements check bypassed for NixOS container"
    exit 0
    CHECK
          chmod +x "$SERVER_DIR/bin/helpers/check-requirements.sh"
        fi
        
        # Create marker file
        touch "$SERVER_DIR/.installed"
        
        echo "VS Code server pre-installed successfully"
      else
        echo "Failed to download VS Code server (network might not be available during build)"
      fi
      
      rm -rf /tmp/vscode-download
    fi
  '';
  
  # Ensure /root/.bashrc exists with proper environment
  environment.etc."skel/.bashrc".text = lib.mkAfter ''
    # VS Code compatibility
    export LD_LIBRARY_PATH="/lib:/usr/lib:/lib64:${pkgs.gcc-unwrapped.lib}/lib:${pkgs.glibc}/lib:$LD_LIBRARY_PATH"
    export PATH="/usr/bin:$PATH"
  '';
  
  # VS Code tunnel setup (optional, controlled by environment variable)
  system.activationScripts.vscode-tunnel = lib.mkIf (builtins.getEnv "VSCODE_TUNNEL_ENABLED" == "true") ''
    echo "Setting up VS Code tunnel..."
    
    # Download VS Code CLI if not present
    if [ ! -f /usr/local/bin/code ]; then
      echo "Downloading VS Code CLI..."
      mkdir -p /usr/local/bin /tmp/vscode-cli
      cd /tmp/vscode-cli
      
      # Download the CLI (it's a standalone binary)
      if ${pkgs.curl}/bin/curl -L "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64" -o vscode-cli.tar.gz; then
        ${pkgs.gnutar}/bin/tar -xzf vscode-cli.tar.gz
        mv code /usr/local/bin/code
        chmod +x /usr/local/bin/code
        echo "VS Code CLI installed to /usr/local/bin/code"
      else
        echo "Failed to download VS Code CLI (network might not be available)"
      fi
      
      rm -rf /tmp/vscode-cli
    fi
    
    # Create systemd service for VS Code tunnel
    if [ -f /usr/local/bin/code ]; then
      cat > /etc/systemd/system/vscode-tunnel.service << 'EOF'
    [Unit]
    Description=VS Code Tunnel
    After=network.target
    
    [Service]
    Type=simple
    ExecStart=/usr/local/bin/code tunnel --accept-server-license-terms
    Restart=always
    RestartSec=10
    User=root
    Environment="HOME=/root"
    WorkingDirectory=/workspace
    
    [Install]
    WantedBy=multi-user.target
    EOF
      
      echo "VS Code tunnel service created (needs authentication on first run)"
    fi
    
    # Note: The tunnel will need to be authenticated on first run
    # Run: code tunnel user login --provider github
    # Or: code tunnel user login --provider microsoft
  '';
  
  # Add tunnel helper script
  environment.etc."vscode-tunnel-setup.sh" = {
    mode = "0755";
    text = ''
      #!/bin/bash
      # Helper script to set up VS Code tunnel
      
      echo "Setting up VS Code tunnel..."
      echo "This will allow you to connect to this container from anywhere without SSH/port-forwarding"
      echo ""
      
      # Download VS Code CLI if not present
      if [ ! -f /usr/local/bin/code ]; then
        echo "VS Code CLI not found. Downloading..."
        mkdir -p /usr/local/bin /tmp/vscode-cli
        cd /tmp/vscode-cli
        
        curl -L "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64" -o vscode-cli.tar.gz
        tar -xzf vscode-cli.tar.gz
        mv code /usr/local/bin/code
        chmod +x /usr/local/bin/code
        rm -rf /tmp/vscode-cli
        echo "VS Code CLI installed!"
      fi
      
      # Check if already authenticated
      if /usr/local/bin/code tunnel user show 2>/dev/null | grep -q "Logged in"; then
        echo "Already authenticated!"
      else
        echo "Please choose your authentication provider:"
        echo "1) GitHub"
        echo "2) Microsoft"
        read -p "Enter choice (1 or 2): " choice
        
        case $choice in
          1)
            /usr/local/bin/code tunnel user login --provider github
            ;;
          2)
            /usr/local/bin/code tunnel user login --provider microsoft
            ;;
          *)
            echo "Invalid choice"
            exit 1
            ;;
        esac
      fi
      
      # Start the tunnel
      echo "Starting VS Code tunnel..."
      echo "You can access this machine at: https://vscode.dev/tunnel/<machine-name>"
      /usr/local/bin/code tunnel --accept-server-license-terms --name "backstage-dev-$(hostname -s)"
    '';
  };
}
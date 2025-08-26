# VS Code Server support using nix-community module
# This replaces our manual VS Code compatibility fixes
{ config, lib, pkgs, ... }:

let
  # Import nixos-vscode-server module from nix-community
  vscode-server-module = builtins.fetchTarball {
    url = "https://github.com/nix-community/nixos-vscode-server/archive/master.tar.gz";
    sha256 = "1rdn70jrg5mxmkkrpy2xk8lydmlc707sk0zb35426v1yxxka10by";
    # You can pin to a specific commit for reproducibility:
    # url = "https://github.com/nix-community/nixos-vscode-server/archive/<commit-hash>.tar.gz";
  };
in
{
  imports = [ 
    "${vscode-server-module}/modules/vscode-server"
  ];
  
  # Enable the vscode-server service
  services.vscode-server = {
    enable = true;
    
    # Create FHS environment for better extension compatibility
    # This helps extensions that expect standard Linux paths
    enableFHS = true;
    
    # Add extra runtime dependencies that extensions might need
    extraRuntimeDependencies = with pkgs; [
      # Essential tools
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
      
      # Development tools
      git
      openssh
      
      # Libraries
      glibc
      gcc-unwrapped.lib
      
      # SSL certificates
      cacert
    ];
    
    # Custom Node.js if needed (defaults to pkgs.nodejs)
    # nodejsPackage = pkgs.nodejs_20;
  };
  
  # SSL Certificate handling for idpbuilder
  environment.variables = {
    # These will be set if idpbuilder certificate is mounted
    SSL_CERT_FILE = lib.mkDefault "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    CURL_CA_BUNDLE = lib.mkDefault "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    NODE_EXTRA_CA_CERTS = lib.mkDefault "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };
  
  # System packages (reduced since vscode-server module handles most)
  environment.systemPackages = with pkgs; [
    # Basic utilities
    bash
    less
    tree
    file
    
    # For debugging
    lsof
    htop
    
    # SSL certificates
    cacert
    
    # Core utilities that VS Code expects in standard paths
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    procps
    hostname
    which
  ];
  
  # Activation script to handle idpbuilder certificate if mounted
  system.activationScripts.idpbuilder-cert = ''
    # If idpbuilder certificate is mounted, use it
    if [ -f /etc/ssl/certs/idpbuilder-ca.crt ]; then
      echo "Using idpbuilder certificate"
      export SSL_CERT_FILE=/etc/ssl/certs/idpbuilder-ca.crt
      export CURL_CA_BUNDLE=/etc/ssl/certs/idpbuilder-ca.crt
      export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/idpbuilder-ca.crt
    fi
  '';
  
  # VS Code compatibility setup for containers
  system.activationScripts.vscode-container-compat = ''
    echo "Setting up VS Code container compatibility..."
    
    # Create /usr/bin with essential symlinks
    mkdir -p /usr/bin
    for cmd in env bash sh uname ps find grep sed hostname which; do
      if command -v $cmd >/dev/null 2>&1; then
        ln -sf $(command -v $cmd) /usr/bin/$cmd 2>/dev/null || true
      fi
    done
    
    # Create /lib64 for dynamic linker
    mkdir -p /lib64
    if [ -f ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 ]; then
      ln -sf ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    fi
    
    # Link essential libraries
    mkdir -p /lib /usr/lib
    for lib in ${pkgs.glibc}/lib/*.so* ${pkgs.gcc-unwrapped.lib}/lib/*.so*; do
      if [ -f "$lib" ]; then
        ln -sf "$lib" /lib/$(basename "$lib") 2>/dev/null || true
        ln -sf "$lib" /usr/lib/$(basename "$lib") 2>/dev/null || true
      fi
    done
    
    # Create ldconfig stub
    cat > /usr/bin/ldconfig << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x /usr/bin/ldconfig 2>/dev/null || true
    
    # Create /etc/os-release if missing
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
    
    echo "VS Code container compatibility setup complete"
  '';
  
  # VS Code tunnel support (optional)
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
  '';
  
  # Create the tunnel helper script
  environment.etc."vscode-tunnel-setup.sh" = lib.mkIf (builtins.getEnv "VSCODE_TUNNEL_ENABLED" == "true") {
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
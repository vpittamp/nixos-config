# VS Code Server support using nix-community module
# This replaces our manual VS Code compatibility fixes
{ config, lib, pkgs, ... }:

{
  # No need to import here - it's imported via the flake
  
  # Enable the vscode-server service
  services.vscode-server = {
    enable = true;
    
    # Disable FHS since we're using nix-ld instead
    # nix-ld provides better compatibility without the FHS downsides
    enableFHS = false;
    
    # Install helper packages that provide the environment VS Code expects
    installPath = "$HOME/.vscode-server";
    
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
    
    # Set NIX_LD environment variables for VS Code compatibility
    NIX_LD_LIBRARY_PATH = lib.mkDefault (lib.makeLibraryPath (with pkgs; [
      stdenv.cc.cc
      stdenv.cc.cc.lib
      glibc
      zlib
      openssl
      curl
      icu
      xz
      libgcc
      gcc-unwrapped.lib
    ]));
    NIX_LD = lib.mkDefault (lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker");
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
    
    # For monitoring VS Code installations
    inotify-tools
    
    # Node.js for VS Code
    nodejs_20
    
    # For patching binaries
    patchelf
    file
    
    # Ripgrep for VS Code search
    ripgrep
  ];
  
  # Note: VS Code compatibility setup (symlinks, libraries, etc.) is handled
  # by /etc/container-entrypoint.sh which runs when the container starts.
  # The nixos-vscode-server module handles node binary replacement.
  
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
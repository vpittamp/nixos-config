# Container services configuration
# Combines SSH, VS Code Server, and Nix development helpers
{ config, lib, pkgs, ... }:

let
  # SSH configuration from environment
  sshEnabled = builtins.getEnv "CONTAINER_SSH_ENABLED" == "true";
  sshPort = let
    port = builtins.getEnv "CONTAINER_SSH_PORT";
  in if port == "" then 2222 else lib.toInt port;
in
{
  #############################################################################
  # SSH Server Configuration
  #############################################################################
  
  # Only enable SSH if explicitly requested
  config = lib.mkMerge [
    (lib.mkIf sshEnabled {
      # Enable OpenSSH server
      services.openssh = {
        enable = true;
        ports = [ sshPort ];
        
        settings = {
          # Security settings
          PermitRootLogin = "yes";  # Required for container access
          PasswordAuthentication = false;
          PubkeyAuthentication = true;
          ChallengeResponseAuthentication = false;
          UsePAM = false;
          
          # Performance settings
          X11Forwarding = false;
          PrintMotd = false;
          PrintLastLog = false;
          TCPKeepAlive = true;
          ClientAliveInterval = 60;
          ClientAliveCountMax = 3;
          
          # Allow specific users
          AllowUsers = [ "root" "code" "vpittamp" ];
          
          # Use only strong ciphers
          Ciphers = [
            "chacha20-poly1305@openssh.com"
            "aes256-gcm@openssh.com"
            "aes128-gcm@openssh.com"
          ];
          
          KexAlgorithms = [
            "curve25519-sha256"
            "curve25519-sha256@libssh.org"
          ];
          
          Macs = [
            "hmac-sha2-512-etm@openssh.com"
            "hmac-sha2-256-etm@openssh.com"
          ];
        };
        
        # Extra configuration
        extraConfig = ''
          # Allow SSH agent forwarding for git operations
          AllowAgentForwarding yes
          
          # Custom SFTP settings for VS Code
          Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
          
          # Host key algorithms
          HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
        '';
      };
      
      # Create SSH directories for users
      system.activationScripts.ssh-setup = ''
        # Setup SSH for root user (required for container access)
        mkdir -p /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        chmod 600 /root/.ssh/authorized_keys
        
        # Copy authorized keys from mounted secret if available
        if [ -f /ssh-keys/authorized_keys ]; then
          cp /ssh-keys/authorized_keys /root/.ssh/authorized_keys
          chmod 600 /root/.ssh/authorized_keys
        fi
        
        # Setup SSH for code user
        if id -u code >/dev/null 2>&1; then
          mkdir -p /home/code/.ssh
          touch /home/code/.ssh/authorized_keys
          chown -R code:users /home/code/.ssh
          chmod 700 /home/code/.ssh
          chmod 600 /home/code/.ssh/authorized_keys
          
          # Copy authorized keys from mounted secret if available
          if [ -f /ssh-keys/authorized_keys ]; then
            cp /ssh-keys/authorized_keys /home/code/.ssh/authorized_keys
            chown code:users /home/code/.ssh/authorized_keys
            chmod 600 /home/code/.ssh/authorized_keys
          fi
        fi
      '';
      
      # Open firewall for SSH (container environments usually don't have firewall)
      networking.firewall.allowedTCPPorts = lib.mkIf config.networking.firewall.enable [ sshPort ];
      
      # Ensure SSH service starts automatically
      systemd.services.sshd = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
      };
    })
    
    #############################################################################
    # VS Code Server Configuration
    #############################################################################
    {
      # Enable the vscode-server service
      services.vscode-server = {
        enable = true;
        
        # Disable FHS since we're using nix-ld instead
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
      };
      
      # SSL Certificate handling
      environment.variables = {
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
      
      # System packages for VS Code support
      environment.systemPackages = with pkgs; [
        # Basic utilities
        bash
        less
        tree
        file
        
        # For debugging
        lsof
        htop
        
        # Core utilities that VS Code expects
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
        
        # Ripgrep for VS Code search
        ripgrep
      ];
      
      #############################################################################
      # Nix Development Helpers
      #############################################################################
      
      # Create helper script that uses nix shell directly
      environment.etc."profile.d/flake-helpers.sh".text = ''
        # Flake helper functions for containers
        
        # Function to use development shells with common packages
        nix-dev() {
          # Check if already in a nix shell to prevent recursion
          if [ -n "$IN_NIX_SHELL" ]; then
            echo "Already in a nix development shell"
            return 0
          fi
          
          local shell="''${1:-nodejs}"  # Default to nodejs
          echo "Entering development shell: $shell"
          
          # Map shell names to package sets
          case "$shell" in
            nodejs|node|js)
              local packages="nodejs_20 nodePackages.yarn nodePackages.pnpm"
              echo "Loading Node.js environment..."
              ;;
            python|py)
              local packages="python3 python3Packages.pip python3Packages.virtualenv"
              echo "Loading Python environment..."
              ;;
            go|golang)
              local packages="go gopls"
              echo "Loading Go environment..."
              ;;
            rust|rs)
              local packages="rustc cargo rustfmt rust-analyzer"
              echo "Loading Rust environment..."
              ;;
            *)
              echo "Unknown shell: $shell"
              echo "Available: nodejs, python, go, rust"
              return 1
              ;;
          esac
          
          # Build the nix shell command
          local cmd="IN_NIX_SHELL=1 nix shell"
          for pkg in $packages; do
            cmd="$cmd nixpkgs#$pkg"
          done
          cmd="$cmd --impure --command bash --norc"
          
          # Execute the command
          eval $cmd
        }
        
        # Function to add packages temporarily
        nix-add() {
          if [ -n "$IN_NIX_SHELL" ]; then
            echo "Already in a nix shell, adding packages to current environment"
          fi
          
          if [ $# -eq 0 ]; then
            echo "Usage: nix-add <package1> [package2] ..."
            echo "Example: nix-add ripgrep fd htop"
            return 1
          fi
          
          local packages=""
          for pkg in "$@"; do
            packages="$packages nixpkgs#$pkg"
          done
          
          echo "Adding packages: $@"
          
          # Use --command with explicit bash to maintain interactive shell
          IN_NIX_SHELL=1 nix shell $packages --impure --command bash -c '
            # Source profile and bashrc for proper initialization
            [ -f /etc/profile ] && source /etc/profile
            [ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null || true
            # Keep the IN_NIX_SHELL marker
            export IN_NIX_SHELL=1
            # Start interactive bash without re-sourcing profiles
            exec bash --norc
          '
        }
        
        # Export functions for use
        export -f nix-dev 2>/dev/null || true
        export -f nix-add 2>/dev/null || true
        
        # Aliases for convenience
        alias nd='nix-dev'
        alias na='nix-add'
        alias ndn='nix-dev nodejs'
        alias ndp='nix-dev python'
        alias ndg='nix-dev go'
        alias ndr='nix-dev rust'
        
        # Info message (only show once per session)
        if [ -z "$_FLAKE_INFO_SHOWN" ]; then
          export _FLAKE_INFO_SHOWN=1
          echo ""
          echo "🚀 Nix shell helpers loaded. Quick commands:"
          echo "  nix-dev [shell]  - Enter development shell (nd)"
          echo "  nix-add pkg ...  - Add packages temporarily (na)"
          echo "  ndn/ndp/ndg/ndr  - Node/Python/Go/Rust shells"
          echo ""
        fi
      '';
    }
  ];
}
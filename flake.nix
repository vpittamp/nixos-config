{
  description = "NixOS WSL2 configuration with Home Manager and Container Support";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # NixOS-WSL
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake utilities for better system/package definitions
    flake-utils.url = "github:numtide/flake-utils";

    # nix-darwin for macOS support
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-wsl, home-manager, flake-utils, darwin, ... }@inputs: 
    let
      # Define supported systems
      linuxSystem = "x86_64-linux";
      darwinSystem = "aarch64-darwin"; # change to "x86_64-darwin" on Intel Macs
      
      # Package sets for each system
      linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
      darwinPkgs = nixpkgs.legacyPackages.${darwinSystem};
    in
    {
      # NixOS configuration for WSL
      nixosConfigurations = {
        nixos-wsl = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          
          modules = [
            # Include the WSL module
            nixos-wsl.nixosModules.wsl
            
            # Main system configuration
            ./configuration.nix
            
            # Home Manager module
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.vpittamp = {
                  imports = [ ./home-vpittamp.nix ];
                  # Fix for version mismatch warning
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
      };

      # macOS configuration via nix-darwin
      darwinConfigurations = {
        macbook = darwin.lib.darwinSystem {
          system = darwinSystem;
          modules = [
            ./nix-darwin.nix
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # Back up existing files instead of failing on clobber
                backupFileExtension = "backup";
                # Use the macOS username for Home Manager
                users.vinodpittampalli = {
                  imports = [ ./home-vpittamp.nix ];
                  # Explicit home directory to satisfy HM on Darwin
                  home.homeDirectory = "/Users/vinodpittampalli";
                };
              };
            }
          ];
        };
      };
      
      # Container packages
      packages.${linuxSystem} = {
        # Example: Basic container with shell utilities
        basic-container = linuxPkgs.dockerTools.buildLayeredImage {
          name = "nixos-basic";
          tag = "latest";
          
          contents = with linuxPkgs; [
            bashInteractive
            coreutils
            curl
            jq
            git
          ];
          
          config = {
            Env = [ "PATH=/bin:/usr/bin" ];
            Cmd = [ "/bin/bash" ];
            WorkingDir = "/";
          };
        };
        
        # Example: Node.js application container
        node-app-container = linuxPkgs.dockerTools.buildLayeredImage {
          name = "node-app";
          tag = "latest";
          
          contents = with linuxPkgs; [
            nodejs_20
            bashInteractive
            coreutils
          ];
          
          config = {
            Env = [ 
              "PATH=/bin:/usr/bin"
              "NODE_ENV=production"
            ];
            Cmd = [ "/bin/node" ];
            WorkingDir = "/app";
            ExposedPorts = {
              "3000/tcp" = {};
            };
          };
        };
        
        # Example: Python application container
        python-app-container = linuxPkgs.dockerTools.buildLayeredImage {
          name = "python-app";
          tag = "latest";
          
          contents = with linuxPkgs; [
            python3
            python3Packages.pip
            python3Packages.requests
            bashInteractive
            coreutils
          ];
          
          config = {
            Env = [ 
              "PATH=/bin:/usr/bin"
              "PYTHONUNBUFFERED=1"
            ];
            Cmd = [ "/bin/python3" ];
            WorkingDir = "/app";
          };
        };
        
        # Development container with Nix for applying configurations
        nix-dev-container = linuxPkgs.dockerTools.buildLayeredImage {
          name = "nix-dev";
          tag = "latest";
          
          contents = with linuxPkgs; [
            # Nix and flakes support
            nix
            
            # Core utilities
            bashInteractive
            coreutils
            cacert
            gitMinimal
            curl
            wget
            
            # User management
            shadow
            su
            sudo
            
            # Required for Home Manager
            gnused
            gnutar
            gzip
            xz
            
            # Create init script
            (linuxPkgs.writeScriptBin "init-nix-env" ''
              #!${bashInteractive}/bin/bash
              set -e
              
              echo "🚀 Initializing Nix development environment..."
              
              # Create user if it doesn't exist
              if ! id -u vpittamp >/dev/null 2>&1; then
                echo "Creating user vpittamp..."
                useradd -m -s /bin/bash vpittamp
                echo "vpittamp ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
              fi
              
              # Switch to user
              su - vpittamp -c "
                # Set up Nix channels
                export USER=vpittamp
                export HOME=/home/vpittamp
                
                # Clone configuration from GitHub
                if [ ! -d ~/.nixos-config ]; then
                  echo 'Cloning configuration from GitHub...'
                  git clone https://github.com/vpittamp/nixos-config.git ~/.nixos-config
                fi
                
                # Apply Home Manager configuration
                echo 'Applying Home Manager configuration...'
                cd ~/.nixos-config
                nix develop --experimental-features 'nix-command flakes' -c echo 'Nix flakes enabled'
                
                # Install Home Manager
                nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
                nix-channel --update
                
                echo '✅ Environment ready! Run: home-manager switch --flake ~/.nixos-config#vpittamp'
              "
            '')
          ];
          
          config = {
            Env = [
              "PATH=/bin:/usr/bin:/run/current-system/sw/bin"
              "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
              "SSL_CERT_FILE=${linuxPkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "USER=root"
            ];
            Cmd = [ "/bin/bash" ];
            WorkingDir = "/";
            Volumes = {
              "/nix/store" = {};
              "/nix/var" = {};
              "/home" = {};
            };
          };
        };
        
        # Full development container with all tools pre-installed
        full-dev-container = 
          let
            # Extract packages from home configuration
            homePackages = with linuxPkgs; [
              # Core utilities from home-vpittamp.nix
              tmux
              git
              stow
              fzf
              ripgrep
              fd
              bat
              eza
              zoxide
              sesh
              
              # Development tools
              gh
              kubectl
              direnv
              tree
              htop
              btop
              ncdu
              jq
              yq
              gum
              
              # System tools
              xclip
              file
              which
              curl
              wget
              
              # Additional essentials
              neovim
              starship
              nodejs_20
            ];
            
            # Create a custom bashrc with your configurations
            customBashrc = linuxPkgs.writeText "bashrc" ''
              # Basic environment
              export EDITOR=nvim
              export VISUAL=nvim
              export PAGER=less
              export LESS="-R"
              export TERM=xterm-256color
              
              # Aliases from home-vpittamp.nix
              alias ..="cd .."
              alias ...="cd ../.."
              alias ....="cd ../../.."
              alias ls="eza --group-directories-first"
              alias ll="eza -l --group-directories-first"
              alias la="eza -la --group-directories-first"
              alias lt="eza --tree"
              alias cat="bat"
              alias grep="rg"
              
              # Git aliases
              alias g="git"
              alias gs="git status"
              alias ga="git add"
              alias gc="git commit"
              alias gp="git push"
              alias gl="git log --oneline --graph --decorate"
              alias gd="git diff"
              alias gco="git checkout"
              alias gb="git branch"
              
              # Kubernetes aliases
              alias k="kubectl"
              alias kgp="kubectl get pods"
              alias kgs="kubectl get svc"
              alias kgd="kubectl get deployment"
              
              # Initialize tools
              eval "$(starship init bash)"
              eval "$(zoxide init bash)"
              eval "$(direnv hook bash)"
              
              # Welcome message
              echo "🚀 Full development environment ready!"
              echo "   User: vpittamp"
              echo "   Tools: $(tmux -V), $(nvim --version | head -1), $(git --version)"
              echo ""
            '';
          in
          linuxPkgs.dockerTools.buildLayeredImage {
            name = "full-dev";
            tag = "latest";
            
            contents = with linuxPkgs; [
              bashInteractive
              coreutils
              shadow
              su
              sudo
              cacert
            ] ++ homePackages ++ [
              # Add initialization script
              (linuxPkgs.writeScriptBin "init-dev" ''
                #!${bashInteractive}/bin/bash
                # Create user if needed
                if ! id -u vpittamp >/dev/null 2>&1; then
                  useradd -m -s /bin/bash vpittamp
                  echo "vpittamp ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
                fi
                
                # Set up bash configuration
                cp ${customBashrc} /home/vpittamp/.bashrc
                chown vpittamp:vpittamp /home/vpittamp/.bashrc
                
                # Set up git config
                su - vpittamp -c "
                  git config --global user.name 'Vinod Pittampalli'
                  git config --global user.email 'vinod@pittampalli.com'
                "
                
                # Switch to user
                exec su - vpittamp
              '')
            ];
            
            config = {
              Env = [
                "PATH=/bin:/usr/bin"
                "SSL_CERT_FILE=${linuxPkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "LANG=en_US.UTF-8"
                "USER=vpittamp"
              ];
              Cmd = [ "/bin/init-dev" ];
              WorkingDir = "/home/vpittamp";
              Volumes = {
                "/home/vpittamp/workspace" = {};
              };
            };
          };
      };
      
      # Development shells
      devShells.${linuxSystem} = {
        # Default development shell with container tools
        default = linuxPkgs.mkShell {
          name = "container-dev";
          
          buildInputs = with linuxPkgs; [
            # Container tools
            docker-compose
            dive              # Inspect container layers
            
            # Kubernetes tools
            kubectl
            kubernetes-helm
            k9s               # Terminal UI for Kubernetes
            kind              # Kubernetes in Docker
            
            # Development tools
            git
            jq
            yq
            curl
            
            # Nix tools
            nix-prefetch-docker
            nixpkgs-fmt
          ];
          
          shellHook = ''
            echo "🐳 Container Development Environment"
            echo ""
            echo "Available commands:"
            echo "  docker    - Docker CLI (via Docker Desktop)"
            echo "  docker-compose - Multi-container orchestration"
            echo "  kubectl   - Kubernetes CLI"
            echo "  helm      - Kubernetes package manager"
            echo "  k9s       - Kubernetes TUI"
            echo "  kind      - Kubernetes in Docker"
            echo ""
            echo "Build containers with:"
            echo "  nix build .#basic-container"
            echo "  nix build .#node-app-container"
            echo "  nix build .#python-app-container"
            echo ""
            echo "Load into Docker with:"
            echo "  docker load < result"
            echo ""
            echo "Docker alias configured: /run/current-system/sw/bin/docker"
          '';
        };
        
        # Kubernetes-focused shell
        k8s = linuxPkgs.mkShell {
          name = "k8s-dev";
          
          buildInputs = with linuxPkgs; [
            kubectl
            kubernetes-helm
            k9s
            kustomize
            kubectx
            stern             # Multi-pod log tailing
            kubeseal          # Sealed secrets
          ];
          
          shellHook = ''
            echo "☸️  Kubernetes Development Environment"
            echo ""
            echo "Kubernetes tools loaded!"
          '';
        };
      };
      
      # Formatter for 'nix fmt'
      formatter.${linuxSystem} = linuxPkgs.nixpkgs-fmt;
      
      # Apps for easy container building
      apps.${linuxSystem} = {
        build-all-containers = {
          type = "app";
          program = "${linuxPkgs.writeShellScript "build-all-containers" ''
            echo "Building all containers..."
            nix build .#basic-container
            echo "✅ basic-container built"
            nix build .#node-app-container
            echo "✅ node-app-container built"
            nix build .#python-app-container
            echo "✅ python-app-container built"
            echo ""
            echo "Load into Docker with: docker load < result"
          ''}";
        };
      };
    };
}

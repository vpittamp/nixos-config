{
  description = "NixOS WSL2 configuration with Home Manager and Container Support";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Nixpkgs unstable-small for bleeding edge AI tools (updates more frequently)
    nixpkgs-bleeding = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };
    
    # NixOS-WSL
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Home Manager - using master branch for latest features including claude-code
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # 1Password Shell Plugins
    onepassword-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # VS Code Server support for NixOS
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake utilities for better system/package definitions
    flake-utils.url = "github:numtide/flake-utils";
    
    # Claude Code with Cachix binaries - avoids build permission issues in containers
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Apple Silicon support for NixOS
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Disk management for NixOS installations
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
  };

  outputs = { self, nixpkgs, nixpkgs-bleeding, nixos-wsl, home-manager, onepassword-shell-plugins, vscode-server, flake-utils, claude-code-nix, nixos-apple-silicon, disko, ... }@inputs: 
    let
      # Support both Linux and Darwin systems
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
      system = "x86_64-linux";  # Default for NixOS config
      
      # Get bleeding edge packages for AI tools
      pkgs-bleeding = import nixpkgs-bleeding {
        inherit system;
        config.allowUnfree = true;
      };
      
      # Import overlays
      overlays = import ./overlays { inherit inputs; };
      
      # Create pkgs with overlays applied
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # NOTE: Overlays are defined but not applied to the base pkgs
        # to avoid increasing container size. They can be used in devShells.
        overlays = [
          # overlays.additions     # Uncomment if needed
          # overlays.modifications # Uncomment if needed
        ];
      };
    in
    {
      # NixOS configuration for WSL
      nixosConfigurations = {
        nixos-wsl = nixpkgs.lib.nixosSystem {
          inherit system;
          
          # Pass inputs to configuration modules
          specialArgs = { inherit inputs; };
          
          modules = [
            # Include the WSL module
            nixos-wsl.nixosModules.wsl
            
            # Main system configuration
            ./configuration.nix
            
            # NPM packages are now defined in overlays/packages.nix
            # to avoid duplication and ensure they're available in containers
            # Home Manager module
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { 
                  inherit inputs;
                  pkgs-unstable = pkgs-bleeding;
                };
                users.vpittamp = {
                  imports = [ 
                    ./home-vpittamp.nix
                    onepassword-shell-plugins.hmModules.default
                  ];
                  # Fix for version mismatch warning
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
        
        # NixOS configuration for VM (UTM/QEMU on macOS)
        nixos-vm = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";  # For M1 Mac virtualization
          
          specialArgs = { inherit inputs; };
          
          modules = [
            # VM-specific configuration
            ./configuration-vm.nix
            
            # Home Manager module
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { 
                  inherit inputs;
                  pkgs-unstable = pkgs-bleeding;
                };
                users.vpittamp = {
                  imports = [ 
                    ./home-vpittamp.nix
                    onepassword-shell-plugins.hmModules.default
                  ];
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
        
        # NixOS configuration for M1 MacBook Pro (Apple Silicon)
        nixos-m1 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          
          specialArgs = { inherit inputs; };
          
          modules = [
            # Apple Silicon hardware support
            nixos-apple-silicon.nixosModules.default
            
            # Hardware configuration for M1 MacBook
            ./hardware-m1.nix
            
            # Main configuration (adapted for bare metal)
            ./configuration-m1.nix
            
            # Home Manager module
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { 
                  inherit inputs;
                  pkgs-unstable = import nixpkgs-bleeding {
                    system = "aarch64-linux";
                    config.allowUnfree = true;
                  };
                };
                users.vpittamp = {
                  imports = [ 
                    ./home-vpittamp.nix
                    onepassword-shell-plugins.hmModules.default
                  ];
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
        
        # NixOS configuration for Hetzner Cloud server
        nixos-hetzner = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          
          specialArgs = { inherit inputs; };
          
          modules = [
            # Disko for disk management
            disko.nixosModules.disko
            
            # Hetzner-specific configuration
            ./configuration-hetzner.nix
            
            # Home Manager module (minimal for now, full config after bootstrap)
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { 
                  inherit inputs;
                  pkgs-unstable = pkgs-bleeding;
                  isDarwin = false;
                };
                users.vpittamp = {
                  imports = [ 
                    # Start minimal, will add full home-manager config after bootstrap
                    onepassword-shell-plugins.hmModules.default
                  ];
                  home = {
                    username = "vpittamp";
                    homeDirectory = "/home/vpittamp";
                    stateVersion = "25.05";
                  };
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
      };
      
      # Development shells for extending environments at runtime
      devShells.${system} = {
        # Default development shell
        default = pkgs.mkShell {
          name = "nix-dev";
          buildInputs = with pkgs; [
            # Basic tools
            git
            curl
            wget
            vim
            # Nix tools
            nix-prefetch-git
            nixpkgs-fmt
            nil
          ];
          # Preserve existing shell environment
          nativeBuildInputs = with pkgs; [
            bashInteractive
          ];
          shellHook = ''
            # Prevent recursive shell invocation
            if [ -n "$IN_NIX_SHELL" ]; then
              return 0
            fi
            export IN_NIX_SHELL=1
            
            echo "Development shell activated"
            # Preserve terminal customization
            export STARSHIP_CONFIG=$HOME/.config/starship.toml
            # Ensure SSL certificates are available
            if [ -n "$NODE_EXTRA_CA_CERTS" ]; then
              export NODE_EXTRA_CA_CERTS="$NODE_EXTRA_CA_CERTS"
            elif [ -f "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ]; then
              export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            fi
            # Re-initialize shell tools
            if command -v starship &> /dev/null; then
              eval "$(starship init bash)"
            fi
            if command -v direnv &> /dev/null; then
              eval "$(direnv hook bash)"
            fi
          '';
        };
        
        # Node.js development shell
        nodejs = pkgs.mkShell {
          name = "nodejs-dev";
          buildInputs = with pkgs; [
            nodejs_20
            nodePackages.yarn
            nodePackages.pnpm
            nodePackages.typescript
            nodePackages.ts-node
            nodePackages.nodemon
            # SSL certificate support
            cacert
          ];
          # Use nativeBuildInputs to preserve environment better
          nativeBuildInputs = with pkgs; [
            # Include tools that should remain available
            bashInteractive
            coreutils
          ];
          shellHook = ''
            # Prevent recursive shell invocation
            if [ -n "$IN_NIX_SHELL" ]; then
              return 0
            fi
            export IN_NIX_SHELL=1
            
            echo "Node.js development environment activated"
            # Fix SSL certificates for yarn/npm
            export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export NODE_TLS_REJECT_UNAUTHORIZED=0  # Only for development!
            echo "Warning: NODE_TLS_REJECT_UNAUTHORIZED=0 is set for development only"
            # Preserve terminal customization
            export STARSHIP_CONFIG=$HOME/.config/starship.toml
            # Re-initialize shell tools if available
            if command -v starship &> /dev/null; then
              eval "$(starship init bash)"
            fi
            if command -v direnv &> /dev/null; then
              eval "$(direnv hook bash)"
            fi
            if command -v zoxide &> /dev/null; then
              eval "$(zoxide init bash)"
            fi
          '';
        };
        
        # Python development shell
        python = pkgs.mkShell {
          name = "python-dev";
          buildInputs = with pkgs; [
            python3
            python3Packages.pip
            python3Packages.virtualenv
            python3Packages.ipython
            python3Packages.black
            python3Packages.pylint
            python3Packages.requests
            python3Packages.certifi
          ];
          shellHook = ''
            # Prevent recursive shell invocation
            if [ -n "$IN_NIX_SHELL" ]; then
              return 0
            fi
            export IN_NIX_SHELL=1
            
            echo "Python development environment activated"
            # Set up Python SSL certificates
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export REQUESTS_CA_BUNDLE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            # Preserve terminal customization
            export STARSHIP_CONFIG=$HOME/.config/starship.toml
          '';
        };
        
        # Go development shell
        go = pkgs.mkShell {
          name = "go-dev";
          buildInputs = with pkgs; [
            go
            gopls
            go-tools
            golangci-lint
            delve
          ];
          shellHook = ''
            # Prevent recursive shell invocation
            if [ -n "$IN_NIX_SHELL" ]; then
              return 0
            fi
            export IN_NIX_SHELL=1
            
            echo "Go development environment activated"
            export GOPATH=$HOME/go
            export PATH=$GOPATH/bin:$PATH
            # Preserve terminal customization
            export STARSHIP_CONFIG=$HOME/.config/starship.toml
          '';
        };
        
        # Rust development shell
        rust = pkgs.mkShell {
          name = "rust-dev";
          buildInputs = with pkgs; [
            rustc
            cargo
            rustfmt
            rust-analyzer
            clippy
            pkg-config
            openssl
          ];
          shellHook = ''
            # Prevent recursive shell invocation
            if [ -n "$IN_NIX_SHELL" ]; then
              return 0
            fi
            export IN_NIX_SHELL=1
            
            echo "Rust development environment activated"
            # Preserve terminal customization
            export STARSHIP_CONFIG=$HOME/.config/starship.toml
          '';
        };
        
        # Full-stack development shell
        fullstack = pkgs.mkShell {
          name = "fullstack-dev";
          buildInputs = with pkgs; [
            # Frontend
            nodejs_20
            nodePackages.yarn
            nodePackages.pnpm
            # Backend languages
            python3
            go
            rustc
            cargo
            # Databases
            postgresql
            redis
            sqlite
            # Tools
            docker-compose
            kubectl
            terraform
            # SSL certificates
            cacert
          ];
          shellHook = ''
            # Prevent recursive shell invocation
            if [ -n "$IN_NIX_SHELL" ]; then
              return 0
            fi
            export IN_NIX_SHELL=1
            
            echo "Full-stack development environment activated"
            # Fix SSL certificates
            export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export REQUESTS_CA_BUNDLE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            # Preserve terminal customization
            export STARSHIP_CONFIG=$HOME/.config/starship.toml
          '';
        };
      };
      
      # Container packages - unified with main configuration
      packages.${system} = {
        # Base container with minimal NixOS and runtime setup capability
        # Usage: nix build .#container-base
        container-base = let
          baseConfig = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs; };
            modules = [
              # Include WSL module (will be disabled by container-profile)
              nixos-wsl.nixosModules.wsl
              ./container-base.nix
              vscode-server.nixosModules.default
            ];
          };
        in with pkgs;
        dockerTools.buildImage {
          name = "nixos-base";
          tag = "latest";
          
          contents = buildEnv {
            name = "container-base-root";
            paths = [
              baseConfig.config.system.path
              bashInteractive
              coreutils
              nix
              
            ];
            pathsToLink = [ "/bin" "/lib" "/share" "/etc" "/usr" ];
          };
          
          config = {
            Env = [
              "PATH=/usr/local/bin:/bin:/usr/bin"
              "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
            ];
            Cmd = [ "/usr/local/bin/nixos-setup" ];
            WorkingDir = "/";
          };
        };
        
        # Build container from main configuration (existing approach)
        # Usage: NIXOS_CONTAINER=1 NIXOS_PACKAGES="essential" nix build .#container
        container = let
          # Build the NixOS configuration with container mode enabled
          containerConfig = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs; };
            modules = [
              # Include WSL module (will be disabled by container-profile)
              nixos-wsl.nixosModules.wsl
              # Start with main configuration
              ./configuration.nix
              # Add home-manager
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users = {
                  # Apply home-manager to root user in container
                  root = { config, pkgs, lib, ... }: {
                    imports = [ ./home-vpittamp.nix ];
                    home = {
                      username = lib.mkForce "root";
                      homeDirectory = lib.mkForce "/root";
                    };
                  };
                  # Apply home-manager to both users in container
                  vpittamp = import ./home-vpittamp.nix;
                  # Code user gets the same configuration but with overrides
                  code = { config, pkgs, lib, ... }: {
                    imports = [ ./home-vpittamp.nix ];
                    home = {
                      username = lib.mkForce "code";
                      homeDirectory = lib.mkForce "/home/code";
                    };
                  };
                };
                home-manager.extraSpecialArgs = { inherit inputs; };
              }
              # Add VS Code server support
              vscode-server.nixosModules.default
              # Apply container-specific overrides last
              ./container-profile.nix
            ];
          };
        in with pkgs;
        # Use buildLayeredImage for better caching and faster builds
        dockerTools.buildLayeredImage {
          name = "nixos-dev";
          tag = let
            profile = builtins.getEnv "NIXOS_PACKAGES";
          in if profile == "" then "latest" else profile;
          
          
          contents = let
            # Get home-manager activation packages for container users
            codeHomeManagerActivation = containerConfig.config.home-manager.users.code.home.activationPackage;
            
            # Pre-stage home-manager configs during build
            # This creates a derivation with home-manager files ready to be copied
            homeStaging = runCommand "home-staging" {} ''
              mkdir -p $out/etc/skel
              
              # Copy home-manager files to staging location
              if [ -d "${codeHomeManagerActivation}/home-files" ]; then
                echo "Staging home-manager configuration files..."
                cp -rL ${codeHomeManagerActivation}/home-files/. $out/etc/skel/
                
                # Ensure proper permissions
                chmod -R 755 $out/etc/skel
              else
                echo "Warning: No home-files found in activation package"
              fi
            '';
            
            # Create user entries as a separate derivation
            userEntries = runCommand "user-entries" {} ''
              mkdir -p $out/etc
              # Don't create /home/code here - it will be mounted as a volume
              # Creating it here causes buildEnv to make it a symlink to nix store
              # which breaks nix shell commands
              mkdir -p $out/tmp
              mkdir -p $out/usr/bin
              mkdir -p $out/lib64
              mkdir -p $out/lib
              
              # Create symlinks for VS Code compatibility
              ln -s /bin/env $out/usr/bin/env 2>/dev/null || true
              ln -s /bin/sh $out/usr/bin/sh 2>/dev/null || true
              ln -s /bin/bash $out/usr/bin/bash 2>/dev/null || true
              
              # Find and link the dynamic loader for VS Code's node binary
              LOADER=$(find ${pkgs.glibc}/lib -name 'ld-linux-x86-64.so.2' -type f 2>/dev/null | head -1)
              if [ -n "$LOADER" ]; then
                ln -sf "$LOADER" $out/lib64/ld-linux-x86-64.so.2
                ln -sf "$LOADER" $out/lib/ld-linux-x86-64.so.2
              fi
              
              # Create passwd with code user entry
              cat > $out/etc/passwd << 'EOF'
              root:x:0:0:System administrator:/root:/bin/bash
              code:x:1000:100:Code User:/home/code:/bin/bash
              EOF
              
              # Create group with users entry
              cat > $out/etc/group << 'EOF'
              root:x:0:
              users:x:100:
              EOF
              
              # Set proper permissions
              chmod 644 $out/etc/passwd $out/etc/group
              # Note: /home/code will be created at runtime via volume mount
              chmod 1777 $out/tmp
              chmod -R 755 $out/usr
            '';
          in buildEnv {
            name = "container-root";
            paths = [
              # Use system.path which contains all packages including home-manager
              containerConfig.config.system.path
              pkgs.bashInteractive
              pkgs.coreutils
              # cacert is already included in container-profile.nix
              
              # Add /etc files from the system build
              containerConfig.config.system.build.etc
              
              # Include the entire system toplevel for activation scripts
              containerConfig.config.system.build.toplevel
              
              # Include home-manager activation package for code user
              # This contains the actual config files and activation script
              codeHomeManagerActivation
              
              # Include pre-staged home-manager configs
              homeStaging
              
              # Include user entries
              userEntries
              
              # Add entrypoint scripts
              (runCommand "entrypoint-scripts" {} ''
                mkdir -p $out/etc
                cat > $out/etc/container-entrypoint.sh << 'ENTRYPOINT_EOF'
                ${builtins.readFile ./container-entrypoint.sh}
                ENTRYPOINT_EOF
                chmod 755 $out/etc/container-entrypoint.sh
                
              '')
              
            ];
            pathsToLink = [ 
              "/bin" 
              "/lib" 
              "/lib64"     # Include lib64 for dynamic linker
              "/share" 
              "/etc"
              "/sw"        # Include sw directory
              "/home"      # Include home directory
              "/tmp"       # Include tmp directory for non-root writes
              "/usr"       # Include usr directory for VS Code compatibility
            ];
            extraOutputsToInstall = [ "out" ];
          };
          
          config = {
            Env = [
              "PATH=/bin:/sbin:/usr/bin:/usr/local/bin"
              "HOME=/home/code"
              "USER=code"
              "TERM=xterm-256color"
              "CONTAINER_SSH_ENABLED=true"
              "CONTAINER_SSH_PORT=2222"
              # Critical for VS Code server to find libraries
              "LD_LIBRARY_PATH=/lib:/usr/lib:/lib64"
              "NIX_LD_LIBRARY_PATH=/lib:/usr/lib:/lib64"
              # Critical for Nix single-user mode in containers
              "NIX_REMOTE="
              "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
            ];
            Entrypoint = [ "/etc/container-entrypoint.sh" ];
            Cmd = [ "sleep" "infinity" ];
            WorkingDir = "/home/code";
            ExposedPorts = {
              "2222/tcp" = {};
            };
          };
        };
      };
      
      # Home Manager configurations for standalone use (e.g., in containers)
      homeConfigurations = {
        # Configuration for containers or non-NixOS systems
        vpittamp = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            ({ lib, ... }: {
              # Container/standalone specific settings - override with force
              home = {
                username = lib.mkForce "root";  # Containers typically run as root
                homeDirectory = lib.mkForce "/root";
                stateVersion = lib.mkForce "25.05";  # Match home-vpittamp.nix
                enableNixpkgsReleaseCheck = false;
              };
              
              # Override package selection via environment variable
              nixpkgs.config.allowUnfree = true;
            })
          ];
          extraSpecialArgs = { 
            inherit inputs;
            pkgs-unstable = pkgs-bleeding;
          };
        };
        
        # Alternative configuration for non-root containers
        vpittamp-user = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              home = {
                username = "vpittamp";
                homeDirectory = "/home/vpittamp";
                stateVersion = "25.05";  # Match home-vpittamp.nix
                enableNixpkgsReleaseCheck = false;
              };
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { 
            inherit inputs;
            pkgs-unstable = pkgs-bleeding;
          };
        };
        
        # Devcontainer user "code" - extends vpittamp-user with overrides
        code = self.homeConfigurations.vpittamp-user.extendModules {
          modules = [{
            home = {
              username = nixpkgs.lib.mkForce "code";
              homeDirectory = nixpkgs.lib.mkForce "/home/code";
            };
          }];
        };
        
        # Container configurations (now using unified home-vpittamp.nix)
        container-minimal = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              home.username = nixpkgs.lib.mkForce "code";
              home.homeDirectory = nixpkgs.lib.mkForce "/home/code";
              home.stateVersion = nixpkgs.lib.mkForce "25.05";
              home.sessionVariables.CONTAINER_PROFILE = "minimal";
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
        
        container-essential = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              home.username = nixpkgs.lib.mkForce "code";
              home.homeDirectory = nixpkgs.lib.mkForce "/home/code";
              home.stateVersion = nixpkgs.lib.mkForce "25.05";
              home.sessionVariables.CONTAINER_PROFILE = "essential";
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
        
        container-development = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              home.username = nixpkgs.lib.mkForce "code";
              home.homeDirectory = nixpkgs.lib.mkForce "/home/code";
              home.stateVersion = nixpkgs.lib.mkForce "25.05";
              home.sessionVariables.CONTAINER_PROFILE = "development";
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
        
        container-ai = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              home.username = nixpkgs.lib.mkForce "code";
              home.homeDirectory = nixpkgs.lib.mkForce "/home/code";
              home.stateVersion = nixpkgs.lib.mkForce "25.05";
              home.sessionVariables.CONTAINER_PROFILE = "development";
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { inherit inputs; };
        };
        
        # Darwin (macOS) configurations
        vpittamp-darwin = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          modules = [
            ./home-vpittamp.nix
            onepassword-shell-plugins.hmModules.default
            {
              # Darwin-specific overrides - using actual Mac system username
              home.username = nixpkgs.lib.mkForce "vinodpittampalli";
              home.homeDirectory = nixpkgs.lib.mkForce "/Users/vinodpittampalli";
              home.stateVersion = "25.05";
              
              # Claude Code will be handled by the module itself
              # Removed the disable override to let it work on Darwin
              
              # Platform detection for conditional configs
              home.sessionVariables = {
                IS_DARWIN = "1";
              };
              
              nixpkgs.config.allowUnfree = true;
            }
          ];
          extraSpecialArgs = { 
            inherit inputs;
            isDarwin = true;
            pkgs-unstable = import nixpkgs-bleeding {
              system = "aarch64-darwin";
              config.allowUnfree = true;
            };
          };
        };
      };
      
      # Formatter for 'nix fmt'
      formatter.${system} = pkgs.nixpkgs-fmt;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixpkgs-fmt;
      formatter.x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.nixpkgs-fmt;
      
      # Apps for container building
      apps.${system} = {
        build-container = {
          type = "app";
          program = "${pkgs.writeShellScript "build-container" ''
            echo "Building NixOS container..."
            echo "Package selection: ''${NIXOS_PACKAGES:-essential}"
            nix build .#container
            echo "✅ Container built"
            echo ""
            echo "Load into Docker with: docker load < result"
            echo ""
            echo "To build with all packages: NIXOS_PACKAGES=full nix run .#build-container"
          ''}";
        };
      };
    };
}
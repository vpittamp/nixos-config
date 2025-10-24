{
  description = "Unified NixOS Configuration - Hetzner, M1, WSL, and Containers";

  inputs = {
    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-bleeding.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Platform support
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Additional tools
    onepassword-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    # Plasma (KDE) user configuration via Home Manager
    # ARCHIVED: KDE Plasma removed in Feature 009 (i3wm migration)
    # M1 configuration still uses this temporarily
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # VM image generation
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Walker application launcher
    elephant = {
      url = "github:abenz1267/elephant";
    };

    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };

    # REMOVED: MangoWC Wayland Compositor (experimental, archived)
    # mangowc = {
    #   url = "github:DreamMaoMao/mangowc";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, nixpkgs-bleeding, nixos-wsl, nixos-apple-silicon, home-manager, onepassword-shell-plugins, vscode-server, claude-code-nix, disko, flake-utils, nixos-generators, ... }@inputs:
    let
      # Helper function to create a system configuration
      mkSystem = { hostname, system, modules }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = modules ++ [
            # Track git revision and metadata in system configuration
            {
              system.configurationRevision = self.rev or self.dirtyRev or "unknown";

              # Add comprehensive build metadata to /etc/nixos-metadata
              environment.etc."nixos-metadata".text = ''
                # NixOS Build Metadata
                # Generated at build time - DO NOT EDIT

                # Git Information
                GIT_COMMIT=${self.rev or self.dirtyRev or "unknown"}
                GIT_SHORT_COMMIT=${nixpkgs.lib.substring 0 7 (self.rev or self.dirtyRev or "unknown")}
                GIT_DIRTY=${if self ? rev then "false" else "true"}
                GIT_LAST_MODIFIED=${self.lastModifiedDate or "unknown"}
                GIT_SOURCE_URL=https://github.com/vpittamp/nixos-config/tree/${self.rev or "main"}

                # Flake Input Revisions (for reproducibility)
                NIXPKGS_REV=${inputs.nixpkgs.rev or "unknown"}
                NIXPKGS_NARHASH=${inputs.nixpkgs.narHash or "unknown"}
                HOME_MANAGER_REV=${inputs.home-manager.rev or "unknown"}

                # System Information
                HOSTNAME=${hostname}
                SYSTEM=${system}
                BUILD_DATE=${builtins.substring 0 8 self.lastModifiedDate or "unknown"}
                FLAKE_URL=github:vpittamp/nixos-config/${self.rev or "main"}

                # Useful Commands
                # Rebuild this exact configuration:
                #   sudo nixos-rebuild switch --flake ${self.sourceInfo.outPath or "."}
                # View git commit:
                #   git show ${self.rev or "HEAD"}
                # Switch to this git revision:
                #   git checkout ${self.rev or "main"}
              '';
            }

            # Home Manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                # Enable backups for file conflicts during system rebuild
                # Backup files can be safely removed after confirming the new config works
                backupFileExtension = "backup";
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit inputs;
                  pkgs-unstable = import nixpkgs-bleeding {
                    inherit system;
                    config.allowUnfree = true;
                  };
                };
                users.vpittamp = {
                  imports = [
                    ./home-vpittamp.nix
                    inputs.plasma-manager.homeModules.plasma-manager
                    # Note: onepassword-shell-plugins is imported in base-home.nix
                  ];
                  home.enableNixpkgsReleaseCheck = false;
                };
              };
            }
          ];
        };
    in
    # Merge nixosConfigurations and homeConfigurations with packages/devShells from eachSystem
    {
      # NixOS Configurations
      nixosConfigurations = {
        # Primary: Hetzner Cloud Server with i3wm (x86_64)
        # Production configuration with i3wm desktop environment
        hetzner = mkSystem {
          hostname = "nixos-hetzner";
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./configurations/hetzner.nix
          ];
        };

        # ARCHIVED CONFIGURATIONS:
        # The following have been moved to archived/obsolete-configs/
        # - hetzner-i3.nix (testing config, consolidated into hetzner.nix)
        # - hetzner-mangowc.nix (MangoWC experimental compositor)
        # - hetzner-minimal.nix, hetzner-example.nix (nixos-anywhere templates)
        # - wsl.nix (WSL2 environment)
        # - vm-*.nix, kubevirt-*.nix (VM/KubeVirt deployments)

        # Secondary: M1 MacBook Pro (aarch64)
        # Note: Still uses KDE Plasma temporarily (migration deferred)
        m1 = mkSystem {
          hostname = "nixos-m1";
          system = "aarch64-linux";
          modules = [ ./configurations/m1.nix ];
        };

        # Container: Docker/K8s deployments
        # Note: container.nix is used via packages.container-* builds
      };

      homeConfigurations =
        let
          currentSystem = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";
          pkgsFor = system: import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          unstableFor = system: import nixpkgs-bleeding {
            inherit system;
            config.allowUnfree = true;
          };
          osConfigFor = system:
            if system == "aarch64-linux" then self.nixosConfigurations.m1.config
            else self.nixosConfigurations.hetzner.config;
          mkHome = modulePath: home-manager.lib.homeManagerConfiguration {
            pkgs = pkgsFor currentSystem;
            extraSpecialArgs = {
              inherit inputs;
              osConfig = osConfigFor currentSystem;
              pkgs-unstable = unstableFor currentSystem;
            };
            modules = [ modulePath ];
          };
          # Darwin-specific home configuration (no osConfig needed)
          mkDarwinHome = modulePath: system: home-manager.lib.homeManagerConfiguration {
            pkgs = pkgsFor system;
            extraSpecialArgs = {
              inherit inputs;
              pkgs-unstable = unstableFor system;
            };
            modules = [ modulePath ];
          };
        in
        {
          vpittamp = mkHome ./home-vpittamp.nix;
          code = mkHome ./home-code.nix;
          # Darwin (macOS) home-manager configuration
          # Usage: home-manager switch --flake .#darwin
          darwin = mkDarwinHome ./home-darwin.nix "aarch64-darwin";
        };

      # Container and VM image packages (manually defined per system)
      packages = let
        mkPackagesFor = system:
          let
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
            pkgsUnstable = import nixpkgs-bleeding {
              inherit system;
              config.allowUnfree = true;
            };
            mkContainerSystem = profile:
              (nixpkgs.lib.nixosSystem {
                inherit system;
                specialArgs = {
                  inherit inputs pkgsUnstable;
                  containerProfile = profile;
                };
                modules = [
                  ./configurations/container.nix
                  home-manager.nixosModules.home-manager
                  ({ config, pkgsUnstable, ... }:
                    {
                      home-manager = {
                        backupFileExtension = "backup";
                        useGlobalPkgs = true;
                        useUserPackages = true;
                        extraSpecialArgs = {
                          inherit inputs;
                          osConfig = config;
                          pkgs-unstable = pkgsUnstable;
                        };
                        users.code = {
                          imports = [ ./home-code.nix ];
                        };
                      };
                    })
                ];
              }).config.system.build.toplevel;
          in
          rec {
            # Minimal KubeVirt VM image (qcow2 format with RustDesk + Tailscale)
            nixos-kubevirt-minimal-image = nixos-generators.nixosGenerate {
              inherit system;
              modules = [ ./configurations/kubevirt-minimal.nix ];
              format = "qcow";
            };

            # Full KubeVirt VM image (qcow2 with complete desktop + home-manager)
            nixos-kubevirt-full-image = nixos-generators.nixosGenerate {
              inherit system;
              modules = [
                ./configurations/kubevirt-full.nix
                # Add home-manager integration (same as mkSystem helper)
                home-manager.nixosModules.home-manager
                {
                  home-manager = {
                    backupFileExtension = "backup";
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    extraSpecialArgs = {
                      inherit inputs;
                      pkgs-unstable = import nixpkgs-bleeding {
                        inherit system;
                        config.allowUnfree = true;
                      };
                    };
                    users.vpittamp = {
                      imports = [
                        ./home-vpittamp.nix
                        inputs.plasma-manager.homeModules.plasma-manager
                      ];
                      home.enableNixpkgsReleaseCheck = false;
                    };
                  };
                }
              ];
              format = "qcow";
            };

            # Optimized KubeVirt VM image (qcow2 with desktop, no home-manager)
            # Fast build: ~15-20 minutes (vs 60+ minutes for full image)
            # Apply home-manager at runtime: nix run home-manager/master -- switch --flake .#vpittamp
            nixos-kubevirt-optimized-image = nixos-generators.nixosGenerate {
              inherit system;
              modules = [ ./configurations/kubevirt-optimized.nix ];
              format = "qcow";
            };

            # Minimal container
            container-minimal = pkgs.dockerTools.buildLayeredImage {
              name = "nixos-container";
              tag = "minimal";
              contents = [ (mkContainerSystem "minimal") ];
              config = {
                Cmd = [ "/bin/bash" ];
                Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=minimal" ];
              };
            };

            # Development container
            container-dev = pkgs.dockerTools.buildLayeredImage {
              name = "nixos-container";
              tag = "development";
              contents = [ (mkContainerSystem "development") ];
              config = {
                Cmd = [ "/bin/bash" ];
                Env = [ "NIXOS_CONTAINER=1" "NIXOS_PACKAGES=development" ];
              };
            };

            # Default container output
            default = container-minimal;
          };
      in
      {
        x86_64-linux = mkPackagesFor "x86_64-linux";
        aarch64-linux = mkPackagesFor "aarch64-linux";
      };

      # Development shells
      devShells = let
        mkDevShellFor = system:
          let
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          in
          {
            default = pkgs.mkShell {
              name = "nixos-dev";
              buildInputs = with pkgs; [
                # Nix tools
                nixpkgs-fmt nixfmt statix deadnix
                # Development tools
                git vim tmux
                # Container tools
                docker docker-compose kubectl
              ];

              shellHook = ''
                echo "NixOS Development Shell"
                echo "Available configurations:"
                echo "  - hetzner: Primary workstation (x86_64)"
                echo "  - m1: Apple Silicon (aarch64)"
                echo "  - wsl: Windows Subsystem for Linux"
                echo "  - container: Docker/K8s containers"
                echo ""
                echo "Build with: nixos-rebuild switch --flake .#<config>"
                echo "Export current Plasma settings: ./scripts/plasma-rc2nix.sh > plasma-latest.nix"
                echo "Apply Home Manager profile: nix run home-manager/master -- switch --flake .#vpittamp"
              '';
            };
          };
      in
      {
        x86_64-linux = mkDevShellFor "x86_64-linux";
        aarch64-linux = mkDevShellFor "aarch64-linux";
        aarch64-darwin = mkDevShellFor "aarch64-darwin";
      };
    };
}

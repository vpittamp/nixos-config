# Container flake module
# This ensures the flake.nix and overlays are available inside containers
# for runtime package management via nix develop and nix shell

{ config, pkgs, lib, ... }:

{
  # Include flake.nix and overlays in the container
  environment.etc = {
    # Include the flake.nix in /etc/nixos
    "nixos/flake.nix".source = ./flake.nix;
    "nixos/flake.lock".source = ./flake.lock;
    
    # Include overlays
    "nixos/overlays/default.nix".source = ./overlays/default.nix;
    "nixos/overlays/packages.nix".source = ./overlays/packages.nix;
    
    # Include home-manager configurations (for reference)
    "nixos/home-vpittamp.nix".source = ./home-vpittamp.nix;
    
    # Include container profiles
    "nixos/container-profile.nix".source = ./container-profile.nix;
    "nixos/container-dev.nix".source = ./container-dev.nix;
    
    # Add a README for container users
    "nixos/README-CONTAINER.md".text = ''
      # NixOS Container - Runtime Package Management
      
      This container includes Nix flakes for runtime package management.
      
      ## Available Commands:
      
      ### Temporary Package Addition
      ```bash
      # Add packages to current shell session
      nix shell nixpkgs#htop nixpkgs#ripgrep
      ```
      
      ### Development Shells
      ```bash
      # List available development shells
      nix flake show /etc/nixos
      
      # Enter default development shell
      nix develop /etc/nixos --impure
      
      # Enter specific development shell
      nix develop /etc/nixos#nodejs --impure  # Node.js environment
      nix develop /etc/nixos#python --impure   # Python environment
      nix develop /etc/nixos#go --impure       # Go environment
      nix develop /etc/nixos#rust --impure     # Rust environment
      nix develop /etc/nixos#fullstack --impure # Full-stack environment
      ```
      
      ### Persistent Package Installation
      ```bash
      # Install packages to user profile
      nix profile install nixpkgs#lazygit
      
      # List installed packages
      nix profile list
      
      # Remove package
      nix profile remove <package-name>
      ```
      
      ### Package Search
      ```bash
      # Search for packages
      nix search nixpkgs postgresql
      nix search nixpkgs nodejs
      ```
      
      ## SSL Certificate Issues
      
      If you encounter SSL certificate errors with yarn/npm:
      - Certificates are pre-configured via NODE_EXTRA_CA_CERTS
      - For development only: set ALLOW_INSECURE_SSL=true in environment
      
      ## Notes
      
      - The --impure flag preserves your terminal customization
      - Packages are cached in /nix/store and reused across sessions
      - User profile installations persist if /home is a volume mount
    '';
  };
  
  # Ensure git is available for flake operations
  environment.systemPackages = with pkgs; [
    git  # Required for flake operations
  ];
}
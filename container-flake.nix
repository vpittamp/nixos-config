# Container flake module
# This ensures the flake.nix and overlays are available inside containers
# for runtime package management via nix develop and nix shell

{ config, pkgs, lib, ... }:

{
  # Include minimal flake files in the container for runtime package management
  environment.etc = {
    # Include the flake.nix in /etc/nixos
    "nixos/flake.nix".source = ./flake.nix;
    "nixos/flake.lock".source = ./flake.lock;
    
    # Also create a .git directory to make it a valid flake
    "nixos/.git/config".text = ''
      [core]
        repositoryformatversion = 0
        filemode = false
        bare = false
    '';
    
    # Add a README for container users
    "nixos/README-CONTAINER.md".text = ''
      # NixOS Container - Runtime Package Management
      
      This container includes Nix flakes for runtime package management.
      
      ## Working Directory
      
      Always run nix develop/shell commands from /etc/nixos:
      ```bash
      cd /etc/nixos
      nix develop .#nodejs --impure
      ```
      
      Or use absolute path:
      ```bash
      nix develop /etc/nixos#nodejs --impure
      ```
      
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
  # Git is already included in the base packages, no need to add it here
}
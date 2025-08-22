{ pkgs, lib, config, inputs }:

let
  # Import home configuration for full system container
  homeModule = import ../home-vpittamp.nix;
  
  # System packages from configuration.nix
  systemPackages = with pkgs; [
    neovim vim git wget curl wslu nodejs_20 claude-code docker-compose
  ];
in
{
  # Node.js application container
  node-app-container = pkgs.dockerTools.buildLayeredImage {
    name = "node-app";
    tag = "latest";
    
    contents = with pkgs; [
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
  
  # Python application container
  python-app-container = pkgs.dockerTools.buildLayeredImage {
    name = "python-app";
    tag = "latest";
    
    contents = with pkgs; [
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
  
  # Full NixOS system container
  nixos-full-system = import ./nixos-full-system.nix {
    inherit pkgs lib homeModule systemPackages inputs;
  };
  
  # Minimal runtime container (production use)
  nixos-runtime-system = import ./nixos-runtime-system.nix {
    inherit pkgs lib inputs;
  };
}
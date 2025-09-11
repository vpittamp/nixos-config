# Development Services Configuration
{ config, lib, pkgs, ... }:

{
  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    # Docker Desktop integration for WSL (will be ignored on other systems)
    # wsl.docker-desktop.enable = lib.mkDefault false;
  };

  # Libvirt for VMs
  virtualisation.libvirtd = {
    enable = lib.mkDefault true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };

  # Add users to necessary groups
  users.users.vpittamp.extraGroups = [ "docker" "libvirtd" ];

  # Development packages
  environment.systemPackages = with pkgs; [
    # Version control and GitHub
    git
    gh  # GitHub CLI for authentication
    
    # Container tools
    docker-compose
    kubectl
    kubernetes-helm
    k9s
    kind
    minikube
    
    # Cloud tools
    terraform
    awscli2
    azure-cli
    google-cloud-sdk
    
    # Development tools
    vscode
    nodejs_20
    python3
    go
    rustc
    cargo
    
    # Build tools
    gcc
    gnumake
    cmake
    pkg-config
    
    # Database clients
    postgresql
    mariadb
    redis
    mongodb-tools
    
    # API tools
    curl
    httpie
    postman
    jq
    yq
  ];

  # Firewall ports for development services
  networking.firewall.allowedTCPPorts = [
    3000   # Node.js dev server
    3001   # Alternative dev server
    4200   # Angular
    5000   # Flask
    5173   # Vite
    8000   # Django/Python
    8080   # Generic web
    8081   # Alternative web
    9000   # PHP
  ];
}
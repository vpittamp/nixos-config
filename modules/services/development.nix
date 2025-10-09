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
      # ovmf submodule removed - OVMF images now available by default with QEMU
    };
  };

  # Add users to necessary groups
  users.users.vpittamp.extraGroups = [ "docker" "libvirtd" ];

  # Development packages
  environment.systemPackages = with pkgs; let
    idpbuilder = pkgs.callPackage ../../packages/idpbuilder.nix { };

    # Headlamp package with desktop entry and icon
    headlamp = pkgs.callPackage ../../packages/headlamp.nix { };
  in
  [
    # Version control and GitHub
    git
    gh # GitHub CLI for authentication


    # Container tools
    docker-compose
    kubectl
    kubernetes-helm
    k9s
    kind
    minikube
    argocd # Argo CD CLI
    devspace # DevSpace for Kubernetes development
    vcluster # Virtual Kubernetes clusters
    nssTools # Provides certutil for Chromium certificate import

    # Cloud tools
    terraform
    # awscli2 # Commented out - not currently used, slow to build
    # azure-cli-bin # Moved to user packages for Codespaces compatibility
    google-cloud-sdk
    hcloud # Hetzner Cloud CLI

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

    # Kubernetes Dashboard
    headlamp # Kubernetes Dashboard UI (now supports both x86_64 and aarch64)
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    idpbuilder # IDP builder tool (x86_64 only)
  ];

  # Firewall ports for development services
  networking.firewall.allowedTCPPorts = [
    3000 # Node.js dev server
    3001 # Alternative dev server
    4200 # Angular
    5000 # Flask
    5173 # Vite
    8000 # Django/Python
    8080 # Generic web
    8081 # Alternative web
    9000 # PHP
  ];
}

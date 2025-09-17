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
  environment.systemPackages = with pkgs; let
    # Define idpbuilder here directly since it's not exposed in nixpkgs
    idpbuilder = pkgs.stdenv.mkDerivation rec {
      pname = "idpbuilder";
      version = "0.10.1";
      
      src = pkgs.fetchurl {
        url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-amd64.tar.gz";
        sha256 = "1w1h6zbr0vzczk1clddn7538qh59zn6cwr37y2vn8mjzhqv8dpsr";
      };
      
      sourceRoot = ".";
      dontBuild = true;
      
      nativeBuildInputs = [ pkgs.autoPatchelfHook ];
      
      installPhase = ''
        mkdir -p $out/bin
        cp idpbuilder $out/bin/
        chmod +x $out/bin/idpbuilder
      '';
      
      meta = with lib; {
        description = "Build Internal Developer Platforms (IDPs) declaratively";
        homepage = "https://github.com/cnoe-io/idpbuilder";
        license = licenses.asl20;
        platforms = [ "x86_64-linux" ];
        mainProgram = "idpbuilder";
      };
    };
    
    # Headlamp package with desktop entry and icon
    headlamp = pkgs.callPackage ../../packages/headlamp.nix {};
  in [
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
    argocd  # Argo CD CLI
    devspace  # DevSpace for Kubernetes development
    vcluster  # Virtual Kubernetes clusters
    
    # Cloud tools
    terraform
    awscli2
    azure-cli
    google-cloud-sdk
    hcloud  # Hetzner Cloud CLI
    
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
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    idpbuilder  # IDP builder tool (x86_64 only)
    headlamp    # Kubernetes Dashboard UI (x86_64 only)
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

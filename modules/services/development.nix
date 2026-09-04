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

  # Libvirt/KVM removed — unused (no VMs defined; containers + Talos-in-Docker
  # cover all workloads). Hosts that genuinely want KVM enable it explicitly via
  # services.bare-metal.enableVirtualization, which owns the libvirtd/kvm groups.

  # Add users to necessary groups
  users.users.vpittamp.extraGroups = [ "docker" ];

  # Development packages
  environment.systemPackages = with pkgs; let
    # virtctl - KubeVirt CLI tool
    virtctl = pkgs.callPackage ../../packages/virtctl.nix { };
  in
  [
    # Version control and GitHub
    git
    gh # GitHub CLI for authentication


    # Container tools
    docker-compose
    # kubectl moved to user packages for Codespaces compatibility
    # kubernetes-helm moved to user packages for Codespaces compatibility
    # k9s moved to user packages for Codespaces compatibility
    kind
    minikube
    virtctl # KubeVirt CLI for managing VMs in Kubernetes
    argocd # Argo CD CLI
    # devspace removed 2026-08-23 (slimming, ~428 MiB); skaffold covers the same
    # local Kubernetes dev loop and is actively used.
    vcluster # Virtual Kubernetes clusters
    nssTools # Provides certutil for Chromium certificate import

    # Cloud tools
    # terraform removed 2026-08-23 (slimming, ~113 MiB); ~/.terraform.d last written
    # 2026-03-03. Infrastructure here is Talos + GitOps, not Terraform.
    # awscli2 # Commented out - not currently used, slow to build
    (google-cloud-sdk.withExtraComponents [
      google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    hcloud # Hetzner Cloud CLI

    # Development tools
    # vscode removed 2026-08-23 (slimming, ~928 MiB): home-manager's programs.vscode
    # already installs it into the per-user profile, so it was built and stored twice
    # (`which -a code` returned both). home-modules/tools/vscode.nix is the owner.
    nodejs
    deno
    python3
    go
    # rustc/cargo removed 2026-08-23 (slimming, ~3.4 GiB including rustc-doc and the
    # rustc/cargo bootstrap closures). rust-analyzer + rustfmt stay in the user profile
    # (~112 MiB, they do not pull the toolchain); use a devshell for actual Rust builds.

    # Build tools
    gcc
    gnumake
    cmake
    pkg-config

    # Database clients
    postgresql
    # mariadb -> mariadb's client only: the full server package was ~262 MiB and this
    # list is explicitly "database clients" (2026-08-23 slimming).
    mariadb.client
    redis
    mongodb-tools

    # API tools
    curl
    httpie
    # postman removed 2026-08-23 (slimming, ~376 MiB): last used 2026-02-13, and it was
    # installed twice (here plus home-modules/tools/postman.nix).
    jq
    yq

    # headlamp removed 2026-08-23 (slimming, ~441 MiB): last used 2026-06-14 and k9s
    # covers the same job. Desktop entry removed in home-modules/tools/kubernetes-apps.nix.
    # idpbuilder moved to user packages for Codespaces compatibility
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

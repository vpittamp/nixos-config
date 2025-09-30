# System-level packages that require root/build permissions
# These packages contain custom derivations, chmod operations, or other
# operations that fail in restricted container environments
{ pkgs, lib, ... }:

let
  # Custom packages
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

  # Azure CLI from stable nixpkgs for Python 3.11 compatibility
  azure-cli-bin = pkgs.callPackage ../packages/azure-cli-bin.nix { };

  # Plugins are now managed through home-manager:
  # - Tmux plugins via programs.tmux.plugins
  # - Vim plugins via programs.neovim.plugins

  # System utilities and tools
  systemTools = with pkgs; [
    # Core system utilities
    coreutils
    findutils
    gnused
    gawk
    gnutar
    gzip
    which
    file
    ncurses

    # Clipboard utilities (Wayland/X11)
    wl-clipboard  # Wayland clipboard
    xclip         # X11 clipboard

    # Nix tools
    nix
    cachix
    nh  # Nix Helper - Yet another nix cli helper

    # VPN tools
    tailscale

    # Certificate management tools
    nssTools  # Provides certutil for managing NSS certificate database

    # Web browsers
    chromium  # Chromium browser (open-source version of Chrome, better ARM64 support)
  ];

  # Development tools that work better at system level
  developmentTools = (with pkgs; [
    # Container tools
    docker-compose
    devpod
    devcontainer
    devspace
    
    # IDP tools
    idpbuilder
    
    # Version control
    git
    gh
    lazygit
    
    # Build tools
    gnumake
    gcc
    pkg-config
    
    # Language support
    nodejs_20
    python3
    go
    rustc
    cargo
  ]) ++ [ 
    # Cloud tools (custom packages)
    azure-cli-bin 
  ];

  # Kubernetes tools (often need system access)
  kubernetesTools = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
    argocd
    vcluster
    kind
  ];

in {
  # Export different package sets
  custom = [ azure-cli-bin ];
  
  # Plugins moved to home-manager
  tmuxPlugins = [];
  vimPlugins = [];
  
  system = systemTools;
  development = developmentTools;
  kubernetes = kubernetesTools;
  
  # All system packages
  all = systemTools ++ developmentTools ++ kubernetesTools ++ [ azure-cli-bin ];
  
  # Essential system packages only
  essential = systemTools ++ (with pkgs; [
    git
    docker-compose
    nodejs_20
    python3
  ]);
  
  # Minimal for containers
  minimal = with pkgs; [
    coreutils
    findutils
    gnused
    git
    which
    file
  ];
}

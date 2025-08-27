{ pkgs, lib, ... }:

let
  # Minimal packages for initial container setup
  minimalPackages = with pkgs; [
    # Absolute essentials only
    tmux git vim
    fzf ripgrep fd bat
    curl wget jq
    which file
  ];
  
  # Essential packages - core tools
  essentialPackages = with pkgs; [
    # Core (extends minimal)
    gnugrep eza zoxide
    yq tree htop
    ncurses direnv stow
    gum             # shell scripts UI
    gnutar          # Required for DevSpace helper injection
    gzip            # Required for DevSpace helper extraction
    gnused          # Required for VS Code Server
    glibc           # Required for VS Code Server
    stdenv.cc.cc.lib # Provides libstdc++
    gawk            # Provides getconf
    coreutils       # Additional utilities
    xclip           # X11 clipboard utility for WSLg
  ];
  
  # Language/runtime packages (large downloads)
  runtimePackages = {
    nodejs_20 = pkgs.nodejs_20;       # ~150MB
    deno = pkgs.deno;                 # ~120MB
    python3 = pkgs.python3;           # ~100MB
  };
  
  # Language servers for development
  languageServers = {
    typescript-language-server = pkgs.nodePackages.typescript-language-server;  # ~50MB
    nil = pkgs.nil;                   # ~10MB - Nix LSP
    pyright = pkgs.pyright;           # ~80MB - Python LSP
  };
  
  # Optional package groups
  kubernetesPackages = {
    kubectl = pkgs.kubectl;           # ~50MB
    helm = pkgs.kubernetes-helm;      # ~50MB
    k9s = pkgs.k9s;                  # ~80MB
    argocd = pkgs.argocd;            # ~100MB
    vcluster = pkgs.vcluster;        # ~40MB
    kind = pkgs.kind;                # ~10MB
  };
  
  developmentPackages = {
    gh = pkgs.gh;                    # ~30MB
    devspace = pkgs.devspace;        # ~70MB
    docker-compose = pkgs.docker-compose;  # ~100MB
    yarn = pkgs.yarn;                # ~10MB - JavaScript package manager
    claude-code = pkgs.claude-code;  # ~50MB
    lazygit = pkgs.lazygit;          # ~20MB - terminal UI for git
    # gitingest = pkgs.gitingest;      # ~15MB - git repository ingestion tool (build failure)
    # VS Code CLI is not in nixpkgs yet, will be installed via script
  };
  
  toolPackages = {
    yazi = pkgs.yazi;                # ~50MB - terminal file manager
    btop = pkgs.btop;
    ncdu = pkgs.ncdu;
    glow = pkgs.glow;
  };
  
  # NIXOS_PACKAGES can be:
  # - "minimal" (bare minimum for container bootstrap)
  # - "essential" (default - common tools)
  # - "essential,kubectl,k9s,gh" (specific packages)
  # - "full" (everything)
  # For main system (non-container), always use "full"
  packageSelection = let
    envValue = builtins.getEnv "NIXOS_PACKAGES";
    isContainer = builtins.getEnv "NIXOS_CONTAINER" != "";
  in if envValue == "" then (if isContainer then "essential" else "full") else envValue;
  
  selectedPackages = lib.splitString "," packageSelection;
  
  # Check if a package should be included
  includePackage = name: 
    packageSelection == "full" || 
    builtins.elem name selectedPackages;
    
  # Apply includePackage filter to package set
  filterPackages = packages: 
    lib.attrValues (lib.filterAttrs (name: _: includePackage name) packages);
in
rec {
  # Custom packages
  claude-manager = pkgs.callPackage ../packages/claude-manager-fetchurl.nix { 
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  
  idpbuilder = pkgs.stdenv.mkDerivation rec {
    pname = "idpbuilder";
    version = "0.9.1";
    src = pkgs.fetchurl {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-amd64.tar.gz";
      sha256 = "sha256-pPFpQ+wgxq1BZk7XrimGKCNo2veCc1ZRb51mh7gwqgk=";
    };
    sourceRoot = ".";
    installPhase = ''
      mkdir -p $out/bin
      cp idpbuilder $out/bin/idpbuilder
      chmod +x $out/bin/idpbuilder
    '';
  };
  
  sesh = pkgs.stdenv.mkDerivation rec {
    pname = "sesh";
    version = "2.6.0";
    src = pkgs.fetchurl {
      url = "https://github.com/joshmedeski/sesh/releases/download/v${version}/sesh_Linux_x86_64.tar.gz";
      sha256 = "1i88yvy0r20ndkhimbcpxvkfndq8gfx8r83jb2axjankwcyriwis";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    unpackPhase = "tar -xzf $src";
    installPhase = ''
      mkdir -p $out/bin
      cp sesh $out/bin/sesh
      chmod +x $out/bin/sesh
      wrapProgram $out/bin/sesh \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.tmux pkgs.zoxide pkgs.fzf ]} \
        --set-default SESH_DEFAULT_SESSION "main" \
        --set-default SESH_DEFAULT_COMMAND "tmux"
    '';
  };

  # Package sets based on selection
  minimal = minimalPackages ++ [ sesh ];
  
  essential = minimalPackages ++ essentialPackages ++ [
    claude-manager
    sesh
  ];
  
  # For container builds - filtered by NIXOS_PACKAGES env var
  extras = lib.flatten [
    (filterPackages runtimePackages)
    (filterPackages languageServers)
    (filterPackages kubernetesPackages)
    (filterPackages developmentPackages)
    (filterPackages toolPackages)
    (lib.optional (includePackage "idpbuilder") idpbuilder)
  ];
  
  # For main system - always include everything
  allExtras = lib.flatten [
    (lib.attrValues runtimePackages)
    (lib.attrValues languageServers)
    (lib.attrValues kubernetesPackages)
    (lib.attrValues developmentPackages)
    (lib.attrValues toolPackages)
    idpbuilder
  ];
  
  # Determine which package set to use
  allPackages = 
    if packageSelection == "minimal" then minimal
    else if packageSelection == "essential" then essential
    else if packageSelection == "full" then essential ++ allExtras
    else essential ++ extras;
}
{ pkgs, lib, ... }:

let
  # Essential packages - always included
  essentialPackages = with pkgs; [
    # Core
    tmux git vim
    fzf ripgrep gnugrep fd bat eza zoxide
    curl wget jq yq tree htop
    which file ncurses direnv stow
    nodejs_20        # ~150MB
    claude-code      # ~50MB
    yazi            # ~50MB - terminal file manager
    gum             # shell scripts UI
  ];
  
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
    deno = pkgs.deno;                # ~120MB
    docker-compose = pkgs.docker-compose;  # ~100MB
    yarn = pkgs.yarn;                # ~10MB - JavaScript package manager
  };
  
  toolPackages = {
    btop = pkgs.btop;
    ncdu = pkgs.ncdu;
    glow = pkgs.glow;
  };
  
  # NIXOS_PACKAGES can be:
  # - "essential" (default)
  # - "essential,kubectl,k9s,gh" (specific packages)
  # - "full" (everything)
  packageSelection = builtins.getEnv "NIXOS_PACKAGES";
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

  essential = essentialPackages ++ [
    claude-manager
    sesh
  ];
  
  # For container builds - filtered by NIXOS_PACKAGES env var
  extras = lib.flatten [
    (filterPackages kubernetesPackages)
    (filterPackages developmentPackages)
    (filterPackages toolPackages)
    (lib.optional (includePackage "idpbuilder") idpbuilder)
  ];
  
  # For main system - always include everything
  allExtras = lib.flatten [
    (lib.attrValues kubernetesPackages)
    (lib.attrValues developmentPackages)
    (lib.attrValues toolPackages)
    idpbuilder
  ];
  
  # Used by main configuration.nix - includes everything
  allPackages = essential ++ allExtras;
}
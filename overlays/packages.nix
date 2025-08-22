# Simplified overlay package definitions
# Use NIXOS_PACKAGES env var to control what gets included
{ pkgs, lib, ... }:

let
  # Get package selection from environment (default: "essential")
  # Options: "essential", "full", or comma-separated list like "essential,kubernetes,development"
  packageSelection = builtins.getEnv "NIXOS_PACKAGES";
  
  # Parse selection
  selectedGroups = if packageSelection == "" then [ "essential" ]
                   else if packageSelection == "full" then [ "essential" "kubernetes" "development" "extras" ]
                   else lib.splitString "," packageSelection;
  
  # Check if a group should be included
  includeGroup = group: builtins.elem group selectedGroups;
in
rec {
  # Custom packages that were in the let block
  claude-manager = pkgs.callPackage ../packages/claude-manager-fetchurl.nix { 
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  
  idpbuilder = pkgs.stdenv.mkDerivation rec {
    pname = "idpbuilder";
    version = "0.9.1";
    src = pkgs.fetchurl {
      url = "https://github.com/cnoe-io/idpbuilder/releases/download/v${version}/idpbuilder-linux-amd64";
      sha256 = "sha256-M7JMUiJ/dECv5jpjCdtOxJQg0PmthVKykq5Vu1OF0Xg=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/idpbuilder
      chmod +x $out/bin/idpbuilder
    '';
  };
  
  sesh = pkgs.stdenv.mkDerivation rec {
    pname = "sesh";
    version = "2.6.0";
    src = pkgs.fetchurl {
      url = "https://github.com/joshmedeski/sesh/releases/download/v${version}/sesh-linux-amd64.tar.gz";
      sha256 = "sha256-nDPnIBnURr9DuB6zi8CE0c8JKGdV//zBpvQCCNhjI7g=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    unpackPhase = "tar -xzf $src";
    installPhase = ''
      mkdir -p $out/bin
      cp sesh-linux-amd64 $out/bin/sesh
      chmod +x $out/bin/sesh
      wrapProgram $out/bin/sesh \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.tmux pkgs.zoxide pkgs.fzf ]} \
        --set-default SESH_DEFAULT_SESSION "main" \
        --set-default SESH_DEFAULT_COMMAND "tmux" \
        --replace "fzf " "${pkgs.fzf}/bin/fzf "
    '';
  };

  # Essential packages - always included unless explicitly building minimal
  # ~1.5GB container
  essential = with pkgs; [
    # Core
    tmux git vim neovim
    fzf ripgrep fd bat eza zoxide
    curl wget jq yq tree htop
    which file ncurses
    direnv stow
    
    # Custom packages
    claude-manager
    sesh
  ];
  
  # Kubernetes tools - ~600MB
  # Include with: NIXOS_PACKAGES="essential,kubernetes"
  kubernetes = if includeGroup "kubernetes" then with pkgs; [
    kubectl
    kubernetes-helm
    k9s
    argocd
    vcluster
    kind
  ] else [];
  
  # Development tools - ~600MB
  # Include with: NIXOS_PACKAGES="essential,development"
  development = if includeGroup "development" then (with pkgs; [
    gh
    docker-compose
    devspace
    deno
    nodejs_20
  ] ++ [ idpbuilder ])  # Add custom idpbuilder
  else [];
  
  # Extra tools - ~200MB
  # Include with: NIXOS_PACKAGES="essential,extras"
  extras = if includeGroup "extras" then with pkgs; [
    btop      # better htop
    ncdu      # disk usage
    yazi      # file manager
    gum       # interactive scripts
    glow      # markdown viewer
  ] else [];
  
  # All packages combined based on selection
  allPackages = essential ++ kubernetes ++ development ++ extras;
}
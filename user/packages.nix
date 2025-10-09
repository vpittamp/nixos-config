# User-level packages safe for home-manager
# These are all from nixpkgs and don't require special build permissions
# Safe to use in restricted container environments
{ pkgs, lib, ... }:

let
  # Azure CLI from stable nixpkgs for Python 3.12 compatibility
  # Moved to user packages for Codespaces compatibility
  azure-cli-bin = pkgs.callPackage ../packages/azure-cli-bin.nix { };

  # IDP Builder - x86_64 only
  idpbuilder = pkgs.callPackage ../packages/idpbuilder.nix { };

  # Text editors and IDEs (from nixpkgs)
  editors = with pkgs; [
    # vim is managed by programs.vim in home-manager
    # neovim is managed by programs.neovim in home-manager
    # vscode is provided at system level via wrapper
  ];

  # Terminal tools and utilities
  terminalTools = with pkgs; [
    tmux
    # sesh is managed by programs.sesh in home-manager
    zoxide
    fzf
    ripgrep
    fd
    bat
    lazydocker
    eza
    direnv
    stow
    tree
    htop
    btop
    ncdu
    glow
    jq
    yq
    curl
    wget
    gum
    tailscale # VPN CLI tool
  ];

  # Shell enhancements
  shellTools = with pkgs; [
    starship
    zsh
    bash
    fish
  ];

  # Language servers and development tools (from nixpkgs)
  languageServers = with pkgs; [
    # TypeScript/JavaScript
    nodePackages.typescript-language-server
    nodePackages.prettier
    nodePackages.eslint

    # Python
    pyright
    black
    ruff

    # Nix
    nil
    nixpkgs-fmt

    # Go
    gopls

    # Rust
    rust-analyzer
    rustfmt
  ];

  # Package managers (from nixpkgs)
  packageManagers = with pkgs; [
    yarn
    nodePackages.pnpm
    poetry
    uv # Fast Python package installer and resolver (for spec-kit and other tools)
  ];

  # File managers
  fileManagers = with pkgs; [
    yazi
    ranger
    lf
  ];

  # Git tools (from nixpkgs, no custom builds)
  gitTools = with pkgs; [
    git-lfs
    git-crypt
    delta
    diff-so-fancy
    lazygit
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    gitkraken # Git GUI client (x86_64 only)
  ];

  # Kubernetes and cloud tools
  kubernetesTools = with pkgs; [
    kubectl # Kubernetes CLI
    kubernetes-helm # Helm package manager for Kubernetes
    k9s # Terminal UI for Kubernetes
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    idpbuilder # IDP builder tool (x86_64 only)
  ];

  # Cloud tools (for containers/Codespaces)
  cloudTools = [
    azure-cli-bin # Azure CLI (from stable nixpkgs)
  ];

  # Documentation and help
  documentation = with pkgs; [
    tldr
    man-pages
    man-pages-posix
  ];

  # Nix helper tools
  nixTools = with pkgs; [
    nh # Yet another nix cli helper
    nix-output-monitor # Prettier nix build output
    nixpkgs-fmt # Nix code formatter
    alejandra # Alternative Nix formatter
    nix-tree # Visualize Nix store dependencies
    nix-prefetch-git # Prefetch git repositories
  ];

in
{
  # Export categorized packages
  editors = editors;
  terminal = terminalTools;
  shell = shellTools;
  languageServers = languageServers;
  packageManagers = packageManagers;
  fileManagers = fileManagers;
  git = gitTools;
  kubernetes = kubernetesTools;
  cloud = cloudTools;
  docs = documentation;
  nix = nixTools;

  # Common package sets
  essential = terminalTools ++ shellTools ++ nixTools ++ [
    # vim handled by programs.vim
    pkgs.git-lfs
    pkgs.tldr
    pkgs.yazi # Terminal file manager
    pkgs.yarn # JavaScript package manager
  ];

  development = terminalTools ++ shellTools ++ editors ++
    languageServers ++ packageManagers ++ gitTools ++ kubernetesTools ++ cloudTools ++ nixTools;

  # All user packages
  all = terminalTools ++ shellTools ++ editors ++
    languageServers ++ packageManagers ++ fileManagers ++
    gitTools ++ kubernetesTools ++ cloudTools ++ documentation ++ nixTools;

  # Minimal for testing
  minimal = with pkgs; [
    # vim handled by programs.vim
    tmux
    git
    curl
    jq
    fzf
    ripgrep
  ];
}

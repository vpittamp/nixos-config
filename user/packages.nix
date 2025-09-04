# User-level packages safe for home-manager
# These are all from nixpkgs and don't require special build permissions
# Safe to use in restricted container environments
{ pkgs, lib, ... }:

let
  # Text editors and IDEs (from nixpkgs)
  editors = with pkgs; [
    # vim is managed by programs.vim in home-manager
    # neovim is managed by programs.neovim in home-manager
    # vscode is provided at system level via wrapper
  ];

  # Terminal tools and utilities
  terminalTools = with pkgs; [
    tmux
    zoxide
    fzf
    ripgrep
    fd
    bat
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
  ];

  # Documentation and help
  documentation = with pkgs; [
    tldr
    man-pages
    man-pages-posix
  ];

in {
  # Export categorized packages
  editors = editors;
  terminal = terminalTools;
  shell = shellTools;
  languageServers = languageServers;
  packageManagers = packageManagers;
  fileManagers = fileManagers;
  git = gitTools;
  docs = documentation;
  
  # Common package sets
  essential = terminalTools ++ shellTools ++ [
    # vim handled by programs.vim
    pkgs.git-lfs
    pkgs.tldr
  ];
  
  development = terminalTools ++ shellTools ++ editors ++ 
    languageServers ++ packageManagers ++ gitTools;
  
  # All user packages
  all = terminalTools ++ shellTools ++ editors ++ 
    languageServers ++ packageManagers ++ fileManagers ++ 
    gitTools ++ documentation;
  
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
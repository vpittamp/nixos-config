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

  # Goose Desktop - AI Agent Desktop Application (x86_64 only)
  goose-desktop = pkgs.callPackage ../packages/goose-desktop.nix { };

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
    chafa # Terminal image viewer for fzf previews
    glib # For gio command (desktop file launcher and file operations)
  ];

  # AI and LLM tools
  aiTools = with pkgs; [
    goose-cli # Goose AI Agent CLI (from nixpkgs)
    openai # OpenAI Python CLI
    # Note: gitingest is run on-demand via: uvx gitingest <repo-url>
    # This ensures we always use the latest version without pre-installation
    # See /etc/nixos/.claude/commands/gitingest.md for usage
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    goose-desktop # Goose AI Agent Desktop (custom package, x86_64 only)
  ];

  # Shell enhancements
  shellTools = with pkgs; [
    starship
    zsh
    bash
    fish
  ];

  # Python testing environment (Feature 039)
  # REMOVED: Merged into sharedPythonEnv in python-environment.nix to prevent buildEnv conflicts
  # All testing packages (pytest, pytest-asyncio, pytest-cov, click, rich, pydantic, i3ipc, psutil)
  # are now available via the shared Python environment

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
    # Feature 039: Python testing environment now provided by sharedPythonEnv (python-environment.nix)

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
    # Terminal-based
    yazi
    ranger
    lf

    # GUI
    xfce.thunar        # Lightweight GTK file manager (popular for i3)
    xfce.thunar-volman # Thunar volume manager
    xfce.thunar-archive-plugin # Archive support for Thunar
    arandr             # GUI for xrandr (display configuration)
  ];

  # Git tools (from nixpkgs, no custom builds)
  gitTools = with pkgs; [
    git-lfs
    git-crypt
    delta
    diff-so-fancy
    lazygit
    gittyup # GUI git client (Qt-based, lightweight alternative to GitKraken)
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    gitkraken # Git GUI client (x86_64 only)
  ];

  # Kubernetes and cloud tools
  kubernetesTools = with pkgs; [
    kubectl # Kubernetes CLI
    kubernetes-helm # Helm package manager for Kubernetes
    k9s # Terminal UI for Kubernetes
    talosctl # CLI for Talos Linux Kubernetes OS
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
  ai = aiTools;

  # Common package sets
  essential = terminalTools ++ shellTools ++ nixTools ++ [
    # vim handled by programs.vim
    pkgs.git-lfs
    pkgs.tldr
    pkgs.yazi # Terminal file manager
    pkgs.yarn # JavaScript package manager
  ];

  development = terminalTools ++ shellTools ++ editors ++
    languageServers ++ packageManagers ++ gitTools ++ kubernetesTools ++ cloudTools ++ nixTools ++ aiTools;

  # All user packages
  all = terminalTools ++ shellTools ++ editors ++
    languageServers ++ packageManagers ++ fileManagers ++
    gitTools ++ kubernetesTools ++ cloudTools ++ documentation ++ nixTools ++ aiTools;

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

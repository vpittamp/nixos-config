# System-level packages that require root/build permissions
# These packages contain custom derivations, chmod operations, or other
# operations that fail in restricted container environments
{ pkgs, lib, ... }:

let
  # Custom binary packages that need chmod +x
  idpbuilder = pkgs.callPackage ../packages/idpbuilder.nix { };
  
  vscode-cli = pkgs.callPackage ../packages/vscode-cli.nix { };
  
  azure-cli-bin = pkgs.callPackage ../packages/azure-cli-bin.nix { };
  
  claude-manager = pkgs.callPackage ../packages/claude-manager-fetchurl.nix { 
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  
  # Sesh session manager - custom binary
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

  # Custom tmux plugins that need build operations
  tmux-mode-indicator = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-mode-indicator";
    version = "unstable-2024-01-01";
    rtpFilePath = "mode_indicator.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "MunifTanjim";
      repo = "tmux-mode-indicator";
      rev = "11520829210a34dc9c7e5be9dead152eaf3a4423";
      sha256 = "sha256-hlhBKC6UzkpUrCanJehs2FxK5SoYBoiGiioXdx6trC4=";
    };
  };

  tmux-sessionx = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-sessionx";
    version = "unstable-2024-12-01";
    rtpFilePath = "sessionx.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "omerxx";
      repo = "tmux-sessionx";
      rev = "main";
      sha256 = "0yfxinx6bdddila3svszpky9776afjprn26c8agj6sqh8glhiz3b";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      substituteInPlace $out/share/tmux-plugins/tmux-sessionx/sessionx.tmux \
        --replace "fzf-tmux" "${pkgs.fzf}/bin/fzf-tmux" \
        --replace "fzf " "${pkgs.fzf}/bin/fzf "
    '';
  };

  # Custom vim plugins that need build operations
  claudecode-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "claudecode-nvim";
    version = "unstable-2024-01-01";
    src = pkgs.fetchFromGitHub {
      owner = "deanrumsby";
      repo = "claudecode.nvim";
      rev = "main";
      sha256 = "sha256-d+eZn2j3xGuiY0QK4Dh5UIrczPLDhwSqQ5uD5fYrqhE=";
    };
  };

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
    
    # WSL integration
    wslu
    wl-clipboard
    
    # Nix tools
    nix
    cachix
  ];

  # Development tools that work better at system level
  developmentTools = with pkgs; [
    # Container tools
    docker-compose
    devpod
    devcontainer
    devspace
    
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
  custom = [
    idpbuilder
    vscode-cli
    azure-cli-bin
    claude-manager
    sesh
  ];
  
  tmuxPlugins = [
    tmux-mode-indicator
    tmux-sessionx
  ];
  
  vimPlugins = [
    claudecode-nvim
  ];
  
  system = systemTools;
  development = developmentTools;
  kubernetes = kubernetesTools;
  
  # All system packages
  all = systemTools ++ developmentTools ++ kubernetesTools ++ [
    idpbuilder
    vscode-cli
    azure-cli-bin
    claude-manager
    sesh
  ];
  
  # Essential system packages only
  essential = systemTools ++ [
    vscode-cli
    sesh
    claude-manager
  ] ++ (with pkgs; [
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
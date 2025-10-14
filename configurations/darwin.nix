# NixOS-style system configuration for macOS via nix-darwin
#
# This configuration replaces standalone home-manager with integrated
# nix-darwin + home-manager, enabling:
# - System-level package management
# - Declarative macOS system preferences
# - Unified rebuild workflow (darwin-rebuild switch)
#
# Usage:
#   darwin-rebuild switch --flake .#darwin
#
# See also:
#   - CLAUDE.md: Darwin-specific commands and troubleshooting
#   - docs/DARWIN_SETUP.md: Setup guide (if exists)
#   - quickstart.md: User-facing quick start

{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # SYSTEM IDENTIFICATION
  # ============================================================================

  # Darwin state version - used for maintaining compatibility
  # Don't change this unless you know what you're doing
  system.stateVersion = 4;

  # System identification (appears in network and system dialogs)
  networking = {
    computerName = "MacBook Pro";
    hostName = "macbook-pro";
    localHostName = "macbook-pro";
  };

  # Primary user for system defaults
  # Required for nix-darwin to apply user-specific system preferences
  system.primaryUser = "vinodpittampalli";

  # ============================================================================
  # NIX CONFIGURATION
  # ============================================================================

  # Disable nix-darwin's Nix management - we're using Determinate Nix
  # Determinate Nix manages its own daemon and configuration
  nix.enable = false;

  # Note: The following nix.* settings are managed by Determinate Nix, not nix-darwin
  # You can configure them in /etc/nix/nix.conf or via Determinate's tools
  /*
  nix = {
    # Nix daemon settings
    settings = {
      # Enable experimental features (flakes and nix-command)
      experimental-features = [ "nix-command" "flakes" ];

      # Trust users (allows these users to use additional substituters)
      trusted-users = [ "vinodpittampalli" "@admin" ];

      # Binary caches for faster builds
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    # Automatic garbage collection
    # Runs weekly to clean up old generations and unused packages
    gc = {
      automatic = true;
      interval = {
        # launchd schedule: Run every Sunday at 3:00 AM
        Weekday = 0;
        Hour = 3;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };

    # Store optimization (deduplicate identical files)
    # Replaces deprecated nix.settings.auto-optimise-store
    optimise.automatic = true;
  };
  */

  # ============================================================================
  # NIXPKGS CONFIGURATION
  # ============================================================================

  nixpkgs = {
    # Allow unfree packages (required for many development tools)
    config.allowUnfree = true;

    # Host platform is automatically set from the system attribute in flake.nix
    # No need to explicitly set hostPlatform here
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================
  #
  # System packages are installed in /run/current-system/sw/bin
  # and are available to all users system-wide.
  #
  # Strategy:
  # - System level: Core CLI tools, compilers, dev tools needed everywhere
  # - User level (home-manager): User-specific tools, shell enhancements, editor plugins

  environment.systemPackages = with pkgs; [
    # Core utilities
    git
    vim
    neovim
    wget
    curl
    htop
    tmux
    tree

    # Enhanced utilities
    ripgrep        # Fast grep alternative
    fd             # Fast find alternative
    ncdu           # Disk usage analyzer
    rsync          # File synchronization
    openssl        # Cryptography library
    jq             # JSON processor
    yq-go          # YAML processor

    # Nix tools
    nix-prefetch-git
    nixpkgs-fmt

    # ============================================================================
    # DEVELOPMENT TOOLS (Phase 6)
    # ============================================================================

    # Compilers and language runtimes
    nodejs         # Node.js runtime
    python3        # Python 3
    go             # Go compiler
    rustc          # Rust compiler
    cargo          # Rust package manager

    # Build tools
    gcc            # GNU C compiler
    gnumake        # GNU Make
    cmake          # Cross-platform build system
    pkg-config     # Package configuration tool

    # Container tools
    # Note: Docker Desktop must be installed separately on macOS
    # Docker Desktop provides the docker CLI and daemon
    # See: https://docs.docker.com/desktop/install/mac-install/
    docker-compose # Docker Compose for multi-container applications

    # Kubernetes tools
    kubectl              # Kubernetes CLI
    kubernetes-helm      # Helm package manager for Kubernetes
    k9s                  # Terminal UI for Kubernetes
    kind                 # Kubernetes in Docker (local clusters)
    argocd               # GitOps continuous delivery

    # Cloud CLIs
    terraform            # Infrastructure as Code
    google-cloud-sdk     # Google Cloud Platform CLI
    hcloud               # Hetzner Cloud CLI
  ];

  # ============================================================================
  # SHELL CONFIGURATION
  # ============================================================================

  # Enable bash (macOS default is bash 3.2, Nix provides 5.x)
  programs.bash.enable = true;

  # ============================================================================
  # SSH CONFIGURATION
  # ============================================================================

  # SSH configuration with 1Password integration
  # Note: nix-darwin doesn't have programs.ssh.enable, use programs.ssh.extraConfig instead
  # The SSH agent socket path is set in home-manager (onepassword-env.nix)
  programs.ssh = {
    extraConfig = ''
      # 1Password SSH Agent Integration (macOS)
      # The agent socket is available at: ~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock
      # SSH_AUTH_SOCK is set in home-manager sessionVariables

      Host *
        # Use 1Password SSH agent for all connections
        # Note: IdentityAgent is set in home-manager's SSH config (home-modules/tools/ssh.nix)
        # to handle platform-specific paths (Linux vs Darwin)

        # Only use explicitly configured SSH keys (prevents trying all keys)
        IdentitiesOnly yes

        # Prefer public key authentication
        PreferredAuthentications publickey,keyboard-interactive,password

        # Keep connections alive
        ServerAliveInterval 60
        ServerAliveCountMax 3
    '';
  };

  # ============================================================================
  # FONTS
  # ============================================================================

  # System fonts (matching NixOS base.nix where applicable)
  # macOS font management uses fonts.packages
  # Note: nerdfonts has been split into individual packages under nerd-fonts namespace
  fonts.packages = with pkgs.nerd-fonts; [
    # Nerd Fonts for terminal and editor
    fira-code
    jetbrains-mono
    hack
    sauce-code-pro  # SourceCodePro is called sauce-code-pro in nerd-fonts
  ];

  # ============================================================================
  # MACOS SYSTEM DEFAULTS
  # ============================================================================
  #
  # These settings are applied via `defaults write` during activation.
  # Most take effect immediately; some require logout or restart.
  # See: https://macos-defaults.com/ for more options

  system.defaults = {
    # Dock configuration
    dock = {
      # Auto-hide dock for more screen space
      autohide = lib.mkDefault true;

      # Dock position
      orientation = lib.mkDefault "bottom";

      # Hide recent applications section
      show-recents = lib.mkDefault false;

      # Icon size (pixels)
      tilesize = lib.mkDefault 48;
    };

    # Finder configuration
    finder = {
      # Show all file extensions
      AppleShowAllExtensions = lib.mkDefault true;

      # Disable extension change warning
      FXEnableExtensionChangeWarning = lib.mkDefault false;

      # Show POSIX path in window title
      _FXShowPosixPathInTitle = lib.mkDefault true;
    };

    # Trackpad configuration
    trackpad = {
      # Enable tap to click
      Clicking = lib.mkDefault true;

      # Enable right-click
      TrackpadRightClick = lib.mkDefault true;

      # Disable three-finger drag (optional)
      TrackpadThreeFingerDrag = lib.mkDefault false;
    };

    # Global macOS preferences
    NSGlobalDomain = {
      # Full keyboard control (tab through all controls)
      AppleKeyboardUIMode = lib.mkDefault 3;

      # Disable press-and-hold for key repeat
      ApplePressAndHoldEnabled = lib.mkDefault false;

      # Fast key repeat settings
      InitialKeyRepeat = lib.mkDefault 15;  # 225ms
      KeyRepeat = lib.mkDefault 2;          # 30ms

      # Disable auto-capitalization
      NSAutomaticCapitalizationEnabled = lib.mkDefault false;

      # Disable auto-correct
      NSAutomaticSpellingCorrectionEnabled = lib.mkDefault false;

      # Enable tap to click system-wide
      "com.apple.mouse.tapBehavior" = lib.mkDefault 1;
    };
  };

  # ============================================================================
  # SECURITY CONFIGURATION
  # ============================================================================

  # Disable password requirement for sudo (convenient for development)
  # Note: This is less secure than TouchID but convenient for automation
  security.sudo = {
    extraConfig = ''
      # Allow vinodpittampalli to run sudo without password
      vinodpittampalli ALL=(ALL) NOPASSWD: ALL
    '';
  };

  # TouchID for sudo authentication (disabled in favor of NOPASSWD above)
  # security.pam.enableSudoTouchIdAuth = true;

  # ============================================================================
  # SERVICES
  # ============================================================================

  # Nix daemon is now managed automatically by nix-darwin when nix.enable is on
  # No need to explicitly enable services.nix-daemon
}

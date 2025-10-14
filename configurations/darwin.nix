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

  # ============================================================================
  # NIX CONFIGURATION
  # ============================================================================

  nix = {
    # Nix daemon settings
    settings = {
      # Enable experimental features (flakes and nix-command)
      experimental-features = [ "nix-command" "flakes" ];

      # Trust users (allows these users to use additional substituters)
      trusted-users = [ "vinodpittampalli" "@admin" ];

      # Auto-optimize store (deduplicate identical files)
      auto-optimise-store = true;

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
  };

  # ============================================================================
  # NIXPKGS CONFIGURATION
  # ============================================================================

  nixpkgs = {
    # Allow unfree packages (required for many development tools)
    config.allowUnfree = true;

    # Host platform (auto-detected: aarch64-darwin or x86_64-darwin)
    hostPlatform = builtins.currentSystem;
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

    # Development tools will be added in later phases
  ];

  # ============================================================================
  # SHELL CONFIGURATION
  # ============================================================================

  # Enable bash (macOS default is bash 3.2, Nix provides 5.x)
  programs.bash.enable = true;

  # SSH configuration
  programs.ssh = {
    # macOS uses different known_hosts and config locations
    # Additional SSH config will be added in Phase 5 for 1Password integration
    enable = true;
  };

  # ============================================================================
  # FONTS
  # ============================================================================

  # System fonts (matching NixOS base.nix where applicable)
  # macOS font management uses fonts.packages
  fonts.packages = with pkgs; [
    # Nerd Fonts for terminal and editor
    (nerdfonts.override {
      fonts = [
        "FiraCode"
        "JetBrainsMono"
        "Hack"
        "SourceCodePro"
      ];
    })
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
  # SERVICES
  # ============================================================================

  # Nix daemon (required - manages Nix store and builds)
  services.nix-daemon.enable = true;

  # ============================================================================
  # SYSTEM ACTIVATION
  # ============================================================================

  # System activation scripts (if needed)
  # These run during `darwin-rebuild switch`
  system.activationScripts.postUserActivation.text = ''
    # Following line should allow us to avoid a logout/login cycle
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}

# Data Model: Nix-Darwin Configuration

**Feature**: Migrate Darwin Home-Manager to Nix-Darwin
**Date**: 2025-10-13
**Status**: Complete

## Overview

This document describes the configuration entities and their relationships for the nix-darwin system. Unlike traditional data models, this describes the declarative configuration structure used by Nix to define system state.

## Configuration Entities

### 1. Darwin System Configuration

**Purpose**: Top-level system configuration managed by nix-darwin

**Location**: `configurations/darwin.nix`

**Key Attributes**:
```nix
{
  # System identification
  system.stateVersion: Integer (4)
  networking.computerName: String
  networking.hostName: String
  networking.localHostName: String

  # Build metadata
  system.configurationRevision: String (git commit)

  # Nix configuration
  nix.settings: AttributeSet {
    experimental-features: List<String>
    trusted-users: List<String>
    auto-optimise-store: Boolean
    substituters: List<String>
    trusted-public-keys: List<String>
  }

  # Garbage collection
  nix.gc: AttributeSet {
    automatic: Boolean
    interval: AttributeSet (launchd schedule)
    options: String (CLI flags)
  }

  # Package management
  nixpkgs.config.allowUnfree: Boolean
  nixpkgs.hostPlatform: String ("aarch64-darwin" | "x86_64-darwin")

  # System packages
  environment.systemPackages: List<Derivation>
  environment.systemPath: List<String> (paths to add to PATH)

  # Shell configuration
  programs.bash.enable: Boolean
  programs.zsh.enable: Boolean

  # SSH configuration
  programs.ssh.extraConfig: String

  # Font configuration
  fonts.packages: List<Derivation>

  # macOS system preferences
  system.defaults: AttributeSet (see MacOS Defaults entity)

  # Services
  services: AttributeSet (see Services entity)
}
```

**Relationships**:
- Contains → MacOS Defaults (1:1)
- Contains → System Packages (1:N)
- Contains → Darwin Services (1:N)
- Imports → Home Manager Module (1:1)

**Validation Rules**:
- `system.stateVersion` must be valid Darwin state version (typically 4)
- `nixpkgs.hostPlatform` must match actual system architecture
- All packages in `environment.systemPackages` must be available on Darwin
- `networking.computerName` should be human-readable

### 2. MacOS System Defaults

**Purpose**: Declarative macOS system preferences (via `defaults write`)

**Location**: `system.defaults` attribute in darwin configuration

**Key Attributes**:
```nix
{
  # Dock configuration
  dock: AttributeSet {
    autohide: Boolean
    autohide-delay: Float (seconds)
    autohide-time-modifier: Float (animation speed)
    orientation: Enum("left" | "right" | "bottom")
    show-recents: Boolean
    tilesize: Integer (pixels)
    minimize-to-application: Boolean
    show-process-indicators: Boolean
    launchanim: Boolean
    expose-animation-duration: Float
    dashboard-in-overlay: Boolean
    mru-spaces: Boolean (arrange spaces by most recently used)
    wvous-*: String (hot corners)
  }

  # Finder configuration
  finder: AttributeSet {
    AppleShowAllExtensions: Boolean
    AppleShowAllFiles: Boolean
    FXEnableExtensionChangeWarning: Boolean
    FXPreferredViewStyle: Enum("icnv" | "Nlsv" | "clmv" | "Flwv")
    QuitMenuItem: Boolean
    ShowPathbar: Boolean
    ShowStatusBar: Boolean
    _FXShowPosixPathInTitle: Boolean
    FXDefaultSearchScope: Enum("SCev" | "SCcf" | "SCsp")
  }

  # Trackpad configuration
  trackpad: AttributeSet {
    Clicking: Boolean (tap to click)
    TrackpadRightClick: Boolean
    TrackpadThreeFingerDrag: Boolean
  }

  # Keyboard and input
  NSGlobalDomain: AttributeSet {
    AppleKeyboardUIMode: Integer (3 = full keyboard control)
    ApplePressAndHoldEnabled: Boolean (false = key repeat)
    InitialKeyRepeat: Integer (15 = 225ms)
    KeyRepeat: Integer (2 = 30ms)
    NSAutomaticCapitalizationEnabled: Boolean
    NSAutomaticDashSubstitutionEnabled: Boolean
    NSAutomaticPeriodSubstitutionEnabled: Boolean
    NSAutomaticQuoteSubstitutionEnabled: Boolean
    NSAutomaticSpellingCorrectionEnabled: Boolean
    NSNavPanelExpandedStateForSaveMode: Boolean
    NSTableViewDefaultSizeMode: Integer (1-3)
    "com.apple.mouse.tapBehavior": Integer (1 = tap to click)
    "com.apple.sound.beep.feedback": Integer (0 = disable)
    "com.apple.swipescrolldirection": Boolean (true = natural scrolling)
  }

  # Screen capture
  screencapture: AttributeSet {
    location: String (path)
    type: Enum("png" | "jpg" | "pdf")
    disable-shadow: Boolean
  }

  # Custom domain defaults
  CustomUserPreferences: AttributeSet<String, AttributeSet> {
    "com.apple.Terminal": { ... }
    "com.googlecode.iterm2": { ... }
    # Any app bundle identifier
  }
}
```

**Relationships**:
- Owned by → Darwin System Configuration (N:1)

**Validation Rules**:
- All boolean values must be explicitly true/false (not 0/1 for nix-darwin)
- Enum values must match macOS expected values exactly (case-sensitive)
- Paths in location fields should be absolute or use `~` for home directory
- Hot corner values (wvous-*) use specific integer codes (see Apple docs)

**State Transitions**:
- On `darwin-rebuild switch`: Writes all defaults to macOS preferences system
- Changes take effect: Immediately (most), after logout (some), after restart (rare)
- Rollback: Previous defaults not automatically restored (manual or via generation rollback)

### 3. Home Manager Configuration

**Purpose**: User-level dotfiles and package management

**Location**: `home-manager.users.vinodpittampalli` attribute in darwin configuration

**Key Attributes**:
```nix
{
  # Import user profile
  imports: List<Path> (includes home-darwin.nix)

  # Home Manager settings
  home.stateVersion: String ("25.05")
  home.enableNixpkgsReleaseCheck: Boolean

  # User packages
  home.packages: List<Derivation>

  # Session variables
  home.sessionVariables: AttributeSet<String, String>

  # User programs (configured via programs.*)
  programs: AttributeSet {
    bash: AttributeSet (see home-modules/shell/bash.nix)
    tmux: AttributeSet (see home-modules/terminal/tmux.nix)
    neovim: AttributeSet (see home-modules/editors/neovim.nix)
    git: AttributeSet (see home-modules/tools/git.nix)
    # ... all other home-manager programs
  }

  # XDG configuration (cross-platform)
  xdg.enable: Boolean
  xdg.configHome: String (default: ~/.config)
  xdg.dataHome: String (default: ~/.local/share)
  xdg.cacheHome: String (default: ~/.cache)
}
```

**Relationships**:
- Owned by → Darwin System Configuration (N:1)
- Contains → User Packages (1:N)
- Contains → Program Configurations (1:N)
- Uses → Darwin-Home Profile (1:1, via imports)

**Validation Rules**:
- `home.stateVersion` must match or be older than nix-darwin version
- All packages must be available on Darwin platform
- Session variables must not conflict with system environment variables
- Programs must have cross-platform support (no Linux-only programs)

### 4. Darwin Services

**Purpose**: System services managed by launchd (Darwin's init system)

**Location**: `services` attribute in darwin configuration

**Key Attributes**:
```nix
{
  # Nix daemon (required)
  nix-daemon.enable: Boolean (default: true)

  # Lorri (optional build tool)
  lorri.enable: Boolean

  # Chunkwm (tiling window manager, optional)
  chunkwm.enable: Boolean

  # Khd (keyboard daemon, optional)
  khd.enable: Boolean

  # Custom launchd agents/daemons
  launchd.user.agents: AttributeSet<String, AttributeSet> {
    "<service-name>": {
      serviceConfig: AttributeSet {
        ProgramArguments: List<String>
        RunAtLoad: Boolean
        KeepAlive: Boolean | AttributeSet
        StandardOutPath: String
        StandardErrorPath: String
        EnvironmentVariables: AttributeSet<String, String>
      }
    }
  }
}
```

**Relationships**:
- Owned by → Darwin System Configuration (N:1)

**Validation Rules**:
- Service names must be valid reverse-domain notation (e.g., com.example.service)
- ProgramArguments[0] must be absolute path to executable
- Paths in StandardOutPath/StandardErrorPath must be writable
- KeepAlive with conditions must use valid keys (SuccessfulExit, NetworkState, etc.)

### 5. System Packages

**Purpose**: Packages installed system-wide and available in all contexts

**Location**: `environment.systemPackages` list

**Key Attributes**:
```nix
Derivation {
  name: String (package-version)
  pname: String (package name)
  version: String
  system: String ("aarch64-darwin" | "x86_64-darwin")
  meta: AttributeSet {
    available: Boolean (true on Darwin)
    broken: Boolean
    platforms: List<String>
    description: String
  }
  # ... other derivation attributes
}
```

**Relationships**:
- Owned by → Darwin System Configuration (N:1)
- Used by → All system users and contexts

**Validation Rules**:
- Must be available on Darwin platform (meta.platforms includes *-darwin)
- Must not be marked as broken on Darwin
- Should not conflict with macOS system tools (e.g., avoid GNU coreutils by default)

**Categories**:
- Core utilities (git, vim, wget, curl, htop, tmux, tree, ripgrep, fd, ncdu, rsync, openssl, jq)
- Nix tools (nix-prefetch-git, nixpkgs-fmt)
- Development tools (compilers, build tools, language runtimes)
- Cloud tools (terraform, kubectl, helm, cloud CLIs)

### 6. User Packages

**Purpose**: Packages installed in user profile via home-manager

**Location**: `home-manager.users.vinodpittampalli.home.packages` list

**Key Attributes**: Same as System Packages

**Relationships**:
- Owned by → Home Manager Configuration (N:1)
- Used by → Specific user only

**Categories**:
- Shell enhancements (bat, eza, fzf, zoxide, starship)
- Editor plugins and LSPs
- Language-specific tools
- Personal utilities

## Configuration Flow

```
1. User runs: darwin-rebuild switch --flake .#darwin
                    ↓
2. Nix evaluates: flake.nix → darwinConfigurations.darwin
                    ↓
3. Loads modules: configurations/darwin.nix
                  modules/darwin/*.nix (if created)
                  home-manager.darwinModules.home-manager
                    ↓
4. Evaluates: System packages, macOS defaults, services
                    ↓
5. Activates:
   - Switches system profile → /run/current-system
   - Writes macOS defaults → ~/Library/Preferences/
   - Activates launchd services
   - Runs home-manager activation
                    ↓
6. Home-manager:
   - Switches user profile → ~/.nix-profile
   - Creates dotfile symlinks → ~/
   - Runs activation scripts
```

## Rollback Flow

```
1. User runs: darwin-rebuild rollback
   OR:        darwin-rebuild switch --rollback
   OR:        sudo nix-env --profile /nix/var/nix/profiles/system --rollback
                    ↓
2. Switches system profile to previous generation
                    ↓
3. Activates previous configuration (system + home-manager)
                    ↓
4. Restores previous packages and defaults
```

## File System Impact

### System Profile

```
/nix/var/nix/profiles/system → /nix/store/<hash>-darwin-system-<version>
  ├── activate                 # Activation script
  ├── sw/                      # System packages
  │   ├── bin/                 # Executables
  │   ├── lib/                 # Libraries
  │   ├── share/               # Data files
  │   └── Applications/        # macOS app bundles (if any)
  └── Library/
      └── LaunchDaemons/       # System services
```

### User Profile

```
~/.nix-profile → /nix/store/<hash>-home-manager-path
  ├── bin/                     # User executables
  ├── lib/                     # User libraries
  └── share/                   # User data files

~/.config/                     # XDG config (managed by home-manager)
~/.local/share/                # XDG data
~/.cache/                      # XDG cache
```

### macOS Preferences

```
~/Library/Preferences/
  ├── .GlobalPreferences.plist           # NSGlobalDomain
  ├── com.apple.dock.plist               # Dock preferences
  ├── com.apple.finder.plist             # Finder preferences
  ├── com.apple.trackpad.plist           # Trackpad preferences
  └── ...                                # Other app preferences
```

## Dependencies

### External Dependencies

- **Nix Package Manager**: 2.18+ with flakes enabled
- **macOS**: 12.0 (Monterey) or newer
- **XCode Command Line Tools**: Required for native builds
- **1Password GUI**: Separate installation for SSH agent functionality
- **Docker Desktop**: Separate installation for Docker daemon

### Nix Dependencies

- **nixpkgs**: Provides packages for Darwin
- **nix-darwin**: System configuration framework
- **home-manager**: User configuration framework
- **nix-darwin.darwinModules.simple**: Base nix-darwin module
- **home-manager.darwinModules.home-manager**: Home-manager integration module

## Cross-Platform Considerations

### Platform-Specific Attributes

Use `pkgs.stdenv.isDarwin` for conditional configuration:

```nix
environment.systemPackages = with pkgs; [
  # Always include
  git
  vim
] ++ lib.optionals (!stdenv.isDarwin) [
  # Linux-only
  qemu
  libvirt
] ++ lib.optionals stdenv.isDarwin [
  # macOS-only
  # (most packages work on both, so this is rare)
];
```

### Path Differences

| Purpose | Linux (NixOS) | macOS (nix-darwin) |
|---------|---------------|---------------------|
| System profile | /run/current-system | /run/current-system |
| System packages | /run/current-system/sw | /run/current-system/sw |
| User profile | ~/.nix-profile | ~/.nix-profile |
| Home config | ~/.config | ~/.config |
| Nix store | /nix/store | /nix/store |
| Nix profiles | /nix/var/nix/profiles | /nix/var/nix/profiles |
| 1Password SSH socket | ~/.1password/agent.sock | ~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock |
| Preferences | /etc/ (NixOS options) | ~/Library/Preferences/*.plist |

## Notes

- This configuration is declarative: state is derived from configuration files, not built up imperatively
- All changes should be made by editing .nix files and running darwin-rebuild
- Manual changes to ~/.config or ~/Library/Preferences may be overwritten by home-manager or nix-darwin
- The system respects the principle of least surprise: defaults should match existing macOS behavior unless explicitly configured otherwise

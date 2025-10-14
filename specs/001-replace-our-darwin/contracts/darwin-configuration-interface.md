# Contract: Darwin Configuration Interface

**Feature**: Migrate Darwin Home-Manager to Nix-Darwin
**Date**: 2025-10-13
**Type**: Configuration Interface
**Version**: 1.0.0

## Overview

This contract defines the interface between the nix-darwin system configuration and the flake.nix outputs. It specifies the expected structure, required attributes, and integration points.

## Flake Output Contract

### darwinConfigurations.darwin

**Type**: DarwinSystem

**Required Attributes**:
```nix
{
  # System architecture
  system: "aarch64-darwin" | "x86_64-darwin";

  # Configuration modules
  modules: List<Path | AttrSet>;

  # Special arguments passed to modules
  specialArgs: {
    inputs: FlakeInputs;
  };
}
```

**Builder Function**: `nix-darwin.lib.darwinSystem`

**Example**:
```nix
darwinConfigurations.darwin = nix-darwin.lib.darwinSystem {
  system = builtins.currentSystem or "aarch64-darwin";
  modules = [
    ./configurations/darwin.nix
    home-manager.darwinModules.home-manager
  ];
  specialArgs = { inherit inputs; };
};
```

## System Configuration Module Contract

### configurations/darwin.nix

**Type**: NixOS Module (Darwin variant)

**Required Top-Level Attributes**:

```nix
{
  # System state version (REQUIRED)
  system.stateVersion: Integer (4);

  # Nix configuration (REQUIRED)
  nix.settings.experimental-features: List<String> (must include ["nix-command" "flakes"]);

  # Package configuration (REQUIRED)
  nixpkgs.config.allowUnfree: Boolean;
  nixpkgs.hostPlatform: String (must match system);

  # Home-manager integration (REQUIRED)
  home-manager: {
    useGlobalPkgs: Boolean (true);
    useUserPackages: Boolean (true);
    backupFileExtension: String ("backup");
    extraSpecialArgs: AttributeSet;
    users.<username>: {
      imports: List<Path>;
      home.stateVersion: String;
    };
  };
}
```

**Optional Attributes**:

```nix
{
  # System identification
  networking.computerName: String;
  networking.hostName: String;
  networking.localHostName: String;

  # Build metadata
  system.configurationRevision: String;

  # Garbage collection
  nix.gc: {
    automatic: Boolean;
    interval: { ... };
    options: String;
  };

  # System packages
  environment.systemPackages: List<Derivation>;
  environment.systemPath: List<String>;

  # Shell configuration
  programs.bash.enable: Boolean;
  programs.zsh.enable: Boolean;

  # SSH configuration
  programs.ssh.extraConfig: String;

  # Font configuration
  fonts.packages: List<Derivation>;

  # macOS system preferences
  system.defaults: AttributeSet;

  # Services
  services: AttributeSet;
}
```

## Home-Manager Integration Contract

### home-manager.users.<username>

**Type**: Home-Manager Configuration Module

**Required Attributes**:

```nix
{
  # Import existing profile
  imports: [./home-darwin.nix];

  # State version
  home.stateVersion: String ("25.05");
  home.enableNixpkgsReleaseCheck: Boolean (false);
}
```

**Expected from home-darwin.nix**:

```nix
{
  imports: [
    ./home-modules/profiles/darwin-home.nix
  ];

  home.username: String;
  home.homeDirectory: String;
  programs.home-manager.enable: Boolean (true);
}
```

## System Defaults Contract

### system.defaults

**Type**: AttributeSet

**Optional Attributes** (all optional, but typed when present):

```nix
{
  dock: {
    autohide: Boolean;
    orientation: "left" | "right" | "bottom";
    show-recents: Boolean;
    tilesize: Integer (16-256);
  };

  finder: {
    AppleShowAllExtensions: Boolean;
    FXEnableExtensionChangeWarning: Boolean;
    _FXShowPosixPathInTitle: Boolean;
  };

  trackpad: {
    Clicking: Boolean;
    TrackpadRightClick: Boolean;
    TrackpadThreeFingerDrag: Boolean;
  };

  NSGlobalDomain: {
    AppleKeyboardUIMode: Integer (0-3);
    ApplePressAndHoldEnabled: Boolean;
    InitialKeyRepeat: Integer (15-120);
    KeyRepeat: Integer (2-120);
    NSAutomaticCapitalizationEnabled: Boolean;
    NSAutomaticSpellingCorrectionEnabled: Boolean;
    "com.apple.mouse.tapBehavior": Integer (0-1);
  };
}
```

## SSH Configuration Contract

### programs.ssh.extraConfig

**Type**: String (SSH config format)

**Required for 1Password Integration**:

```ssh-config
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  IdentitiesOnly yes
  PreferredAuthentications publickey
```

## Build Command Interface

### darwin-rebuild

**Required Commands**:

```bash
# Syntax check
darwin-rebuild check --flake .#darwin
Exit Code: 0 (success) | non-zero (error)
Output: Error messages if any

# Dry run
darwin-rebuild --dry-run switch --flake .#darwin
Exit Code: 0 (success) | non-zero (error)
Output: List of packages to be installed/removed

# Build without activation
darwin-rebuild build --flake .#darwin
Exit Code: 0 (success) | non-zero (error)
Output: Build log, result symlink created

# Apply configuration
darwin-rebuild switch --flake .#darwin
Exit Code: 0 (success) | non-zero (error)
Output: Activation log, generation number
Side Effects:
  - System profile switched
  - macOS defaults written
  - Services restarted
  - Home-manager activated

# Rollback
darwin-rebuild rollback
Exit Code: 0 (success) | non-zero (error)
Output: Previous generation activated
Side Effects: System reverted to previous state
```

## Environment Contract

### System Expectations

**Pre-conditions**:
- macOS 12.0 (Monterey) or newer
- Nix 2.18+ installed with flakes enabled
- User has sudo privileges
- XCode Command Line Tools installed
- Current working directory is repository root

**Post-conditions (after darwin-rebuild switch)**:
- `/run/current-system` points to new generation
- `~/.nix-profile` updated if home-manager changes
- macOS preferences applied
- Services started/restarted as needed
- User can immediately use new configuration

### PATH Management

**System Packages Available At**:
- `/run/current-system/sw/bin`
- Automatically added to PATH by nix-darwin

**User Packages Available At**:
- `~/.nix-profile/bin`
- Added to PATH by shell initialization

**Expected PATH Order**:
1. `~/.nix-profile/bin` (user packages)
2. `/run/current-system/sw/bin` (system packages)
3. `/usr/local/bin` (Homebrew, Docker Desktop)
4. `/usr/bin` (macOS system)
5. `/bin` (macOS core)

## Integration Points

### With Existing NixOS Configuration

**Shared Inputs** (from flake.nix):
- `nixpkgs`
- `home-manager`
- `onepassword-shell-plugins`

**Shared Modules** (unchanged):
- `home-modules/shell/*`
- `home-modules/terminal/*`
- `home-modules/editors/*`
- `home-modules/tools/*`
- `home-modules/ai-assistants/*`

**Shared Package Lists**:
- `shared/package-lists.nix` (with platform filtering)

### With External Services

**1Password**:
- Input: 1Password GUI installed and configured
- Output: SSH agent socket available at macOS-specific path
- Interface: SSH config points to socket, environment variable set

**Docker Desktop**:
- Input: Docker Desktop installed and running
- Output: Docker socket available at `/var/run/docker.sock`
- Interface: docker-compose CLI available, shell integration configured

## Validation Contract

### Pre-Build Validation

**Check 1: System Architecture**
```bash
Test: uname -m
Expected: "arm64" | "x86_64"
Match to: system attribute in darwinConfigurations
```

**Check 2: macOS Version**
```bash
Test: sw_vers -productVersion
Expected: >= 12.0
```

**Check 3: Nix Version**
```bash
Test: nix --version
Expected: >= 2.18
```

**Check 4: Flake Inputs**
```bash
Test: nix flake metadata
Expected: Valid flake.lock, no errors
```

### Post-Build Validation

**Check 1: System Profile**
```bash
Test: ls -l /run/current-system
Expected: Symlink to /nix/store/<hash>-darwin-system-<version>
```

**Check 2: System Packages**
```bash
Test: which git vim curl
Expected: Paths in /run/current-system/sw/bin
```

**Check 3: User Profile**
```bash
Test: ls -l ~/.nix-profile
Expected: Symlink to /nix/store/<hash>-home-manager-path
```

**Check 4: Shell Configuration**
```bash
Test: echo $SHELL
Expected: /bin/bash or ~/.nix-profile/bin/bash
```

**Check 5: macOS Defaults**
```bash
Test: defaults read com.apple.dock autohide
Expected: Value matches system.defaults.dock.autohide
```

## Error Handling Contract

### Build Errors

**Error Type**: Syntax Error
```
Exit Code: 1
Output Pattern: "error: syntax error, unexpected"
Recovery: Fix syntax in .nix file, retry build
```

**Error Type**: Missing Attribute
```
Exit Code: 1
Output Pattern: "error: attribute .* missing"
Recovery: Add required attribute, retry build
```

**Error Type**: Package Not Available on Darwin
```
Exit Code: 1
Output Pattern: "error: Package .* is not available on this system"
Recovery: Remove package or add platform check, retry build
```

### Activation Errors

**Error Type**: Permission Denied
```
Exit Code: 1
Output Pattern: "permission denied"
Recovery: Run with sudo, check file permissions
```

**Error Type**: Conflicting Files
```
Exit Code: 1
Output Pattern: "Existing file .* is in the way"
Recovery: Backup file, remove, retry; or use backupFileExtension
```

## Rollback Contract

**Trigger Conditions**:
- Build succeeds but activation fails
- User manually runs `darwin-rebuild rollback`
- System behavior undesirable after switch

**Rollback Process**:
1. Identify previous generation (`/nix/var/nix/profiles/system-*-link`)
2. Switch system profile to previous generation
3. Run activation script of previous generation
4. Restore previous macOS defaults (if changed)
5. Restart affected services

**Guarantees**:
- System state matches previous successful activation
- No data loss (user data unchanged)
- Services return to previous configuration
- Rollback can be performed multiple generations back

**Limitations**:
- macOS system preferences may not fully revert (some require logout)
- External state changes (file modifications outside Nix) not reverted
- Homebrew or manually installed software unaffected

## Version Compatibility

**Minimum Versions**:
- nix: 2.18.0
- nix-darwin: Latest from flake input (compatible with Nix 2.18+)
- home-manager: Latest from master branch
- macOS: 12.0 (Monterey)

**Maximum Versions**:
- macOS: 15.x (Sequoia) - tested
- Nix: 2.25.x - forward compatible

**Breaking Changes**:
- Major version changes in nix-darwin (rare, check changelog)
- macOS version transitions (test before upgrading)
- Nix 3.0 (when released) - may require flake.lock update

## Security Considerations

**Trusted Users**:
- System configuration requires sudo (admin privileges)
- Nix trusted users can modify system via Nix store

**File Permissions**:
- System configuration files: 644 (world-readable)
- User home files: 600-755 (user-restricted)
- SSH keys via 1Password: Never written to disk

**Secrets Management**:
- Secrets NOT stored in .nix files (public git repository)
- Use 1Password for SSH keys, API tokens
- Use environment variables for runtime secrets
- Consider agenix/sops-nix for deployment secrets (future enhancement)

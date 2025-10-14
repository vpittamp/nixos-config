# Research: Nix-Darwin Migration

**Feature**: Migrate Darwin Home-Manager to Nix-Darwin
**Date**: 2025-10-13
**Status**: Complete

## Research Questions

### Q1: What is the nix-darwin flake structure for system configuration?

**Decision**: Use `nix-darwin.lib.darwinSystem` function similar to `nixpkgs.lib.nixosSystem`

**Rationale**:
- nix-darwin provides a `darwinSystem` builder function that works analogously to NixOS's `nixosSystem`
- Takes similar arguments: `system`, `modules`, `specialArgs`
- Integrates seamlessly with flakes using the `nix-darwin.darwinModules.simple` module
- Follows the same modular composition pattern as the existing NixOS configurations

**Alternatives Considered**:
- **Standalone home-manager** (current approach): Lacks system-level configuration, requires manual PATH management, cannot set macOS defaults
- **Manual nix-darwin setup**: More complex, doesn't integrate with flake outputs cleanly
- **Home-manager + manual scripts**: Imperative, violates Declarative Configuration principle

**Example Structure**:
```nix
darwinConfigurations.darwin = nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";  # or x86_64-darwin
  modules = [
    ./configurations/darwin.nix
    home-manager.darwinModules.home-manager
  ];
  specialArgs = { inherit inputs; };
};
```

### Q2: How does nix-darwin integrate with home-manager?

**Decision**: Import `home-manager.darwinModules.home-manager` as a nix-darwin module

**Rationale**:
- home-manager provides a Darwin-specific module (`darwinModules.home-manager`)
- Integrates at the nix-darwin level (not as a standalone tool)
- Allows unified rebuild command: `darwin-rebuild switch --flake .#darwin`
- Shares the same `specialArgs` and `inputs` with the system configuration
- Maintains separation: system packages via `environment.systemPackages`, user packages via `home-manager.users.<username>`

**Best Practices**:
- System-level: Install packages that need to be in PATH for all users (git, vim, curl)
- User-level: Install user-specific tools and dotfiles (bash config, tmux, neovim plugins)
- Use `home-manager.useGlobalPkgs = true` to share nixpkgs evaluation
- Use `home-manager.useUserPackages = true` to install packages in user profile
- Set `home-manager.backupFileExtension = "backup"` to avoid conflicts

**Alternatives Considered**:
- **Separate home-manager invocation**: Requires two commands, loses system integration
- **home-manager as NixOS module approach**: Doesn't work on Darwin, needs Darwin-specific module

### Q3: What packages from base.nix can be installed on macOS?

**Decision**: Most packages available, exclude Linux-specific virtualization and display server packages

**Rationale**:
- Core utilities work: git, vim, wget, curl, htop, tmux, tree, ripgrep, fd, ncdu, rsync, openssl, jq
- Nerd Fonts work identically on macOS
- Nix tools work: nix-prefetch-git, nixpkgs-fmt, nh (though nh is NixOS-focused)
- Exclude: QEMU/KVM (Linux-only), X11/Wayland packages, systemd services

**macOS-specific considerations**:
- Use native BSD utilities where possible (ls, ps, etc.) unless GNU versions specifically needed
- macOS has its own font management - nix-darwin uses `fonts.packages`
- Some packages compile differently on Darwin (different dependencies)

**Package Categories**:
- ✅ **Core utilities**: All work (vim, git, wget, curl, htop, tmux, tree, ripgrep, fd, ncdu, rsync, openssl, jq)
- ✅ **Nix tools**: All work (nix-prefetch-git, nixpkgs-fmt, nh with caveats)
- ✅ **Fonts**: Nerd Fonts work with nix-darwin's font management
- ❌ **Virtualization**: QEMU, KVM (Linux kernel features)
- ❌ **Display servers**: X11, Wayland (macOS uses its own window server)
- ❌ **Systemd**: macOS uses launchd instead

### Q4: How does 1Password SSH agent configuration differ on macOS?

**Decision**: Use similar configuration with macOS-specific paths

**Rationale**:
- 1Password GUI on macOS stores socket at `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`
- SSH config must point to this Darwin-specific path (not `~/.1password/agent.sock` like Linux)
- Use `programs.ssh.extraConfig` in nix-darwin (same as NixOS)
- CLI authentication works identically with `op signin`
- Git signing configuration identical to NixOS

**macOS-specific paths**:
```bash
# SSH Agent Socket
~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock

# 1Password Config Directory
~/Library/Application Support/1Password

# 1Password CLI Config
~/.config/op/
```

**Configuration Pattern**:
```nix
programs.ssh.extraConfig = ''
  Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
'';
```

**Alternatives Considered**:
- **Manual SSH config**: Imperative, violates Declarative Configuration principle
- **Symlink to Linux path**: Fragile, doesn't work across macOS updates
- **Environment variable only**: Doesn't persist across all contexts (sudo, etc.)

### Q5: What macOS system defaults should be managed declaratively?

**Decision**: Configure dock, keyboard, trackpad, finder, and NSGlobalDomain preferences

**Rationale**:
- nix-darwin provides `system.defaults` options for common macOS preferences
- Matches philosophy of NixOS configuration (declarative system state)
- Most settings take effect immediately or on next login (no manual defaults write commands)
- Documented in nix-darwin manual: https://daiderd.com/nix-darwin/manual/index.html

**Recommended Settings** (based on NixOS KDE preferences):
```nix
system.defaults = {
  dock = {
    autohide = true;
    orientation = "bottom";
    show-recents = false;
    tilesize = 48;
  };

  finder = {
    AppleShowAllExtensions = true;
    FXEnableExtensionChangeWarning = false;
    _FXShowPosixPathInTitle = true;
  };

  trackpad = {
    Clicking = true;  # Tap to click
    TrackpadRightClick = true;
    TrackpadThreeFingerDrag = false;
  };

  NSGlobalDomain = {
    AppleKeyboardUIMode = 3;  # Full keyboard control
    ApplePressAndHoldEnabled = false;  # Key repeat
    InitialKeyRepeat = 15;
    KeyRepeat = 2;
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    "com.apple.mouse.tapBehavior" = 1;  # Tap to click
  };
};
```

**Alternatives Considered**:
- **Manual defaults write commands**: Imperative, hard to maintain, not reproducible
- **Scripted configuration**: Can run on every rebuild, slower, not idempotent
- **No system preferences**: User must manually configure, violates principle of declarative config

### Q6: What is the rebuild workflow for nix-darwin?

**Decision**: Use `darwin-rebuild switch --flake .#darwin` analogous to `nixos-rebuild`

**Rationale**:
- nix-darwin provides `darwin-rebuild` command (similar to `nixos-rebuild`)
- Supports same operations: `switch`, `build`, `check`, `dry-run`
- Works with flakes natively with `--flake` flag
- No dry-build equivalent but `--dry-run` shows what would change
- Generations managed at `/nix/var/nix/profiles/system` (different from NixOS `/run/current-system`)

**Build Commands**:
```bash
# Check configuration syntax
darwin-rebuild check --flake .#darwin

# Dry-run (show what would change)
darwin-rebuild --dry-run switch --flake .#darwin

# Apply configuration
darwin-rebuild switch --flake .#darwin

# Build without activating
darwin-rebuild build --flake .#darwin
```

**Rollback**:
```bash
# List generations
darwin-rebuild --list-generations

# Rollback to previous generation
darwin-rebuild rollback
```

**Testing Workflow** (adapted from constitution):
1. Check syntax: `darwin-rebuild check --flake .#darwin`
2. Dry-run: `darwin-rebuild --dry-run switch --flake .#darwin`
3. Build: `darwin-rebuild build --flake .#darwin` (test without activating)
4. Apply: `darwin-rebuild switch --flake .#darwin`

**Alternatives Considered**:
- **Direct nix build**: Doesn't activate system configuration
- **Manual profile switching**: Error-prone, loses generation tracking
- **nixos-rebuild on Darwin**: Doesn't exist, NixOS-specific

### Q7: How should development packages be organized between system and user level?

**Decision**: System packages for CLI tools needed globally, user packages for dev-specific tools

**Rationale**:
- System-level (`environment.systemPackages`): Available in `/run/current-system/sw/bin`, used by all contexts
- User-level (`home-manager.users.<username>.home.packages`): Available in user profile, user-specific
- Development tools split: compilers and languages at system level, language-specific tools at user level

**Distribution**:

**System Level** (environment.systemPackages):
- Core dev tools: git, gh, vim, neovim
- Compilers & runtimes: nodejs, python3, go, rustc, cargo
- Build tools: gcc, gnumake, cmake, pkg-config
- Container tools: docker-compose (Docker Desktop installed separately)
- Cloud CLIs: terraform, google-cloud-sdk, hcloud
- Kubernetes: kubectl, helm, k9s, kind, argocd

**User Level** (home-manager packages):
- Language-specific tools (npm packages, pip tools, cargo binaries)
- Editor plugins and configurations
- Shell enhancements (bat, eza, fzf, zoxide)
- Personal utilities and scripts

**Rationale for Split**:
- System tools need to be available in system contexts (before user login, in system services)
- User tools are user-preference driven (different users might want different versions)
- Matches NixOS pattern from base.nix and development.nix

**Alternatives Considered**:
- **Everything in home-manager**: Requires user login, not available in system contexts, PATH issues
- **Everything in system**: No per-user customization, bloated system profile
- **Mix arbitrarily**: Confusing, hard to maintain, violates Single Source of Truth

### Q8: How does Docker Desktop integration work on macOS?

**Decision**: Docker Desktop must be installed separately; nix-darwin only configures shell integration

**Rationale**:
- Docker Desktop for Mac is proprietary GUI application, not available in nixpkgs
- Installed via official DMG or Homebrew: `brew install --cask docker`
- Nix can provide: docker-compose CLI, docker CLI wrappers, shell completions
- Socket located at `/var/run/docker.sock` (managed by Docker Desktop)
- Similar to WSL approach: Docker Desktop provides daemon, Nix provides CLI tools

**Configuration**:
```nix
# In darwin configuration
environment.systemPackages = with pkgs; [
  docker-compose
  # Note: docker CLI comes from Docker Desktop, not Nix
];

# In home-manager
programs.bash.shellAliases = {
  d = "docker";
  dc = "docker-compose";
  dps = "docker ps";
};
```

**User Requirements**:
- Install Docker Desktop from https://www.docker.com/products/docker-desktop
- Or via Homebrew: `brew install --cask docker`
- Start Docker Desktop and allow it to create socket

**Alternatives Considered**:
- **OrbStack**: Modern Docker Desktop alternative, but not in scope (user choice)
- **Colima**: Open-source Docker runtime, but less tested than Docker Desktop
- **Podman**: Different tool, not Docker-compatible enough for general use

## Technology Decisions

### Primary Technologies

| Component | Technology | Version | Rationale |
|-----------|------------|---------|-----------|
| System Configuration | nix-darwin | Latest stable | Official macOS system configuration tool from Nix ecosystem |
| User Configuration | home-manager | Latest stable (master branch) | Proven user-level dotfile management, matches NixOS usage |
| Package Manager | Nix | 2.18+ | Already installed, flakes support required |
| Configuration Language | Nix Expression Language | N/A | Required for nix-darwin/home-manager |

### Architecture Pattern

- **Modular Composition**: Follow NixOS pattern of base + platform-specific modules
- **Flake-based**: Use flake outputs for `darwinConfigurations` (matches NixOS pattern)
- **Two-tier Package Management**: System packages + user packages via home-manager
- **Declarative Preferences**: Use `system.defaults` for macOS preferences

### File Structure

```
nixos-config/
├── flake.nix                           # Add darwinConfigurations output
├── configurations/
│   └── darwin.nix                      # New: nix-darwin system configuration
├── modules/
│   └── darwin/                         # New: Darwin-specific modules
│       ├── defaults.nix                # macOS system preferences
│       ├── packages.nix                # System-level packages
│       └── services.nix                # Darwin services (if needed)
└── home-darwin.nix                     # Existing: no changes needed
```

## Integration Points

### With Existing NixOS Configuration

- **Shared**: home-modules (bash, tmux, neovim, git, ssh, etc.)
- **Shared**: package-lists.nix profiles (with platform filtering)
- **Similar**: Modular architecture (base + modules)
- **Similar**: Flake outputs pattern

### With Current Darwin Home-Manager

- **Replace**: `homeConfigurations.darwin` with `darwinConfigurations.darwin`
- **Integrate**: Import home-darwin.nix as module within nix-darwin
- **Preserve**: All home-modules work unchanged
- **Add**: System-level package management

### With 1Password

- **System**: SSH config points to macOS-specific socket path
- **System**: Environment variables for SSH_AUTH_SOCK
- **User**: Git signing configuration (via home-manager)
- **User**: Shell integration (via home-manager)

## Performance Considerations

- **Build Time**: Expect 2-5 minutes for initial build (similar to NixOS)
- **Rebuild Time**: 30-60 seconds for incremental changes (cached dependencies)
- **Activation Time**: 5-10 seconds (faster than NixOS, fewer system services)
- **Store Size**: Expect 2-5 GB for full development environment

## Risk Mitigation

### Risk 1: Breaking Current Home-Manager Setup

**Mitigation**:
- Keep home-darwin.nix unchanged
- Test nix-darwin integration without removing old home-manager profile
- Rollback available via nix-darwin generations
- Document migration steps clearly

### Risk 2: macOS System Updates Breaking Configuration

**Mitigation**:
- Pin nix-darwin and home-manager versions in flake.lock
- Document macOS version compatibility (12.0+)
- Test on incremental macOS updates (15.0.1 → 15.1)
- Keep rollback generation available

### Risk 3: Package Availability Differences Between Linux and macOS

**Mitigation**:
- Use `pkgs.stdenv.isDarwin` checks for platform-specific packages
- Document macOS-specific package limitations
- Use fallbacks where needed (BSD vs GNU utilities)
- Test all critical workflows after migration

## References

- nix-darwin Manual: https://daiderd.com/nix-darwin/manual/index.html
- nix-darwin GitHub: https://github.com/LnL7/nix-darwin
- home-manager Darwin Module: https://nix-community.github.io/home-manager/index.xhtml#sec-install-nix-darwin-module
- Nix Darwin Options: https://daiderd.com/nix-darwin/manual/index.html#sec-options

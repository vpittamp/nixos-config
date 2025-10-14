# Feature Specification: Migrate Darwin Home-Manager to Nix-Darwin

**Feature Branch**: `001-replace-our-darwin`
**Created**: 2025-10-13
**Status**: Draft
**Input**: User description: "replace our darwin home-manager configuration with a nix-darwin configuration. review our full configuration to understand our base configurations for hetzner vm, m1, container config, etc. and then revise the nix-darwin config to match as closely as possible for applicable functionality on macos system"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - System-Level Package Management (Priority: P1)

As a macOS user, I want nix-darwin to manage system-level packages and services so that my development environment is consistent with my NixOS systems.

**Why this priority**: This is the foundation - without system-level management, the rest of the configuration cannot function properly. This enables declarative system configuration similar to NixOS.

**Independent Test**: Can be fully tested by running `darwin-rebuild switch --flake .#darwin` and verifying that core packages (git, vim, tmux, etc.) are available system-wide.

**Acceptance Scenarios**:

1. **Given** a fresh macOS system with Nix installed, **When** I run `darwin-rebuild switch --flake .#darwin`, **Then** core development tools are available system-wide
2. **Given** nix-darwin is configured, **When** I add a new package to the configuration, **Then** the package is installed on the next rebuild
3. **Given** nix-darwin is active, **When** I check system packages, **Then** they match the packages available on NixOS systems (where applicable)

---

### User Story 2 - Home-Manager Integration (Priority: P1)

As a macOS user, I want home-manager integrated with nix-darwin so that my user-level dotfiles and configurations work seamlessly.

**Why this priority**: Home-manager provides user-level configuration that complements system-level nix-darwin configuration. This maintains parity with the NixOS systems which use home-manager extensively.

**Independent Test**: Can be tested by verifying that bash, tmux, neovim, and other user-level configurations from home-modules work correctly after darwin-rebuild.

**Acceptance Scenarios**:

1. **Given** nix-darwin with home-manager, **When** I rebuild the system, **Then** my shell configurations (bash, starship) are applied
2. **Given** home-manager dotfiles, **When** I open a new terminal, **Then** my tmux and bash configurations are active
3. **Given** editor configurations, **When** I launch neovim, **Then** my plugins and settings from NixOS are present

---

### User Story 3 - 1Password Integration (Priority: P2)

As a macOS user, I want 1Password CLI and SSH agent configured so that I can access secrets and authenticate with SSH keys consistently across all systems.

**Why this priority**: 1Password is critical for development workflow (Git signing, SSH authentication, secret management), but the system can function without it initially.

**Independent Test**: Can be tested by running `op signin`, checking SSH authentication with `ssh -T git@github.com`, and verifying Git commit signing works.

**Acceptance Scenarios**:

1. **Given** 1Password is configured, **When** I run `op item list`, **Then** I can access my 1Password vaults
2. **Given** SSH agent is configured, **When** I attempt SSH authentication, **Then** 1Password prompts for key approval
3. **Given** Git signing is configured, **When** I commit code, **Then** commits are signed with my 1Password SSH key

---

### User Story 4 - Development Services (Priority: P2)

As a macOS user, I want Docker and other development services configured so that my development workflow matches my Linux systems.

**Why this priority**: Development services enable actual work but require the base system to be functional first.

**Independent Test**: Can be tested by running `docker ps`, verifying kubectl/k9s work, and testing local development workflows.

**Acceptance Scenarios**:

1. **Given** Docker Desktop is installed, **When** I run `docker ps`, **Then** Docker is accessible without sudo
2. **Given** Kubernetes tools are configured, **When** I run `kubectl version`, **Then** kubectl is available and configured
3. **Given** development tools are installed, **When** I check available commands, **Then** node, python, go, and rust are available

---

### User Story 5 - macOS System Preferences (Priority: P3)

As a macOS user, I want common macOS system preferences managed declaratively so that my system settings are reproducible.

**Why this priority**: System preferences enhance usability but aren't critical for development functionality. This is a nice-to-have for consistency.

**Independent Test**: Can be tested by verifying dock settings, keyboard preferences, and trackpad configurations are applied after rebuild.

**Acceptance Scenarios**:

1. **Given** dock preferences are configured, **When** I rebuild the system, **Then** dock settings match my NixOS KDE panel preferences
2. **Given** keyboard settings are configured, **When** I type, **Then** key repeat and modifier keys work as expected
3. **Given** trackpad settings are configured, **When** I use trackpad gestures, **Then** natural scrolling and tap-to-click work as configured

---

### Edge Cases

- What happens when nix-darwin conflicts with existing Homebrew installations?
- How does the system handle macOS-specific services that don't exist on Linux (e.g., launchd vs systemd)?
- What happens when packages available on NixOS don't have macOS equivalents?
- How does the system handle Apple Silicon (aarch64-darwin) vs Intel (x86_64-darwin) differences?
- What happens when upgrading macOS versions with an existing nix-darwin configuration?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a nix-darwin configuration that replaces the current home-manager-only Darwin setup
- **FR-002**: System MUST integrate home-manager as a module within nix-darwin (not standalone)
- **FR-003**: System MUST include core development packages matching those in base.nix (git, vim, curl, wget, etc.)
- **FR-004**: System MUST configure 1Password CLI and SSH agent integration for macOS
- **FR-005**: System MUST support both Apple Silicon (aarch64-darwin) and Intel (x86_64-darwin) architectures
- **FR-006**: System MUST configure Nix with flakes and experimental features enabled
- **FR-007**: System MUST import darwin-home.nix for user-level configurations
- **FR-008**: System MUST configure system fonts matching NixOS configuration (Nerd Fonts)
- **FR-009**: System MUST set up garbage collection for Nix store
- **FR-010**: System MUST configure SSH to use 1Password agent (matching onepassword.nix)
- **FR-011**: System MUST provide equivalent functionality to development.nix where applicable on macOS
- **FR-012**: System MUST use lib.mkDefault for overrideable settings to match NixOS convention
- **FR-013**: System MUST maintain compatibility with existing darwin-home.nix without requiring changes
- **FR-014**: System MUST configure PATH to include /run/current-system/sw/bin for system packages
- **FR-015**: System MUST enable macOS-specific integrations (dock, finder, keyboard, trackpad)

### Key Entities *(include if feature involves data)*

- **Darwin Configuration**: The nix-darwin system configuration (darwin-configuration.nix) that replaces the standalone home-manager setup
- **Home Manager Module**: The home-manager integration within nix-darwin that imports darwin-home.nix
- **System Packages**: Core packages installed system-wide via nix-darwin (equivalent to base.nix packages)
- **User Packages**: User-level packages managed by home-manager (from darwin-home.nix)
- **macOS Defaults**: System preferences managed declaratively via nix-darwin's `system.defaults` options

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can rebuild the Darwin system with `darwin-rebuild switch --flake .#darwin` successfully
- **SC-002**: All core development tools from base.nix are available system-wide after rebuild
- **SC-003**: User's bash, tmux, and neovim configurations work identically to the current home-manager-only setup
- **SC-004**: 1Password SSH agent authenticates successfully for Git and SSH operations
- **SC-005**: Docker commands work without requiring sudo (Docker Desktop integration)
- **SC-006**: System remains functional across macOS version upgrades
- **SC-007**: Rebuild time is comparable to current home-manager-only builds (within 20%)
- **SC-008**: All packages from current darwin-home.nix remain functional
- **SC-009**: User can switch between Intel and Apple Silicon Macs using the same configuration
- **SC-010**: System preferences (dock, keyboard, trackpad) persist across rebuilds

### Assumptions

- Nix package manager is already installed on macOS (via the official Nix installer or Determinate Systems installer)
- Docker Desktop is installed separately (nix-darwin manages integration, not installation)
- User has an existing 1Password account and vault configured
- macOS version is 12.0 (Monterey) or newer
- User has admin privileges to run darwin-rebuild
- The current darwin-home.nix profile is working correctly
- System follows standard macOS directory structure (/Users/username, /Applications, etc.)

### Out of Scope

- Installing Docker Desktop (only configuration/integration)
- Installing macOS system updates
- Managing Homebrew packages (focus on Nix-only solution)
- GUI application installations from App Store
- macOS-specific development tools that require proprietary licenses (Xcode managed separately)
- Migration of existing Homebrew configurations to Nix
- Backup and restore of macOS system settings
- Multi-user nix-darwin configurations (focus on single-user: vinodpittampalli)

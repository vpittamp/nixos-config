# Feature Specification: Make NixOS Config Portable

**Feature Branch**: `106-make-nixos-config-portable`
**Created**: 2025-12-01
**Status**: Draft
**Input**: User description: "currently we symlink the current directory into /etc/nixos as my nixos / home-manager configuration; i use worktrees from the current repo to work in parallel on changes to the configuration. since our primary configuration is in /etc/nixos some of our paths are relative to the /etc/nixos path, but i would like the configuration to be portable, and be built from any directory with the same outcome; review the current project and resolve in a way that we can build the configuration from any directory. we'll know when our solution works when we can build from the current directory and we get the same exact outcome as when we build from etc/nixos"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build Configuration from Worktree Directory (Priority: P1)

As a developer working on NixOS configuration changes, I want to build the system configuration directly from my git worktree directory without having to symlink it to `/etc/nixos` first, so that I can test changes in isolation and work on multiple features in parallel.

**Why this priority**: This is the core functionality requested. Currently, building requires either being in `/etc/nixos` or having a symlink there. Enabling builds from any directory is the primary goal that unlocks all other benefits.

**Independent Test**: Can be fully tested by running `sudo nixos-rebuild dry-build --flake .#<target>` from the worktree directory and verifying the build succeeds with identical output to building from `/etc/nixos`.

**Acceptance Scenarios**:

1. **Given** I am in a worktree directory (e.g., `/home/vpittamp/repos/vpittamp/nixos-config/106-make-nixos-config-portable`), **When** I run `sudo nixos-rebuild dry-build --flake .#wsl`, **Then** the build succeeds without errors related to missing paths or files.

2. **Given** I build the configuration from worktree directory, **When** I compare the resulting derivation hash to one built from `/etc/nixos`, **Then** both derivations are identical (same store path).

3. **Given** the worktree directory is at any filesystem location, **When** I run a rebuild command, **Then** all runtime paths (scripts, icons, configs) resolve correctly without hardcoded `/etc/nixos` references.

---

### User Story 2 - Runtime Script Execution Works from Any Build Location (Priority: P2)

As a user of the built system, I want keybindings and desktop integrations to work correctly regardless of where the configuration was built from, so that the system functions identically whether built from `/etc/nixos` or a worktree.

**Why this priority**: Even if the build succeeds, runtime failures would make the feature unusable. Scripts executed via Sway keybindings, i3pm commands, and other integrations must resolve their paths correctly.

**Independent Test**: After building from a worktree and switching to the new configuration, test that `Mod+D` (Walker launcher), `Mod+P` (project switcher), and other keybindings execute their scripts successfully.

**Acceptance Scenarios**:

1. **Given** a system built from a worktree directory, **When** I press `Mod+D` to open Walker, **Then** the launcher opens successfully with all icons visible.

2. **Given** a system built from a worktree directory, **When** I run `i3pm project switch <project>`, **Then** project switching works and all associated scripts execute correctly.

3. **Given** a system built from a worktree directory, **When** I trigger Claude Code notification callbacks, **Then** the callback scripts execute and focus returns to the correct window.

---

### User Story 3 - Environment Variables Reflect Build Source (Priority: P3)

As a developer using `nh` (nix helper) commands, I want environment variables like `NH_FLAKE` to point to the correct flake location automatically, so that subsequent operations target the right configuration source.

**Why this priority**: While not strictly necessary for builds, having environment variables reflect the actual flake location improves developer experience and prevents confusion when running commands like `nh os switch`.

**Independent Test**: After building from a worktree, verify that `echo $NH_FLAKE` returns the worktree path (or a mechanism exists to override it).

**Acceptance Scenarios**:

1. **Given** a build from worktree at `/home/user/worktrees/106-feature`, **When** I examine `$NH_FLAKE` after activation, **Then** the variable either points to the worktree or can be overridden easily.

2. **Given** I want to use `nh os switch`, **When** I run the command, **Then** it uses the flake from my current working directory (or configured path) rather than a hardcoded `/etc/nixos`.

---

### Edge Cases

- What happens when building from a directory with spaces in the path?
- How does the system handle building when `/etc/nixos` doesn't exist at all?
- What happens when multiple worktrees exist and both have been used for builds?
- How are relative imports in Nix files resolved when built from different directories?
- What happens to runtime paths when the worktree is deleted after building?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST build successfully with `nixos-rebuild` when invoked from any directory containing the flake
- **FR-002**: System MUST produce identical derivations (same store paths) regardless of the source directory used for building
- **FR-003**: Runtime scripts (keybindings, daemons, hooks) MUST execute correctly after building from any directory
- **FR-004**: Icon and asset paths MUST resolve correctly at runtime regardless of build source location
- **FR-005**: System MUST NOT require `/etc/nixos` symlink to exist for successful builds
- **FR-006**: Nix module imports MUST resolve correctly using relative paths from flake root
- **FR-007**: Environment variables (`NH_FLAKE`, `NH_OS_FLAKE`) MUST be configurable rather than hardcoded to `/etc/nixos`
- **FR-008**: Python scripts used at runtime MUST discover their paths dynamically rather than using hardcoded `/etc/nixos` paths
- **FR-009**: Shell scripts MUST use flake root discovery (e.g., git toplevel) rather than hardcoded paths
- **FR-010**: Test scripts MUST work when run from any worktree directory

### Key Entities

- **Flake Root**: The directory containing `flake.nix` - the source of truth for all path resolution
- **Runtime Assets**: Icons, scripts, and configuration files that must be accessible after system activation
- **Build-time Paths**: Paths resolved during `nixos-rebuild` that become fixed in the resulting derivation
- **Runtime Paths**: Paths resolved when the built system is running (scripts, configs, icons)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `sudo nixos-rebuild dry-build --flake .#<target>` from the worktree directory completes without path-related errors
- **SC-002**: The derivation hash produced from worktree build matches the hash from `/etc/nixos` build (100% identical output)
- **SC-003**: All 52+ runtime script references execute successfully after building from worktree
- **SC-004**: All 57+ icon/asset references render correctly in UI components (Eww, Walker, etc.)
- **SC-005**: Zero hardcoded `/etc/nixos` paths remain in runtime-executed code (scripts, Python, shell)
- **SC-006**: Test suite passes when run from any worktree directory without modifications

## Assumptions

1. **Git-based discovery is acceptable**: Scripts can use `git rev-parse --show-toplevel` to find the flake root at runtime
2. **Nix store paths are preferred for runtime assets**: Icons and scripts should be copied to the Nix store during build, making them available at fixed store paths regardless of source location
3. **Environment variable overrides are acceptable**: Users can set `NH_FLAKE` to their preferred location rather than having it auto-detected
4. **Documentation paths are informational**: The 544+ documentation references to `/etc/nixos` don't need to change as they don't affect runtime behavior
5. **Symlink to `/etc/nixos` may still exist**: The solution doesn't require removing the symlink, just makes it optional

## Out of Scope

- Changing the default NixOS convention of `/etc/nixos` for system configurations
- Supporting builds from non-git directories (git discovery is acceptable)
- Automatic migration of existing symlink-based setups
- Multi-user support where different users have different configuration sources

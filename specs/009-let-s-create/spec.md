# Feature Specification: NixOS Configuration Consolidation - KDE Plasma to i3wm Migration

**Feature Branch**: `009-let-s-create`
**Created**: 2025-10-17
**Status**: Draft
**Input**: User description: "let's create a new feature that involves migrating completely from kde plasma to i3wm; and in the case of m1, from wayland to x11. we want to streamline our nixos/home-manager configurations in the following ways. remove kde plasma completely, and replace functionality with i3wm where possible. we should consider the \"hetzner\" configuration (hetzner-i3wm) to be our \"primary\" configuration, and all other configs should be modifications of it, trying to stay as close to it as possible, while adjusting based on environment/architecture. i also want to drastically reduce the size of our configuration by removing some of our configs altogther. determine which configs are no longer relevant, such as wsl, and remove them altogether. find documentation that is no logner relevant and remove it, or in limited cases update them."

## Clarifications

### Session 2025-10-17

- Q: How should the migration handle VM and KubeVirt configurations (kubevirt-*.nix, vm-*.nix files)? → A: Archive VM configs to separate branch - remove from main but preserve access
- Q: How should the system handle users trying to build removed configurations after the migration (e.g., `nixos-rebuild switch --flake .#wsl`)? → A: Document in MIGRATION.md only - no special handling
- Q: Should the migration include formal performance benchmarking beyond the basic memory/boot time measurements already specified in success criteria? → A: No - basic metrics (SC-004, SC-005) are sufficient for validation

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete KDE Plasma Removal (Priority: P1)

As a system administrator, I need all KDE Plasma desktop environment components completely removed from the NixOS configuration so that the system runs exclusively with i3wm and eliminates unnecessary dependencies and resource usage.

**Why this priority**: This is the foundation of the migration. Removing KDE Plasma is essential before any other consolidation work can proceed, as it affects module dependencies, configuration structure, and system resources.

**Independent Test**: Can be fully tested by rebuilding the system configuration and verifying no KDE/Plasma packages are installed, no KDE services are running, and the system boots directly to i3wm.

**Acceptance Scenarios**:

1. **Given** the current NixOS configuration with KDE Plasma, **When** the migration is applied, **Then** no KDE Plasma packages appear in the system package list
2. **Given** the migrated configuration, **When** the system boots, **Then** only i3wm and X11 services start (no Plasma Desktop, kwin, plasmashell, or KDE services)
3. **Given** the migrated configuration, **When** checking module imports, **Then** no kde-plasma.nix or related KDE modules are imported
4. **Given** the migrated configuration on M1, **When** checking display server, **Then** X11 is running instead of Wayland
5. **Given** the migrated desktop modules directory, **When** listing files, **Then** kde-plasma.nix, kde-plasma-vm.nix, and mangowc.nix modules are removed

---

### User Story 2 - Configuration Consolidation with Hetzner-i3 as Primary (Priority: P2)

As a system administrator, I need to consolidate all platform configurations to derive from hetzner-i3.nix as the primary reference configuration, so that configuration maintenance is simplified and platform-specific variations are minimal and clearly documented.

**Why this priority**: Once KDE Plasma is removed, the next critical step is establishing a clean configuration hierarchy. This prevents configuration drift and makes future maintenance predictable.

**Independent Test**: Can be tested by examining configuration inheritance, verifying that M1, container, and other configurations import hetzner-i3.nix as their base and only override platform-specific settings.

**Acceptance Scenarios**:

1. **Given** the consolidated configuration structure, **When** examining configuration files, **Then** hetzner-i3.nix serves as the base configuration with all core i3wm functionality
2. **Given** the M1 configuration, **When** reviewing its structure, **Then** it imports and extends hetzner-i3.nix with only M1-specific hardware and display settings
3. **Given** the container configuration, **When** reviewing its structure, **Then** it derives from hetzner-i3.nix but disables GUI components via conditional logic
4. **Given** all platform configurations, **When** comparing their content, **Then** 80% or more of configuration is shared through inheritance from hetzner-i3.nix
5. **Given** the base.nix file, **When** reviewing its content, **Then** it now references hetzner-i3.nix patterns instead of KDE Plasma patterns

---

### User Story 3 - Remove Obsolete Configurations and Documentation (Priority: P3)

As a system administrator, I need all obsolete configuration files and documentation removed from the repository, so that the codebase is lean, maintainable, and only contains actively used configurations.

**Why this priority**: After establishing the new configuration hierarchy, cleaning up obsolete files prevents confusion and reduces maintenance burden. This is less critical than the actual migration but essential for long-term maintainability.

**Independent Test**: Can be tested by checking that removed configurations are no longer in the repository, documentation only references active configurations, and the total file/line count is significantly reduced.

**Acceptance Scenarios**:

1. **Given** the repository with obsolete configurations, **When** WSL configuration is evaluated, **Then** wsl.nix and WSL-specific modules are removed (if determined obsolete)
2. **Given** the repository with multiple Hetzner variants, **When** consolidation is complete, **Then** only hetzner-i3.nix remains as the primary Hetzner configuration
3. **Given** the documentation directory, **When** reviewing KDE/Plasma-specific docs, **Then** PLASMA_CONFIG_STRATEGY.md, PLASMA_MANAGER.md, and IPHONE_KDECONNECT_GUIDE.md are removed
4. **Given** the documentation directory, **When** reviewing remaining docs, **Then** PWA_SYSTEM.md, PWA_COMPARISON.md, and PWA_PARAMETERIZATION.md are updated to reflect i3wm context (PWAs still functional with Firefox)
5. **Given** the consolidated repository, **When** counting configuration files, **Then** the total is reduced by at least 30% (from ~17 config files to ~12 or fewer)
6. **Given** the consolidated repository, **When** counting documentation files, **Then** obsolete docs are removed and total is reduced by at least 15% (from ~45 docs to ~38 or fewer)

---

### User Story 4 - M1 Wayland to X11 Migration (Priority: P2)

As an M1 Mac user, I need the display server migrated from Wayland to X11 so that my M1 configuration aligns with the Hetzner reference configuration and maintains compatibility with X11-dependent tools.

**Why this priority**: Critical for M1 users but can be developed in parallel with configuration consolidation. Ensures M1 configuration matches the reference architecture.

**Independent Test**: Can be tested by building the M1 configuration and verifying X11 is running, Wayland-specific configurations are removed, and all critical tools (1Password, Firefox PWAs, terminal, clipboard manager) function correctly.

**Acceptance Scenarios**:

1. **Given** the M1 configuration with Wayland, **When** the migration is applied, **Then** X11 server is configured and starts on boot
2. **Given** the migrated M1 configuration, **When** checking display server environment variables, **Then** $DISPLAY is set and $WAYLAND_DISPLAY is unset
3. **Given** the migrated M1 configuration, **When** reviewing module imports, **Then** wayland-remote-access.nix is removed or disabled
4. **Given** the migrated M1 configuration, **When** testing HiDPI scaling, **Then** X11 DPI settings provide equivalent scaling to previous Wayland configuration
5. **Given** the migrated M1 configuration, **When** testing touch gestures, **Then** basic gesture support (2-finger scroll, pinch zoom via touchegg or similar) is acceptable

---

### Edge Cases

- **Removed configuration builds**: When users try to build removed configurations (e.g., `nixos-rebuild switch --flake .#wsl`), Nix will return a standard "attribute not found" error. MIGRATION.md will document all removed configurations and their replacements (e.g., wsl → hetzner-i3, vm-* → see archive/vm-configs branch).
- **Partial migrations**: System handles partial migrations gracefully - each platform configuration is independent, so Hetzner can migrate before M1 without breaking either system.
- **KDE home-manager remnants**: If KDE configuration remnants exist in home-manager user configurations, they will be ignored (no longer referenced) but not automatically removed - user must clean up manually.
- **Custom KDE Plasma settings**: Custom user modifications to KDE Plasma settings will be lost - users should document needed settings before migration (noted in MIGRATION.md).
- **PWA functionality breakage**: If PWA functionality breaks after removing KDE Plasma components, rollback via `nixos-rebuild switch --rollback` to previous generation, investigate, and file issue.
- **M1 Wayland preference**: M1 users who prefer Wayland can maintain their own fork or use the archive branch - this migration standardizes on X11 for consistency with reference configuration.

## Requirements *(mandatory)*

### Functional Requirements

#### Desktop Environment Migration

- **FR-001**: System MUST remove all KDE Plasma packages from environment.systemPackages across all configurations
- **FR-002**: System MUST remove all KDE Plasma services from systemd configuration across all configurations
- **FR-003**: System MUST replace KDE Plasma desktop functionality with i3wm equivalents (application launcher, window management, workspace navigation, session management)
- **FR-004**: System MUST maintain clipboard functionality using clipcat instead of KDE's klipper
- **FR-005**: System MUST maintain screen locking capability using i3lock instead of KDE's screen locker
- **FR-006**: System MUST maintain application launcher functionality using rofi instead of KDE's KRunner
- **FR-007**: M1 configuration MUST switch from Wayland to X11 display server
- **FR-008**: M1 configuration MUST maintain HiDPI display scaling using X11 DPI configuration

#### Configuration File Removal

- **FR-009**: System MUST remove modules/desktop/kde-plasma.nix module file
- **FR-010**: System MUST remove modules/desktop/kde-plasma-vm.nix module file
- **FR-011**: System MUST remove modules/desktop/mangowc.nix module file (Wayland compositor)
- **FR-012**: System MUST remove modules/desktop/wayland-remote-access.nix module file
- **FR-013**: System MUST remove configurations/hetzner.nix (old KDE-based config) while keeping configurations/hetzner-i3.nix
- **FR-014**: System MUST remove configurations/hetzner-mangowc.nix (Wayland-based config)
- **FR-015**: System MUST remove configurations/wsl.nix (WSL environment no longer in use)
- **FR-016**: System MUST archive VM configurations (vm-hetzner.nix, vm-minimal.nix) to a separate git branch (e.g., archive/vm-configs) and remove from main branch to reduce active configuration count
- **FR-017**: System MUST archive kubevirt configurations to a separate git branch (e.g., archive/kubevirt-configs) and remove from main branch while preserving access via git history

#### Configuration Consolidation

- **FR-018**: System MUST establish configurations/hetzner-i3.nix as the primary reference configuration
- **FR-019**: System MUST modify configurations/m1.nix to import and extend hetzner-i3.nix with M1-specific overrides only
- **FR-020**: System MUST modify configurations/container.nix to derive from hetzner-i3.nix with GUI components disabled
- **FR-021**: System MUST update configurations/base.nix to reflect i3wm patterns instead of KDE Plasma patterns
- **FR-022**: System MUST maintain all existing i3wm functionality from current hetzner-i3.nix configuration (rofi, i3wsr, clipcat, alacritty, tmux integration)
- **FR-023**: System MUST preserve all PWA (Progressive Web App) functionality for Firefox-based web applications

#### Documentation Updates

- **FR-024**: System MUST remove docs/PLASMA_CONFIG_STRATEGY.md
- **FR-025**: System MUST remove docs/PLASMA_MANAGER.md
- **FR-026**: System MUST remove docs/IPHONE_KDECONNECT_GUIDE.md (KDE Connect no longer applicable)
- **FR-027**: System MUST update docs/PWA_SYSTEM.md to reflect i3wm context and remove KDE panel references
- **FR-028**: System MUST update docs/PWA_COMPARISON.md to remove KDE-specific context
- **FR-029**: System MUST update docs/PWA_PARAMETERIZATION.md to focus on i3wm workspace integration
- **FR-030**: System MUST update CLAUDE.md to replace all KDE Plasma references with i3wm references
- **FR-031**: System MUST update docs/M1_SETUP.md to document X11 configuration instead of Wayland
- **FR-032**: System MUST update docs/ARCHITECTURE.md to reflect new configuration hierarchy with hetzner-i3.nix as primary

#### Build and Test Requirements

- **FR-033**: System MUST successfully build all remaining configurations (hetzner-i3, m1, container) using nixos-rebuild dry-build
- **FR-034**: System MUST verify no KDE/Plasma packages remain in closure for any configuration
- **FR-035**: System MUST verify all i3wm functionality works across all remaining configurations
- **FR-036**: System MUST maintain all 1Password integration functionality (desktop app, CLI, browser integration)

### Key Entities

- **Platform Configuration**: Represents a complete NixOS system configuration for a specific platform (Hetzner, M1, container), including hardware settings, desktop environment, services, and user environment
- **Desktop Module**: Encapsulates desktop environment functionality (window manager, display server, peripheral services like clipboard, screen locking, application launching)
- **Documentation File**: Technical guides explaining configuration, setup, and usage patterns for specific features or platforms

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Configuration repository size is reduced by at least 30% measured by total configuration file count (from ~17 to ~12 or fewer files)
- **SC-002**: Documentation directory is reduced by at least 15% measured by file count (from ~45 to ~38 or fewer files)
- **SC-003**: All remaining configurations (hetzner-i3, m1, container) build successfully without errors within 5 minutes
- **SC-004**: System boot time to usable i3wm desktop is 30 seconds or less on Hetzner configuration
- **SC-005**: System memory usage at idle is reduced by at least 200MB compared to KDE Plasma configuration (measured after login with no applications running)
- **SC-006**: All critical integrations (1Password, Firefox PWAs, tmux, clipcat, rofi) function correctly on all remaining platforms
- **SC-007**: M1 configuration successfully runs X11 with functional HiDPI scaling equivalent to previous Wayland setup
- **SC-008**: No KDE/Plasma packages appear in nix-store queries for any remaining configuration
- **SC-009**: Configuration inheritance analysis shows at least 80% code reuse from hetzner-i3.nix base across platform configurations
- **SC-010**: Developer can rebuild any configuration from scratch in under 10 minutes using updated documentation

## Assumptions *(optional)*

1. **WSL Configuration Obsolescence**: Assuming WSL environment is no longer in active use based on user's mention. If WSL is still needed, it will be retained and migrated to i3wm-based configuration.

2. **KDE Connect Replacement**: Assuming iPhone KDE Connect functionality is not critical or will be replaced with alternative solution (like using web-based services or SSH).

3. **Wayland Gesture Support**: Assuming X11-based gesture support on M1 (via touchegg or similar) is acceptable, though may not be as mature as Wayland's native gestures.

4. **PWA Compatibility**: Assuming Firefox PWA functionality is independent of desktop environment and will continue working with i3wm (based on current hetzner-i3.nix implementation).

5. **Virtual Machine Configurations**: VM and kubevirt-* configurations will be archived to separate git branches rather than permanently deleted, preserving access while reducing active configuration count in main branch.

6. **Multi-Session RDP**: Assuming xrdp multi-session functionality (currently working with i3wm on Hetzner) is preserved and remains a core requirement.

7. **Home-Manager Integration**: Assuming user-specific KDE configuration in home-manager modules will be manually cleaned by user or handled in separate cleanup phase.

8. **Display Server Performance**: Assuming X11 performance on M1 is acceptable for the user's workflow (may have different performance characteristics vs Wayland for rendering and input handling).

## Out of Scope *(optional)*

1. **Wayland Support**: Future Wayland support for i3-compatible compositor (sway) is not included in this migration
2. **KDE Application Retention**: Individual KDE applications (like Konsole, Kate, Dolphin) that user may prefer are not specifically removed - only the Plasma desktop environment itself
3. **Home-Manager User Config Cleanup**: Cleaning up user-specific KDE configuration in home-manager dotfiles is left to user discretion
4. **Alternative Desktop Environments**: No provision for alternative desktop environments beyond i3wm
5. **Automated Migration Scripts**: No automated scripts to migrate user data, settings, or preferences from KDE to i3wm
6. **Performance Benchmarking**: No formal performance testing beyond basic memory usage (SC-005: 200MB reduction) and boot time measurements (SC-004: <30 seconds) - detailed CPU, disk I/O, and network benchmarks are not required
7. **Multi-Display Configuration**: Complex multi-monitor xrandr configurations on M1 are left to user configuration (basic single/dual display expected to work)

## Dependencies *(optional)*

- Current hetzner-i3.nix configuration must be stable and fully functional
- i3wm module (modules/desktop/i3wm.nix) must be complete with all required integrations
- xrdp module must be compatible with i3wm and X11-only configuration
- clipcat, rofi, i3wsr, and alacritty packages must be available in nixpkgs
- Firefox PWA runtime (firefoxpwa) must remain functional without KDE desktop environment
- 1Password desktop application must function correctly with i3wm and X11
- M1 hardware must have stable X11 driver support via Asahi Linux project

## Notes *(optional)*

### Aggressive Cleanup Philosophy

This migration prioritizes **forward-looking efficiency** over backward compatibility:
- **Git history preserves all removed code** - no need to maintain unused configurations "just in case"
- **Remove aggressively** - if a configuration or file is not actively used, delete it
- **No deprecation period** - direct removal of obsolete components
- **Focus on the future** - optimize for current and planned use cases, not historical ones
- **Simplicity over completeness** - fewer, well-maintained configs are better than many partially-maintained ones

### Configuration Reduction Strategy

The consolidation will follow this priority order:
1. Remove duplicate Hetzner configurations (keep only hetzner-i3.nix)
2. Remove Wayland-specific configurations (mangowc, wayland-remote-access)
3. Remove KDE Plasma modules
4. Remove WSL configuration (no longer in use)
5. Remove experimental/staging configs (kubevirt-*, vm-*, hetzner-example, hetzner-minimal)
6. Update remaining configs to inherit from hetzner-i3.nix

### Migration Risk Areas

- **M1 Gesture Support**: Wayland to X11 migration may degrade gesture quality on M1 trackpad
- **PWA Taskbar Integration**: PWA icons may need different integration approach without KDE panels
- **Display Scaling**: X11 HiDPI on M1 may require manual DPI configuration vs Wayland's automatic scaling
- **Session Management**: Ensure xrdp multi-session functionality is fully preserved during KDE removal

### Post-Migration Recommendations

1. Consider creating docs/I3WM_SETUP.md for comprehensive i3wm configuration guide
2. Update constitution.md if not already updated to reflect i3wm as standard desktop environment
3. Test remote desktop functionality thoroughly on all platforms after migration
4. Monitor system resource usage to validate memory reduction claims
5. Consider periodic audits of configuration inheritance to maintain 80%+ code reuse target

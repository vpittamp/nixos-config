# Feature Specification: PWA Installation Fix

**Feature Branch**: `001-pwa-installation-fix`
**Created**: 2025-11-02
**Status**: Draft
**Input**: User description: "Fix PWA installation system to ensure Firefox PWA desktop files (FFPWA-*.desktop) are created and accessible to Walker/Elephant launcher"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Launch PWA from Walker (Priority: P1)

User wants to launch a PWA (e.g., YouTube, Google AI) from Walker/Elephant application launcher and have it open immediately in a dedicated window with proper workspace assignment.

**Why this priority**: This is the core value proposition - users need to launch PWAs just like any other application. Without this, PWAs are unusable via the primary application launcher.

**Independent Test**: Can be fully tested by opening Walker (Meta+D), typing "youtube", hitting Return, and verifying YouTube PWA opens in a dedicated window on the configured workspace.

**Acceptance Scenarios**:

1. **Given** PWAs are declared in `firefox-pwas-declarative.nix`, **When** user types "youtube" in Walker, **Then** YouTube PWA option appears in launcher results
2. **Given** user selects YouTube PWA from Walker, **When** Return key is pressed, **Then** YouTube PWA launches in dedicated window within 2 seconds
3. **Given** YouTube PWA has `preferred_workspace = 4` in app-registry-data.nix, **When** PWA launches, **Then** window appears on workspace 4
4. **Given** PWA is scoped to a project, **When** PWA launches with active project, **Then** `i3pm events` shows workspace::assignment event with correct project context

---

### User Story 2 - Verify PWA Installation (Priority: P2)

User wants to verify which PWAs are installed and accessible, and see clear error messages if a PWA fails to install or launch.

**Why this priority**: This enables troubleshooting and validation without diving into system logs. It's not critical for basic functionality but essential for maintainability.

**Independent Test**: Can be fully tested by running `pwa-list` command and verifying all declared PWAs show up with "INSTALLED" status and correct desktop file paths.

**Acceptance Scenarios**:

1. **Given** PWAs are declared in configuration, **When** `pwa-list` is run, **Then** all PWAs show with INSTALLED status and FFPWA-*.desktop file paths
2. **Given** a PWA installation failed, **When** `pwa-list` is run, **Then** PWA shows with ERROR status and helpful error message
3. **Given** PWA desktop files exist, **When** `ls ~/.local/share/applications/FFPWA-*.desktop` is run, **Then** files are present and readable

---

### User Story 3 - Automatic PWA Sync (Priority: P3)

User wants PWA desktop files to automatically sync when configuration changes, without manual intervention.

**Why this priority**: This improves UX by making PWA management declarative, but P1/P2 functionality can work with manual sync steps.

**Independent Test**: Can be fully tested by modifying `firefox-pwas-declarative.nix` to add a new PWA, rebuilding NixOS, and verifying the new PWA appears in Walker without running `pwa-install-all`.

**Acceptance Scenarios**:

1. **Given** a new PWA is added to configuration, **When** `nixos-rebuild switch` completes, **Then** PWA desktop file exists in `~/.local/share/applications/`
2. **Given** a PWA is removed from configuration, **When** `nixos-rebuild switch` completes, **Then** corresponding FFPWA-*.desktop file is removed
3. **Given** PWA URL is updated, **When** `nixos-rebuild switch` completes, **Then** desktop file reflects new URL

---

### Edge Cases

- What happens when Firefox PWA extension is not installed?
- How does system handle PWA profile corruption or missing data directory?
- What if `~/.local/share/applications/` directory doesn't exist?
- How does system handle concurrent PWA installations?
- What if a PWA desktop file already exists but with different content?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST create FFPWA-*.desktop files in `~/.local/share/applications/` for all PWAs declared in `firefox-pwas-declarative.nix`
- **FR-002**: System MUST ensure `launch-pwa-by-name` script looks for FFPWA-*.desktop files (not WebApp-*.desktop)
- **FR-003**: `pwa-install-all` command MUST create desktop files idempotently (safe to run multiple times)
- **FR-004**: PWA desktop files MUST include correct Exec command pointing to `firefoxpwa site launch <profile-id>`
- **FR-005**: System MUST validate Firefox PWA extension is installed before attempting installation
- **FR-006**: Walker/Elephant launcher MUST be able to discover and launch FFPWA-*.desktop files
- **FR-007**: System MUST log PWA launch attempts to `~/.local/state/app-launcher.log` with success/failure status
- **FR-008**: PWA launches MUST trigger window::new and workspace::assignment events visible in `i3pm events`
- **FR-009**: System MUST symlink FFPWA desktop files to `~/.local/share/i3pm-applications/applications/` for registry consistency
- **FR-010**: `pwa-list` command MUST show installation status (INSTALLED, MISSING, ERROR) for all declared PWAs

### Key Entities *(include if feature involves data)*

- **PWA Desktop File**: Represents a Firefox PWA application launcher file with .desktop extension, containing Name, Exec, Icon, Categories metadata
- **PWA Profile**: Firefox PWA installation identified by unique ID (e.g., 01K666N2V6BQMDSBMX3AY74TY7), stored in `~/.local/share/firefoxpwa/profiles/`
- **Application Registry Entry**: Configuration entry in app-registry-data.nix with app name, command, workspace assignment, and scope

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can launch any declared PWA from Walker within 2 seconds (from typing to window open)
- **SC-002**: `pwa-install-all` succeeds for 100% of declared PWAs with Firefox PWA extension installed
- **SC-003**: PWA launches generate visible workspace::assignment events in `i3pm events` output within 100ms
- **SC-004**: `pwa-list` accurately reports installation status for all PWAs with <1% false positives
- **SC-005**: PWA desktop files persist across system reboots and NixOS rebuilds
- **SC-006**: PWA workspace assignments work with 100% reliability (same as Feature 053 Phase 6)

## Assumptions

- Firefox PWA extension (firefoxpwa) is installed and functional
- User has at least one PWA profile created via `firefoxpwa site install <url>`
- `~/.local/share/applications/` directory has correct permissions (user writable)
- Walker/Elephant launcher respects XDG desktop file specification

## Dependencies

- **Feature 053**: Workspace assignment enhancement (complete) - provides event-driven assignment logic
- **Firefox PWA Extension**: Required for PWA profile management
- **Walker/Elephant**: Application launcher service must be running

## Out of Scope

- Creating new PWA profiles (assumes profiles already exist)
- Firefox PWA extension installation/configuration
- PWA icon customization beyond desktop file Icon field
- Multi-user PWA sharing
- PWA auto-update mechanism
- Converting existing WebApp-*.desktop files to FFPWA format

## Technical Constraints

- Must maintain compatibility with existing `app-registry-data.nix` structure
- Must not break existing non-PWA application launches
- Must work with both Sway (Hetzner) and i3 (if applicable) window managers
- Desktop files must follow freedesktop.org desktop entry specification
- Must preserve existing `pwa-install-all`, `pwa-list`, `pwa-get-ids` command interfaces

## Risks

- **Risk**: Firefox PWA profile IDs may change if PWAs are reinstalled
  - **Mitigation**: Document profile ID discovery process and provide tooling to update configuration

- **Risk**: Walker/Elephant may cache desktop file list and miss new PWAs
  - **Mitigation**: Document restart procedure for Elephant service after PWA installation

- **Risk**: Concurrent `pwa-install-all` runs could create race conditions
  - **Mitigation**: Use file locking or detect running instances

## Open Questions

- Should `pwa-install-all` automatically restart Elephant service to refresh launcher cache?
- Should system automatically create PWA profiles from URLs in configuration, or require manual installation?
- Should desktop files include custom categories for better organization in launchers?
- Should we validate PWA profile IDs exist before creating desktop files?

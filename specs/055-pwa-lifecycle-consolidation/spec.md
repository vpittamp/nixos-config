# Feature Specification: PWA Lifecycle Consolidation

**Feature Branch**: `055-pwa-lifecycle-consolidation`
**Created**: 2025-11-02
**Status**: Draft
**Input**: User description: "Create a new feature that reviews our logic for installing, managing, launching pwa apps. We may have several sets of logic (from various iterations that we've used in the past) to manage pwa's. We need to reconcile to make sure we only have one set of logic, and that it directly aligns with our full app lifecycle logic that we use within our python module, sway, window management, etc. We should also consider how we manage pwa apps across multiple machines (m1, hetzner-sway, etc); consider whether we can query for pwa id via firefoxpwa cli commands since the id is system generated. Also, consider how we map each pwa to a workspace id that is unique. Currently we try to centralize app logic in app-registry-data.nix but we need to determine if that approach works for pwa's. Explore the best solution. One very important principle we should follow is the following: don't worry about backwards compatibility. Create the best solution and discard legacy approaches. We want a streamlined codebase that doesn't contain legacy code that is no longer relevant."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified PWA Management Across Machines (Priority: P1)

User wants to declare a PWA once in configuration and have it work seamlessly across all machines (hetzner-sway, m1) without hardcoding machine-specific profile IDs, using dynamic runtime discovery for portability.

**Why this priority**: This is the core consolidation goal - eliminating duplicate/conflicting PWA logic and achieving cross-machine portability. Without this, each machine requires separate configuration and profile ID management.

**Independent Test**: Can be fully tested by declaring YouTube PWA in configuration, deploying to both hetzner-sway and m1, and verifying it launches correctly on both systems using their respective auto-generated profile IDs.

**Acceptance Scenarios**:

1. **Given** YouTube PWA is declared with name "YouTube" in app-registry-data.nix, **When** configuration is deployed to hetzner-sway, **Then** `firefoxpwa profile list` is queried at runtime to find profile ID matching "YouTube"
2. **Given** same configuration is deployed to m1, **When** YouTube is launched, **Then** system discovers m1's unique profile ID dynamically (no hardcoded hetzner-sway ID)
3. **Given** PWA profile ID changes after reinstall, **When** PWA is launched, **Then** system automatically discovers new ID without configuration changes
4. **Given** all PWAs use dynamic discovery, **When** comparing app-registry-data.nix entries, **Then** no hardcoded profile IDs exist (e.g., no "FFPWA-01K666N2V6BQMDSBMX3AY74TY7" strings)

---

### User Story 2 - Single Source of Truth for PWA Configuration (Priority: P2)

User wants all PWA metadata (name, workspace, scope, fallback behavior) centralized in app-registry-data.nix with no duplicate configuration files or legacy scripts, using the same app lifecycle as regular applications.

**Why this priority**: Consolidation eliminates maintenance burden of multiple config sources and ensures consistency between PWAs and regular apps in event handling, workspace assignment, and window management.

**Independent Test**: Can be fully tested by verifying PWAs use identical launch flow as regular apps (app-launcher-wrapper.sh ’ launch notification ’ window correlation ’ workspace assignment) with all metadata sourced from app-registry-data.nix.

**Acceptance Scenarios**:

1. **Given** YouTube PWA is defined in app-registry-data.nix, **When** searching codebase, **Then** no other config files (firefox-pwas-declarative.nix, pwa-specific scripts) contain YouTube metadata
2. **Given** PWA and regular app both launch, **When** comparing event logs, **Then** both follow identical lifecycle: launch notification ’ window::new ’ workspace::assignment with same event structure
3. **Given** PWA has `preferred_workspace = 4`, **When** launched, **Then** daemon uses same Priority 0-3 decision tree as regular apps (no special PWA assignment logic)
4. **Given** all legacy PWA scripts are removed, **When** running tests, **Then** 100% of PWAs launch successfully using unified app-launcher-wrapper.sh flow

---

### User Story 3 - Automatic PWA Discovery and Validation (Priority: P3)

User wants system to automatically discover which PWAs are installed, validate configuration matches reality, and warn about mismatches (missing PWAs, renamed PWAs, orphaned desktop files).

**Why this priority**: This provides operational visibility and prevents silent failures, but P1/P2 functionality works without automatic validation (manual checks suffice).

**Independent Test**: Can be fully tested by running `pwa-validate` command which queries firefoxpwa, compares with app-registry-data.nix, and reports discrepancies with actionable suggestions.

**Acceptance Scenarios**:

1. **Given** app-registry-data.nix declares "YouTube" PWA, **When** `pwa-validate` runs, **Then** system queries `firefoxpwa profile list` and confirms "YouTube" exists
2. **Given** "ChatGPT" PWA is installed but not in configuration, **When** validation runs, **Then** warning appears: "Installed PWA 'ChatGPT' not found in app-registry-data.nix"
3. **Given** "Google AI" declared but renamed to "Gemini" in Firefox, **When** validation runs, **Then** error appears: "PWA 'Google AI' not found, did you mean 'Gemini'?"
4. **Given** desktop files exist for deleted PWAs, **When** cleanup runs, **Then** orphaned .desktop files are removed from ~/.local/share/applications/

---

### Edge Cases

- What happens when firefoxpwa command not available or returns empty list?
- How does system handle PWA name collisions (two PWAs with same name)?
- What if firefoxpwa profile list format changes in future versions?
- How does system handle special characters in PWA names (e.g., "ChatGPT: Codex")?
- What if user manually creates PWA with same name on different machines (conflict resolution)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST query `firefoxpwa profile list` at runtime to discover PWA profile IDs (no hardcoded IDs in app-registry-data.nix)
- **FR-002**: app-registry-data.nix MUST use PWA display name (e.g., "YouTube") instead of profile ID for PWA entries
- **FR-003**: `launch-pwa-by-name` MUST be the sole PWA launcher (remove firefox-pwas-declarative.nix, pwa-install-all, ice/WebApp scripts)
- **FR-004**: PWA entries in app-registry-data.nix MUST use identical structure as regular apps (name, display_name, command, parameters, scope, preferred_workspace)
- **FR-005**: PWA launches MUST follow unified app lifecycle: app-launcher-wrapper.sh ’ launch notification ’ systemd-run ’ window correlation
- **FR-006**: Daemon MUST handle PWA windows identically to regular app windows (no special PWA event handling code)
- **FR-007**: Workspace assignment MUST use same Priority 0-3 decision tree for PWAs (launch_notification ’ I3PM_TARGET_WORKSPACE ’ registry ’ class)
- **FR-008**: Desktop files MUST be generated from app-registry-data.nix (single source of truth, no manual .desktop file creation)
- **FR-009**: System MUST work identically on hetzner-sway and m1 without configuration changes (runtime PWA ID discovery handles differences)
- **FR-010**: Legacy PWA code MUST be removed: firefox-pwas-declarative.nix, WebApp-*.desktop files, ice scripts, pwa-specific window rules

### Key Entities

- **PWA Entry**: Application registry entry with display_name matching firefoxpwa profile name, using `launch-pwa-by-name` command
- **PWA Profile**: firefoxpwa-managed installation with auto-generated ID, discoverable via `firefoxpwa profile list`
- **Dynamic PWA Mapping**: Runtime lookup from display_name ’ profile ID via firefoxpwa query (no static mapping)
- **Unified App Lifecycle**: Single event flow for all apps (PWA and regular): launch ’ notify ’ execute ’ correlate ’ assign

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All PWAs work on both hetzner-sway and m1 with zero configuration differences (100% portability)
- **SC-002**: app-registry-data.nix contains zero hardcoded profile IDs (e.g., no "01K[A-Z0-9]+" strings in PWA entries)
- **SC-003**: Codebase contains zero legacy PWA files after cleanup (firefox-pwas-declarative.nix, pwa-install-all, WebApp scripts deleted)
- **SC-004**: PWA and regular app event logs show identical lifecycle structure (100% consistency in event sequence)
- **SC-005**: PWA profile ID changes (after reinstall) require zero configuration updates (dynamic discovery handles automatically)
- **SC-006**: PWA workspace assignment uses same decision tree as regular apps (no special PWA assignment code paths)

## Assumptions

- firefoxpwa CLI is installed and functional on all target machines
- PWA profile names in Firefox match display_name values in app-registry-data.nix (user ensures naming consistency)
- All PWAs are already installed via firefoxpwa (system discovers existing installations, doesn't create new ones)
- Desktop environment respects freedesktop.org .desktop file specification for PWA launching
- User accepts breaking changes (no backwards compatibility with old PWA system)

## Dependencies

- **Feature 054**: PWA launcher integration (provides launch-pwa-by-name dynamic discovery foundation)
- **Feature 053**: Workspace assignment enhancement (provides unified Priority 0-3 decision tree)
- **Feature 041**: IPC launch context (provides launch notification ’ window correlation)
- **Feature 035**: Registry-centric architecture (provides app-registry-data.nix as single source of truth)
- **firefoxpwa**: Required for PWA profile management and runtime discovery

## Out of Scope

- Installing new PWAs (assumes PWAs already installed via `firefoxpwa site install`)
- Modifying firefoxpwa itself or proposing changes to its CLI interface
- Supporting non-Firefox PWA systems (Chrome PWAs, Epiphany WebApps, etc.)
- Auto-syncing PWA installations across machines (user installs PWAs manually on each machine)
- PWA icon management or customization (uses default firefoxpwa icons)
- Migrating existing WebApp-*.desktop files to FFPWA format (clean install approach)

## Technical Constraints

- Must maintain compatibility with Sway/i3 IPC protocol for window management
- Must preserve existing app-launcher-wrapper.sh parameter substitution ($PROJECT_DIR, etc.)
- Must work with systemd-run for process isolation (existing launch infrastructure)
- Desktop files must follow freedesktop.org spec v1.5
- firefoxpwa profile list output must be parsable (grep/awk compatible)
- Must not break existing non-PWA application launches

## Risks

- **Risk**: firefoxpwa CLI output format changes in future versions
  - **Mitigation**: Use stable output pattern (grep for "^- Name:"), add version detection if needed

- **Risk**: PWA names contain special characters causing grep/regex failures
  - **Mitigation**: Escape special characters in launch-pwa-by-name, validate PWA names in app-registry-data.nix

- **Risk**: User forgets to install PWA on new machine before launching
  - **Mitigation**: Validation tool warns about missing PWAs, launch-pwa-by-name shows clear error with installation instructions

- **Risk**: Large-scale refactor breaks existing PWA launches during transition
  - **Mitigation**: Incremental migration plan, test each PWA after code removal, rollback capability via git

## Open Questions

- Should system auto-generate desktop files on every rebuild or only when app-registry-data.nix changes?
- Should validation tool run automatically on nixos-rebuild or be manual command only?
- Should PWA entries in app-registry-data.nix have a `type = "pwa"` field for clarity or infer from `command = "launch-pwa-by-name"`?
- Should system support PWA-specific features (manifest updates, offline mode) or treat PWAs purely as launchers?

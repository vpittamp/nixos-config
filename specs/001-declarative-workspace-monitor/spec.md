# Feature Specification: Declarative Workspace-to-Monitor Assignment with Floating Window Configuration

**Feature Branch**: `001-declarative-workspace-monitor`
**Created**: 2025-11-10
**Status**: Draft
**Input**: User description: "explore the best options for assigning workspaces to specific outputs. if possible, i would like to define in @home-modules/desktop/app-registry-data.nix, and similarly for firefox pwa's in a similar config, perhaps @shared/pwa-sites.nix. the "preferred monitor" should correspond to three monitor setup, and we should have fallback logic, for when we have only 2 or 1 monitors. i think we want this configuration to be fully declarative just as we have application/workspace mapping assignments. Also add declarative floating window configuration with size presets and project filtering integration."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declarative Monitor Role Assignment for Applications (Priority: P1)

As a developer managing workspace layouts, I want to declare which monitor role (primary/secondary/tertiary) each application should appear on in the same configuration file where I define the application, so that workspace-to-monitor assignments are centralized and version-controlled alongside other application metadata.

**Why this priority**: This is the core value proposition - consolidating workspace AND monitor preferences into a single declarative configuration eliminates the need for separate runtime configuration files and provides a single source of truth for workspace layout.

**Independent Test**: Can be fully tested by adding a `preferred_monitor_role` field to an application in `app-registry-data.nix`, rebuilding the system, and verifying the application's workspace appears on the correct monitor role (e.g., VS Code on workspace 2 → primary monitor).

**Acceptance Scenarios**:

1. **Given** an application entry in `app-registry-data.nix` with `preferred_workspace = 2` and `preferred_monitor_role = "primary"`, **When** the system starts with 3 monitors, **Then** workspace 2 is assigned to the primary monitor output
2. **Given** a PWA entry in `pwa-sites.nix` with `preferred_workspace = 50` and `preferred_monitor_role = "secondary"`, **When** the PWA launches, **Then** it appears on workspace 50 which is assigned to the secondary monitor
3. **Given** multiple applications with the same `preferred_monitor_role`, **When** monitor assignments are calculated, **Then** all applications with that role share the same monitor output
4. **Given** an application with `preferred_monitor_role = "tertiary"`, **When** only 2 monitors are active, **Then** the system falls back to secondary monitor using documented fallback rules

---

### User Story 2 - Automatic Fallback for Reduced Monitor Configurations (Priority: P1)

As a remote developer switching between 1, 2, and 3 monitor setups, I want the system to automatically reassign workspaces to available monitors when a preferred monitor role is unavailable, so that all applications remain accessible regardless of current monitor count without manual intervention.

**Why this priority**: Equal priority with declarative config because without fallback logic, disconnecting monitors breaks workspace assignments and users lose access to applications.

**Independent Test**: Can be fully tested by configuring applications for 3 monitors (primary/secondary/tertiary), then disconnecting monitors sequentially and verifying workspaces automatically reassign to available monitors following predictable fallback rules.

**Acceptance Scenarios**:

1. **Given** workspace assigned to "tertiary" role and only 2 monitors active, **When** system calculates assignments, **Then** workspace falls back to "secondary" monitor
2. **Given** workspace assigned to "secondary" or "tertiary" role and only 1 monitor active, **When** system calculates assignments, **Then** all workspaces fall back to "primary" (single) monitor
3. **Given** 3 monitors active with workspaces distributed, **When** tertiary monitor disconnects, **Then** workspaces from tertiary role automatically reassign to secondary monitor within 1 second
4. **Given** fallback rules applied due to reduced monitors, **When** missing monitor reconnects, **Then** workspaces automatically restore to preferred monitor roles

---

### User Story 3 - PWA-Specific Monitor Preferences (Priority: P2)

As a user of multiple Progressive Web Apps, I want to define monitor preferences for each PWA in the centralized PWA configuration file, so that PWAs automatically appear on my preferred monitors alongside workspace assignments.

**Why this priority**: Important for PWA-heavy workflows but secondary to core application support. PWAs can initially use workspace-based assignments without explicit monitor roles.

**Independent Test**: Can be fully tested by adding `preferred_monitor_role = "secondary"` to a PWA definition in `pwa-sites.nix`, launching the PWA, and verifying it appears on the secondary monitor.

**Acceptance Scenarios**:

1. **Given** YouTube PWA with `preferred_monitor_role = "primary"` in `pwa-sites.nix`, **When** YouTube PWA launches, **Then** it appears on workspace 50 assigned to primary monitor
2. **Given** ChatGPT PWA with `preferred_monitor_role = "tertiary"` and only 2 monitors active, **When** ChatGPT launches, **Then** it appears on secondary monitor (fallback from tertiary)
3. **Given** multiple PWAs with different monitor role preferences, **When** system rebuilds, **Then** each PWA's workspace is assigned to the correct monitor role
4. **Given** PWA without explicit `preferred_monitor_role` field, **When** PWA launches, **Then** system uses workspace number to infer monitor role based on distribution rules

---

### User Story 4 - Declarative Floating Window Configuration (Priority: P2)

As a user who prefers certain applications to float above tiled windows, I want to declare which applications should float by default in the same configuration file where I define the application, so that floating behavior, window sizing, and workspace placement are centralized and predictable without manual window manipulation.

**Why this priority**: Important for workflow efficiency as certain applications (calculators, system monitors, temporary terminals) work better as floating overlays. Secondary to core monitor assignment but enhances overall workspace layout control.

**Independent Test**: Can be fully tested by adding `floating = true` and `floating_size = "medium"` to an application in `app-registry-data.nix`, launching the application, and verifying it appears as a floating window at the specified size on its preferred workspace.

**Acceptance Scenarios**:

1. **Given** an application entry with `floating = true` and `preferred_workspace = 7`, **When** the application launches, **Then** it appears as a floating window overlaying workspace 7 rather than tiling into the layout
2. **Given** a floating application with `floating_size = "scratchpad"` (1200×600), **When** the application launches, **Then** the window is sized to 1200×600 pixels and centered on the current monitor
3. **Given** a floating application with `scope = "scoped"`, **When** switching to a different project, **Then** the floating window hides along with other scoped windows for that project
4. **Given** a floating application with `scope = "global"`, **When** switching projects, **Then** the floating window remains visible across all projects
5. **Given** multiple floating windows on the same workspace, **When** windows launch, **Then** each maintains its configured size and stacks according to launch order
6. **Given** an application without explicit `floating` field, **When** the application launches, **Then** it defaults to tiling behavior (floating = false)

---

### User Story 5 - Monitor Role to Output Name Mapping (Priority: P3)

As a user with consistent monitor hardware, I want to specify which physical monitor outputs correspond to which roles (e.g., "HDMI-A-1" is always primary), so that my preferred monitor setup persists across reboots and doesn't depend on connection order.

**Why this priority**: Nice-to-have for users with stable hardware setups, but not essential for core functionality. Most users can rely on connection order-based role assignment.

**Independent Test**: Can be fully tested by defining output preferences in configuration (e.g., primary = "HDMI-A-1"), connecting monitors in different order, and verifying roles remain consistent with preferences.

**Acceptance Scenarios**:

1. **Given** configuration specifying `output_preferences = { primary = ["HDMI-A-1"]; secondary = ["eDP-1"]; }`, **When** monitors connect, **Then** HDMI-A-1 is assigned primary role regardless of connection order
2. **Given** preferred output for a role is disconnected, **When** system assigns roles, **Then** role is assigned to next available monitor in connection order
3. **Given** no output preferences defined, **When** monitors connect, **Then** roles are assigned by connection order (first = primary, second = secondary, third = tertiary)
4. **Given** output preferences change in configuration, **When** system rebuilds, **Then** new preferences take effect on next monitor change event

---

### Edge Cases

**Monitor Role Assignment**:
- What happens when an application specifies an invalid monitor role (e.g., "quaternary")? (System logs warning and falls back to primary role)
- How does system handle workspace numbers that conflict with distribution rules (e.g., WS 1 assigned to tertiary but WS 1-2 are hardcoded to primary)? (Explicit `preferred_monitor_role` overrides distribution rules)
- What happens when multiple applications share the same workspace number but specify different monitor roles? (Last declaration wins, log warning about conflict)
- How does system handle legacy apps without `preferred_monitor_role` field? (Use workspace number to infer role from distribution rules: WS 1-2 → primary, WS 3-5 → secondary, WS 6+ → tertiary)
- What happens when user manually moves a workspace to a different monitor? (Manual moves persist until next automatic reassignment event, then configuration overrides)
- How does system handle case-sensitivity in monitor role names? (Normalize to lowercase: "Primary" → "primary", "SECONDARY" → "secondary")
- What happens when a PWA and a regular app both specify the same workspace with different monitor roles? (PWA preference wins, as PWAs are more specific than general apps)

**Floating Window Behavior**:
- What happens when a floating window specifies an invalid size preset (e.g., "gigantic")? (System logs warning and falls back to "medium" size)
- How does system handle floating windows when their preferred workspace is on a disconnected monitor? (Window appears on fallback monitor, still floating on the reassigned workspace)
- What happens when a user manually toggles a floating window to tiling mode? (Manual toggle persists for current session, resets to configured behavior on next launch)
- How does system handle floating windows without explicit `floating_size` field? (Defaults to application's natural window size, still floats and centers)
- What happens when multiple floating windows overlap on the same workspace? (Windows stack by launch order, most recently launched on top, user can focus/reorder manually)
- How does system handle scoped floating windows during project switch? (Scoped floating windows hide to scratchpad like tiling windows, global floating windows remain visible)
- What happens when a floating window is moved to a different workspace manually? (Manual workspace move persists until window closes, resets to preferred workspace on next launch)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST read `preferred_monitor_role` field from application definitions in `app-registry-data.nix`
- **FR-002**: System MUST read `preferred_monitor_role` field from PWA definitions in `pwa-sites.nix`
- **FR-003**: System MUST validate `preferred_monitor_role` values are one of: "primary", "secondary", "tertiary" (case-insensitive)
- **FR-004**: System MUST apply fallback rules when preferred monitor role is unavailable: tertiary → secondary → primary
- **FR-005**: System MUST calculate workspace-to-output assignments based on combined data from app registry and PWA sites
- **FR-006**: System MUST apply workspace assignments during monitor connect/disconnect events (integrate with Feature 049)
- **FR-007**: System MUST assign monitor roles to outputs based on connection order when no output preferences exist
- **FR-008**: System MUST allow optional `output_preferences` configuration to map specific outputs to roles
- **FR-009**: System MUST prioritize explicit `preferred_monitor_role` declarations over workspace-based distribution rules
- **FR-010**: System MUST handle missing `preferred_monitor_role` field by inferring role from workspace number and distribution rules
- **FR-011**: System MUST persist current workspace-to-output assignments to match Feature 049's state file structure
- **FR-012**: System MUST log warnings when conflicting monitor roles are specified for the same workspace
- **FR-013**: System MUST support all three monitor configurations: 1 monitor, 2 monitors, 3+ monitors
- **FR-014**: System MUST complete workspace reassignment within existing performance budget (<1 second for typical configurations)
- **FR-015**: System MUST be hot-reloadable for application/PWA configuration changes without requiring full NixOS rebuild
- **FR-016**: System MUST read `floating` boolean field from application definitions to determine if window should float by default
- **FR-017**: System MUST read optional `floating_size` field from application definitions to determine floating window dimensions
- **FR-018**: System MUST validate `floating_size` values are one of: "scratchpad" (1200×600), "small" (800×500), "medium" (1200×800), "large" (1600×1000), or omitted for natural size
- **FR-019**: System MUST apply floating window rules during window launch, positioning window centered on the current monitor
- **FR-020**: System MUST assign floating windows to their configured `preferred_workspace` (floating windows overlay the workspace, not separate)
- **FR-021**: System MUST respect project filtering for floating windows based on `scope` field (scoped floating windows hide with project switch, global floating windows remain visible)
- **FR-022**: System MUST apply floating window size configuration via Sway window rules at launch time
- **FR-023**: System MUST handle missing `floating` field by defaulting to tiling behavior (floating = false)
- **FR-024**: System MUST handle missing `floating_size` field by allowing application's natural window size for floating windows

### Key Entities

- **Monitor Role**: Represents a logical monitor position (primary, secondary, tertiary) that applications and PWAs can reference for workspace placement, independent of physical output names
- **Workspace-Monitor Assignment**: Maps a workspace number to both a monitor role (from app/PWA configuration) and a physical output name (resolved at runtime based on active monitors), with fallback logic for reduced monitor counts
- **Application Monitor Preference**: Optional field in application/PWA definitions specifying the preferred monitor role for that application's workspace, provides centralized control over workspace layout
- **Output Preference**: Optional configuration mapping physical output names to monitor roles, allows users to specify consistent role assignments for specific hardware
- **Floating Window Configuration**: Optional fields in application/PWA definitions (`floating` boolean and `floating_size` preset) that control whether a window floats by default and its dimensions, integrated with workspace assignment and project filtering

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can define workspace-to-monitor assignments for 100% of applications and PWAs in a single declarative configuration file without runtime JSON files
- **SC-002**: System automatically reassigns workspaces within 1 second when monitor configuration changes from 3→2, 2→1, or 1→2→3 monitors
- **SC-003**: Workspace assignments persist correctly across system reboots with no manual intervention required
- **SC-004**: Users can predict workspace-to-monitor layout by reading configuration files alone, without inspecting runtime state
- **SC-005**: Configuration changes to monitor roles take effect immediately via hot-reload mechanism (no NixOS rebuild required)
- **SC-006**: Zero windows are lost or become inaccessible when monitors disconnect due to automatic fallback reassignment
- **SC-007**: Monitor role conflicts (multiple apps on same workspace with different roles) are detected and logged at configuration parse time, not runtime
- **SC-008**: System supports migration from existing hardcoded distribution rules to declarative configuration with zero downtime
- **SC-009**: Users can define floating behavior and window sizing for 100% of applications in declarative configuration without manual window rules
- **SC-010**: Floating windows respect project filtering with scoped floating windows hiding during project switch within 100ms
- **SC-011**: Floating window size presets provide consistent sizing across all applications without per-app custom dimensions

## Assumptions *(mandatory for AI-generated specs)*

1. **Configuration File Location**: We assume adding `preferred_monitor_role` to existing `app-registry-data.nix` and `pwa-sites.nix` files is acceptable, rather than creating new configuration files
2. **Fallback Logic**: We assume the fallback order tertiary → secondary → primary matches user expectations for degraded monitor configurations
3. **Integration with Feature 049**: We assume this feature extends Feature 049's automatic workspace distribution rather than replacing it
4. **Hot-Reload Mechanism**: We assume the existing Feature 047 dynamic config system can be adapted for monitor role assignments, or that Nix configuration changes can trigger reassignment without full rebuild
5. **Role Validation**: We assume three monitor roles (primary/secondary/tertiary) are sufficient, and additional roles (quaternary, etc.) are not needed
6. **Workspace Conflicts**: We assume last-declaration-wins is an acceptable conflict resolution strategy when multiple apps specify different roles for the same workspace
7. **Legacy Application Support**: We assume applications without `preferred_monitor_role` field should use workspace-based inference rather than failing validation
8. **Output Name Consistency**: We assume output names (e.g., "HDMI-A-1", "eDP-1") remain consistent across reboots for the same physical monitor
9. **State Persistence**: We assume Feature 049's `monitor-state.json` can be extended to include role-based assignments alongside output-based assignments
10. **Performance Impact**: We assume adding monitor role resolution adds negligible overhead (<10ms) to existing workspace assignment calculations
11. **Floating Window Workspace Assignment**: We assume floating windows should be assigned to regular workspaces (overlaying them) rather than having a dedicated floating workspace or no workspace assignment
12. **Floating Window Size Presets**: We assume four size presets (scratchpad, small, medium, large) plus natural size cover most use cases without requiring custom pixel-perfect dimensions per application
13. **Floating Window Positioning**: We assume centered positioning on the current monitor is the most intuitive default for floating windows
14. **Project Filtering for Floating Windows**: We assume floating windows should respect the existing `scope` field (scoped/global) for project filtering behavior, treating them identically to tiling windows except for their floating state

## Dependencies

- **External**: Sway 1.5+ (for output events and workspace commands), i3ipc Python library (for monitor queries)
- **Internal**:
  - Feature 049 (Intelligent Automatic Workspace-to-Monitor Assignment) - provides automatic reassignment infrastructure
  - Feature 047 (Sway Config Manager) - potentially provides hot-reload mechanism for configuration changes
  - `app-registry-data.nix` - application metadata source
  - `pwa-sites.nix` - PWA metadata source
  - i3pm daemon - event handling and workspace management
- **Configuration Files**:
  - `home-modules/desktop/app-registry-data.nix` (UPDATED - add `preferred_monitor_role` field)
  - `shared/pwa-sites.nix` (UPDATED - add `preferred_monitor_role` field)
  - `~/.config/sway/monitor-state.json` (UPDATED - include role-based assignments)

## Open Questions (Maximum 3 Clarifications)

None - reasonable defaults documented in Assumptions section cover all critical decisions.

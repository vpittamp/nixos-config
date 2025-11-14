# Feature Specification: Mark-Based App Identification with Key-Value Storage

**Feature Branch**: `076-mark-based-app-identification`
**Created**: 2025-11-14
**Status**: Draft
**Input**: User description: "while we're revising the approach more. here's another item to explore: does it make sense to inject a mark for the APP_NAME from our app-registry that uniquely defines that app that we launch in addition to our other marks? that way, when we restore we already have the app that needs to be launched? also, when considering how to store the marks, and retrieve them, does it make sense to use a key-value format so that we can add more valuable information in the future?"

## User Scenarios & Testing

### User Story 1 - Persistent App Identification During Layout Save (Priority: P1)

When saving a workspace layout, the system captures which applications are running and stores this information in a way that survives window manager restarts, process deaths, and PWA parent process reuse.

**Why this priority**: This is the foundation for reliable layout restoration. Without persistent app identification, the system cannot accurately restore layouts, especially for PWA applications that share parent processes.

**Independent Test**: Can be fully tested by saving a layout with multiple apps (including PWAs), examining the saved layout file to verify app names are stored, and confirms that information persists across system restarts.

**Acceptance Scenarios**:

1. **Given** multiple applications are running (terminal, code, PWAs), **When** user saves the layout, **Then** each window's app-registry name is stored in the layout file with its associated mark
2. **Given** a layout has been saved with app marks, **When** user examines the layout file, **Then** app names are clearly identifiable without needing to inspect running processes
3. **Given** PWA windows share a parent process, **When** layout is saved, **Then** each PWA window stores its unique app name (e.g., "chatgpt-pwa", "gmail-pwa") rather than generic "firefox"

---

### User Story 2 - Accurate Layout Restoration Using Stored App Names (Priority: P2)

When restoring a saved layout, the system reads the stored app names and launches exactly the applications that were saved, without needing to correlate windows after launch.

**Why this priority**: This directly addresses the correlation problem identified in Feature 075 research - by storing app names at save time, restoration becomes deterministic.

**Independent Test**: Can be fully tested by saving a layout, closing all applications, restoring the layout, and verifying that the exact applications from the saved layout are launched.

**Acceptance Scenarios**:

1. **Given** a layout with 3 apps saved (terminal on WS 1, code on WS 2, lazygit on WS 5), **When** user restores the layout starting from empty workspaces, **Then** exactly those 3 apps launch on their saved workspaces
2. **Given** a saved layout contains PWA apps, **When** user restores the layout, **Then** the correct PWA variants launch (e.g., chatgpt-pwa vs gmail-pwa) without ambiguity
3. **Given** some apps from a saved layout are already running, **When** user restores the layout, **Then** system identifies running apps by their marks and skips relaunching them (idempotent restore)

---

### User Story 3 - Extensible Mark Storage for Future Metadata (Priority: P3)

The system stores marks in a structured key-value format that allows adding additional metadata in the future (e.g., focused state, geometry, custom properties) without breaking existing layouts.

**Why this priority**: This is forward-looking infrastructure that prevents technical debt. While not critical for MVP, it avoids future rewrites when new features need additional metadata.

**Independent Test**: Can be fully tested by saving layouts with current mark format, adding a new key-value pair to the mark schema, and verifying that old layouts still restore correctly.

**Acceptance Scenarios**:

1. **Given** a layout is saved with current mark format, **When** system is updated with new metadata fields, **Then** old layouts continue to restore successfully (backward compatibility)
2. **Given** marks support key-value format, **When** future features add new metadata (e.g., "focused": true), **Then** marks can store and retrieve this data without schema migration
3. **Given** a mark contains multiple key-value pairs, **When** system reads the mark, **Then** it can access individual values efficiently without string parsing

---

### Edge Cases

- What happens when a mark contains a key-value pair the system doesn't recognize (forward compatibility)?
- How does the system handle marks that are malformed or corrupted?
- What if an app's registry name changes between save and restore (app renamed)?
- How are marks cleaned up when windows close (prevent mark pollution)?
- What happens if two windows have identical app names and workspaces (multi-instance apps)?

## Requirements

### Functional Requirements

- **FR-001**: System MUST inject a mark containing the app-registry name when launching any application via app-registry wrapper
- **FR-002**: System MUST store marks in a structured key-value format (e.g., `i3pm_app:terminal`, `i3pm_ws:1`)
- **FR-003**: System MUST persist marks in saved layout files alongside existing window data
- **FR-004**: System MUST read app names from marks during layout restoration without needing to inspect process environments
- **FR-005**: System MUST support adding new key-value pairs to marks without breaking existing functionality (extensibility)
- **FR-006**: System MUST handle missing or malformed marks gracefully (fall back to environment variable detection)
- **FR-007**: System MUST remove marks when windows close to prevent mark namespace pollution
- **FR-008**: System MUST support querying marks by key (e.g., "get all windows with `i3pm_app:terminal`")
- **FR-009**: System MUST ensure marks are unique per window (no mark conflicts)
- **FR-010**: System MUST preserve marks across Sway reloads and restarts

### Key Entities

- **Mark**: A Sway-native identifier attached to a window, stored as key-value pairs (e.g., `i3pm_app:terminal`, `i3pm_project:nixos`, `i3pm_ws:1`)
  - Contains: key (string), value (string), window_id (reference)
  - Relationship: One window can have multiple marks, each mark belongs to one window

- **Saved Layout Window**: A window entry in a saved layout file
  - Contains: app_registry_name (from mark), workspace (from mark), cwd, focused state, geometry, associated marks
  - Relationship: Each saved window preserves its marks for restoration

- **App Registry Entry**: Definition of an application in the app-registry
  - Contains: app_name (unique identifier), launch_command, default_workspace, scoped flag
  - Relationship: Each app registry entry corresponds to one unique app_name stored in marks

## Success Criteria

### Measurable Outcomes

- **SC-001**: Layout save operation captures app names for 100% of windows launched via app-registry
- **SC-002**: Layout restoration identifies app to launch from saved marks in under 1ms per window (no process environment scanning needed)
- **SC-003**: Restoration is idempotent - running restore 3 times consecutively with all apps running results in 0 duplicate windows
- **SC-004**: Mark format supports adding new key-value pairs without breaking layouts saved in previous versions (backward compatibility)
- **SC-005**: PWA windows with shared parent processes are correctly identified by their unique app names from marks
- **SC-006**: Mark cleanup rate is 100% - no orphaned marks remain after windows close

## Assumptions

1. **Sway mark support**: Assumes Sway's mark/unmark commands work reliably and marks persist across window manager reloads
2. **Unique app names**: Assumes app-registry names are unique identifiers (no two different apps share the same name)
3. **Key-value format**: Assumes marks can contain colon-separated key-value pairs without conflicting with Sway's mark syntax (e.g., `i3pm_app:terminal` is valid)
4. **Launch wrapper control**: Assumes all app launches go through the app-registry wrapper (system can inject marks at launch time)
5. **Mark namespace**: Assumes `i3pm_` prefix prevents conflicts with user-created marks or other tools
6. **Storage format**: Assumes layout files can store mark data as structured JSON/TOML (not just window IDs)

## Dependencies

- **Feature 074**: Session Management infrastructure (layout save/restore framework)
- **Feature 035**: Registry-Centric Architecture (app-registry definitions and wrapper system)
- **Sway IPC**: Mark/unmark commands, window query with marks filter

## Design Decisions

### Mark Storage Format

**Decision**: Marks will be stored in layout files as structured nested objects (e.g., `"marks": {"app": "terminal", "project": "nixos"}`)

**Rationale**: This format provides easier querying of specific keys during restore operations and better supports future extensibility when adding new metadata fields. While it requires slightly more complex parsing than flat arrays, the benefit of structured access outweighs the implementation cost.

### Non-App-Registry Apps Handling

**Decision**: Layout save will ignore windows not launched via app-registry wrapper (layout only includes app-registry apps)

**Rationale**: This provides the simplest and most reliable implementation. By restricting layouts to app-registry apps only, we ensure 100% restore accuracy and avoid correlation issues. Users can add manually-started apps to the app-registry if they need them in layouts.

### Mark Cleanup Strategy

**Decision**: Marks will be cleaned up immediately when windows close via window::close event handler

**Rationale**: Immediate cleanup guarantees zero mark namespace pollution and provides real-time consistency. While this adds event handler overhead, the cleanup operation is fast (single IPC unmark command) and prevents any potential conflicts from orphaned marks.

# Feature Specification: PWA Launcher Integration & Event Logging

**Feature Branch**: `054-pwa-launcher-integration`
**Created**: 2025-11-02
**Status**: Draft
**Input**: User description: "Fix PWA launcher integration to ensure Walker/Elephant can discover and launch installed Firefox PWAs. Review pwa-install-all output to verify profile IDs match desktop file naming. Add app-launcher-wrapper.sh logging to i3pm events for launch visibility."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Launch PWA from Walker (Priority: P1)

User wants to launch an installed PWA (e.g., YouTube, Google AI) from Walker/Elephant application launcher by typing the app name and having it open immediately in a dedicated window with proper workspace assignment.

**Why this priority**: This is the core value proposition - PWAs are already installed via firefoxpwa (confirmed by `pwa-install-all` showing all 13 PWAs), but users cannot launch them from the primary application launcher. Without this, installed PWAs are unusable.

**Independent Test**: Can be fully tested by opening Walker (Meta+D), typing "youtube", hitting Return, and verifying YouTube PWA opens in a dedicated window on workspace 4.

**Acceptance Scenarios**:

1. **Given** PWAs are installed via firefoxpwa (13 PWAs with valid profile IDs), **When** user types "youtube" in Walker, **Then** YouTube PWA option appears in launcher results
2. **Given** user selects YouTube PWA from Walker, **When** Return key is pressed, **Then** `launch-pwa-by-name youtube-pwa` executes successfully
3. **Given** YouTube PWA profile ID is 01K666N2V6BQMDSBMX3AY74TY7, **When** launch command runs, **Then** `firefoxpwa site launch 01K666N2V6BQMDSBMX3AY74TY7` is invoked
4. **Given** YouTube PWA has `preferred_workspace = 4` in app-registry-data.nix, **When** PWA window appears, **Then** window is assigned to workspace 4 via Feature 053 event-driven assignment

---

### User Story 2 - Monitor PWA Launch Events (Priority: P2)

User wants to see real-time PWA launch events in `i3pm events` output, showing when Walker triggers app-launcher-wrapper.sh and how the launch progresses through notification ’ window creation ’ workspace assignment.

**Why this priority**: This enables troubleshooting launch failures and validates the end-to-end launch pipeline. It's essential for debugging but P1 functionality (successful launch) can work without visible logging.

**Independent Test**: Can be fully tested by running `i3pm events --follow` in one terminal, launching YouTube PWA from Walker, and verifying events appear showing launch notification ’ systemd-run execution ’ window creation ’ workspace assignment.

**Acceptance Scenarios**:

1. **Given** `i3pm events --follow` is running, **When** user launches YouTube PWA from Walker, **Then** app::launch event appears with app_name=youtube-pwa
2. **Given** app-launcher-wrapper.sh executes, **When** systemd-run launches firefoxpwa, **Then** app::launch_success or app::launch_failed event appears with exit code
3. **Given** PWA window appears, **When** daemon processes window::new, **Then** window::new event shows FFPWA class and correct profile correlation
4. **Given** workspace assignment completes, **When** daemon assigns to workspace 4, **Then** workspace::assignment event shows decision tree with launch_notification priority 0 match

---

### User Story 3 - Verify Desktop File Discovery (Priority: P3)

User wants to verify which desktop files Walker/Elephant can discover, ensuring all installed PWAs have accessible .desktop files with correct naming and Exec commands.

**Why this priority**: This enables validation of the integration layer but is diagnostic/maintenance focused. P1/P2 cover the user-facing functionality.

**Independent Test**: Can be fully tested by running a desktop file discovery command and verifying all 13 PWAs appear with correct naming pattern (FFPWA-* or app registry name) and valid Exec commands.

**Acceptance Scenarios**:

1. **Given** 13 PWAs are installed, **When** desktop file discovery runs, **Then** all 13 PWAs have discoverable .desktop files
2. **Given** YouTube PWA profile is 01K666N2V6BQMDSBMX3AY74TY7, **When** desktop file is read, **Then** Exec command matches `firefoxpwa site launch 01K666N2V6BQMDSBMX3AY74TY7` or `launch-pwa-by-name youtube-pwa`
3. **Given** desktop files exist, **When** Elephant service starts, **Then** all PWAs appear in Walker search index
4. **Given** `pwa-list` command runs, **When** comparing installed PWAs to discoverable desktop files, **Then** 100% match rate

---

### Edge Cases

- What happens when a PWA profile ID in configuration doesn't match the actual installed profile?
- How does system handle PWA launch when firefoxpwa command is not found?
- What if Walker/Elephant cache is stale and doesn't see new desktop files?
- How does system log launch failures (e.g., profile not found, permission denied)?
- What if multiple PWAs have similar names (e.g., "Google AI" vs "Google AI Studio")?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `launch-pwa-by-name` script MUST map PWA app names to correct firefoxpwa profile IDs (e.g., youtube-pwa ’ 01K666N2V6BQMDSBMX3AY74TY7)
- **FR-002**: Desktop files MUST be discoverable by Walker/Elephant in standard XDG locations (~/.local/share/applications/ or ~/.local/share/i3pm-applications/applications/)
- **FR-003**: Desktop file Exec commands MUST invoke `launch-pwa-by-name <app-name>` or `firefoxpwa site launch <profile-id>`
- **FR-004**: `app-launcher-wrapper.sh` MUST emit app::launch event to daemon when PWA launch is triggered
- **FR-005**: `app-launcher-wrapper.sh` MUST emit app::launch_success event with execution details when systemd-run succeeds
- **FR-006**: `app-launcher-wrapper.sh` MUST emit app::launch_failed event with error message and exit code when systemd-run fails
- **FR-007**: Launch events MUST include app_name, command, launcher_pid, timestamp fields for correlation
- **FR-008**: `i3pm events` command MUST display app::launch, app::launch_success, app::launch_failed events with readable formatting
- **FR-009**: Event buffer MUST record launch events with retention of last 500 events (same as other event types)
- **FR-010**: Launch event timestamps MUST correlate with window::new events within 5 seconds for successful launches

### Key Entities *(include if feature involves data)*

- **PWA Desktop File**: XDG desktop entry with Name, Exec, Icon fields pointing to firefoxpwa or launch-pwa-by-name
- **PWA Profile ID**: Unique identifier from firefoxpwa (e.g., 01K666N2V6BQMDSBMX3AY74TY7) stored in ~/.local/share/firefoxpwa/profiles/
- **Launch Event**: Event buffer entry capturing app launch attempt with app_name, command, status, error (if failed)
- **App Registry Entry**: Configuration mapping app name to launch command and profile ID

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can launch any of the 13 installed PWAs from Walker within 2 seconds (from typing to window open)
- **SC-002**: 100% of installed PWAs (13/13) appear in Walker search results when user types app name
- **SC-003**: PWA launches generate visible app::launch event in `i3pm events` output within 50ms of Walker execution
- **SC-004**: Successful PWA launches show app::launch_success event with systemd-run output within 100ms
- **SC-005**: Failed PWA launches show app::launch_failed event with error message and non-zero exit code
- **SC-006**: Launch events correlate with window::new events (same app_name) within 5 seconds for 95% of successful launches

## Assumptions

- Firefox PWA extension (firefoxpwa) is installed and all 13 PWAs are already installed (confirmed by user's pwa-install-all output)
- PWA profile IDs in configuration match actual installed profiles (e.g., YouTube = 01K666N2V6BQMDSBMX3AY74TY7)
- Walker/Elephant launcher respects XDG desktop file specification for application discovery
- `app-launcher-wrapper.sh` is the standard launcher invoked by Walker/Elephant for registry apps
- Daemon event buffer infrastructure from Feature 053 is available for launch event recording

## Dependencies

- **Feature 053**: Workspace assignment enhancement (complete) - provides event-driven assignment and event buffer
- **Feature 043**: Walker/Elephant launcher - provides application launcher service
- **Firefox PWA Extension**: firefoxpwa command must be available in PATH
- **systemd-run**: Required by app-launcher-wrapper.sh for process isolation

## Out of Scope

- Creating new PWA profiles (all 13 PWAs already installed)
- Modifying firefoxpwa profile IDs or PWA installation logic
- Changing Walker/Elephant search algorithm or ranking
- PWA icon customization (icons already configured)
- PWA auto-update or sync mechanisms
- Converting between desktop file naming schemes (FFPWA-* vs WebApp-*)

## Technical Constraints

- Must maintain compatibility with existing app-launcher-wrapper.sh parameter substitution (I3PM_* env vars)
- Must not break existing non-PWA application launches
- Must work with both Sway (Hetzner) and i3 (if applicable) window managers
- Desktop files must follow freedesktop.org desktop entry specification v1.5
- Must preserve existing event buffer capacity (500 events) and performance (<10ms event recording)
- Launch events must use same EventEntry dataclass as other event types (flat structure)

## Risks

- **Risk**: PWA profile IDs in configuration may not match installed profiles (e.g., after reinstallation)
  - **Mitigation**: Add validation step to compare pwa-install-all output with app-registry-data.nix profile mappings

- **Risk**: Walker/Elephant may cache desktop file list and miss updates
  - **Mitigation**: Document Elephant service restart procedure (systemctl --user restart elephant)

- **Risk**: Launch event flooding if rapid launches occur (e.g., user spamming Return key)
  - **Mitigation**: Use existing event buffer deque with maxlen=500 (old events auto-purge)

- **Risk**: systemd-run output capture may truncate or fail for long-running processes
  - **Mitigation**: Capture only initial launch status, rely on window::new correlation for success confirmation

## Open Questions

- Should launch events include full command string or just app_name for security/privacy?
- Should we add a PWA profile ID validation check to app-launcher-wrapper.sh before launching?
- Should Elephant service automatically refresh desktop file cache when PWAs are installed?
- Should launch events distinguish between Walker launches vs manual command-line launches?

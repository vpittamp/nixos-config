# Feature Specification: i3run-Inspired Application Launch UX

**Feature Branch**: `051-i3run-enhanced-launch`
**Created**: 2025-01-06
**Updated**: 2025-01-06 (scope revision after critical analysis)
**Status**: Draft
**Input**: User description: "after transforming our project to use 'sway exec' to launch applications, create a new feature that considers the opensource project, @docs/budlabs-i3run-c0cc4cc3b3bf7341.txt, which contains logic for launching applications in i3 (equivalent to sway in x11) that addresses some of the quirks of i3/sway and thinks about the user experience relative to running sway/i3 applications. determine if any of the project's logic and consolidated commands would help our implementation relative to better user experience, simplicity, and enhanced functionality."

**See**: `analysis-window-matching.md` for detailed comparison of i3run vs our I3PM_* environment system

## Executive Summary

This feature adopts i3run's superior **UX patterns** for application launching while **rejecting** its window matching approach. Our existing I3PM_* environment variable system provides objectively better window identification than i3run's class/instance/title matching.

**Core Insight**: i3run solves two problems:
1. Window matching (class/instance/title) - **We have better solution** (I3PM_* environment)
2. Application launch UX (run-raise-hide, summon) - **We should adopt** (proven patterns)

This spec focuses on #2 only.

## User Scenarios & Testing

### User Story 1 - Smart Application Toggle (Run-Raise-Hide) (Priority: P1)

User wants single keybinding to toggle frequently-used applications without managing window state manually. Current system requires separate commands for launch vs focus vs hide.

**Why this priority**: Foundational UX improvement that every application interaction benefits from. Reduces cognitive load and keybinding complexity.

**Independent Test**: Bind single key (e.g., Super+B for browser), press repeatedly:
- Press 1: Launches firefox (not running)
- Press 2: Focuses firefox (was on different workspace)
- Press 3: Hides firefox to scratchpad (was focused)
- Press 4: Shows firefox from scratchpad (was hidden)
- Press 5: Hides again (cycle continues)

**Acceptance Scenarios**:

1. **Given** application not running, **When** user triggers run command, **Then** application launches via existing app-launcher-wrapper.sh
2. **Given** application running on different workspace, **When** user triggers run command, **Then** user switches to application's workspace and window receives focus
3. **Given** application running and focused on current workspace, **When** user triggers run command, **Then** application hides to scratchpad
4. **Given** application hidden in scratchpad, **When** user triggers run command, **Then** application appears on current workspace with focus
5. **Given** application running but unfocused on current workspace, **When** user triggers run command, **Then** application receives focus (no hide)

---

### User Story 2 - Summon Mode (Bring Window to Current Workspace) (Priority: P1)

User wants option to bring window to current workspace instead of switching workspace. Useful when composing work across multiple workspaces or quickly referencing information.

**Why this priority**: Critical for multi-workspace workflows. Default behavior (workspace switch) interrupts context, summon mode preserves it.

**Independent Test**: Launch application on workspace 1, switch to workspace 2, trigger run command with --summon flag, verify window moves to workspace 2 (rather than switching to workspace 1).

**Acceptance Scenarios**:

1. **Given** application on workspace 1 and user on workspace 2, **When** user triggers run --summon, **Then** window moves to workspace 2 with focus
2. **Given** application in scratchpad, **When** user triggers run --summon, **Then** window appears on current workspace (same as normal run)
3. **Given** summon mode active and window moved to new workspace, **When** window properties checked, **Then** original floating state and geometry are preserved

---

### User Story 3 - Generalized Scratchpad State Preservation (Priority: P2)

User wants windows to remember their floating state and geometry when hiding/showing from scratchpad. Currently only scratchpad terminal (Feature 062) preserves state.

**Why this priority**: Prevents jarring state changes when toggling applications. Important for consistent UX, but not critical for basic functionality.

**Independent Test**: Configure floating window with specific geometry, hide to scratchpad via run command, show from scratchpad, verify floating state and geometry match original (within 10-pixel tolerance).

**Acceptance Scenarios**:

1. **Given** tiling window on workspace, **When** hidden to scratchpad, **Then** system stores floating=false
2. **Given** floating window with geometry (1000x600 at 500,300), **When** hidden to scratchpad, **Then** system stores floating=true and geometry
3. **Given** window hidden with stored state, **When** shown from scratchpad, **Then** window restores floating=false/true and geometry (within 10px tolerance)
4. **Given** window shown and closed, **When** state storage checked, **Then** stored state is cleared (no memory leak)

---

### User Story 4 - Force Multi-Instance Launch (Priority: P2)

User wants explicit control to launch new instance of application even when existing instance is running. Useful for terminals, browsers with different profiles, VS Code for different projects.

**Why this priority**: Enables power-user workflows but not required for basic use. Most applications are single-instance.

**Independent Test**: Launch terminal normally (focuses existing), trigger run --force, verify new terminal appears with different I3PM_APP_ID while original terminal remains running.

**Acceptance Scenarios**:

1. **Given** application running, **When** user triggers run --force, **Then** new instance launches via app-launcher-wrapper.sh (existing window not affected)
2. **Given** force-launched instance appears, **When** daemon identifies window, **Then** window has unique I3PM_APP_ID (includes PID and timestamp)
3. **Given** multiple instances running, **When** user triggers normal run (no --force), **Then** most recently focused instance receives focus (no new launch)

---

### User Story 5 - Explicit Hide/Nohide Control (Priority: P3)

User wants option to prevent hiding when window is focused, or always hide regardless of state. Useful for scripting and custom workflows.

**Why this priority**: Niche use case for power users. Smart toggle (P1) works well for most scenarios.

**Independent Test**: Configure application with --nohide flag, ensure window is focused, trigger run command, verify focus changes but window doesn't hide. Then test --hide flag to always hide regardless of state.

**Acceptance Scenarios**:

1. **Given** window focused and --nohide flag set, **When** user triggers run, **Then** focus remains but window doesn't hide to scratchpad
2. **Given** window on different workspace and --hide flag set, **When** user triggers run, **Then** window hides to scratchpad (doesn't focus first)
3. **Given** window in scratchpad and --hide flag set, **When** user triggers run, **Then** window shows (hide only applies when visible)

---

### Edge Cases

- **Window closed during operation**: System detects missing window via Sway IPC query, returns error to user
- **Multiple instances with same app name**: System uses I3PM_APP_ID for unique identification, targets most recently focused
- **Launch command fails**: System logs error, returns non-zero exit code, provides actionable error message (command not found, permission denied)
- **Window appears on wrong workspace**: Launch notification (Feature 041) guides workspace assignment, daemon validates via I3PM_TARGET_WORKSPACE
- **Scratchpad state storage grows unbounded**: System clears stored state when window is closed (monitors window::close events)
- **Summon disrupts tiling layout**: Sway automatically reflows layout when window moves, user can manually adjust if needed

## Requirements

### Functional Requirements

#### Core Application Control

- **FR-001**: System MUST support Run-Raise-Hide pattern with 5 states: not found (launch), different workspace (switch+focus), same workspace unfocused (focus), same workspace focused (hide), scratchpad (show)
- **FR-002**: System MUST use existing I3PM_* environment variables for window identification (NO new multi-criteria matching system)
- **FR-003**: System MUST integrate with existing app-launcher-wrapper.sh for application launching (no duplicate launch logic)
- **FR-004**: System MUST query daemon via IPC for window state detection (workspace, focus, scratchpad)

#### Workspace Behavior

- **FR-005**: System MUST support goto mode (switch to window's workspace) as default behavior
- **FR-006**: System MUST support summon mode (move window to current workspace) via --summon flag
- **FR-007**: System MUST preserve window floating state and geometry when moving between workspaces

#### Scratchpad Management

- **FR-008**: System MUST store window floating state (true/false) before hiding to scratchpad
- **FR-009**: System MUST store window geometry (x, y, width, height) before hiding to scratchpad (floating windows only)
- **FR-010**: System MUST restore original floating state when showing window from scratchpad
- **FR-011**: System MUST restore original geometry when showing window from scratchpad (within 10-pixel tolerance)
- **FR-012**: System MUST clear stored state when window is closed (prevent memory leak)
- **FR-013**: System MUST support explicit --hide flag (always hide) and --nohide flag (never hide) to override smart toggle

#### Multi-Instance Support

- **FR-014**: System MUST support --force flag to launch new instance even if window exists
- **FR-015**: System MUST use existing I3PM_APP_ID for instance differentiation (no new mechanism required)
- **FR-016**: System MUST target most recently focused window when multiple instances match same app name

#### CLI Interface

- **FR-017**: System MUST provide `i3pm run <app-name>` command accepting registered application name from registry
- **FR-018**: System MUST accept flags: --summon (move to current workspace), --force (launch new instance), --hide (always hide), --nohide (never hide)
- **FR-019**: System MUST return container ID on success (for scripting integration)
- **FR-020**: System MUST return non-zero exit code on failure (command not found, timeout, window closed)

#### Error Handling

- **FR-021**: System MUST handle launch failures gracefully (command not found, permission denied, timeout after 2 seconds)
- **FR-022**: System MUST handle missing window gracefully (window closed between query and operation)
- **FR-023**: System MUST provide actionable error messages (not just "failed", but "command 'foo' not found, install via nix-env -iA nixpkgs.foo")

#### Integration Points

- **FR-024**: System MUST integrate with existing application registry (application-registry.json) for app name lookup
- **FR-025**: System MUST integrate with existing i3pm daemon IPC protocol for window state queries
- **FR-026**: System MUST integrate with existing app-launcher-wrapper.sh for launching (no duplicate logic)
- **FR-027**: System MUST integrate with existing scratchpad terminal implementation (Feature 062) patterns for state storage

### Key Entities

- **Window State** (detected via Sway IPC):
  - workspace: Current workspace number or "__i3_scratch" (scratchpad)
  - focused: Whether window currently has input focus (boolean)
  - visible: Whether window is visible on a workspace (not hidden)
  - floating: Whether window is floating or tiled (boolean)
  - geometry: Window position and size {x, y, width, height} (floating only)

- **Scratchpad State Storage** (in daemon memory):
  - Key: Window container ID (Sway conid)
  - Value: {floating: boolean, geometry: {x, y, width, height}}
  - Lifecycle: Created on hide, restored on show, cleared on window close

- **Run Command Behavior**:
  - app_name: Application identifier from registry (e.g., "firefox", "alacritty")
  - mode: "goto" (default, switch workspace) or "summon" (move window)
  - force: boolean (launch new instance vs focus existing)
  - hide_override: "smart" (default), "always", or "never"

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can toggle any registered application with single command, with correct state-dependent behavior (launch/focus/hide/show) occurring within 500ms in 95% of cases
- **SC-002**: Summon mode successfully moves windows between workspaces while preserving floating state and geometry (within 10-pixel tolerance) in 100% of cases
- **SC-003**: Scratchpad hide/show operations preserve window state with less than 10-pixel geometry error in 95% of cases
- **SC-004**: Force-launch mode successfully creates independent instances with unique I3PM_APP_ID in 100% of cases
- **SC-005**: CLI commands provide clear actionable error messages for all failure modes (launch fail, window closed, timeout) in 100% of cases
- **SC-006**: State storage memory usage remains bounded (no leaks) during 24-hour operation with 100+ hide/show cycles

## Assumptions

- Sway compositor is running and swaymsg command is available for IPC communication
- I3pm daemon is running and accepting IPC requests via Unix socket
- Application registry is properly configured with all application names user wants to toggle
- All applications are launched via app-launcher-wrapper.sh (ensures I3PM_* environment variables)
- User has basic familiarity with i3/Sway workspace model and scratchpad concept
- Scratchpad can hold multiple hidden windows simultaneously (Sway feature)
- Window geometry is stable after launch (not dynamically resizing frequently)

## Dependencies

- **Feature 041**: IPC Launch Context - Pre-notification system for window correlation
- **Feature 057**: Unified Application Launcher - app-launcher-wrapper.sh and I3PM_* environment injection
- **Feature 062**: Project-Scoped Scratchpad Terminal - Existing scratchpad state preservation patterns
- **Feature 058**: Python Backend Consolidation - Daemon infrastructure for IPC and state management
- **Sway IPC**: Direct access to compositor state via swaymsg commands and GET_TREE queries
- **Application Registry**: JSON configuration file with application definitions

## Out of Scope

- **Multi-criteria window matching** (class/instance/title/conid/winid) - Our I3PM_* environment system is superior, see analysis-window-matching.md
- **Window renaming/property modification** (i3run's --rename feature) - Requires xdotool, incompatible with Wayland, unnecessary with I3PM_* system
- **External rule files** (i3king-style rules) - We have Feature 047 (dynamic Sway config) + application registry, no duplication needed
- **Mouse-relative window positioning** (i3run's --mouse feature) - Niche use case, adds complexity (cursor queries, geometry calculations), defer to future enhancement
- **i3fyra container integration** - Specialized layout system not applicable to general window management
- **Window state persistence across compositor restarts** - Requires separate layout save/restore feature
- **Automatic window property learning** - Requires observation over time, unnecessary with deterministic I3PM_* matching

## Technical Notes

### Why We Rejected i3run's Window Matching

See `analysis-window-matching.md` for detailed comparison. Summary:

**i3run uses**: class, instance, title, conid, winid matching (non-deterministic, fragile, configuration burden)

**We have**: I3PM_* environment variables (100% deterministic, fast <5ms, project-aware, works with PWAs/Electron)

**Verdict**: Our system is objectively superior. No value in adopting i3run's matching approach.

### What We DID Adopt from i3run

1. **Run-Raise-Hide State Machine** (i3run lines 134-138, 615-697):
   - 5-state pattern: not found → launch, different WS → goto, same WS unfocused → focus, focused → hide, hidden → show
   - Proven UX, reduces keybinding complexity

2. **Summon vs Workspace Switch** (i3run lines 660-691):
   - User choice: move window to current workspace vs switching to window's workspace
   - Critical for multi-workspace workflows

3. **Scratchpad State Preservation** (i3run lines 706-724):
   - Store floating state + geometry before hiding
   - Restore when showing (prevents jarring state changes)
   - Generalize Feature 062's scratchpad terminal logic

4. **Force-Launch Flag** (i3run lines 693, 718):
   - Explicit control to launch new instance
   - Uses existing I3PM_APP_ID for differentiation

### What We Rejected from i3run

1. **Window Property Matching** - Solved by I3PM_* environment
2. **Window Renaming** - Wayland-incompatible, unnecessary
3. **External Rule Files** - Have Feature 047 + registry
4. **Mouse Positioning** - Niche, complex, defer

### Implementation Architecture

```
User: i3pm run firefox
  ↓
CLI parses command + flags (--summon, --force, --hide, --nohide)
  ↓
Query daemon via IPC: get_window_state(app_name="firefox")
  ├→ Daemon queries Sway IPC for windows with I3PM_APP_NAME=firefox
  ├→ Returns: {state: "focused"|"unfocused"|"different_ws"|"scratchpad"|"not_found",
  │           conid: 12345, workspace: 3, floating: true, geometry: {...}}
  └→ For multiple instances: returns most recently focused
  ↓
State Machine Transition (based on state + flags):
  ├→ not_found: Launch via app-launcher-wrapper.sh
  ├→ different_ws + goto: Switch to workspace, focus window
  ├→ different_ws + summon: Move window to current WS, focus
  ├→ unfocused: Focus window
  ├→ focused + smart_toggle: Store state, hide to scratchpad
  ├→ focused + nohide: No action (or refocus)
  ├→ scratchpad: Restore state, show on current WS
  └→ any + force: Launch new instance (skip state check)
  ↓
Execute Sway IPC commands
  ↓
Return container ID or error
```

### Scratchpad State Storage

Stored in daemon memory (dict):

```python
scratchpad_states: Dict[int, ScratchpadState] = {}

@dataclass
class ScratchpadState:
    conid: int
    floating: bool
    geometry: Optional[Rect]  # None for tiling windows
    stored_at: float  # timestamp for debugging

# On hide:
state = ScratchpadState(
    conid=window.id,
    floating=window.floating,
    geometry=window.rect if window.floating else None,
    stored_at=time.time()
)
scratchpad_states[window.id] = state

# On show:
state = scratchpad_states.get(window.id)
if state:
    # Apply state via Sway IPC
    swaymsg(f"[con_id={state.conid}] floating {'enable' if state.floating else 'disable'}")
    if state.geometry:
        swaymsg(f"[con_id={state.conid}] move absolute position {state.geometry.x} {state.geometry.y}")
        swaymsg(f"[con_id={state.conid}] resize set {state.geometry.width} {state.geometry.height}")

# On window::close event:
if window.id in scratchpad_states:
    del scratchpad_states[window.id]
```

### CLI Command Design

```bash
# Basic toggle (smart run-raise-hide)
i3pm run firefox                    # Launch or focus or hide (depending on state)

# Summon mode (bring to current workspace)
i3pm run firefox --summon           # Move window to current WS instead of switching

# Force new instance
i3pm run alacritty --force          # Launch new terminal even if one exists

# Explicit hide control
i3pm run firefox --hide             # Always hide (even if on different WS)
i3pm run firefox --nohide           # Never hide (focus only)

# Combinations
i3pm run firefox --summon --nohide  # Bring to current WS, don't hide if already here

# Scripting
CONID=$(i3pm run firefox --summon)  # Returns container ID on success
if [ $? -eq 0 ]; then
    echo "Firefox container: $CONID"
else
    echo "Failed to run firefox"
fi
```

### Integration with Existing Features

- **Feature 041**: Launch notification already implemented, no changes needed
- **Feature 057**: app-launcher-wrapper.sh already injects I3PM_*, no changes needed
- **Feature 062**: Scratchpad terminal uses same state preservation pattern, generalize to `scratchpad_manager.py` module
- **Feature 058**: Daemon infrastructure ready, add `get_window_state()` RPC method

### Performance Targets

- Window state query: <10ms (Sway IPC GET_TREE + /proc read)
- State transition execution: <50ms (Sway IPC commands)
- Total run command latency: <100ms (query + transition + response)
- Memory overhead: <1KB per stored scratchpad state (<100KB for 100 windows)

# Research Report: Interactive Monitoring Widget Actions

**Feature**: 093-actions-window-widget
**Date**: 2025-11-23
**Purpose**: Resolve technical unknowns for adding click interactions to Eww monitoring panel

## Research Questions & Findings

### 1. Eww Click Handler Implementation Patterns

**Question**: How are click handlers implemented in existing Eww widgets, and what are the patterns for command execution, variable interpolation, and error handling?

**Findings**:

#### Pattern A: Simple External Command Execution
```yuck
:onclick "COMMAND &"
```
**Examples from codebase**:
- `"nm-connection-editor &"` (network settings)
- `"pavucontrol &"` (volume control)
- `"i3pm project switch &"` (project switching)

**Key characteristics**:
- Background execution using `&` for GUI apps
- Direct command invocation without intermediate scripts
- No error handling at Eww level

#### Pattern B: Eww Variable Update
```yuck
:onclick "eww --config $HOME/.config/eww-monitoring-panel update current_view=windows"
```
**Use case**: Tab switching in monitoring panel (lines 429-450 in eww-monitoring-panel.nix)

**Key characteristics**:
- Immediate UI state changes
- Full config path required (`--config $HOME/...`)
- Variable interpolation: `''${window.id}` for dynamic values

#### Pattern C: Inline Shell Script with Arguments
```yuck
:onclick "${pkgs.writeShellScript "copy-json" ''
  # Bash code here
''} ''${window.json_base64} ''${window.id} &"
```
**Use case**: Clipboard copy with visual feedback (lines 653-661 in eww-monitoring-panel.nix)

**Key characteristics**:
- Nix store paths for reproducibility
- Arguments passed after script path
- State feedback via eww update
- Auto-reset after delay: `(sleep 2 && eww update ...) &`

#### Pattern D: Service Restart with Error Notifications
```yuck
:onclick "restart-service ''${service.service_name} ''${service.is_user_service ? 'true' : 'false'} &"
```
**Shell script wrapper** (lines 167-207):
```bash
if [[ -z "$SERVICE_NAME" ]]; then
    notify-send -u critical "Service Restart Failed" "No service name provided"
    exit 1
fi

if systemctl restart "$SERVICE_NAME"; then
    notify-send -u normal "Service Restarted" "Successfully restarted $SERVICE_NAME"
else
    notify-send -u critical "Service Restart Failed" "..."
fi
```

**Key characteristics**:
- Input validation with error messages
- Success/failure notifications via `notify-send`
- Exit code propagation
- User-friendly error messages

#### Pattern E: Sway IPC Command with Escaping
```yuck
:onclick {
  "swaymsg workspace \""
  + replace(workspace_name, "\"", "\\\"")
  + "\""
}
```
**Use case**: Workspace navigation (lines 511-534 in eww-workspace-bar.nix)

**Key characteristics**:
- Multi-line string concatenation
- Quote escaping for special characters
- Direct Sway IPC command execution

**Recommendation**: Use **Pattern D** (shell script wrapper with notifications) for window focus actions, and **Pattern B** (eww update) for UI state changes. Combine both for complete feedback loop.

---

### 2. i3pm Project Switch and Window Focus Commands

**Question**: What are the exact commands and sequences for project switching and window focusing? What's the interaction between i3pm daemon and Sway IPC?

**Findings**:

#### CLI Commands

**Project switch**:
```bash
i3pm project switch <project_name>
```
- Exit code: 0 (success), 1 (failure)
- Duration: <200ms (optimized in Feature 091)
- Side effects: Hides old scoped windows, restores new scoped windows

**Window focus (Sway IPC)**:
```bash
swaymsg '[con_id=<WINDOW_ID>] focus'
```
- Automatically switches workspace if window on different workspace
- Handles hidden windows by restoring from scratchpad first
- No project switch - only focuses window

**Workspace focus (Sway IPC)**:
```bash
swaymsg 'workspace <NUMBER>'
```
- Switches to workspace without focusing specific window
- Restores last focused window on that workspace

#### Cross-Project Window Focus Sequence

Based on spec requirements, the correct sequence is:

```bash
# 1. Switch project context (if different project)
i3pm project switch <target_project_name>

# 2. Focus the window (after project switch completes)
swaymsg '[con_id=<WINDOW_ID>] focus'
```

**Rationale**:
- Project switch brings scoped windows into view (~200ms)
- Then window focus navigates to specific window (~100ms)
- Total time: ~300ms for cross-project focus

**Alternative considered**: Focus window first, then switch project
- **Rejected**: Would focus hidden window, then hide it again during project switch, causing flicker

#### Daemon JSON-RPC Methods

**Method**: `project.switchWithFiltering(old_project, new_project, fallback_workspace)`
- Implements 2-phase filtering (hide + restore)
- Broadcasts `project_switched` event
- Updates daemon state

**No dedicated "focus window in project" method exists** - needs to be implemented as sequential commands.

**Recommendation**: Create wrapper script `focus-window-action` that:
1. Reads window's project association from JSON data
2. Compares to current active project
3. If different, calls `i3pm project switch <project>`
4. Waits for switch completion (monitor exit code)
5. Calls `swaymsg [con_id=X] focus`
6. Shows notification on error

---

### 3. CSS Hover and Click Visual Feedback Patterns

**Question**: What CSS patterns are used for hover states, click animations, and visual feedback in existing Eww widgets?

**Findings**:

#### Catppuccin Mocha Color Palette (Unified)

```nix
mocha = {
  base = "#1e1e2e";        # Dark background
  surface0 = "#313244";    # Surface layer 1
  surface1 = "#45475a";    # Surface layer 2
  overlay0 = "#6c7086";    # Borders, overlays
  text = "#cdd6f4";        # Primary text
  subtext0 = "#a6adc8";    # Secondary text
  blue = "#89b4fa";        # Focused state
  teal = "#94e2d5";        # Scoped windows
  green = "#a6e3a1";       # Success
  yellow = "#f9e2af";      # Warning/pending
  peach = "#fab387";       # Floating windows
  red = "#f38ba8";         # Critical
  mauve = "#cba6f7";       # Focus glow
};
```

#### Hover State Progression

**Tab buttons** (monitoring panel, lines 1151-1179):
```scss
.tab {
  background-color: rgba(49, 50, 68, 0.4);      /* surface0 40% */
  color: ${mocha.subtext0};
  border: 1px solid ${mocha.overlay0};
}

.tab:hover {
  background-color: rgba(69, 71, 90, 0.5);      /* surface1 50% */
  color: ${mocha.text};
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.tab.active {
  background-color: rgba(137, 180, 250, 0.6);   /* blue 60% */
  color: ${mocha.base};
  border-color: ${mocha.blue};
  box-shadow: 0 0 8px rgba(137, 180, 250, 0.4); /* Blue glow */
}
```

**State progression**:
- Default: 40% opacity
- Hover: 50% opacity + shadow
- Active: 60% opacity + colored glow

#### Click Visual Feedback

**Copy button with success state** (lines 1343-1376):
```scss
.json-copy-btn {
  background-color: rgba(137, 180, 250, 0.2);   /* blue 20% */
  border: 1px solid ${mocha.blue};
}

.json-copy-btn:hover {
  background-color: rgba(137, 180, 250, 0.3);   /* +10% */
  box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
}

.json-copy-btn:active {
  background-color: rgba(137, 180, 250, 0.5);   /* +20% */
  box-shadow: 0 0 12px rgba(137, 180, 250, 0.6);
}

.json-copy-btn.copied {
  background-color: rgba(166, 227, 161, 0.3);   /* green */
  color: ${mocha.green};
  box-shadow: 0 0 12px rgba(166, 227, 161, 0.5),
              inset 0 0 8px rgba(166, 227, 161, 0.2);
}
```

**Feedback mechanism**:
```bash
# In onclick script
eww update copied_window_id=$WINDOW_ID
(sleep 2 && eww update copied_window_id=0) &
```

**CSS class binding**:
```yuck
:class "json-copy-btn''${copied_window_id == window.id ? ' copied' : ""}"
```

#### GTK CSS Limitations

**Not supported**:
- `transform` (scale, translate, rotate)
- `transition` property (use Eww `:transition` instead)
- `@keyframes` (only opacity animations work)
- `cursor` (use `:cursor` in Yuck widget)

**Supported**:
- `opacity` transitions
- `background` and `border` transitions
- `box-shadow` (performance cost acceptable for <50 elements)
- `-gtk-icon-shadow` (GTK-specific)
- `linear-gradient` backgrounds

#### Animation Timing Reference

| Element | Duration | Usage |
|---------|----------|-------|
| Metric pills | 120ms | Fast hover feedback |
| Project items | 150ms | Navigation selection |
| Tabs/buttons | 200ms | Standard interaction |
| Pulse animations | 3000ms | Continuous status indicator |

**Recommendation**: Use 150ms for window row hover (matches project items), 200ms for project header hover (matches tabs). Visual feedback via:
- Hover: Increase opacity +10%, add subtle shadow
- Click: Temporary highlight (2s auto-reset like copy button)
- Success: Brief green glow before panel update
- Error: Red notification via notify-send

---

### 4. Debouncing and Rapid Click Prevention

**Question**: How are rapid clicks handled in existing widgets? Do we need debouncing logic?

**Findings**:

#### Existing Patterns

**No explicit debouncing found** in Eww onclick handlers. However, implicit debouncing exists through:

1. **Background execution** (`&`) prevents UI blocking
2. **State updates** provide visual feedback that click was registered
3. **Long-running operations** naturally debounce (can't click again while executing)

#### Polling Interval Pattern

```yuck
(defpoll notification_center_visible
  :interval "2s"
  :initial "false"
  `swaync-client --subscribe | ...`)
```

**Not applicable to onclick** - polling is for data refresh, not click handling.

#### Auto-Reset Mechanism

```bash
# Visual state resets after 2 seconds
eww update clicked_window_id=$WINDOW_ID
(sleep 2 && eww update clicked_window_id=0) &
```

**Provides natural rate limiting** - users see visual feedback preventing duplicate clicks.

#### Recommendation

**Implement debouncing in shell script wrapper**:

```bash
#!/usr/bin/env bash
LOCK_FILE="/tmp/eww-monitoring-focus.lock"

# Exit if already running
if [[ -f "$LOCK_FILE" ]]; then
    notify-send -u low "Focus Action" "Previous action still in progress"
    exit 1
fi

# Create lock
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Execute focus action
# ... (project switch + window focus)

# Lock automatically removed on exit
```

**Rationale**:
- Prevents duplicate commands during 200-500ms execution time
- User-friendly notification for rapid clicks
- Automatic cleanup via trap
- Complements visual feedback (clicked state)

**Alternative considered**: JavaScript/TypeScript debounce in Eww widget
- **Rejected**: Eww doesn't support JS, only Yuck expressions and shell commands

---

### 5. Error Handling and User Feedback Best Practices

**Question**: What patterns exist for error handling and showing success/failure feedback to users?

**Findings**:

#### Notification System (SwayNC)

**Success notification** (service restart, line 201):
```bash
notify-send -u normal "Service Restarted" "Successfully restarted $SERVICE_NAME"
```

**Error notification** (service restart, line 205):
```bash
notify-send -u critical "Service Restart Failed" "Failed to restart $SERVICE_NAME (exit code: $EXIT_CODE)"
```

**Urgency levels**:
- `low`: Informational (e.g., "Already in target project")
- `normal`: Success confirmation
- `critical`: Errors requiring attention

#### Visual State Feedback

**Success indicator** (clipboard copy):
```scss
.json-copy-btn.copied {
  background-color: rgba(166, 227, 161, 0.3);   /* Green */
  box-shadow: 0 0 12px rgba(166, 227, 161, 0.5);
}
```

**Auto-reset**:
```bash
(sleep 2 && eww update copied_window_id=0) &
```

#### Exit Code Handling

**Pattern from i3pm CLI**:
```bash
if i3pm project switch "$PROJECT_NAME"; then
    # Success path
    notify-send -u normal "Switched to project $PROJECT_NAME"
else
    EXIT_CODE=$?
    notify-send -u critical "Project switch failed" "Exit code: $EXIT_CODE"
    exit $EXIT_CODE
fi
```

#### Recommendation

**Multi-layer feedback**:

1. **Immediate visual feedback** (CSS state change):
   - Window row highlights on click
   - Eww variable: `clicked_window_id`
   - Auto-reset after 2 seconds

2. **Success notification** (after action completes):
   ```bash
   notify-send -u normal "Window Focused" "Switched to project $PROJECT_NAME"
   ```

3. **Error notification** (on failure):
   ```bash
   notify-send -u critical "Focus Failed" "Window no longer exists"
   ```

4. **Panel auto-update** (via deflisten event stream):
   - Monitoring panel refreshes within 100ms
   - User sees updated state without manual refresh

**Error scenarios to handle**:
- Window closed between click and focus
- Project switch failed (daemon not running)
- Sway IPC connection lost
- Invalid window ID in JSON data

---

## Technology Stack Decisions

Based on research findings and constitution compliance:

### Implementation Language: Bash + Nix
**Rationale**:
- Existing Eww onclick handlers use bash scripts
- Nix `pkgs.writeShellScriptBin` pattern proven in codebase
- No need for TypeScript/Deno complexity for simple command sequencing

### Data Flow: Eww → Bash Script → Sway IPC + i3pm CLI
**Rationale**:
- Eww provides window metadata (ID, project, workspace) via JSON
- Bash script handles sequencing and error handling
- Direct command execution for minimal latency

### Error Feedback: SwayNC Notifications + CSS State
**Rationale**:
- SwayNC already integrated (Feature 090)
- CSS state provides immediate visual feedback
- Notifications provide detailed error messages

### State Management: Eww Variables + Deflisten Auto-Refresh
**Rationale**:
- Eww variables track clicked state (2s timeout)
- Deflisten stream automatically updates panel after Sway changes
- No manual refresh needed

## Alternatives Considered & Rejected

### Alternative 1: Daemon JSON-RPC Method for Window Focus
**Description**: Add `window.focusInProject(window_id, project_name)` to daemon

**Pros**:
- Single method call instead of two commands
- Centralized error handling
- Consistent with daemon architecture

**Cons**:
- Requires daemon modification (outside Eww widget scope)
- Adds complexity for simple sequential operation
- Violates Principle XII (Forward-Only Development) - daemon doesn't need this abstraction yet

**Decision**: **Rejected** - shell script wrapper is simpler and sufficient for MVP

---

### Alternative 2: Focus Workspace Instead of Individual Window
**Description**: Click on window navigates to its workspace, relies on Sway's last-focused tracking

**Pros**:
- Simpler command (just workspace switch)
- Lets user manually select window if multiple exist

**Cons**:
- Less precise than direct window focus
- User asked for "focus on window" specifically
- Workspace focus doesn't guarantee correct window focused

**Decision**: **Rejected** - spec clearly requires individual window focus (User Story 1)

---

### Alternative 3: TypeScript/Deno Script for Click Handling
**Description**: Use Deno script to handle project switch + window focus logic

**Pros**:
- Type safety for window metadata
- Better error handling patterns
- Consistent with i3pm CLI (TypeScript)

**Cons**:
- Slower startup time than bash (~50ms)
- Unnecessary complexity for sequential commands
- Existing Eww widgets use bash exclusively

**Decision**: **Rejected** - bash is sufficient and matches existing patterns

---

### Alternative 4: Debouncing in Eww Widget via Variable Timing
**Description**: Use Eww poll intervals to rate-limit clicks

**Pros**:
- No external script needed
- Pure Eww/Yuck solution

**Cons**:
- Eww doesn't support JavaScript-style debouncing
- Polling adds unnecessary CPU overhead
- Less reliable than lock file approach

**Decision**: **Rejected** - lock file in bash script is cleaner

---

## Best Practices for Implementation

### 1. Quote Escaping Pattern
```yuck
:onclick {
  "focus-window-action "
  + replace(project_name, "\"", "\\\"")
  + " "
  + window.id
}
```

### 2. Nix Script Wrapper
```nix
focusWindowScript = pkgs.writeShellScriptBin "focus-window-action" ''
  #!${pkgs.bash}/bin/bash
  set -euo pipefail

  PROJECT_NAME="''${1:-}"
  WINDOW_ID="''${2:-}"
  CURRENT_PROJECT=$(i3pm project current --json | jq -r '.project_name // "global"')

  # Lock file for debouncing
  LOCK_FILE="/tmp/eww-monitoring-focus-''${WINDOW_ID}.lock"

  # ... rest of implementation
'';
```

### 3. CSS Hover State
```scss
.window-row {
  background-color: rgba(49, 50, 68, 0.4);
  border: 1px solid ${mocha.overlay0};
  transition: all 150ms ease;
}

.window-row:hover {
  background-color: rgba(69, 71, 90, 0.5);
  border-color: ${mocha.blue};
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
  cursor: pointer;
}

.window-row.clicked {
  background-color: rgba(137, 180, 250, 0.3);
  box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
}
```

### 4. Eww Widget Pattern
```yuck
(defwidget window-row [window]
  (eventbox
    :cursor "pointer"
    :onclick "focus-window-action ''${window.project_name} ''${window.id} &"
    (box
      :class "window-row''${clicked_window_id == window.id ? ' clicked' : ""}"
      ; ... window display content
      )))
```

---

## Performance Considerations

### Expected Latencies

| Action | Duration | Measurement Method |
|--------|----------|-------------------|
| CSS hover state | 150ms | Transition timing |
| Eww variable update | <50ms | Client-side only |
| Project switch | 200ms | Feature 091 benchmark |
| Window focus (same project) | 100ms | Sway IPC RTT |
| Window focus (cross-project) | 300ms | 200ms + 100ms |
| Panel refresh (deflisten) | 100ms | Event stream latency |
| Total (cross-project) | ~500ms | Sequential sum |

### Optimization Notes

- Lock file check adds ~5ms (negligible)
- Notification display is async (doesn't block)
- CSS transitions don't block main thread
- Eww variables update in <1ms

### Scale Assumptions

- Max 50 windows displayed simultaneously
- Max 20 projects in system
- Each window row: ~100 bytes JSON
- Total JSON payload: <5KB
- CSS stylesheet: ~50KB (already loaded)

**No performance concerns identified** for typical usage (<100 windows).

---

## Summary of Decisions

| Decision Point | Choice | Rationale |
|---------------|--------|-----------|
| Click handler implementation | Bash script wrapper | Matches existing patterns, simple sequencing |
| Project switch then focus | Sequential commands | Prevents flicker, reliable state |
| Visual feedback | CSS state + notifications | Multi-layer feedback, proven pattern |
| Debouncing | Lock file in script | Simple, reliable, automatic cleanup |
| Error handling | Exit codes + notify-send | Consistent with service restart pattern |
| Hover timing | 150ms transition | Matches project item pattern |
| Focus target | Individual window | Spec requirement, more precise |
| CSS framework | GTK3 CSS (Catppuccin) | No change needed, already styled |

---

## Open Questions for Implementation Phase

None - all technical unknowns resolved through codebase research.

---

## References

**Files analyzed**:
- `/home/vpittamp/nixos-093-actions-window-widget/home-modules/desktop/eww-monitoring-panel.nix` (1888 lines)
- `/home/vpittamp/nixos-093-actions-window-widget/home-modules/desktop/eww-workspace-bar.nix` (1053 lines)
- `/home/vpittamp/nixos-093-actions-window-widget/home-modules/desktop/eww-top-bar/eww.scss.nix` (436 lines)
- `/home/vpittamp/nixos-093-actions-window-widget/home-modules/tools/i3_project_manager/cli/commands.py`
- `/home/vpittamp/nixos-093-actions-window-widget/home-modules/desktop/i3-project-event-daemon/`

**Related features**:
- Feature 085: Sway Monitoring Widget (base panel)
- Feature 091: Optimized i3pm Project Switching (<200ms)
- Feature 090: SwayNC Notification System
- Feature 076: Mark-Based App Identification

**Constitution principles**:
- Principle X: Python Development Standards (not applicable - using bash)
- Principle XIII: Deno CLI Standards (not applicable - using bash)
- Principle XIV: Test-Driven Development (will use sway-test framework)
- Principle XV: Sway Test Framework Standards

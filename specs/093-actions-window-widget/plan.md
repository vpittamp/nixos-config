# Implementation Plan: Interactive Monitoring Widget Actions

**Branch**: `093-actions-window-widget` | **Date**: 2025-11-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/093-actions-window-widget/spec.md`

## Summary

Add click interactivity to the Eww monitoring panel, enabling users to:
1. Click any window to focus it (automatically switching projects if needed)
2. Click project headers to switch project context
3. Receive visual and notification feedback for all actions

**Technical approach**: Extend existing monitoring panel Yuck widgets with `:onclick` handlers that call bash script wrappers for project switching and window focusing. Use Catppuccin Mocha CSS hover states for visual feedback and SwayNC notifications for error handling. Total latency: <500ms for cross-project window focus.

## Technical Context

**Language/Version**: Bash 5.0+ (shell scripts), Yuck/GTK3 CSS (Eww widget definition), Nix 2.18+ (build system)
**Primary Dependencies**:
  - Eww 0.4+ (widget framework, existing)
  - Sway 1.8+ (window manager IPC, existing)
  - i3pm daemon (project management, existing)
  - SwayNC 0.10+ (notifications, existing)
  - jq 1.6+ (JSON parsing in scripts)

**Storage**: Eww runtime state (in-memory variables), no persistence required
**Testing**: sway-test framework (declarative JSON tests per Principle XV), manual UI testing
**Target Platform**: NixOS with Sway Wayland compositor (Hetzner reference + M1 hybrid)
**Project Type**: Single project (Eww widget extension + bash scripts)
**Performance Goals**:
  - Window focus (same project): <300ms total latency
  - Window focus (cross-project): <500ms total latency
  - CSS hover feedback: <50ms visual response
  - Panel refresh after action: <100ms (via deflisten)

**Constraints**:
  - GTK CSS limitations (no transform, no @keyframes except opacity)
  - Eww onclick handlers execute bash commands only
  - Must preserve existing monitoring panel functionality
  - Must not break Feature 085 deflisten event stream

**Scale/Scope**:
  - Max 50 windows displayed simultaneously
  - Max 20 projects in system
  - 3 clickable element types (window rows, project headers, workspace badges)
  - 2 bash script wrappers (focus-window, switch-project)
  - ~200 lines of new Yuck code
  - ~100 lines of bash scripts
  - ~80 lines of CSS hover states

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition
✅ **Pass** - Feature extends existing `eww-monitoring-panel.nix` module, no new module needed. Bash scripts added to same module for encapsulation.

### Principle III: Test-Before-Apply
✅ **Pass** - Standard dry-build workflow required. No special considerations.

### Principle VI: Declarative Configuration Over Imperative
✅ **Pass** - Eww widget definitions are declarative Nix expressions. Bash scripts generated via `pkgs.writeShellScriptBin` (declarative). No imperative post-install steps.

### Principle X: Python Development & Testing Standards
⚠️ **Not Applicable** - Feature uses bash scripts, not Python. Python daemon (i3pm) is consumed, not modified.

### Principle XII: Forward-Only Development & Legacy Elimination
✅ **Pass** - No legacy code to preserve. New click handlers don't affect existing panel functionality. If better pattern emerges, can replace onclick scripts entirely.

### Principle XIII: Deno CLI Development Standards
⚠️ **Not Applicable** - Feature uses bash for command sequencing, not Deno CLI. Deno would add unnecessary startup latency (~50ms) for simple sequential commands.

### Principle XIV: Test-Driven Development & Autonomous Testing
✅ **Pass** - Will use sway-test framework (Principle XV) for end-to-end tests. UI automation via ydotool for click simulation. State verification via Sway IPC tree queries.

### Principle XV: Sway Test Framework Standards
✅ **Pass** - Test definitions will use declarative JSON format with partial mode state comparison (focusedWorkspace, windowCount, workspace structure per examples). Tests validate click actions execute correctly and result in expected Sway state.

### Principle VIII: Remote Desktop & Multi-Session Standards
✅ **Pass** - Click handlers work across RDP/VNC sessions. Mouse events captured by Eww regardless of remote desktop protocol.

### Principle IX: Tiling Window Manager & Productivity Standards
✅ **Pass** - Enhances keyboard-driven workflow with mouse alternative. Does not replace keyboard shortcuts. Monitoring panel remains accessible via Mod+M.

**Overall Assessment**: ✅ **All Gates Passed** - No constitution violations. Feature aligns with modular composition, declarative config, and test-driven development principles.

---

## Project Structure

### Documentation (this feature)

```text
specs/093-actions-window-widget/
├── plan.md              # This file (/speckit.plan command output)
├── spec.md              # Feature specification (/speckit.specify command output)
├── research.md          # Phase 0 output (complete)
├── data-model.md        # Phase 1 output (to be generated)
├── quickstart.md        # Phase 1 output (to be generated)
├── contracts/           # Phase 1 output (to be generated)
│   ├── focus-window-action.sh  # Bash script contract (input/output specification)
│   ├── switch-project-action.sh  # Bash script contract
│   └── eww-click-events.schema.json  # Eww variable state schema
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-monitoring-panel.nix     # MODIFIED: Add onclick handlers, CSS hover states
│   ├── focusWindowScript        # NEW: Bash script for window focus
│   ├── switchProjectScript      # NEW: Bash script for project switch
│   └── monitoringPanelYuck      # MODIFIED: Add :onclick to widgets
│
└── sway-keybindings.nix         # NO CHANGE: Keyboard shortcuts remain same

tests/093-actions-window-widget/
├── test_window_focus_same_project.json      # NEW: Click window in same project
├── test_window_focus_cross_project.json     # NEW: Click window in different project
├── test_project_switch_click.json           # NEW: Click project header
├── test_hover_visual_feedback.json          # NEW: Verify CSS hover states
├── test_rapid_click_debouncing.json         # NEW: Verify lock file prevents duplicates
└── test_error_handling_closed_window.json   # NEW: Verify error notification
```

**Structure Decision**: Single project structure (Option 1) - feature extends existing Eww widget module without creating new directories. All changes contained in `eww-monitoring-panel.nix`. Tests use sway-test framework with declarative JSON definitions per Principle XV.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations identified** - table not applicable.

---

## Phase 0: Research & Technical Decisions ✅ COMPLETE

### Research Questions Resolved

1. ✅ **Eww onclick handler patterns** - Analyzed 6 patterns from existing widgets (simple commands, eww updates, inline scripts, service restart with notifications, Sway IPC with escaping)
2. ✅ **i3pm project switch + window focus commands** - Documented CLI interface, JSON-RPC daemon methods, cross-project focus sequence (switch then focus)
3. ✅ **CSS hover and visual feedback patterns** - Analyzed Catppuccin Mocha color palette, state progression (40% → 50% → 60%), timing (150-200ms), GTK CSS limitations
4. ✅ **Debouncing and rapid click prevention** - Determined lock file approach in bash script, auto-reset visual state after 2s
5. ✅ **Error handling and user feedback** - Documented SwayNC notification patterns (success, error, urgency levels), visual state feedback, exit code handling

### Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Implementation language** | Bash scripts | Matches existing Eww onclick patterns, simple command sequencing |
| **Click handler pattern** | Shell script wrapper with notifications | Proven pattern from service restart (lines 167-207 in eww-monitoring-panel.nix) |
| **Project switch sequence** | Switch project THEN focus window | Prevents flicker (avoids focusing hidden window then hiding it again) |
| **Visual feedback** | CSS hover states + temporary highlight | Multi-layer: instant hover (CSS), click highlight (2s), panel update (100ms) |
| **Error handling** | Exit codes + SwayNC notifications | Consistent with existing service restart error pattern |
| **Debouncing mechanism** | Lock file in bash script | Prevents duplicate commands during 200-500ms execution time |
| **Hover transition timing** | 150ms | Matches existing project item hover (eww-workspace-bar.nix:823) |
| **Focus target** | Individual window (not workspace) | Spec requirement (User Story 1), more precise than workspace focus |

### Alternatives Considered & Rejected

1. **Daemon JSON-RPC method for window focus** - Rejected: adds complexity for simple sequential operation, violates Principle XII (no unnecessary abstraction)
2. **Focus workspace instead of individual window** - Rejected: less precise, spec explicitly requires window focus
3. **TypeScript/Deno script for click handling** - Rejected: slower startup (~50ms), unnecessary for sequential commands
4. **Debouncing via Eww poll intervals** - Rejected: Eww doesn't support JS-style debouncing, lock file is cleaner

---

## Phase 1: Design & Contracts

### Data Model

See [data-model.md](./data-model.md) for complete entity definitions.

**Key Entities**:
- **WindowMetadata**: `{ id: number, project_name: string, workspace_number: number, display_name: string, is_focused: boolean, is_hidden: boolean }`
- **ClickAction**: `{ action_type: "focus_window" | "switch_project", target_id: string | number, timestamp: number, success: boolean }`
- **EwwClickState**: `{ clicked_window_id: number, clicked_project: string, click_in_progress: boolean }`

### API Contracts

See [contracts/](./contracts/) directory for complete specifications.

**Bash Script Contracts**:

#### `focus-window-action.sh`
```bash
# Input: PROJECT_NAME WINDOW_ID
# Output: Exit code 0 (success) or 1 (failure)
# Side effects:
#   - Calls `i3pm project switch $PROJECT_NAME` if different project
#   - Calls `swaymsg [con_id=$WINDOW_ID] focus`
#   - Shows notification on success/error
#   - Creates lock file during execution
```

#### `switch-project-action.sh`
```bash
# Input: PROJECT_NAME
# Output: Exit code 0 (success) or 1 (failure)
# Side effects:
#   - Calls `i3pm project switch $PROJECT_NAME`
#   - Shows notification on success/error
#   - Creates lock file during execution
```

**Eww Variable State**:
```json
{
  "clicked_window_id": 0,        // Window ID of last clicked window (0 = none)
  "clicked_project": "",         // Project name of last clicked project ("" = none)
  "click_in_progress": false     // True during action execution
}
```

### CSS Style Contracts

**Window row hover states**:
```scss
.window-row {
  background-color: rgba(49, 50, 68, 0.4);      // surface0 40%
  transition: all 150ms ease;
}

.window-row:hover {
  background-color: rgba(69, 71, 90, 0.5);      // surface1 50%
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
  cursor: pointer;
}

.window-row.clicked {
  background-color: rgba(137, 180, 250, 0.3);   // blue 30%
  box-shadow: 0 0 8px rgba(137, 180, 250, 0.4);
}
```

**Project header hover states**:
```scss
.project-header {
  background-color: rgba(49, 50, 68, 0.6);      // surface0 60%
  transition: all 200ms ease;
}

.project-header:hover {
  background-color: rgba(69, 71, 90, 0.8);      // surface1 80%
  border-color: rgba(137, 180, 250, 0.6);       // blue 60%
  box-shadow: 0 0 8px rgba(137, 180, 250, 0.3);
}
```

### Integration Points

**1. Eww Widget → Bash Script**:
```yuck
(eventbox
  :cursor "pointer"
  :onclick "focus-window-action ''${window.project_name} ''${window.id} &"
  (box :class "window-row''${clicked_window_id == window.id ? ' clicked' : ""}"
    ; ... window display content
  ))
```

**2. Bash Script → i3pm CLI**:
```bash
CURRENT_PROJECT=$(i3pm project current --json | jq -r '.project_name // "global"')
if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
    i3pm project switch "$PROJECT_NAME"
fi
```

**3. Bash Script → Sway IPC**:
```bash
swaymsg "[con_id=$WINDOW_ID] focus"
```

**4. Bash Script → SwayNC**:
```bash
notify-send -u normal "Window Focused" "Switched to project $PROJECT_NAME"
notify-send -u critical "Focus Failed" "Window no longer exists"
```

**5. Sway Events → Eww Deflisten**:
```bash
# Existing mechanism (no changes needed)
python monitoring_data.py --listen  # Emits JSON on stdout
eww update monitoring_state="$(cat)"  # Deflisten consumes stream
```

### User Flow Diagrams

**User Story 1: Click Window to Focus (Same Project)**

```
User clicks window row
    ↓
Eww onclick handler triggers
    ↓
focus-window-action.sh executed
    ↓
Check current project (i3pm project current)
    ↓
[Project matches] → Skip project switch
    ↓
Execute: swaymsg [con_id=X] focus
    ↓
[Success] → notify-send "Window Focused"
    ↓
Eww variable: clicked_window_id = X
    ↓
CSS class .clicked applied (blue highlight)
    ↓
Auto-reset after 2s: clicked_window_id = 0
    ↓
Deflisten stream emits updated state
    ↓
Panel refreshes within 100ms
```

**Total time**: ~300ms (100ms Sway IPC + 50ms notification + 150ms CSS transition)

---

**User Story 1: Click Window to Focus (Different Project)**

```
User clicks window row
    ↓
Eww onclick handler triggers
    ↓
focus-window-action.sh executed
    ↓
Check current project (i3pm project current)
    ↓
[Project differs] → Execute: i3pm project switch <project>
    ↓
[Project switch: 200ms] → Scoped windows hidden/restored
    ↓
Execute: swaymsg [con_id=X] focus
    ↓
[Success] → notify-send "Window Focused" "Switched to project Y"
    ↓
Eww variable: clicked_window_id = X
    ↓
CSS class .clicked applied
    ↓
Auto-reset after 2s
    ↓
Deflisten stream emits updated state
    ↓
Panel refreshes within 100ms
```

**Total time**: ~500ms (200ms project switch + 100ms window focus + 50ms notification + 150ms CSS)

---

**User Story 2: Click Project Header to Switch**

```
User clicks project header
    ↓
Eww onclick handler triggers
    ↓
switch-project-action.sh executed
    ↓
Check if already in target project
    ↓
[Different] → Execute: i3pm project switch <project>
    ↓
[Success] → notify-send "Switched to project X"
    ↓
Eww variable: clicked_project = X
    ↓
CSS class .clicked applied
    ↓
Auto-reset after 2s
    ↓
Deflisten stream emits updated state
    ↓
Panel refreshes showing new project windows
```

**Total time**: ~350ms (200ms project switch + 50ms notification + 100ms panel refresh)

---

### Quickstart Guide

See [quickstart.md](./quickstart.md) for complete user documentation.

**Quick reference**:

**Usage**:
1. Open monitoring panel: `Mod+M`
2. Click any window row to focus that window
3. Click any project header to switch to that project
4. Hover over rows for visual feedback

**Troubleshooting**:
```bash
# Check if panel is running
systemctl --user status eww-monitoring-panel

# View panel logs
journalctl --user -u eww-monitoring-panel -f

# Test focus script manually
focus-window-action "my-project" 12345
```

---

## Phase 2: Tasks Generation (NOT DONE BY /speckit.plan)

**Stop here** - `/speckit.plan` command ends after Phase 1.

Use `/speckit.tasks` command to generate `tasks.md` with implementation tasks, test cases, and acceptance criteria.

---

## Agent Context Update

Agent-specific context files will be updated automatically after Phase 1 completion via:

```bash
.specify/scripts/bash/update-agent-context.sh claude
```

**Technologies to add**:
- Eww 0.4+ (Yuck widget definitions, :onclick handlers)
- GTK3 CSS (hover states, transitions, Catppuccin Mocha)
- Bash 5.0+ (shell script wrappers, lock files)
- SwayNC (notification feedback)
- sway-test framework (declarative JSON tests)

**No removal of existing technologies** - feature is additive.

---

## Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Window focus (same project) | <300ms | Time from click to focus complete |
| Window focus (cross-project) | <500ms | Time from click to focus complete |
| CSS hover feedback | <50ms | Visual state change on hover |
| Panel refresh after action | <100ms | Deflisten stream update latency |
| Lock file check overhead | <5ms | Bash file existence test |
| Notification display | <100ms | SwayNC async display |

**Targets based on**:
- Feature 091 benchmark: <200ms project switch
- Sway IPC RTT: ~100ms for focus command
- Eww deflisten: ~100ms event stream latency
- CSS transition: 150ms (explicit timing)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Window closes between click and focus | Medium | Low | Check exit code, show error notification |
| Rapid clicks cause duplicate commands | Medium | Medium | Lock file prevents duplicate execution |
| Project switch fails (daemon down) | Low | Medium | Catch exit code, notify user, suggest restart |
| CSS hover states conflict with existing styles | Low | Low | Use scoped class names (.window-row-clickable) |
| GTK CSS limitations prevent desired animations | Low | Low | Use opacity-based fallbacks, proven in research |
| Deflisten stream breaks after changes | Low | High | Extensive testing, verify event subscriptions |

**Overall risk**: **Low** - Feature extends existing proven patterns without modifying core daemon or IPC logic.

---

## Success Criteria Validation

Mapping success criteria from spec to implementation plan:

| Success Criteria | Implementation | Validation Method |
|------------------|----------------|-------------------|
| SC-001: Focus any window in <2 clicks | 1 click to open panel (Mod+M), 1 click on window | Manual test + sway-test |
| SC-002: Same-project focus <300ms | Bash script + Sway IPC (~100ms total) | Performance benchmark |
| SC-003: Cross-project focus <500ms | Project switch (200ms) + focus (100ms) + overhead | Performance benchmark |
| SC-004: Visual feedback <50ms | CSS transition immediate, Eww variable <10ms | Browser devtools timing |
| SC-005: 95% edge case handling | Lock file, exit codes, error notifications | sway-test error scenarios |
| SC-006: Panel updates <100ms | Deflisten stream (existing, <100ms proven) | Event stream monitoring |
| SC-007: Project switch in 1 click | Click project header → switch (200ms) | Manual test + sway-test |

**All success criteria achievable** with planned implementation.

---

## Next Steps

1. ✅ **Phase 0 Complete**: Research findings documented in [research.md](./research.md)
2. **Phase 1 Complete**: This plan document finalized
3. **Run agent context update**: `.specify/scripts/bash/update-agent-context.sh claude`
4. **Generate tasks**: Run `/speckit.tasks` to create implementation task list
5. **Implementation**: Follow tasks.md for TDD workflow (tests first, then code)
6. **Testing**: Validate with sway-test framework
7. **Documentation**: Update CLAUDE.md with new keybindings/usage

---

**End of /speckit.plan output** - Use `/speckit.tasks` to continue with task generation.

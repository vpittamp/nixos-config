# Implementation Plan: Monitor Panel Focus Enhancement

**Branch**: `086-monitor-focus-enhancement` | **Date**: 2025-11-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/086-monitor-focus-enhancement/spec.md`

## Summary

Fix the monitoring panel (Feature 085) focus regression by implementing `focusable: "ondemand"` in Eww combined with Sway `no_focus` rule. Add keybinding (`Mod+Shift+M`) for explicit focus toggle with automatic return to previous window.

## Technical Context

**Language/Version**: Nix (home-manager modules), Bash (toggle scripts)
**Primary Dependencies**: Eww 0.4+ (GTK3), Sway 1.8+, i3ipc (for swaymsg)
**Storage**: N/A (config files only)
**Testing**: Manual verification + existing sway-test framework
**Target Platform**: NixOS with Sway/Wayland (Hetzner, M1)
**Project Type**: Configuration change (no new services)
**Performance Goals**: <100ms for focus toggle, <100ms for panel show/hide (already met)
**Constraints**: Must not break existing panel functionality (real-time updates, tab switching)
**Scale/Scope**: Single panel widget, 3 configuration files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ Pass | Changes in existing modules only |
| III. Test-Before-Apply | ✅ Pass | Will use dry-build before switch |
| VI. Declarative Config | ✅ Pass | All changes in Nix expressions |
| IX. Tiling WM Standards | ✅ Pass | Maintains keyboard-driven workflow |
| XII. Forward-Only | ✅ Pass | No backwards compatibility needed |

## Project Structure

### Documentation (this feature)

```text
specs/086-monitor-focus-enhancement/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 research findings
├── quickstart.md        # Phase 1 user guide
└── checklists/
    └── requirements.md  # Quality validation checklist
```

### Source Code (repository root)

```text
home-modules/desktop/
├── eww-monitoring-panel.nix   # MODIFY: focusable property, toggle script
├── sway-keybindings.nix       # MODIFY: add Mod+Shift+M binding
└── sway.nix                   # MODIFY: add no_focus window rule
```

**Structure Decision**: Minimal footprint - only modify existing modules, no new files.

## Design

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       User Actions                           │
├──────────────┬──────────────────────┬───────────────────────┤
│   Mod+M      │   Mod+Shift+M        │   Click app window     │
│   (toggle)   │   (focus toggle)     │   (focus change)       │
└──────┬───────┴──────────┬───────────┴───────────┬───────────┘
       │                  │                       │
       ▼                  ▼                       ▼
┌──────────────┐  ┌───────────────────┐  ┌─────────────────────┐
│ eww open/    │  │ toggle-panel-     │  │ Sway focus handling │
│ close panel  │  │ focus script      │  │ (no_focus rule)     │
└──────────────┘  └─────────┬─────────┘  └──────────┬──────────┘
                            │                       │
                            ▼                       ▼
                  ┌─────────────────────────────────────────────┐
                  │              Eww Panel Window               │
                  │   focusable: "ondemand"                    │
                  │   stacking: "overlay"                      │
                  │   windowtype: "normal"                     │
                  └─────────────────────────────────────────────┘
```

### Focus Toggle Script

```bash
#!/usr/bin/env bash
# toggle-panel-focus: Toggle keyboard focus on monitoring panel
PANEL_APP_ID="eww-monitoring-panel"

# Check if panel window exists and is focused
is_focused=$(swaymsg -t get_tree | jq -r '
  .. | select(.focused? == true) | .app_id // empty
' 2>/dev/null)

if [ "$is_focused" = "$PANEL_APP_ID" ]; then
  # Panel is focused - return focus to previous window
  swaymsg 'focus prev'
else
  # Panel not focused - focus it (if visible)
  swaymsg "[app_id=\"$PANEL_APP_ID\"] focus" 2>/dev/null || \
    echo "Panel not visible - use Mod+M to show it first"
fi
```

### Configuration Changes

**1. eww-monitoring-panel.nix - Window Definition**

```yuck
(defwindow monitoring-panel
  :monitor "${primaryOutput}"
  :geometry (geometry ...)
  :namespace "eww-monitoring-panel"
  :stacking "overlay"
  :focusable "ondemand"    ; CHANGED from true
  :exclusive false
  :windowtype "normal"
  (monitoring-panel-content))
```

**2. sway.nix - Window Rule**

```nix
wayland.windowManager.sway.config.window = {
  commands = [
    # Prevent monitoring panel from stealing focus
    { criteria = { app_id = "eww-monitoring-panel"; };
      command = "no_focus"; }
  ];
};
```

**3. sway-keybindings.nix - Focus Toggle Binding**

```nix
"${modifier}+Shift+m" = "exec toggle-panel-focus";
```

## Acceptance Mapping

| Requirement | Implementation |
|-------------|----------------|
| FR-001: focusable "ondemand" | `eww-monitoring-panel.nix` line ~185 |
| FR-002: no_focus rule | `sway.nix` window commands |
| FR-003: Mod+Shift+M toggle | `sway-keybindings.nix` + new script |
| FR-004: Return to previous | `swaymsg 'focus prev'` in toggle script |
| FR-005: Scratchpad visibility | ❌ REVISED - keep eww open/close |
| FR-006: Sticky behavior | Already working (`:stacking "overlay"`) |
| FR-007: Position preserved | Already working (eww geometry) |

### FR-005 Revision Note

Research revealed scratchpad would introduce focus-stealing. The existing `toggle-monitoring-panel` script using `eww open/close` already provides the needed functionality without focus issues. Spec can be updated to reflect this.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `focusable "ondemand"` not working | Low | High | Test on dev first; fallback to `"none"` + external focus handling |
| `no_focus` ineffective for eww | Medium | Medium | Alternative: `focus_on_window_activation none` per-window |
| `focus prev` unreliable | Low | Medium | Track con_id before focus, restore explicitly |
| Tab shortcuts (Alt+1-4) break | Low | High | Already global Sway bindings, independent of panel focus |

## Complexity Tracking

> No complexity violations - minimal changes to existing modules.

## Next Steps

1. Run `/speckit.tasks` to generate implementation tasks
2. Execute tasks in order
3. Test on Hetzner (primary test platform)
4. Validate all acceptance scenarios
5. Dry-build and apply

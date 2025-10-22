# Feature 024 Overlap Analysis with Existing i3pm Module

**Date**: 2025-10-22
**Status**: CRITICAL - Significant overlap detected, reconciliation required

## Executive Summary

After analyzing the existing i3pm daemon codebase, **Feature 024's planned implementation has 60-70% overlap with already-existing functionality**. The current i3pm event daemon (`home-modules/desktop/i3-project-event-daemon/`) already implements:

1. ✅ **Window rules engine** - `window_rules.py` with WindowRule class
2. ✅ **Pattern matching** - `pattern.py` with PatternRule class (exact, glob, regex, pwa, title patterns)
3. ✅ **Window classification** - `pattern_resolver.py` with 4-level precedence (project → window rules → app patterns → default)
4. ✅ **Workspace management** - `workspace_manager.py` with MonitorConfig and multi-monitor support
5. ✅ **Event handlers** - `handlers.py` with window::new, tick, workspace events
6. ✅ **Project-scoped management** - Project switching with hide/show window logic

## Detailed Overlap Analysis

### 1. Window Rules Engine (MAJOR OVERLAP)

**Existing Implementation** (`window_rules.py`):
- ✅ WindowRule class with pattern_rule, workspace, command, modifier, blacklist
- ✅ Rule loading from JSON (`load_window_rules()`)
- ✅ Rule validation and priority sorting
- ✅ Pattern matching via PatternRule
- ✅ Serialization/deserialization (to_json/from_json)

**Feature 024 Plan** (data-model.md):
- ❌ **DUPLICATE**: WindowRule Pydantic model with match_criteria, actions, priority
- ❌ **DUPLICATE**: RulesConfig with rules array and defaults
- ❌ **DUPLICATE**: load_window_rules() function

**Reconciliation Strategy**:
- ✅ **KEEP EXISTING**: window_rules.py (already working, battle-tested)
- ✅ **EXTEND**: Add Pydantic validation on top of existing dataclass
- ✅ **ENHANCE**: Add new action types (layout, float) to existing WindowRule
- ❌ **DON'T CREATE**: New window_rules.py in i3_project_manager/core/

### 2. Pattern Matching (COMPLETE OVERLAP)

**Existing Implementation** (`pattern.py`):
```python
@dataclass(frozen=True)
class PatternRule:
    """Pattern types: literal, glob:, regex:, pwa:, title:, title:glob:, title:regex:"""
    pattern: str
    scope: Literal["scoped", "global"]
    priority: int
    description: str

    def matches(self, window_class: str, window_title: str = "") -> bool:
        # Implements all pattern types with regex compilation
```

**Feature 024 Plan** (data-model.md):
- ❌ **DUPLICATE**: PatternMatch Pydantic model with pattern, match_type, case_sensitive
- ❌ **DUPLICATE**: match_exact(), match_regex(), match_wildcard() functions

**Reconciliation Strategy**:
- ✅ **KEEP EXISTING**: pattern.py (comprehensive, supports PWA, title patterns)
- ✅ **MAP SCHEMA**: Feature 024's JSON schema → existing PatternRule format
  - `"match_type": "exact"` → literal pattern (no prefix)
  - `"match_type": "regex"` → `"regex:pattern"`
  - `"match_type": "wildcard"` → `"glob:pattern"`
- ❌ **DON'T CREATE**: New pattern matching functions

### 3. Window Classification (COMPLETE IMPLEMENTATION)

**Existing Implementation** (`pattern_resolver.py`):
```python
def classify_window(
    window_class: str,
    window_title: str = "",
    active_project_scoped_classes: Optional[List[str]] = None,
    window_rules: Optional[List[WindowRule]] = None,
    app_classification_patterns: Optional[List[PatternRule]] = None,
    app_classification_scoped: Optional[List[str]] = None,
    app_classification_global: Optional[List[str]] = None,
) -> Classification:
    """4-level precedence hierarchy:
    1. Project scoped_classes (priority 1000)
    2. Window rules (priority 200-500) ← ALREADY INTEGRATED
    3. App classification patterns (priority 100)
    4. App classification lists (priority 50)
    """
```

**Feature 024 Plan** (tasks.md T013):
- ❌ **DUPLICATE**: find_matching_rule() function

**Reconciliation Strategy**:
- ✅ **KEEP EXISTING**: pattern_resolver.py (fully implements 4-level precedence)
- ✅ **ALREADY DONE**: Window rules already integrated at priority 200-500
- ❌ **DON'T CREATE**: New classification logic

### 4. Workspace Management (PARTIAL OVERLAP)

**Existing Implementation** (`workspace_manager.py`):
- ✅ MonitorConfig dataclass with role assignment
- ✅ get_monitor_configs() - queries GET_OUTPUTS, assigns roles
- ✅ Multi-monitor distribution rules (1/2/3+ monitors)
- ✅ assign_workspaces_to_monitors() - distributes WS based on monitor count

**Feature 024 Plan** (tasks.md T030-T036):
- ⚠️ **PARTIAL OVERLAP**: get_workspace_distribution_rule() - similar to existing logic
- ⚠️ **PARTIAL OVERLAP**: apply_workspace_distribution() - similar to assign_workspaces_to_monitors()
- ✅ **NEW**: validate_target_workspace() - validates workspace on active output (T036)
- ✅ **NEW**: on_output() event handler - revalidates on monitor changes (T034-T035)

**Reconciliation Strategy**:
- ✅ **KEEP EXISTING**: workspace_manager.py core functions
- ✅ **ADD NEW**: validate_target_workspace() function (doesn't exist yet)
- ✅ **ADD NEW**: on_output() event handler in handlers.py
- ✅ **ENHANCE**: Integrate workspace validation into window rule application

### 5. Window Property Extraction (EXISTS IN HANDLERS)

**Existing Implementation** (`handlers.py`):
- ✅ on_window_new() - extracts window properties from container
- ✅ WindowInfo model in models.py - stores window_id, window_class, window_title, etc.

**Feature 024 Plan** (tasks.md T004, T009):
- ❌ **DUPLICATE**: WindowProperties dataclass
- ❌ **DUPLICATE**: extract_window_properties() function

**Reconciliation Strategy**:
- ✅ **KEEP EXISTING**: WindowInfo model in models.py
- ✅ **ENHANCE**: Add missing properties (window_role, window_type, transient_for)
- ❌ **DON'T CREATE**: New WindowProperties dataclass

### 6. Rule Actions (PARTIAL IMPLEMENTATION)

**Existing Implementation** (`window_rules.py`):
- ✅ WindowRule.workspace - moves window to workspace
- ✅ WindowRule.command - executes arbitrary i3 command
- ❌ **MISSING**: Structured action types (workspace, mark, float, layout)
- ❌ **MISSING**: Multiple actions per rule

**Feature 024 Plan** (data-model.md):
- ✅ **NEW**: RuleAction discriminated union (WorkspaceAction, MarkAction, FloatAction, LayoutAction)
- ✅ **NEW**: Multiple actions per rule
- ✅ **NEW**: apply_rule_actions() function

**Reconciliation Strategy**:
- ✅ **ENHANCE EXISTING**: Add `actions: List[RuleAction]` to WindowRule
- ✅ **ADD NEW**: rule_action.py with action types
- ✅ **ADD NEW**: apply_rule_actions() in workspace_manager.py
- ✅ **DEPRECATE**: WindowRule.command (replace with structured actions)

### 7. Project-Scoped Window Management (COMPLETE)

**Existing Implementation** (`handlers.py`):
- ✅ on_tick() - handles project:switch and project:none
- ✅ _switch_project() - hides old, shows new project windows
- ✅ hide_window() / show_window() - scratchpad management
- ✅ Project mark generation - "project:{name}"

**Feature 024 Plan** (tasks.md T023-T029):
- ❌ **DUPLICATE**: get_active_project() - already in state_manager
- ❌ **DUPLICATE**: toggle_project_windows() - already implemented as hide/show

**Reconciliation Strategy**:
- ✅ **KEEP EXISTING**: All project switching logic
- ✅ **NO CHANGES NEEDED**: Already complete

## What Actually Needs Implementation

After removing duplicates, **Feature 024 reduces to these net-new items**:

### A. Schema & Configuration Format Migration (T001-T002)

**Goal**: Migrate from simple JSON array to structured schema with actions

**Current format** (`window-rules.json`):
```json
[
  {
    "pattern_rule": {
      "pattern": "glob:FFPWA-*",
      "scope": "global",
      "priority": 200
    },
    "workspace": 4,
    "command": "layout tabbed"
  }
]
```

**New format** (Feature 024):
```json
{
  "version": "1.0",
  "rules": [
    {
      "name": "pwa-youtube",
      "match_criteria": {
        "class": {"pattern": "FFPWA-*", "match_type": "wildcard"}
      },
      "actions": [
        {"type": "workspace", "target": 4},
        {"type": "layout", "mode": "tabbed"}
      ],
      "priority": "global"
    }
  ],
  "defaults": {"workspace": "current", "focus": true}
}
```

**Tasks**:
- ✅ T001: Create JSON schema file (contracts/window-rule-schema.json → home-modules/tools/i3_project_manager/schemas/)
- ✅ T002: Create window-rules-default.json template
- ✅ **NEW**: Add migration script from old → new format

### B. Structured Rule Actions (T006, T017-T018)

**Goal**: Replace string commands with typed action objects

**Tasks**:
- ✅ T006: Create RuleAction types (workspace, mark, float, layout)
- ✅ T017: Implement action execution functions (set_window_floating, set_container_layout)
- ✅ T018: Implement apply_rule_actions() dispatcher
- ✅ **MODIFY**: WindowRule to use `actions: List[RuleAction]` instead of `workspace` + `command`

### C. Workspace Validation for Multi-Monitor (T036)

**Goal**: Prevent assigning windows to workspaces on inactive outputs

**Tasks**:
- ✅ T036: Add validate_target_workspace() to workspace_manager.py
- ✅ **INTEGRATE**: Call validation before workspace assignment

### D. Output Event Handling (T034-T035)

**Goal**: Revalidate workspace assignments when monitors change

**Tasks**:
- ✅ T034: Add on_output() handler to handlers.py
- ✅ T035: Subscribe to output events in daemon.py main()

### E. CLI Tools (T037-T040)

**Goal**: User-facing validation and testing commands

**Tasks**:
- ✅ T037: Implement validate_rules.py CLI command
- ✅ T038: Implement test_rule.py CLI command
- ✅ T039: Add `i3pm validate-rules` command
- ✅ T040: Add `i3pm test-rule` command

### F. Hot-Reload (T041-T043)

**Goal**: Reload rules without daemon restart

**Tasks**:
- ✅ T041: Implement watch_rules_file() with inotify
- ✅ T042: Add on_rules_file_changed() handler
- ✅ T043: Add reload timestamp tracking

### G. Polish (T045-T052)

**Goal**: Error handling, logging, performance monitoring

**Tasks**:
- ✅ T045-T046: Error handling and logging
- ✅ T047: State restoration (daemon restart)
- ✅ T048: on_window_close() cleanup
- ✅ T049: Update launcher scripts
- ✅ T050: Performance monitoring
- ✅ T051-T052: Validation and deployment

## Revised Task Count

**Original Plan**: 52 tasks across 7 phases
**After Deduplication**:
- ❌ **REMOVE**: 28 tasks (duplicates of existing functionality)
- ✅ **KEEP**: 24 tasks (net-new functionality)

**Revised Phases**:
1. **Phase 1: Schema Migration** (3 tasks) - T001-T002 + migration script
2. **Phase 2: Rule Actions** (6 tasks) - T006, T017-T018, WindowRule refactor
3. **Phase 3: Multi-Monitor Validation** (3 tasks) - T034-T036
4. **Phase 4: CLI Tools** (4 tasks) - T037-T040
5. **Phase 5: Hot-Reload** (3 tasks) - T041-T043
6. **Phase 6: Polish** (5 tasks) - T045-T050, T051-T052

**Estimated Time**: 3-4 days (down from 7-11 days)

## Reconciliation Recommendations

### 1. Update plan.md Immediately

**BEFORE**:
```markdown
## Project Structure
home-modules/tools/i3_project_manager/
├── core/
│   ├── window_rules.py          # NEW: Rule engine and matcher
│   ├── workspace_manager.py     # NEW: Workspace assignment logic
```

**AFTER**:
```markdown
## Project Structure
home-modules/desktop/i3-project-event-daemon/
├── window_rules.py          # EXISTING: Enhance with actions
├── workspace_manager.py     # EXISTING: Add validation
├── rule_action.py           # NEW: Action types
```

### 2. Update tasks.md to Remove Duplicates

Mark as **SKIP** (already implemented):
- T004-T005: WindowProperties/MatchCriteria (use existing WindowInfo/PatternRule)
- T009-T010: Window property extraction (exists in handlers.py)
- T011-T012: Pattern matching functions (exists in pattern.py)
- T013: find_matching_rule() (exists in pattern_resolver.py)
- T014: load_window_rules() (exists in window_rules.py)
- T023-T029: Project-scoped management (fully implemented)
- T030-T033: Multi-monitor distribution (exists in workspace_manager.py)

### 3. Update data-model.md to Reference Existing Models

Replace new model definitions with:
```markdown
## WindowRule (EXISTING)
See: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/window_rules.py`

## PatternRule (EXISTING)
See: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/pattern.py`

## MonitorConfig (EXISTING)
See: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
```

### 4. Constitution Principle Compliance

✅ **Principle I (No Duplication)**: Reconciliation resolves duplication violations
✅ **Principle XII (Forward-Only)**: Keep existing working code, enhance don't replace

## Next Steps

1. ✅ **UPDATE** plan.md with reconciliation strategy
2. ✅ **UPDATE** tasks.md to remove 28 duplicate tasks
3. ✅ **UPDATE** data-model.md to reference existing models
4. ✅ **CREATE** revised tasks-reconciled.md with 24 real tasks
5. ✅ **PROCEED** with implementation of net-new functionality only

## Conclusion

**Feature 024 is 60-70% already implemented**. The core window rules engine, pattern matching, classification logic, workspace management, and project-scoped management all exist and are working in production.

**What we actually need to do**:
1. Migrate JSON schema format (backwards-compatible)
2. Add structured action types (enhance existing WindowRule)
3. Add workspace validation for multi-monitor (new function)
4. Add output event handling (new handler)
5. Add CLI validation tools (new commands)
6. Add hot-reload support (new feature)
7. Polish and testing (always needed)

**This is NOT a new feature** - it's an **enhancement and formalization** of existing functionality.

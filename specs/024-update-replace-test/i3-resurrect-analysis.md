# i3-resurrect Integration Analysis

**Date**: 2025-10-22
**Context**: Feature 024 - Dynamic Window Management System

## Executive Summary

**RECOMMENDATION: DO NOT USE i3-resurrect - Different Problem Domain**

i3-resurrect solves **workspace layout persistence** (save/restore on reboot), while Feature 024 solves **dynamic window assignment** (real-time workspace routing). These are orthogonal concerns with minimal code overlap.

**Tactical Decision**: Extract only the `treeutils.py` patterns for window property extraction, reimpl ement in our existing i3pm architecture using i3ipc.aio (async). Do NOT add i3-resurrect as dependency.

## Problem Domain Comparison

### i3-resurrect's Problem
**Goal**: Save workspace layouts to survive reboots/restarts
- User manually saves workspace state (layout + program cmdlines)
- System stores: window tree structure, swallow criteria, process cmdlines/cwd
- User manually restores workspace after reboot
- Uses xdotool to unmap/remap windows for layout reapplication
- Profile-based workspace snapshots

**Key Operations**: Manual save → file storage → manual restore

### Feature 024's Problem
**Goal**: Automatically route new windows to correct workspaces in real-time
- System automatically detects new windows (<100ms)
- System applies first-matching rule from configuration
- System moves window to target workspace dynamically
- No manual save/restore - continuous event-driven operation
- Project-scoped vs global application management

**Key Operations**: Event subscription → rule evaluation → automatic assignment

## Architecture Comparison

### i3-resurrect Architecture
```
Synchronous CLI Tool (Click-based)
├── config.py          # JSON config management
├── layout.py          # Layout save/restore via i3ipc + xdotool
├── main.py            # Click CLI interface
├── programs.py        # Process cmdline/cwd extraction (psutil)
├── treeutils.py       # i3 tree traversal utilities
└── util.py            # Helper functions

Dependencies: i3ipc (sync), Click, psutil, xdotool
Pattern: Imperative CLI commands (save/restore)
State: Stateless - reads/writes JSON files
```

### Feature 024 Architecture (i3pm)
```
Async Event-Driven Daemon (systemd service)
├── core/
│   ├── event_processor.py      # i3 IPC event handling
│   ├── window_rules.py         # NEW: Rule engine
│   ├── workspace_manager.py    # NEW: Workspace assignment
│   └── monitor_manager.py      # NEW: Multi-monitor distribution
├── models/
│   ├── window_rule.py          # NEW: WindowRule Pydantic model
│   └── window_properties.py    # NEW: Window property extraction
└── cli/
    └── validate_rules.py       # NEW: Rule validation

Dependencies: i3ipc.aio (async), pydantic, pytest-asyncio
Pattern: Event-driven daemon with i3 IPC subscriptions
State: Stateful - maintains active project, monitor config
```

## Code Reusability Analysis

### ✅ REUSABLE: treeutils.py Patterns

**What We Need**:
```python
# Window property extraction from i3 tree
window_properties = {
    "class": con.window_properties.get("class", ""),
    "instance": con.window_properties.get("instance", ""),
    "title": con.window_properties.get("title", ""),
    "window_role": con.window_properties.get("window_role", ""),
    "window_type": con.window_properties.get("window_type", "")
}

# Swallow criteria matching patterns
swallow_criteria = ["class", "instance", "title", "window_role"]
```

**Adaptation Required**:
- Convert from synchronous i3ipc to async i3ipc.aio
- Integrate with Pydantic models (WindowProperties)
- Remove xdotool dependencies (not needed for our use case)
- Use i3-msg for window movement (not xdotool unmap/remap)

### ❌ NOT REUSABLE: layout.py

**Why Not**:
- Focuses on layout tree serialization/restoration
- Uses xdotool for window unmapping/remapping (not our pattern)
- Builds complete workspace tree for append_layout
- We need real-time event handling, not snapshot/restore

**Our Alternative**: Direct i3-msg commands in window_rules.py

### ❌ NOT REUSABLE: programs.py

**Why Not**:
- Extracts cmdline/cwd for relaunching programs after reboot
- Uses psutil to traverse process tree
- We don't relaunch programs - we route already-launched windows

**Our Alternative**: N/A - different problem domain

### ❌ NOT REUSABLE: config.py

**Why Not**:
- Singleton pattern with module-level state
- window_command_mappings for process relaunching
- terminals list for cwd extraction
- We use Pydantic models with JSON schema validation

**Our Alternative**: models/window_rule.py with pydantic

### ❌ NOT REUSABLE: main.py (CLI)

**Why Not**:
- Click-based CLI for save/restore commands
- User-initiated operations, not event-driven
- No daemon mode - one-shot execution

**Our Alternative**: event_processor.py + daemon architecture

## Integration Strategy

### Option A: Use as External Dependency ❌ REJECTED
**Pros**: Mature, tested code
**Cons**:
- Solves different problem (layout persistence vs dynamic routing)
- Synchronous API conflicts with our async architecture
- Adds unnecessary dependencies (Click, xdotool, psutil)
- No daemon mode - would require wrapper
- GPL v3 license (our codebase compatibility?)

**Verdict**: Architectural mismatch - more complexity than value

### Option B: Fork and Modify ❌ REJECTED
**Pros**: Could adapt existing code
**Cons**:
- Would need to rewrite >70% of code (async conversion, remove CLI)
- Maintenance burden of fork
- Still solves different problem
- GPL v3 license implications for derivative works

**Verdict**: Technical debt without clear benefit

### Option C: Extract Patterns Only ✅ RECOMMENDED
**Pros**:
- Reuse proven window property extraction patterns
- No dependency overhead
- Maintain architectural consistency (async, Pydantic)
- Clean integration with existing i3pm
- No licensing concerns (patterns, not code copying)

**Cons**:
- Requires reimplementation (but minimal code)
- No test suite inheritance (we write our own with pytest-asyncio)

**Verdict**: Optimal balance - learn from i3-resurrect without coupling to it

## Recommended Implementation

### Phase 1: Window Property Extraction

Create `models/window_properties.py`:
```python
from pydantic import BaseModel
from typing import Optional
import i3ipc.aio

class WindowProperties(BaseModel):
    """
    Window properties extracted from i3 tree.
    Inspired by i3-resurrect/treeutils.py REQUIRED_ATTRIBUTES.
    """
    window_id: int
    class_name: Optional[str] = None  # window_properties.class
    instance: Optional[str] = None    # window_properties.instance
    title: Optional[str] = None       # window_properties.title
    window_role: Optional[str] = None # window_properties.window_role
    window_type: Optional[str] = None # window_properties.window_type
    workspace: str                    # container.workspace().name
    marks: list[str]                  # container.marks

    @classmethod
    async def from_i3_container(cls, container) -> "WindowProperties":
        """
        Extract window properties from i3ipc.aio container.
        Pattern adapted from i3-resurrect/treeutils.py:process_node()
        """
        props = container.window_properties or {}
        workspace = container.workspace()

        return cls(
            window_id=container.window,
            class_name=props.get("class"),
            instance=props.get("instance"),
            title=props.get("title"),
            window_role=props.get("window_role"),
            window_type=props.get("window_type"),
            workspace=workspace.name if workspace else "unknown",
            marks=container.marks or []
        )
```

### Phase 2: Rule Matching Engine

Create `core/window_rules.py`:
```python
import re
from typing import Optional
from models.window_rule import WindowRule
from models.window_properties import WindowProperties

class WindowRulesEngine:
    """
    First-match rule evaluation engine.
    Swallow criteria matching inspired by i3-resurrect/treeutils.py.
    """

    def __init__(self, rules: list[WindowRule]):
        self.rules = rules
        # Compile regex patterns at initialization
        self._compile_patterns()

    def match_window(self, props: WindowProperties) -> Optional[WindowRule]:
        """
        Find first matching rule for window.
        Pattern: First-match semantics (i3-resurrect uses per-window criteria).
        """
        for rule in self.rules:
            if self._matches_criteria(rule, props):
                return rule
        return None

    def _matches_criteria(self, rule: WindowRule, props: WindowProperties) -> bool:
        """
        Check if window properties match rule criteria.
        Supports: exact match, regex, wildcard (like i3-resurrect swallow criteria).
        """
        # Match class (if specified)
        if rule.match_class and not self._matches_pattern(
            rule.match_class, props.class_name
        ):
            return False

        # Match instance (if specified)
        if rule.match_instance and not self._matches_pattern(
            rule.match_instance, props.instance
        ):
            return False

        # Match title (if specified)
        if rule.match_title and not self._matches_pattern(
            rule.match_title, props.title
        ):
            return False

        # Match window_role (if specified)
        if rule.match_window_role and not self._matches_pattern(
            rule.match_window_role, props.window_role
        ):
            return False

        return True

    def _matches_pattern(self, pattern: str, value: Optional[str]) -> bool:
        """
        Match pattern against value (exact, regex, wildcard).
        Pattern inspired by i3-resurrect swallow criteria with re.escape().
        """
        if value is None:
            return False

        # Regex pattern (starts with ^)
        if pattern.startswith("^"):
            return bool(re.match(pattern, value))

        # Wildcard pattern (contains *)
        if "*" in pattern:
            regex = pattern.replace("*", ".*")
            return bool(re.match(f"^{regex}$", value))

        # Exact match
        return pattern == value
```

### Phase 3: Workspace Assignment

Create `core/workspace_manager.py`:
```python
import i3ipc.aio
from models.window_rule import WindowRule

class WorkspaceManager:
    """
    Handles window-to-workspace assignment.
    Uses i3-msg commands (not xdotool like i3-resurrect).
    """

    def __init__(self, i3: i3ipc.aio.Connection):
        self.i3 = i3

    async def assign_window_to_workspace(
        self,
        window_id: int,
        workspace: str,
        focus: bool = False
    ):
        """
        Move window to target workspace.
        If focus=True, switch to that workspace.

        i3-resurrect uses xdotool unmap/remap for layout restoration.
        We use direct i3-msg commands for real-time assignment.
        """
        # Move window to workspace
        await self.i3.command(
            f'[id="{window_id}"] move container to workspace {workspace}'
        )

        # Switch focus if requested
        if focus:
            await self.i3.command(f'workspace {workspace}')
```

## What We Learn from i3-resurrect

### Good Patterns to Adopt
1. **Window Property Extraction**: Comprehensive property coverage (class, instance, title, window_role)
2. **Swallow Criteria Matching**: regex escaping patterns for special characters
3. **Configuration Structure**: JSON-based with per-window override capability
4. **Error Handling**: Explicit file not found vs permission errors
5. **Testing Strategy**: Unit tests for tree traversal and property extraction

### Patterns to Avoid
1. **Synchronous i3ipc**: We need async for event subscriptions
2. **xdotool Dependencies**: Use native i3-msg commands instead
3. **Module-Level State**: Use dependency injection with Pydantic
4. **Click CLI**: We have event-driven daemon, not user CLI commands
5. **Manual Save/Restore**: We need automatic, continuous operation

## Dependencies Decision

### Add to pyproject.toml (if using):
```toml
[tool.poetry.dependencies]
python = "^3.11"
i3ipc = {extras = ["aio"], version = "^2.2.1"}  # Already have this
pydantic = "^2.0"          # Already have this
# NO: Click, xdotool, psutil - not needed for our use case
```

### NixOS Package Dependencies:
```nix
# home-modules/tools/i3_project_manager/default.nix
buildPythonApplication {
  propagatedBuildInputs = [
    python311Packages.i3ipc  # aio support included
    python311Packages.pydantic
    # NO: python311Packages.click
    # NO: xdotool (X11 tool, we use i3-msg)
    # NO: python311Packages.psutil
  ];
}
```

## Future Consideration: Layout Persistence

If we later want to add **workspace layout persistence** (survive reboots), we could:

**Option 1**: Add i3-resurrect as **separate, complementary tool**
- User runs `i3-resurrect save -w 1` manually before reboot
- User runs `i3-resurrect restore -w 1` after reboot
- Our dynamic window system continues routing new windows
- No code coupling - two independent systems

**Option 2**: Implement our own layout persistence in i3pm
- Reuse i3-resurrect's layout.py patterns (if we want this feature)
- Integrate with our event daemon for automatic save triggers
- Store layouts in ~/.config/i3/layouts/ with project association

**Recommendation**: Defer until user requests it - out of scope for Feature 024

## License Considerations

### i3-resurrect License
- **GPL v3**: Strong copyleft license
- Requires derivative works to be GPL v3
- Pattern extraction (not code copying) avoids GPL requirements

### Our Codebase
- Check existing license compatibility
- If MIT/Apache: Pattern extraction is safe (no code copying)
- If GPL compatible: Could use code directly, but still prefer our async arch

**Decision**: Extract patterns only - no licensing concerns

## Testing Strategy

### What i3-resurrect Tests Well
- `tests/test_treeutils.py`: Tree traversal and node processing
- `tests/test_programs.py`: Process cmdline/cwd extraction
- `tests/test_layout.py`: Layout building and swallow criteria

### Our Testing Approach (Different)
- `tests/unit/test_window_rules.py`: Async rule matching with pytest-asyncio
- `tests/integration/test_rule_engine.py`: End-to-end with mock i3 IPC
- `tests/scenarios/test_window_lifecycle.py`: Event-driven workflow tests

**Key Difference**: Our tests must handle async/await patterns and event subscriptions

## Conclusion

**DO NOT** add i3-resurrect as dependency or fork the codebase.

**DO** extract and adapt these proven patterns:
1. Window property extraction comprehensiveness
2. Swallow criteria matching with regex support
3. Configuration structure for per-window overrides
4. Test patterns for tree traversal

**REASON**: i3-resurrect solves layout persistence (save/restore on reboot). We solve dynamic window routing (real-time workspace assignment). Different problems require different architectures. Learning from their patterns without coupling to their implementation maintains our async, event-driven design while benefiting from their domain knowledge.

## References

- i3-resurrect: https://github.com/JonnyHaystack/i3-resurrect
- Documentation: `/etc/nixos/docs/jonnyhaystack-i3-resurrect-8a5edab282632443.txt`
- Feature 024 Spec: `/etc/nixos/specs/024-update-replace-test/spec.md`
- Feature 024 Plan: `/etc/nixos/specs/024-update-replace-test/plan.md`
- Constitution Principle XII: Forward-Only Development & Legacy Elimination

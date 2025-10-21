# Research: Dynamic Window Management System

**Feature**: 021-lets-create-a
**Date**: 2025-10-21

## Research Summary

**Status**: No research required - all technical context fully specified.

All dependencies, patterns, and integration points are already established in the existing i3pm codebase:

1. **Pattern Matching**: Existing `PatternRule` model (models/pattern.py) provides glob, regex, and literal matching with validation
2. **i3 IPC Integration**: Existing daemon uses i3ipc.aio with async event subscriptions
3. **Config Loading**: Existing patterns in `config.py` for JSON file loading and validation
4. **Daemon Architecture**: Existing event loop, handlers, and IPC server provide extension points
5. **Testing Framework**: pytest with pytest-asyncio already in use for existing tests

## Technical Decisions

### Decision 1: Reuse PatternRule Model (Not Create New)

**Chosen**: Reuse existing `i3_project_manager.models.pattern.PatternRule`

**Rationale**:
- Already has validation for glob, regex, literal patterns
- Already has `matches()` method with caching
- Already has priority-based ordering
- Frozen dataclass ensures immutability
- Used successfully in existing codebase

**Alternatives Considered**:
- Create new pattern model in daemon: Would duplicate existing code, violate DRY
- Use simple string patterns: Would lose validation and type safety

**Implementation**: WindowRule references PatternRule as a field

---

### Decision 2: Configuration File Watch Strategy

**Chosen**: Use Python watchdog library with polling fallback

**Rationale**:
- watchdog provides cross-platform file system event monitoring
- Supports inotify on Linux (most efficient)
- Graceful fallback to polling if inotify unavailable
- Already used in similar Python daemons

**Alternatives Considered**:
- Pure inotify via pyinotify: Linux-only, would break on other platforms
- Polling only: Less efficient, higher latency (500ms-1s delay)
- Manual reload command: Violates user story requirement (<1s automatic reload)

**Implementation**: Add watchdog observer in daemon startup, reload configs on modification event

---

### Decision 3: AppClassification.class_patterns Schema Evolution

**Chosen**: Support both Dict[str, str] and List[PatternRule] with automatic conversion

**Rationale**:
- Existing JSON files use dict format: `{"pwa-": "global"}`
- Need List[PatternRule] for priority ordering and validation
- Backward compatibility is non-negotiable requirement (FR-027, SC-011)
- Conversion logic is straightforward

**Conversion Algorithm**:
```python
# Load from JSON
if isinstance(class_patterns, dict):
    # Convert dict to PatternRule list (priority 100)
    pattern_list = [
        PatternRule(pattern=k, scope=v, priority=100)
        for k, v in class_patterns.items()
    ]
elif isinstance(class_patterns, list):
    # Already list of dicts, deserialize to PatternRule
    pattern_list = [PatternRule(**item) for item in class_patterns]
```

**Implementation**: Enhance `AppClassification.from_json()` to handle both formats

---

### Decision 4: i3 IPC State Query Pattern

**Chosen**: Query i3 IPC on-demand, never cache state

**Rationale**:
- i3 is authoritative source of truth (Constitution XI)
- State can change outside daemon control (manual i3-msg commands, other tools)
- Caching creates synchronization bugs (Feature 018 lesson)
- i3 IPC queries are fast (<1ms for GET_WORKSPACES, GET_OUTPUTS)

**Query Points**:
- Window classification: Query GET_TREE for window properties
- Workspace assignment: Query GET_WORKSPACES for current assignments
- Monitor detection: Query GET_OUTPUTS for active outputs
- Mark verification: Query GET_MARKS to validate window marks

**Implementation**: Pass i3 connection to all functions, query on-demand

---

### Decision 5: 4-Level Precedence Resolution Algorithm

**Chosen**: Sequential evaluation with early return (waterfall pattern)

**Rationale**:
- Clear precedence: Project (1000) > WindowRule (200-500) > AppClassification patterns (100) > AppClassification lists (50)
- Short-circuit evaluation improves performance
- Source attribution enables debugging (know which rule matched)
- Deterministic behavior (no ambiguity)

**Algorithm** (from spec.md lines 242-272):
```python
def classify_window(window, active_project: Optional[Project]) -> Classification:
    # Priority 1000: Project-specific scoped_classes
    if active_project and window.window_class in active_project.scoped_classes:
        return Classification(scope="scoped", workspace=None, source="project")

    # Priority 200-500: window-rules.json patterns (user-defined priorities)
    matched_rule = match_window_rules(window)
    if matched_rule:
        return Classification(
            scope=matched_rule.pattern_rule.scope,
            workspace=matched_rule.workspace,
            source="window_rule"
        )

    # Priority 100: app-classes.json class_patterns
    matched_pattern = app_classification.match_pattern(window.window_class)
    if matched_pattern:
        return Classification(
            scope=matched_pattern.scope,
            workspace=None,
            source="app_classes"
        )

    # Priority 50: app-classes.json literal lists
    if window.window_class in app_classification.scoped_classes:
        return Classification(scope="scoped", workspace=None, source="app_classes")
    if window.window_class in app_classification.global_classes:
        return Classification(scope="global", workspace=None, source="app_classes")

    # Default: global (unscoped)
    return Classification(scope="global", workspace=None, source="default")
```

**Implementation**: Create `pattern_resolver.py` with classify_window() function

---

### Decision 6: Multi-Monitor Workspace Assignment Logic

**Chosen**: Query i3 GET_OUTPUTS, apply distribution rules, execute i3 commands

**Rationale**:
- i3 provides GET_OUTPUTS with current monitor configuration
- Distribution rules from spec: 1 monitor (all WS primary), 2 monitors (WS 1-2 primary, 3-9 secondary), 3+ monitors (WS 1-2 primary, 3-5 secondary, 6-9 tertiary)
- i3 commands execute workspace-to-output assignments: `workspace 1 output <name>`
- Fast execution (<500ms for all 9 workspaces per SC-005)

**Implementation**: Create `workspace_manager.py` with monitor detection and assignment logic

---

## Best Practices from Existing Codebase

### From i3-project-event-daemon (Feature 015)

1. **Async Event Loop Pattern**:
   ```python
   async def main():
       async with i3ipc.aio.Connection() as i3:
           i3.on('window::new', on_window_new)
           await i3.main()
   ```

2. **Event Handler Registration**:
   ```python
   def register_handlers(daemon, i3):
       i3.on('window::new', lambda i3, e: daemon.on_window_new(e))
       i3.on('window::close', lambda i3, e: daemon.on_window_close(e))
   ```

3. **Config Reload on SIGHUP**:
   ```python
   signal.signal(signal.SIGHUP, lambda sig, frame: daemon.reload_config())
   ```

### From i3_project_manager.core.pattern_matcher (Feature 019)

1. **LRU Cache for Performance**:
   ```python
   @lru_cache(maxsize=1024)
   def _match_impl(window_class: str, patterns_snapshot: tuple) -> Optional[str]:
       for pattern in patterns_snapshot:
           if pattern.matches(window_class):
               return pattern.scope
       return None
   ```

2. **Priority-Ordered Matching**:
   ```python
   self.patterns = sorted(patterns, key=lambda p: p.priority, reverse=True)
   ```

### From Python Development Standards (Constitution X)

1. **Data Validation with Dataclasses**:
   ```python
   @dataclass
   class WindowRule:
       pattern_rule: PatternRule
       workspace: Optional[int] = None

       def __post_init__(self):
           if self.workspace and not (1 <= self.workspace <= 9):
               raise ValueError("Workspace must be 1-9")
   ```

2. **Async/Await for i3 IPC**:
   ```python
   async def get_outputs(i3: i3ipc.aio.Connection) -> List[Output]:
       outputs = await i3.get_outputs()
       return [o for o in outputs if o.active]
   ```

## References

- Existing PatternRule: `home-modules/tools/i3_project_manager/models/pattern.py`
- Existing PatternMatcher: `home-modules/tools/i3_project_manager/core/pattern_matcher.py`
- Existing Daemon: `home-modules/desktop/i3-project-event-daemon/`
- Constitution: `.specify/memory/constitution.md`
- i3 IPC Docs: `docs/i3-ipc.txt`
- i3ipc-python Examples: `docs/altdesktop-i3ipc-python-1a130cabaa8a47b0.txt`

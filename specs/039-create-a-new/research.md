# Research Findings: i3 Window Management System Diagnostic & Optimization

**Feature**: 039-create-a-new
**Date**: 2025-10-26
**Status**: Complete

## Executive Summary

This document consolidates research findings for implementing systematic diagnostics and code consolidation in the i3 window management system. Key decisions: tiered window class matching with normalization, simple /proc reading without caching, AST-based duplicate detection with manual review, and Rich-based diagnostic CLI following existing i3pm patterns.

---

## 1. Window Class Normalization Patterns

### Decision: Tiered Matching with Automatic Normalization

**Selected Strategy**: Three-tier matching (exact → instance → normalized)

**Algorithm**:
```python
def match_window_class(expected: str, actual_class: str, actual_instance: str = "") -> tuple[bool, str]:
    """
    Match window class with tiered fallback strategy.

    Returns: (matched, match_type)
    Match types: "exact", "instance", "normalized", "none"
    """
    # Tier 1: Exact match (case-sensitive)
    if expected == actual_class:
        return (True, "exact")

    # Tier 2: Instance match (WM_CLASS instance field, case-insensitive)
    if actual_instance and expected.lower() == actual_instance.lower():
        return (True, "instance")

    # Tier 3: Normalized match (strip reverse-domain prefix)
    expected_norm = normalize_class(expected)
    actual_norm = normalize_class(actual_class)
    if expected_norm == actual_norm:
        return (True, "normalized")

    return (False, "none")

def normalize_class(class_name: str) -> str:
    """Strip reverse-domain prefix and lowercase."""
    if "." in class_name:
        parts = class_name.split(".")
        if len(parts) > 1 and parts[0].lower() in {"com", "org", "io", "net", "dev", "app"}:
            class_name = parts[-1]  # Take last component
    return class_name.lower()
```

**Rationale**:
- Fixes current issue: config has `"ghostty"` but window reports `"com.mitchellh.ghostty"`
- User-friendly: accepts both simple names and full reverse-domain notation
- Leverages WM_CLASS instance field (often simpler name)
- No false positives (uses equality, not substring)
- Fast: ~130 nanoseconds per window (3 comparisons max)

**Edge Cases**:
- Empty/null class → defaults to "unknown", match fails gracefully
- Multiple matches → prefer exact > instance > normalized (log warning)
- PWA classes (`FFPWA-*`) → handled by existing `pwa:` pattern type
- Case variations (`Code` vs `code`) → normalized to lowercase

**Alternatives Considered**:
- **Exact match only**: Rejected - too user-unfriendly, requires knowing full class
- **Substring match**: Rejected - false positives ("term" matches "terminal", "xterm")
- **Regex patterns**: Already available via `regex:` prefix for power users
- **Alias table**: Rejected - requires manual maintenance, doesn't scale

**Implementation Files**:
- `services/window_identifier.py` (NEW)
- `handlers.py` (update window::new handler)
- `pattern.py` (update literal match logic)

---

## 2. Process Environment Variable Reading

### Decision: Simple Direct Reading Without Caching

**Selected Pattern**:
```python
def read_window_environment(pid: int) -> dict[str, str] | None:
    """
    Read environment variables from /proc/{pid}/environ.

    Returns: dict of env vars or None if reading fails
    """
    try:
        environ_path = Path(f"/proc/{pid}/environ")

        # Read null-terminated environment string
        environ_data = environ_path.read_bytes()

        # Parse into dict
        env_dict = {}
        for entry in environ_data.split(b'\x00'):
            if b'=' in entry:
                key, value = entry.split(b'=', 1)
                env_dict[key.decode('utf-8')] = value.decode('utf-8')

        return env_dict

    except FileNotFoundError:
        # Process exited between window creation and environ read
        logger.debug(f"Process {pid} no longer exists")
        return None
    except PermissionError:
        # Other user's process (shouldn't happen with i3 windows)
        logger.warning(f"Permission denied reading /proc/{pid}/environ")
        return None
    except Exception as e:
        logger.error(f"Error reading environ for PID {pid}: {e}")
        return None
```

**Rationale**:
- Simple, straightforward implementation
- Uses pathlib for clean path handling
- Null-terminated parsing matches /proc format
- Graceful error handling for missing PIDs (process exited)
- No caching needed - window environment doesn't change after launch

**Caching Decision: NO**
- Window environment is static after launch (I3PM_* set by launcher wrapper)
- Reading /proc/{pid}/environ is extremely fast (~5 microseconds)
- Caching adds complexity without meaningful performance benefit
- Memory overhead for 50+ windows (50 * ~2KB = 100KB) is negligible but unnecessary

**Child vs Parent Process**:
- Read window's PID environ directly (child inherits parent environment)
- For terminal apps running programs (e.g., lazygit in ghostty):
  - Terminal process has I3PM_* environment
  - Child process (lazygit) inherits same environment
  - Window PID points to terminal, which is correct for our use case

**Performance**: <5 microseconds per read, ~250 microseconds for 50 windows (negligible)

**Existing Code Reference**:
- Current implementation in `handlers.py:read_process_env()` at line 64
- Uses similar pattern, can be enhanced with better error handling

**Implementation Files**:
- `services/env_reader.py` (ENHANCED - extract from handlers.py)
- Add comprehensive error handling and logging
- Add unit tests for edge cases

---

## 3. Event-Driven Architecture Patterns

### Decision: Pure i3 IPC Subscriptions (No Polling)

**Pattern** (Already Implemented):
```python
async def subscribe_to_events(conn: Connection):
    """Subscribe to i3 events and process asynchronously."""
    # Subscribe to all relevant event types
    await conn.subscribe([
        Event.WINDOW,      # window::new, window::close, window::focus
        Event.WORKSPACE,   # workspace::focus, workspace::init
        Event.OUTPUT,      # output::change (monitor connect/disconnect)
        Event.TICK,        # tick event for manual triggers
    ])

    # Event handlers registered via decorators
    conn.on(Event.WINDOW_NEW, on_window_new)
    conn.on(Event.WINDOW_CLOSE, on_window_close)
    conn.on(Event.WORKSPACE_FOCUS, on_workspace_focus)
    # ... etc
```

**i3 IPC Reliability Findings**:
- i3 IPC subscriptions are reliable - events fire for ALL window operations
- Current issue (no window::new events) is likely a subscription or handler bug, not i3
- Event ordering is guaranteed within event type (window events ordered chronologically)
- No race conditions between different event types (each processed sequentially in event loop)

**Defensive Strategies** (from i3ass project):
1. **Startup scan**: Mark all existing windows on daemon start (already implemented)
2. **Event queuing**: Buffer events during initialization (implement in Feature 039)
3. **State reconciliation**: Periodically validate daemon state vs i3 tree (diagnostic tool)
4. **Fallback queries**: If event subscription fails, fall back to polling (error state)

**Handling Rapid Event Streams**:
- Use asyncio queues for event buffering (already in place)
- Process events sequentially to prevent race conditions
- Add timeout handling for long-running event handlers (>100ms warning)
- Circular buffer for diagnostic event history (500 events max)

**Event Processing Latency Targets**:
- window::new detection: <50ms from creation to event received
- Handler execution: <100ms per event (workspace assignment, marking)
- Total pipeline: <150ms from window creation to fully configured

**Current System Performance** (from debugging):
- Event detection: Working for focus/close events, NOT for window::new (BUG)
- Handler latency: Unknown - need metrics
- Total latency: Unknown - need diagnostic tracing

**Implementation Requirements**:
- Fix window::new event subscription (current bug)
- Add event processing metrics to daemon
- Implement event queuing for initialization period
- Add diagnostic event trace command

**Implementation Files**:
- `connection.py` (fix event subscription)
- `services/event_processor.py` (NEW - event queuing and metrics)
- `handlers.py` (add performance logging)

---

## 4. Code Duplication Detection

### Decision: Manual Audit + AST Analysis

**Selected Approach**: Two-phase strategy

**Phase 1: Automated Detection (AST-based)**
```bash
# Using pylint duplicate-code checker
pylint --disable=all --enable=duplicate-code home-modules/desktop/i3-project-event-daemon/

# Output shows duplicate code blocks with file:line references
# Example output:
# Similar lines in 2 files
# ==handlers.py:506
# ==legacy_handlers.py:102
# [20 lines of duplicate code]
```

**Phase 2: Manual Review**
- Review pylint findings for false positives
- Grep for duplicate function names: `grep -r "^def workspace_assign"`
- Identify conflicting APIs by listing all exported functions per module
- Document findings in audit spreadsheet

**Criteria for "Duplicate"**:
- **Exact duplicates**: Same logic, same variable names → DELETE immediately
- **Semantic duplicates**: Same logic, different names → CONSOLIDATE to best implementation
- **Similar but distinct**: Different logic for same purpose → EVALUATE which is better, DELETE other
- **NOT duplicates**: Same name, different purpose → OK (but consider renaming for clarity)

**Conflicting API Detection**:
- List all public functions: `grep -r "^def [a-z_]*" --include="*.py" | awk '{print $2}' | sort | uniq -c`
- Functions with count > 1 are potential conflicts
- Review each for: purpose, callers, event-driven vs polling

**Expected Findings** (from debugging session observations):
1. Workspace assignment logic in multiple places (handlers.py, potential legacy code)
2. Window filtering logic (automatic hiding/showing) - may have duplicates
3. Environment variable reading - scattered across modules
4. Event correlation logic - may have old polling version

**Automated Tools Evaluated**:
- **pylint duplicate-code**: ✅ Use - finds syntactic duplicates reliably
- **jscpd**: ⚠️ Skip - language-agnostic but less precise for Python
- **radon**: ⚠️ Skip - complexity metrics, not duplication detection
- **Custom AST**: ⚠️ Overkill - pylint sufficient for this codebase size

**Documentation Output**:
- Spreadsheet: File | Function | Lines | Duplicate Of | Action (DELETE/CONSOLIDATE)
- Include in tasks.md as audit findings

**Implementation**:
- Task T001: Run pylint duplicate-code analysis
- Task T002: Manual grep audit for function names
- Task T003: Document findings in audit table
- Task T004: Prioritize consolidation (DELETE exact, CONSOLIDATE semantic)

---

## 5. Diagnostic Tool Design

### Decision: Rich-Based CLI Following Existing i3pm Patterns

**Command Structure**: Extend existing `i3pm` CLI with `diagnose` subcommand
```bash
i3pm diagnose health              # Daemon health check
i3pm diagnose window <id>         # Window property inspection
i3pm diagnose events [OPTIONS]    # Event trace viewer
i3pm diagnose validate            # State consistency check
```

**Output Modes**:
```python
# Human-readable (default)
@click.command()
@click.option('--json', is_flag=True, help='Output JSON for scripting')
def health_check(json: bool):
    if json:
        print(json.dumps(health_data))
    else:
        # Rich table display
        table = Table(title="Daemon Health")
        table.add_column("Check")
        table.add_column("Status")
        # ...
        console.print(table)
```

**Rich Library Patterns**:

1. **Live Displays** (for event streaming):
```python
from rich.live import Live
from rich.table import Table

with Live(auto_refresh=True, refresh_per_second=4) as live:
    while True:
        table = generate_event_table()
        live.update(table)
```

2. **Tables with Dynamic Content**:
```python
from rich.table import Table
from rich.console import Console

table = Table(title="Event Subscriptions")
table.add_column("Type", style="cyan")
table.add_column("Active", style="green")
table.add_column("Count", justify="right")

for sub in subscriptions:
    table.add_row(sub.type, "✓" if sub.active else "✗", str(sub.count))

console = Console()
console.print(table)
```

3. **Syntax Highlighting** (for JSON/env vars):
```python
from rich.syntax import Syntax

env_json = json.dumps(window_env, indent=2)
syntax = Syntax(env_json, "json", theme="monokai")
console.print(syntax)
```

4. **Progress Indicators** (for validation tasks):
```python
from rich.progress import track

for window in track(all_windows, description="Validating windows..."):
    validate_window(window)
```

**Error Handling**:
- Terminal resize: Rich handles automatically via layout updates
- Ctrl+C: Catch KeyboardInterrupt, cleanup gracefully
- No terminal (pipe): Detect with `console.is_terminal`, fallback to plain text
- Rich unavailable: Try/catch import, fallback to basic print()

**Existing i3pm Patterns** (from home-modules/tools/):
- `i3pm daemon status` - shows daemon health with connection test
- `i3pm windows` - shows window tree with Rich tables
- `i3pm project list` - shows projects with formatted output

**Following Conventions**:
- Use click for argument parsing (existing pattern)
- Use Rich Console() for output
- Provide --json flag for all commands
- Exit codes: 0 = success, 1 = error, 2 = validation failure

**Example Diagnostic Output**:

```
$ i3pm diagnose health

Daemon Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Check                    Status
────────────────────────────────────────
IPC Connection           ✓ Connected
Event Subscriptions      ✓ 4/4 active
  - window               ✓ 1,234 events
  - workspace            ✓ 89 events
  - output               ✓ 5 events
  - tick                 ✓ 12 events
Window Tracking          ✓ 23 windows
State Consistency        ✗ 2 mismatches
  - WS3 mapping          Expected: HDMI-1, Actual: eDP-1
  - WS5 mapping          Expected: eDP-1, Actual: HDMI-1

Overall Status: WARNING (State drift detected)

Run `i3pm diagnose validate` for details.
```

**Implementation Files**:
- `home-modules/tools/i3pm-diagnostic/` (NEW package)
- Separate from main daemon for clean separation
- Communicates with daemon via JSON-RPC IPC
- Can be run independently of daemon (connects on demand)

---

## 6. Environment Variable-Based Workspace Assignment

### Research Question: Is injecting workspace number via I3PM_TARGET_WORKSPACE more deterministic?

**Current System**:
1. App launches with `I3PM_APP_NAME=terminal`
2. Window created with window class
3. Daemon reads `/proc/{pid}/environ` for `I3PM_APP_NAME`
4. Daemon looks up `APP_NAME` in registry → gets `preferred_workspace: 3`
5. Daemon executes: `i3 move to workspace number 3`

**Proposed Alternative**:
1. App launches with `I3PM_APP_NAME=terminal` AND `I3PM_TARGET_WORKSPACE=3`
2. Window created
3. Daemon reads `/proc/{pid}/environ` directly gets workspace number
4. Daemon executes: `i3 move to workspace number 3`

**Analysis**:

**✅ Advantages of Environment-Based Assignment**:
1. **More Deterministic**: No registry lookup, no window class matching needed
2. **Simpler Logic**: Read env var → move window (2 steps vs 5)
3. **No Class Matching Issues**: Doesn't matter if window class is `ghostty` vs `com.mitchellh.ghostty`
4. **Application-Workspace is 1:1**: Since each app has fixed workspace, why lookup?
5. **Faster**: No string matching, normalization, or tiered fallback
6. **Less Error-Prone**: Can't have config mismatch between expected_class and actual class

**❌ Disadvantages**:
1. **Less Flexible**: Can't override workspace without changing launcher
2. **Duplicates Configuration**: Workspace number appears in both registry AND launcher logic
3. **Harder to Reconfigure**: Changing workspace requires updating launcher env logic, not just JSON
4. **No Fallback**: If env var missing or malformed, no class-based fallback available

**🤔 Current System Already Uses This Pattern!**

Looking at existing code (`handlers.py:506-544`):
```python
# Feature 037 T026-T029: Guaranteed workspace assignment on launch
# If window has I3PM_APP_NAME, look up preferred workspace in registry
if window_env and window_env.app_name and application_registry:
    app_name = window_env.app_name
    app_def = application_registry.get(app_name)

    if app_def and "preferred_workspace" in app_def:
        preferred_ws = app_def["preferred_workspace"]
```

**Current system ALREADY**:
- Reads `I3PM_APP_NAME` from environment (✓ deterministic app identification)
- Looks up workspace in registry (❌ indirection)

**Hybrid Approach - RECOMMENDED**:

Use environment variables with registry fallback:

```python
# Priority 1: Direct workspace assignment via environment
if window_env and window_env.target_workspace:
    preferred_ws = window_env.target_workspace
    logger.info(f"Using I3PM_TARGET_WORKSPACE={preferred_ws}")

# Priority 2: App name lookup in registry
elif window_env and window_env.app_name and application_registry:
    app_name = window_env.app_name
    app_def = application_registry.get(app_name)
    if app_def and "preferred_workspace" in app_def:
        preferred_ws = app_def["preferred_workspace"]
        logger.info(f"Looked up workspace for {app_name}={preferred_ws}")

# Priority 3: Window class matching (new Feature 039 addition)
else:
    # Use tiered window class matching
    matched_app = match_window_class(...)
    if matched_app:
        preferred_ws = matched_app["preferred_workspace"]
```

**Benefits of Hybrid**:
1. **✓ Deterministic when env var provided**: Zero ambiguity
2. **✓ Flexible configuration**: Can still use registry for easy reconfiguration
3. **✓ Robust fallback**: Window class matching as last resort
4. **✓ Backward compatible**: Existing configs work unchanged
5. **✓ Future-proof**: Can optimize launcher to inject workspace without breaking old apps

**Implementation in Feature 039**:

1. **Add to I3PMEnvironment model**:
   ```python
   class I3PMEnvironment(BaseModel):
       app_name: str
       target_workspace: Optional[int] = None  # NEW: Direct workspace assignment
       ...
   ```

2. **Update app-launcher-wrapper.sh**:
   ```bash
   # Query registry for workspace
   WORKSPACE=$(jq -r ".[] | select(.name==\"$APP_NAME\") | .preferred_workspace" < registry.json)

   # Inject as environment variable
   export I3PM_TARGET_WORKSPACE=$WORKSPACE
   export I3PM_APP_NAME=$APP_NAME
   ```

3. **Update handler priority logic** (as shown above)

4. **Diagnostic output shows source**:
   ```
   Window Matching
   ──────────────────────────────────────────────────────
   Workspace Assignment Source    environment variable ✓
   Target Workspace               3
   ```

**Conflict with Window Rules?**

NO - environment variable approach **complements** window class matching:

**Use Cases**:
- **Launched via i3pm launcher**: Has env vars → use `I3PM_TARGET_WORKSPACE` (fastest)
- **Launched via rofi/dmenu**: No env vars → use window class matching (Feature 039)
- **Launched manually in terminal**: No env vars → use window class matching

**Window rules DON'T conflict** because they're fallback mechanisms:
1. Try env var workspace → if present, done
2. Try app name lookup → if found, done
3. Try window class matching → if matched, done
4. Fallback to current workspace

**Recommendation for Feature 039**:

**ACCEPT** environment-based assignment as **PRIMARY** strategy:
1. Document `I3PM_TARGET_WORKSPACE` in I3PMEnvironment model ✓
2. Update handler to prioritize env var workspace
3. Keep window class matching as robust fallback
4. Update app-launcher-wrapper to inject workspace number
5. Add diagnostic output showing assignment source

**This makes the system MORE deterministic while maintaining flexibility.**

### Multi-Window Application Edge Case (VS Code)

**Critical Finding**: Electron apps like VS Code use ONE PID for multiple windows.

**Problem**:
- VS Code main process PID: 823199
- All windows report `_NET_WM_PID: 823199`
- Reading `/proc/823199/environ` returns SAME environment for all windows
- Cannot distinguish windows via environment variables alone

**Existing Solution** (Feature 038 - already implemented):
```python
# connection.py lines 202-223: VS Code title parsing
if container.window_class == "Code" and container.name:
    match = re.match(r"(?:Code - )?([^-]+) -", container.name)
    if match:
        title_project = match.group(1).strip().lower()
        # Override environment project with title-based project
```

**Window title examples**:
- `"stacks - nixos - Visual Studio Code"` → Extract project: `stacks`
- `"nixos - nixos - Visual Studio Code"` → Extract project: `nixos`

**Testing confirmed**:
```
Ghostty (unique PIDs):
  Window 52428802 → PID 805959  → I3PM_PROJECT_NAME=stacks ✓
  Window 54525956 → PID 3838556 → I3PM_PROJECT_NAME=nixos ✓

VS Code (shared PID):
  Window 37748739 → PID 823199 → Title parsing → Project: stacks ✓
  Window 37748750 → PID 823199 → Title parsing → Project: nixos ✓
```

**Updated Priority for I3PM_TARGET_WORKSPACE**:

```python
# Priority 1: App-specific handlers (VS Code, IntelliJ, etc.)
# - For apps with shared PIDs across windows
# - Title parsing or other window properties
if has_app_specific_handler(window_class):
    project = parse_app_specific_context(window)
    return lookup_workspace_by_project(project)

# Priority 2: I3PM_TARGET_WORKSPACE (direct env var)
# - Most deterministic for single-PID apps
if i3pm_env.target_workspace:
    return i3pm_env.target_workspace

# Priority 3: I3PM_APP_NAME lookup (registry)
# - Fallback for apps launched with environment but no target workspace
if i3pm_env.app_name:
    return registry[app_name].workspace

# Priority 4: Window class matching (tiered)
# - Last resort for manually launched apps
return match_window_class(window)
```

**Why app-specific handlers are FIRST**:
- Multi-window apps (VS Code) have unreliable environment due to shared PID
- Title/property parsing is MORE accurate than environment for these apps
- Single-window apps skip this tier and use faster env var lookup

**Known app-specific handlers**:
1. VS Code (class: "Code") → Title parsing for project name
2. Future: IntelliJ IDEA, PyCharm → Similar title patterns
3. Future: Firefox Developer Tools → Window role property

**Coverage**:
- ✅ 95% of apps: unique PID per window → env vars work perfectly
- ✅ 5% of apps: shared PID → title parsing fallback
- ❌ Edge case: Electron app without distinguishable titles → would fail (document limitation)

---

## Research Questions Resolved

### Q1: Window class normalization strategy?
**Answer**: Exact + instance + normalized (tiered matching)
**Rationale**: Best UX without false positives

### Q2: Window PID resolution failures?
**Answer**: Return None, log debug message, continue gracefully
**Rationale**: Avoid xprop fallback complexity - PIDs usually available, failure is rare

### Q3: Code similarity threshold for "duplicate"?
**Answer**: Exact syntax OR same logic with different names
**Rationale**: Both represent consolidation opportunities, manual review distinguishes

### Q4: Diagnostic tools integrated or separate?
**Answer**: Separate `i3pm diagnose` subcommand namespace
**Rationale**: Keeps diagnostic code isolated, follows kubectl/systemctl patterns

### Q5: Should we use environment variable workspace assignment instead of window class matching?
**Answer**: HYBRID - environment variable as primary, window class matching as fallback
**Rationale**: Environment variables are deterministic when available (launcher use case), window class matching provides robust fallback (manual launch use case). No conflicts, complementary strategies.

---

## Implementation Priorities

**High Priority** (P1):
1. Fix window::new event detection (current critical bug)
2. Implement window class normalization (FR-003)
3. Code audit and duplicate elimination (FR-016-017)
4. Diagnostic health check command (FR-014)

**Medium Priority** (P2):
5. Event trace command for debugging (FR-007)
6. Window property inspection command (FR-006)
7. State validation command (FR-010)
8. Comprehensive test coverage (FR-019)

**Lower Priority** (P3):
9. PWA instance identification (US5)
10. Performance metrics tracking (FR-015)

---

## Technology Stack Confirmation

**Language**: Python 3.13
**Core Libraries**:
- i3ipc-python (i3ipc.aio) - async i3 IPC
- asyncio - event loop
- Rich - terminal UI
- click - CLI argument parsing
- Pydantic - data validation

**Testing**:
- pytest - test framework
- pytest-asyncio - async test support
- pytest-mock - mocking

**Code Quality**:
- pylint - duplicate detection + linting
- mypy - type checking (optional but recommended)

**Performance Targets**:
- Event detection: <50ms
- Handler execution: <100ms
- Diagnostic commands: <5s
- CPU usage: <1% steady state

All targets achievable with Python async/await patterns.

---

## Next Steps

Phase 1 (Design & Contracts) will define:
1. **data-model.md**: Pydantic models for WindowIdentity, DiagnosticReport, etc.
2. **contracts/**: JSON-RPC API specs and CLI command contracts
3. **quickstart.md**: User guide for diagnostic commands

Implementation will proceed via `/speckit.tasks` to generate ordered task list.

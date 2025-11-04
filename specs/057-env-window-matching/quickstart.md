# Quickstart Guide: Environment Variable-Based Window Matching

**Feature**: 057-env-window-matching
**Date**: 2025-11-03
**Target Users**: Developers, power users, i3pm system administrators

## What This Feature Provides

Environment variable-based window matching **simplifies and accelerates** window identification by replacing complex multi-tier class matching with deterministic environment variable lookup. Instead of fuzzy matching on window class, instance, or title, the system reads I3PM_* variables directly from the window's process environment.

**Key Benefits**:
- ✅ **15-27x faster** window identification (0.4ms vs 6-11ms)
- ✅ **100% deterministic** - no more race conditions from window property timing
- ✅ **Simpler codebase** - 280 lines of complex logic replaced with dict lookups
- ✅ **Multi-instance tracking** - unique I3PM_APP_ID for every window instance
- ✅ **Reliable PWA support** - no class pattern matching heuristics

---

## Quick Reference

### Essential Commands

```bash
# Validate environment variable coverage
i3pm diagnose coverage

# Benchmark /proc filesystem performance
i3pm benchmark environ

# View window environment variables
i3pm windows --table          # See APP_ID column
window-env <PID|class|title>  # View full I3PM_* variables

# Check specific window
i3pm diagnose window <window_id>
```

---

## Understanding Environment Variables

Every application launched through the i3pm launcher wrapper receives these environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `I3PM_APP_ID` | Unique instance identifier | `"claude-pwa-nixos-833032-1762201416"` |
| `I3PM_APP_NAME` | Application type | `"claude-pwa"`, `"vscode"`, `"terminal"` |
| `I3PM_PROJECT_NAME` | Project association | `"nixos"`, `"stacks"`, `""` (empty if no project) |
| `I3PM_PROJECT_DIR` | Project working directory | `"/etc/nixos"` |
| `I3PM_SCOPE` | Visibility scope | `"global"` (always visible) or `"scoped"` (project-specific) |
| `I3PM_TARGET_WORKSPACE` | Preferred workspace | `52`, `2`, etc. |
| `I3PM_EXPECTED_CLASS` | Expected window class (for validation) | `"FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5"` |

**Query a window's environment**:
```bash
# By PID
window-env 833032

# By window class
window-env Claude

# By window title
window-env "Claude — Mozilla Firefox"

# Filter I3PM_* variables only
window-env --filter I3PM_ Claude
```

**Output**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Window: FFPWA-01JCYF8Z2... - Claude — Mozilla Firefox
ID: 94532735639728  PID: 833032  Workspace: 52  Project: nixos
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Environment variables (filtered by 'I3PM_'):

  I3PM_ACTIVE=true
  I3PM_APP_ID=claude-pwa-nixos-833032-1762201416
  I3PM_APP_NAME=claude-pwa
  I3PM_EXPECTED_CLASS=FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5
  I3PM_LAUNCHER_PID=833032
  I3PM_LAUNCH_TIME=1762201416
  I3PM_PROJECT_DIR=/etc/nixos
  I3PM_PROJECT_DISPLAY_NAME=NixOS
  I3PM_PROJECT_ICON=❄️
  I3PM_PROJECT_NAME=nixos
  I3PM_SCOPE=scoped
  I3PM_TARGET_WORKSPACE=52
```

---

## How Window Matching Works

### Before (Legacy Multi-Tier Matching):

```python
# Complex tiered fallback logic (window_identifier.py - REMOVED)
1. Try exact window class match (case-sensitive)
2. Try instance match (case-insensitive)
3. Try normalized match (strip prefix, lowercase)
4. Try alias matching (iterate all aliases)
5. Try PWA detection (FFPWA-*, Google-chrome patterns)
6. Iterate through entire application registry (50+ apps)

Result: 6-11ms per window, non-deterministic for PWAs
```

### After (Environment-Based Matching):

```python
# Simple environment variable lookup
1. Read /proc/<pid>/environ → Dict[str, str]
2. Parse I3PM_APP_NAME from dict (O(1) hash lookup)
3. Parse I3PM_PROJECT_NAME, I3PM_SCOPE (O(1) lookups)
4. Done

Result: 0.4ms per window, 100% deterministic
```

**Key Advantage**: No window property parsing, no registry iteration, no fuzzy matching - just direct environment variable access.

---

## Common Use Cases

### Use Case 1: Identify Application Type

**Before (Legacy)**:
```python
# Complex class matching with normalization
identity = get_window_identity(
    actual_class="FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",
    actual_instance="claude",
    window_title="Claude — Mozilla Firefox"
)
app_type = identity["normalized_class"]  # "ffpwa-01jcyf8z2m7r4n6qw9xkphvtb5" (not useful)

# Requires PWA detection heuristics
if identity["is_pwa"]:
    # Infer app type from registry based on PWA ID
```

**After (Environment-Based)**:
```python
# Direct environment variable lookup
env_vars = read_process_environ(window.pid)
window_env = WindowEnvironment.from_env_dict(env_vars)

app_type = window_env.app_name  # "claude-pwa" (explicit, deterministic)
```

---

### Use Case 2: Distinguish Multiple Window Instances

**Before (Legacy)**:
```python
# No reliable way to distinguish instances
# Window class: "Code" for all VS Code windows
# Window title: Changes frequently (file names)
# Result: Multi-instance tracking requires complex title parsing
```

**After (Environment-Based)**:
```python
# Each instance has unique I3PM_APP_ID
window1_env = WindowEnvironment.from_env_dict(read_process_environ(pid1))
window2_env = WindowEnvironment.from_env_dict(read_process_environ(pid2))

window1_env.app_id  # "vscode-nixos-1187796-1762201000"
window2_env.app_id  # "vscode-stacks-1198765-1762202000"

# Unique identifiers enable layout restoration, window tracking
```

---

### Use Case 3: Determine Project Association

**Before (Legacy)**:
```python
# Infer from window marks (set asynchronously after window creation)
marks = window.marks
project_name = None
for mark in marks:
    if mark.startswith("project:"):
        project_name = mark.split(":", 1)[1]

# Problem: Race condition - marks may not be set yet
# Problem: Mark-based filtering requires separate state tracking
```

**After (Environment-Based)**:
```python
# Direct from environment (set at launch, never changes)
env_vars = read_process_environ(window.pid)
window_env = WindowEnvironment.from_env_dict(env_vars)

project_name = window_env.project_name  # "nixos" or "" if no project

# No race condition - environment set before process starts
# No mark parsing - single source of truth
```

---

### Use Case 4: Control Window Visibility (Project Switching)

**Before (Legacy)**:
```python
# Check marks + registry scope lookup
marks = window.marks
has_project_mark = any(mark.startswith("project:") for mark in marks)

# Look up scope in registry by window class
app_def = match_with_registry(window.window_class, window.window_instance)
scope = app_def["scope"] if app_def else "unknown"

if scope == "global":
    show_window()
elif scope == "scoped" and has_project_mark:
    if project_matches(marks, active_project):
        show_window()
    else:
        hide_window()
```

**After (Environment-Based)**:
```python
# Direct visibility check from environment
env_vars = read_process_environ(window.pid)
window_env = WindowEnvironment.from_env_dict(env_vars)

if window_env.should_be_visible(active_project="nixos"):
    show_window()
else:
    hide_window()

# WindowEnvironment.should_be_visible() logic:
# - If scope == "global" → always visible
# - If scope == "scoped" → visible only if project_name matches active_project
```

---

## Validation & Monitoring

### Validate Environment Variable Coverage

**Check that all windows have I3PM_* variables**:
```bash
i3pm diagnose coverage
```

**Expected Output** (100% coverage):
```
Environment Variable Coverage Report
=====================================
Total Windows:        42
With I3PM_* Variables: 42
Coverage:             100.0%
Status:               PASS

No missing windows.
```

**If coverage < 100%** (gap detected):
```
Environment Variable Coverage Report
=====================================
Total Windows:        43
With I3PM_* Variables: 42
Coverage:             97.7%
Status:               FAIL

Missing Windows:
  ID: 12345678  Class: firefox  Title: Mozilla Firefox  Reason: no_variables
```

**Resolution**:
- Windows launched outside launcher (e.g., `firefox` from command line) won't have I3PM_* variables
- This is expected - unmanaged windows are not part of project system
- If application from registry is missing variables → launcher wrapper bug (report issue)

---

### Benchmark Performance

**Measure /proc filesystem read latency**:
```bash
i3pm benchmark environ --samples 1000
```

**Expected Output**:
```
Environment Query Performance Benchmark
========================================
Operation:     read_process_environ
Sample Size:   1000
Average:       0.42ms
p50 (Median):  0.35ms
p95:           1.23ms
p99:           2.87ms
Max:           4.56ms
Status:        PASS (p95 < 10ms)
```

**Success Criteria**:
- p95 latency < 10ms → **PASS**
- p95 latency >= 10ms → **FAIL** (investigate /proc performance)

---

### Monitor Window Identification

**View all windows with environment details**:
```bash
i3pm windows --table
```

**New APP_ID column**:
```
              ID |      PID | APP_ID                    | Class              | Title                               | WS   | Project
-----------------+----------+---------------------------+--------------------+-------------------------------------+------+--------
             152 |   716344 | terminal-nixos-716243-... | Alacritty          | Alacritty                           | 1    | nixos:152
        20971524 |  1188968 | vscode-nixos-1187796-1... | Code               | app-registry-data.nix (03ea3a1) ... | 2    | nixos:11
```

**APP_ID format**: `<app_name>-<project_name>-<launcher_pid>-<launch_time>`
- Shortened to 25 chars in table (full value in JSON output)
- Unique per window instance
- Persistent across daemon restarts (stored in layout save/restore)

---

## Troubleshooting

### Problem: Window not identified (no I3PM_* variables)

**Symptoms**:
- `i3pm diagnose coverage` shows < 100%
- `window-env <pid>` returns empty I3PM_* section

**Diagnosis**:
```bash
# Check if process has I3PM_* variables
window-env <pid> | grep I3PM_

# If empty, check if launched via launcher wrapper
ps aux | grep <pid>

# Check launcher wrapper logs
tail -f ~/.local/state/app-launcher.log
```

**Causes**:
1. **Application launched outside launcher** (e.g., from command line)
   - Resolution: Use launcher (Win+D) or `i3pm app launch <app_name>`
2. **Launcher wrapper not injecting variables** (bug)
   - Resolution: Check wrapper script at `scripts/i3pm/app-launcher-wrapper.sh`
3. **Child process doesn't inherit environment** (rare)
   - Resolution: Parent PID traversal should handle this (up to 3 levels)

---

### Problem: Parent traversal not finding variables

**Symptoms**:
- `i3pm diagnose window <id>` shows `traversal_depth > 0` but `environment: None`

**Diagnosis**:
```bash
# Check PID hierarchy
pstree -p <window_pid>

# Manually check parent environments
window-env <parent_pid_1>
window-env <parent_pid_2>
window-env <parent_pid_3>
```

**Causes**:
1. **Process chain exceeds 3 levels** (rare)
   - Resolution: Increase `max_depth` in `get_window_environment()` (requires code change)
2. **Parent process replaced environment** (overwrote variables)
   - Resolution: Fix application launch flow to preserve I3PM_* variables
3. **Process not spawned by launcher** (direct exec)
   - Resolution: No fix - treat as unmanaged window

---

### Problem: Performance degradation (queries > 10ms)

**Symptoms**:
- `i3pm benchmark environ` shows p95 > 10ms
- Lag when switching projects or creating windows

**Diagnosis**:
```bash
# Run benchmark
i3pm benchmark environ --samples 1000

# Check /proc filesystem performance
time cat /proc/self/environ > /dev/null

# Check disk I/O
iostat -x 1
```

**Causes**:
1. **High system load** (100+ processes, CPU maxed)
   - Resolution: Reduce background processes, optimize daemon CPU usage
2. **/proc on slow filesystem** (rare - /proc is tmpfs)
   - Resolution: Verify /proc mount with `mount | grep proc`
3. **Parent traversal in hot path** (excessive traversal)
   - Resolution: Check daemon logs for traversal frequency

---

## Migration from Legacy Code

### Files Removed

**Complete removal** (no backward compatibility):
- `services/window_identifier.py` (280 lines) - Replaced by `services/window_environment.py`

**Functions removed**:
- `normalize_class()`
- `match_window_class()`
- `_match_single()`
- `get_window_identity()`
- `match_pwa_instance()`
- `match_with_registry()`

### Configuration Changes

**app-registry-data.nix** (simplified):

**Before**:
```nix
{
  claude-pwa = {
    name = "claude-pwa";
    display_name = "Claude PWA";
    expected_class = "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5";  # Used for matching
    aliases = ["claude"];                                # Used for fuzzy matching
    scope = "scoped";
    preferred_workspace = 52;
    command = "firefoxpwa site launch ...";
  };
}
```

**After**:
```nix
{
  claude-pwa = {
    name = "claude-pwa";
    display_name = "Claude PWA";
    expected_class = "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5";  # For VALIDATION only
    # aliases removed - no longer used for matching
    scope = "scoped";
    preferred_workspace = 52;
    command = "firefoxpwa site launch ...";
  };
}
```

**Changes**:
- `expected_class`: Now used **only for validation** (I3PM_EXPECTED_CLASS vs actual window class)
- `aliases`: **Removed** - no longer needed (I3PM_APP_NAME is deterministic)
- Matching uses `I3PM_APP_NAME` instead of `expected_class`

---

## Developer Guide

### Adding Environment Variable Support to New Applications

**1. Update app-registry-data.nix** (if not already present):
```nix
{
  my-new-app = {
    name = "my-new-app";                # This becomes I3PM_APP_NAME
    display_name = "My New App";
    expected_class = "MyAppClass";      # Expected window class (for validation)
    scope = "scoped";                   # "global" or "scoped"
    preferred_workspace = 10;           # Target workspace
    command = "/path/to/my-app";
  };
}
```

**2. Ensure app launches via wrapper** (already automatic for registered apps):
- Applications in registry automatically use `app-launcher-wrapper.sh`
- Wrapper injects I3PM_* variables before launching process
- No additional configuration needed

**3. Validate environment injection**:
```bash
# Launch app via launcher
# Win+D → type "my new app" → Enter

# Check environment
i3pm windows --table | grep "my-new-app"
window-env "My New App" | grep I3PM_
```

**Expected variables**:
```
I3PM_APP_ID=my-new-app-nixos-123456-1762201416
I3PM_APP_NAME=my-new-app
I3PM_PROJECT_NAME=nixos
I3PM_SCOPE=scoped
I3PM_TARGET_WORKSPACE=10
I3PM_EXPECTED_CLASS=MyAppClass
```

---

### Testing Environment-Based Matching

**Unit tests** (pytest):
```python
# tests/unit/test_window_environment.py
def test_parse_environment_variables():
    env_dict = {
        "I3PM_APP_ID": "test-app-project-123-456",
        "I3PM_APP_NAME": "test-app",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "project",
    }

    window_env = WindowEnvironment.from_env_dict(env_dict)

    assert window_env.app_id == "test-app-project-123-456"
    assert window_env.app_name == "test-app"
    assert window_env.scope == "scoped"
    assert window_env.project_name == "project"
    assert window_env.is_scoped is True

def test_visibility_logic():
    window_env = WindowEnvironment(
        app_id="test-123",
        app_name="test",
        scope="scoped",
        project_name="nixos"
    )

    # Scoped window visible only in matching project
    assert window_env.should_be_visible("nixos") is True
    assert window_env.should_be_visible("stacks") is False
    assert window_env.should_be_visible(None) is False

    # Global window always visible
    global_env = WindowEnvironment(
        app_id="test-456",
        app_name="test",
        scope="global"
    )
    assert global_env.should_be_visible("nixos") is True
    assert global_env.should_be_visible(None) is True
```

**Integration tests**:
```python
# tests/integration/test_proc_filesystem.py
import pytest
from pathlib import Path

@pytest.mark.asyncio
async def test_read_process_environ_real_process():
    # Get current process PID
    pid = os.getpid()

    # Read environment
    env_vars = read_process_environ(pid)

    # Verify we can read our own environment
    assert "PATH" in env_vars
    assert len(env_vars) > 0

@pytest.mark.asyncio
async def test_environment_query_with_traversal():
    # Create test process hierarchy (parent → child)
    # ... test implementation

    result = await get_window_environment(window_id, child_pid)

    # Should find parent's I3PM_* variables
    assert result.success is True
    assert result.traversal_depth > 0
```

---

## Performance Characteristics

### Latency Benchmarks

| Operation | Average | p95 | p99 | Target |
|-----------|---------|-----|-----|--------|
| read_process_environ() | 0.4ms | 1.2ms | 2.8ms | <10ms |
| WindowEnvironment.from_env_dict() | 0.1ms | 0.2ms | 0.3ms | <1ms |
| get_window_environment() (no traversal) | 0.5ms | 1.5ms | 3.0ms | <10ms |
| get_window_environment() (with traversal) | 1.8ms | 4.2ms | 6.8ms | <20ms |
| Batch query (50 windows) | 25ms | 48ms | 72ms | <100ms |

**Comparison to Legacy Matching**:
- Legacy: 6-11ms per window (class matching + registry iteration)
- Environment-based: 0.4ms per window (15-27x faster)

### Memory Usage

- WindowEnvironment object: ~200 bytes per instance
- Environment dict cache: ~1-4KB per process
- Total overhead: <1MB for 100 windows

---

## Frequently Asked Questions

### Q: What happens if I launch an app from the command line (not via launcher)?

**A**: The application won't have I3PM_* environment variables and will be treated as an **unmanaged window**.

- **Not identified**: No app_name, no project association
- **Not filtered**: Won't hide/show during project switches
- **Not assigned**: Won't go to preferred workspace

**Solution**: Launch apps via launcher (Win+D) or use `i3pm app launch <app_name>` command.

---

### Q: Do child processes inherit I3PM_* variables?

**A**: **Usually yes**, but parent traversal handles edge cases.

- Most applications preserve environment for child processes (inherit)
- Electron apps, shell scripts, browser tabs typically inherit
- If child doesn't inherit, parent PID traversal (up to 3 levels) finds variables
- Edge case: Process explicitly clears environment → becomes unmanaged window

---

### Q: Can I manually set I3PM_* variables for an application?

**A**: **Yes**, but not recommended (use launcher wrapper instead).

**Manual injection** (for testing):
```bash
I3PM_APP_ID="manual-test-$(date +%s)" \
I3PM_APP_NAME="manual-test" \
I3PM_SCOPE="global" \
/path/to/application
```

**Better approach**: Add application to registry and launch via launcher.

---

### Q: How does this affect layout save/restore?

**A**: **Improved reliability** - layouts match by I3PM_APP_ID instead of window class.

**Before (Legacy)**:
- Saved layout stores window class: `"Code"`
- On restore, matches first VS Code window found (ambiguous for multi-instance)

**After (Environment-Based)**:
- Saved layout stores I3PM_APP_ID: `"vscode-nixos-1187796-1762201000"`
- On restore, matches exact instance by app_id (unambiguous)

**Benefits**:
- Multi-instance apps restore to correct positions
- No class normalization ambiguity
- Deterministic matching even with multiple instances

---

### Q: Does this work with Firefox PWAs?

**A**: **Yes** - Firefox PWAs fully supported (already tested in Feature 056).

- firefoxpwa-wrapper.sh injects I3PM_* variables before launching PWA
- Each PWA instance has unique I3PM_APP_ID
- I3PM_APP_NAME identifies PWA type (e.g., "claude-pwa", "youtube-pwa")
- I3PM_EXPECTED_CLASS contains FFPWA ULID for validation

**Validation**:
```bash
window-env YouTube
# Shows I3PM_APP_NAME=youtube-pwa, I3PM_APP_ID=youtube-pwa-nixos-...
```

---

## Summary

**Environment variable-based window matching** replaces complex, non-deterministic window class matching with simple, fast, deterministic environment variable lookups.

**Key Takeaways**:
- ✅ **15-27x faster** than legacy class matching
- ✅ **100% deterministic** - no race conditions or fuzzy matching
- ✅ **Simpler codebase** - 280 lines removed
- ✅ **Multi-instance tracking** - unique app_id per window
- ✅ **Reliable PWA support** - explicit app_name instead of class patterns

**Next Steps**:
- Validate coverage: `i3pm diagnose coverage`
- Benchmark performance: `i3pm benchmark environ`
- Monitor windows: `i3pm windows --table`
- Query environment: `window-env <pid|class|title>`

**Migration**: No user action required - environment variables already injected by launchers.

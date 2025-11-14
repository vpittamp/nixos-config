# Restoration Mark Flow Contract

**Feature**: 075-layout-restore-production

## Overview

This contract defines the complete flow of restoration marks from generation through correlation, ensuring all components handle marks correctly.

## Flow Stages

### Stage 1: Mark Generation

**Component**: `home-modules/desktop/i3-project-event-daemon/layout/restore.py`
**Trigger**: User runs `i3pm layout restore <project> <name>`
**Action**: Generate unique mark for each window placeholder

**Contract**:
```python
def generate_restoration_mark() -> str:
    """Generate unique restoration mark."""
    import uuid
    suffix = uuid.uuid4().hex[:8]
    mark = f"i3pm-restore-{suffix}"
    assert len(mark) == 20  # "i3pm-restore-" (13) + 8 hex = 21 chars
    assert mark.startswith("i3pm-restore-")
    return mark

# Assign to each placeholder
for placeholder in layout.placeholders:
    placeholder.restoration_mark = generate_restoration_mark()
```

**Postconditions**:
- Each placeholder has unique restoration_mark
- Mark format: `i3pm-restore-[0-9a-f]{8}`
- No duplicate marks in session

---

### Stage 2: AppLauncher Setup

**Component**: `home-modules/desktop/i3-project-event-daemon/services/app_launcher.py`
**Trigger**: `restore.py` calls `app_launcher.launch_app(app_name, restore_mark=mark)`
**Action**: Set I3PM_RESTORE_MARK environment variable before launching

**Contract**:
```python
async def launch_app(
    self,
    app_name: str,
    restore_mark: Optional[str] = None,
    **kwargs
) -> LaunchResult:
    """Launch app with optional restoration mark."""
    env = os.environ.copy()

    # Standard I3PM_* variables
    env["I3PM_APP_NAME"] = app_name
    # ... other vars

    # Feature 075: Add restoration mark
    if restore_mark:
        env["I3PM_RESTORE_MARK"] = restore_mark
        logger.debug(f"Setting I3PM_RESTORE_MARK={restore_mark} for {app_name}")

    # Launch wrapper with environment
    proc = await asyncio.create_subprocess_exec(
        "app-launcher-wrapper.sh",
        app_name,
        env=env,  # Pass environment to subprocess
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
```

**Postconditions**:
- Wrapper process inherits I3PM_RESTORE_MARK in environment
- Mark is logged for debugging
- Wrapper can access mark via `${I3PM_RESTORE_MARK}`

---

### Stage 3: Wrapper Export

**Component**: `scripts/app-launcher-wrapper.sh`
**Trigger**: Wrapper launched by AppLauncher with I3PM_RESTORE_MARK in env
**Action**: Export mark and add to ENV_EXPORTS array

**Contract**:
```bash
# Line 273-278: Export restoration mark if present
if [[ -n "${I3PM_RESTORE_MARK:-}" ]]; then
    export I3PM_RESTORE_MARK
    log "DEBUG" "I3PM_RESTORE_MARK=$I3PM_RESTORE_MARK (layout restore)"
fi

# Line 398-417: Build ENV_EXPORTS array
ENV_EXPORTS=(
    "export I3PM_APP_ID='$I3PM_APP_ID'"
    # ... other exports
)

# Feature 075 FIX: Add restoration mark to exports
if [[ -n "${I3PM_RESTORE_MARK:-}" ]]; then
    ENV_EXPORTS+=("export I3PM_RESTORE_MARK='$I3PM_RESTORE_MARK'")
fi

# Line 419: Build environment string
ENV_STRING=$(IFS='; '; echo "${ENV_EXPORTS[*]}")
```

**Postconditions**:
- I3PM_RESTORE_MARK exported in wrapper environment
- Mark added to ENV_EXPORTS array
- ENV_STRING contains restoration mark export

---

### Stage 4: Sway Exec

**Component**: `scripts/app-launcher-wrapper.sh`
**Trigger**: After ENV_STRING built
**Action**: Launch app via swaymsg exec with environment

**Contract**:
```bash
# Line 431-438: Execute via Sway IPC
FULL_CMD="$ENV_STRING; $APP_CMD"

if command -v swaymsg &>/dev/null; then
    SWAY_RESULT=$(swaymsg exec "bash -c \"$FULL_CMD\"" 2>&1)
    # bash -c will export all variables before running $APP_CMD
    # Launched process will have I3PM_RESTORE_MARK in environment
fi
```

**Example FULL_CMD**:
```bash
export I3PM_APP_ID='alacritty-nixos-12345-1699980330'; \
export I3PM_APP_NAME='alacritty'; \
export I3PM_RESTORE_MARK='i3pm-restore-abc12345'; \
cd '/etc/nixos' && alacritty
```

**Postconditions**:
- swaymsg exec receives complete environment string
- bash -c executes exports before launching app
- Launched app inherits all I3PM_* variables

---

### Stage 5: Process Environment

**Component**: Launched application (any app)
**Trigger**: swaymsg exec completes
**Action**: Application runs with I3PM_* environment

**Contract**:
```bash
# Verification via /proc/<pid>/environ
cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM_

# Expected output:
I3PM_APP_ID=alacritty-nixos-12345-1699980330
I3PM_APP_NAME=alacritty
I3PM_RESTORE_MARK=i3pm-restore-abc12345
# ... other I3PM_* vars
```

**Postconditions**:
- All I3PM_* variables readable from /proc/<pid>/environ
- Mark value matches what was generated in Stage 1
- Process can be queried by daemon

---

### Stage 6: Daemon Detection

**Component**: `home-modules/desktop/i3-project-event-daemon/handlers.py`
**Trigger**: window::new event from Sway IPC
**Action**: Read restoration mark from process environment

**Contract**:
```python
async def on_window_new(self, i3: Connection, event: WindowEvent):
    """Handle window::new event."""
    window = event.container
    pid = window.pid

    if not pid:
        return

    # Read process environment
    env_dict = self._read_process_environ(pid)

    # Check for restoration mark
    restore_mark = env_dict.get("I3PM_RESTORE_MARK")

    if restore_mark:
        logger.info(f"Found restoration mark: {restore_mark} for window {window.id}")

        # Apply mark to window
        await i3.command(f'[con_id={window.id}] mark {restore_mark}')

        # Notify correlation system
        await self.correlation_service.window_marked(window.id, restore_mark)

def _read_process_environ(self, pid: int) -> dict:
    """Read environment variables from /proc/<pid>/environ."""
    try:
        with open(f"/proc/{pid}/environ", "r") as f:
            content = f.read()
        pairs = content.split("\0")
        return dict(pair.split("=", 1) for pair in pairs if "=" in pair)
    except Exception as e:
        logger.error(f"Failed to read environ for PID {pid}: {e}")
        return {}
```

**Postconditions**:
- Restoration mark read from /proc/<pid>/environ
- Mark applied to Sway window via `swaymsg mark`
- Correlation service notified

---

### Stage 7: Sway Mark Application

**Component**: Sway compositor
**Trigger**: Daemon runs `swaymsg mark <mark>`
**Action**: Mark attached to window in Sway tree

**Verification**:
```bash
# Query Sway for window with mark
swaymsg -t get_tree | jq '.. | select(.marks? and (.marks | index("i3pm-restore-abc12345"))) | {id, app_id, marks}'

# Expected output:
{
  "id": 123456,
  "app_id": "Alacritty",
  "marks": ["i3pm-restore-abc12345"]
}
```

**Postconditions**:
- Window has mark in Sway tree
- Mark queryable via GET_TREE
- Mark visible in GET_MARKS

---

### Stage 8: Correlation Match

**Component**: `home-modules/desktop/i3-project-event-daemon/layout/correlation.py`
**Trigger**: Correlation service notified of window with mark
**Action**: Match window to placeholder by mark

**Contract**:
```python
async def window_marked(self, window_id: int, restore_mark: str):
    """Handle window with restoration mark."""
    if restore_mark not in self.pending_marks:
        logger.warning(f"Unknown restoration mark: {restore_mark}")
        return

    placeholder = self.pending_marks[restore_mark]

    # Match window to placeholder
    self.matched_windows[window_id] = restore_mark
    del self.pending_marks[restore_mark]

    logger.info(f"Matched window {window_id} to placeholder via mark {restore_mark}")

    # Apply saved geometry and state
    await self._apply_placeholder_state(window_id, placeholder)

    # Check if all windows matched
    if not self.pending_marks:
        await self._complete_restoration()
```

**Postconditions**:
- Window matched to correct placeholder
- Mark removed from pending_marks
- Geometry and focus applied
- Success logged and reported

---

## End-to-End Timing

Target performance for single window:

| Stage | Component | Target Time | Notes |
|-------|-----------|-------------|-------|
| 1. Mark Generation | restore.py | <1ms | UUID generation |
| 2. AppLauncher Setup | app_launcher.py | <10ms | Environment setup |
| 3. Wrapper Export | wrapper script | <50ms | Script execution |
| 4. Sway Exec | swaymsg | <100ms | IPC command |
| 5. Process Start | application | Variable | Depends on app |
| 6. Daemon Detection | handlers.py | <100ms | Read + mark apply |
| 7. Sway Mark | Sway IPC | <50ms | Mark attachment |
| 8. Correlation | correlation.py | <10ms | Dict lookup |
| **Total** | | **<1s + app start** | Excluding app startup |

**Current Issue**: Stage 3-4 broken (mark not in ENV_EXPORTS) → 30s timeout per window

**After Fix**: <1s per window (excluding app startup time)

---

## Failure Points and Detection

| Stage | Failure Mode | Detection | Fix |
|-------|--------------|-----------|-----|
| 3. Wrapper Export | Mark not in ENV_EXPORTS | Correlation timeout (30s) | Add conditional export (Feature 075) |
| 4. Sway Exec | ENV_STRING malformed | Wrapper logs error | Validate ENV_STRING construction |
| 5. Process Env | Mark not inherited | Daemon can't read from /proc | Check swaymsg exec syntax |
| 6. Daemon Detection | File read permission | Exception in _read_process_environ | Ensure daemon has access |
| 7. Sway Mark | IPC command fails | swaymsg returns error | Check window ID valid |
| 8. Correlation | Unknown mark | Warning logged | Ensure mark in pending_marks |

---

## Testing Contract

Each stage MUST have automated test:

```python
# TEST: Stage 1 - Mark Generation
def test_generate_restoration_mark():
    mark = generate_restoration_mark()
    assert mark.startswith("i3pm-restore-")
    assert len(mark) == 21
    assert all(c in "0123456789abcdef" for c in mark[-8:])

# TEST: Stage 3 - Wrapper Export
def test_wrapper_env_exports():
    """Verify wrapper adds I3PM_RESTORE_MARK to ENV_EXPORTS."""
    result = subprocess.run(
        ["bash", "-c", "export I3PM_RESTORE_MARK=test123 && source app-launcher-wrapper.sh && echo ${ENV_EXPORTS[@]}"],
        capture_output=True,
        text=True,
    )
    assert "I3PM_RESTORE_MARK" in result.stdout

# TEST: Stage 6 - Daemon Detection
def test_daemon_reads_mark_from_proc():
    """Verify daemon reads mark from /proc/<pid>/environ."""
    # Launch process with mark
    env = os.environ.copy()
    env["I3PM_RESTORE_MARK"] = "i3pm-restore-test456"
    proc = subprocess.Popen(["sleep", "10"], env=env)

    # Read from /proc
    env_dict = read_process_environ(proc.pid)
    assert env_dict["I3PM_RESTORE_MARK"] == "i3pm-restore-test456"

    proc.terminate()
```

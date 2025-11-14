# Environment Variable Contract

**Feature**: 075-layout-restore-production

## I3PM_RESTORE_MARK

**Purpose**: Unique correlation identifier for window matching during layout restoration

**Format**: `i3pm-restore-XXXXXXXX` (8 hex digits)

**Lifecycle**:
1. **Generation**: `restore.py` generates mark for each window placeholder
2. **Set by**: `app_launcher.py` when launching apps during restore
3. **Exported by**: `app-launcher-wrapper.sh` in ENV_EXPORTS array
4. **Passed via**: `swaymsg exec` bash -c environment string
5. **Read by**: `handlers.py` from `/proc/<pid>/environ` on window::new event
6. **Applied as**: Sway window mark via `swaymsg mark`
7. **Matched by**: `correlation.py` to associate window with placeholder

**Required Conditions**:
- MUST be set in AppLauncher environment when launching during restore
- MUST be present in wrapper environment (checked by wrapper script)
- MUST be added to ENV_EXPORTS array (Feature 075 fix)
- MUST be passed to swaymsg exec command
- MUST appear in launched process /proc/<pid>/environ
- MUST be applied to window as Sway mark
- MUST match format `^i3pm-restore-[0-9a-f]{8}$`

**Feature 075 Fix**: Add to ENV_EXPORTS array
```bash
# app-launcher-wrapper.sh lines 414-416
if [[ -n "${I3PM_RESTORE_MARK:-}" ]]; then
    ENV_EXPORTS+=("export I3PM_RESTORE_MARK='$I3PM_RESTORE_MARK'")
fi
```

---

## Standard I3PM Environment Variables

All always present when launching via app-launcher-wrapper.sh:

| Variable | Type | Example | Purpose |
|----------|------|---------|---------|
| I3PM_APP_ID | string | `alacritty-nixos-12345-1699980330` | Unique app instance ID |
| I3PM_APP_NAME | string | `alacritty` | Registry app name |
| I3PM_SCOPE | enum | `scoped` / `global` | Window visibility scope |
| I3PM_ACTIVE | bool | `true` / `false` | Project context active |
| I3PM_LAUNCH_TIME | int | `1699980330` | Unix timestamp |
| I3PM_LAUNCHER_PID | int | `12345` | Wrapper script PID |

Optional (depends on context):

| Variable | Type | Example | Purpose |
|----------|------|---------|---------|
| I3PM_PROJECT_NAME | string | `nixos` | Active project name |
| I3PM_PROJECT_DIR | string | `/etc/nixos` | Project directory path |
| I3PM_TARGET_WORKSPACE | string | `1` | Preferred workspace |
| I3PM_EXPECTED_CLASS | string | `Alacritty` | Expected window class |
| I3PM_RESTORE_MARK | string | `i3pm-restore-abc12345` | Restoration mark (Feature 075) |

---

## Validation

**Pre-Launch** (app_launcher.py):
```python
env = {
    "I3PM_APP_ID": app_id,
    "I3PM_APP_NAME": app_name,
    # ... other vars
}
if restore_mark:
    env["I3PM_RESTORE_MARK"] = restore_mark
```

**Wrapper Export** (app-launcher-wrapper.sh):
```bash
export I3PM_RESTORE_MARK="$I3PM_RESTORE_MARK"
# CRITICAL: Must also add to ENV_EXPORTS array
```

**Post-Launch** (handlers.py):
```python
env_dict = read_process_environ(window.pid)
restore_mark = env_dict.get("I3PM_RESTORE_MARK")
if restore_mark:
    apply_sway_mark(window.id, restore_mark)
```

---

## Error Detection

| Check Point | Validation | Error if Fails |
|-------------|------------|----------------|
| AppLauncher | `restore_mark in env` | Mark not set before launch |
| Wrapper | `test -n "${I3PM_RESTORE_MARK:-}"` | Mark not inherited |
| ENV_EXPORTS | `grep RESTORE_MARK ENV_EXPORTS` | Mark not in export array |
| Process Env | `cat /proc/<pid>/environ \| grep RESTORE_MARK` | Mark not passed to process |
| Sway Mark | `swaymsg -t get_marks \| grep $mark` | Mark not applied to window |
| Correlation | `find_window_by_mark(mark)` | Window not matched |

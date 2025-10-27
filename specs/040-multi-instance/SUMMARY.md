# Multi-Instance App Tracking - Investigation Summary

**Feature**: 040-multi-instance
**Date**: 2025-10-27
**Status**: Investigation Complete - Ready for Implementation

## The Problem

VS Code windows showing "stacks - nixos" in title, indicating both project names. Root cause: **All VS Code windows share one process (PID 503543)**, so they inherit the same I3PM environment from the first launch.

### Observed Behavior

```
# First launch (nixos project):
PID 503543: I3PM_PROJECT_NAME=nixos ✅

# Second launch (stacks project, reuses process):
Window 27262990 reads PID 503543 environment → I3PM_PROJECT_NAME=nixos ❌

# 1 second later: Title changes to "stacks - nixos - Visual Studio Code"
Daemon parses title → Updates mark from nixos to stacks ✅
```

**Current workaround**: Title-based detection auto-corrects after 1 second delay (fragile).

## Investigation Results

Five approaches investigated:

1. **Force Separate Processes** (`--new-instance`)
   - Reliability: ⭐⭐⭐⭐⭐
   - UX Impact: ⭐⭐ (breaks features, memory overhead)
   - **Verdict**: Good as opt-in, not default

2. **X Window Properties**
   - Reliability: ⭐⭐⭐⭐
   - Wayland: ❌
   - **Verdict**: Good for X11, but not future-proof

3. **IPC Launch Context** (RECOMMENDED)
   - Reliability: ⭐⭐⭐⭐
   - Performance: ⭐⭐⭐⭐⭐
   - Wayland: ✅
   - **Verdict**: Best long-term solution

4. **Enhanced Title Parsing**
   - Reliability: ⭐⭐
   - **Verdict**: Keep as fallback only

5. **Desktop Files Per Project**
   - Reliability: ⭐⭐⭐⭐
   - Complexity: ⭐⭐⭐⭐⭐
   - **Verdict**: Too complex for general use

## Recommended Solution: IPC Launch Context

### Architecture

```
┌──────────────────────┐
│ app-launcher-wrapper │  1. Notifies: "Launching vscode for nixos"
└──────────────────────┘
          │
          ▼
   ┌──────────────┐
   │   Daemon     │  2. Stores launch in pending queue
   │              │     [{app: vscode, project: nixos, time: T}]
   └──────────────┘
          ▲
          │
   ┌──────────────┐
   │  VS Code     │  3. Window appears
   │  (window_id  │     Daemon matches: class=Code, time≈T → nixos ✅
   │   27262990)  │
   └──────────────┘
```

### How It Works

1. **Wrapper notifies daemon** before launch:
   ```bash
   i3pm daemon notify-launch vscode nixos /etc/nixos 12345 2
   code --new-window /etc/nixos
   ```

2. **Daemon tracks pending launches** (5-second window):
   ```python
   pending_launches = [
       {app: "vscode", project: "nixos", timestamp: T, workspace: 2}
   ]
   ```

3. **On window creation**, daemon correlates using multiple signals:
   - App class match: `Code` ↔ `vscode` ✅
   - Time delta: 0.5s < 5s ✅
   - Workspace match: workspace 2 = 2 ✅
   - **Confidence: HIGH** → Mark as `project:nixos:27262990` ✅

4. **Fallback chain** if correlation fails:
   - IPC launch context (primary)
   - Title parsing (fallback for manual launches)
   - Active project (last resort)

### Prototype Results

✅ **All tests passed**:
- Sequential launches: 100% accuracy, HIGH confidence
- Rapid launches (0.1s apart): Correctly disambiguated
- Launch timeout (6s): Correctly expired
- Mixed apps: Correctly matched by class

### Benefits Over Current Approach

| Metric | Title Parsing (Current) | IPC Launch Context |
|--------|--------------------------|---------------------|
| Reliability | ⭐⭐ (fragile) | ⭐⭐⭐⭐ (robust) |
| Latency | ~1 second delay | <100ms |
| App Support | VS Code only | All apps |
| Wayland | ✅ | ✅ |
| Maintenance | High (app-specific) | Low (generic) |

## Implementation Plan

### Phase 1: Add IPC Method (1 hour)

1. Add `LaunchContextTracker` to daemon:
   ```python
   # daemon.py
   self.launch_tracker = LaunchContextTracker(timeout=5.0)
   ```

2. Add IPC method:
   ```python
   # ipc_server.py
   async def notify_launch(self, app_name, project_name, project_dir, launcher_pid, workspace):
       await self.daemon.launch_tracker.notify_launch(...)
       return {"status": "ok"}
   ```

3. Add CLI command:
   ```python
   # cli.py
   @cli.command()
   def notify_launch(app, project, directory, pid, workspace):
       client.notify_launch(app, project, directory, pid, workspace)
   ```

### Phase 2: Update Wrapper (30 minutes)

```bash
# app-launcher-wrapper.sh (after line 220, before systemd-run)

# Notify daemon of imminent launch
i3pm daemon notify-launch "$APP_NAME" "$PROJECT_NAME" "$PROJECT_DIR" $$ "$PREFERRED_WORKSPACE" 2>/dev/null || true

# Launch app
systemd-run --user --scope --setenv=I3PM_APP_NAME="$APP_NAME" ... "$COMMAND" $PARAM_RESOLVED
```

### Phase 3: Update Handler (1 hour)

```python
# handlers.py - on_window_new()

async def on_window_new(event):
    window_id = event.container.id
    window_class = event.container.window_properties.class

    # Try IPC launch context first
    project, confidence = await daemon.launch_tracker.match_window(
        WindowInfo(window_id, window_class, pid, workspace, timestamp)
    )

    if confidence.value >= MatchConfidence.MEDIUM.value:
        # High confidence match from IPC
        logger.info(f"Window {window_id} matched to {project} via IPC (confidence: {confidence.name})")
        await mark_window(window_id, project)
        return

    # Fallback 1: Title parsing (for VS Code, etc.)
    if window_class == "Code":
        project = await extract_project_from_title(window_title)
        if project:
            logger.info(f"Window {window_id} matched to {project} via title parsing")
            await mark_window(window_id, project)
            return

    # Fallback 2: Active project
    project = daemon.get_active_project()
    logger.info(f"Window {window_id} assigned to active project {project}")
    await mark_window(window_id, project)
```

### Phase 4: Testing (1 hour)

Test scenarios:
1. Sequential VS Code launches → Both correct
2. Rapid launches (< 0.2s apart) → Disambiguated correctly
3. Manual launch (`code /etc/nixos` from terminal) → Falls back to title parsing
4. Launch timeout (app takes 6s to open) → Falls back gracefully
5. Mixed apps (VS Code + Alacritty simultaneously) → Both correct

**Total estimated time**: 3.5 hours

## Alternative: Separate Processes (Opt-In)

For users who prefer isolation over features, add configuration option:

```nix
# app-registry-data.nix
(mkApp {
  name = "vscode";
  command = "code";
  parameters = "--new-window $PROJECT_DIR";
  force_separate_process = false;  # Set to true to enable
  # ...
})
```

**app-launcher-wrapper.sh**:
```bash
if [[ "$FORCE_SEPARATE_PROCESS" == "true" ]]; then
    COMMAND="$COMMAND --new-instance"  # For VS Code
    # Add similar flags for other apps that support it
fi
```

## Open Questions

1. **PID correlation**: Should we track PID trees for better matching?
   - Answer: Yes, implement in Phase 5 as enhancement

2. **Launch timeout**: Is 5 seconds sufficient?
   - Answer: Yes for fast apps, but make configurable

3. **Rapid launch ambiguity**: How to handle 2 identical apps launched <0.1s apart?
   - Answer: First match wins (FIFO), or use workspace as tie-breaker

4. **Manual launches**: User runs `code /etc/nixos` directly (not via wrapper)
   - Answer: Title parsing fallback handles this

5. **Backward compatibility**: Does this break existing workflows?
   - Answer: No, falls back gracefully; fully backward compatible

## Conclusion

**IPC Launch Context** is the recommended solution:
- ✅ Solves multi-instance problem reliably
- ✅ Works for all apps, not just VS Code
- ✅ Wayland compatible
- ✅ Minimal latency (<100ms)
- ✅ Backward compatible (fallback chain)
- ✅ Prototype validated (all tests pass)

**Next action**: Implement Phase 1-4 (estimated 3.5 hours)

## Files

- `investigation.md` - Detailed analysis of all approaches
- `prototype-ipc-launch-context.py` - Working prototype with tests
- `SUMMARY.md` - This document

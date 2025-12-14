# Research: Improve Notification Progress Indicators

**Feature**: 117-improve-notification-progress-indicators
**Date**: 2025-12-14
**Status**: Complete

## R1: Badge Storage Mechanism - File-Only vs File+IPC

### Decision: File-based only

### Rationale

The current implementation writes badges to both files AND sends IPC messages:

```bash
# Current dual-write in prompt-submit-notification.sh
cat > "$BADGE_FILE" <<EOF
{"window_id": $WINDOW_ID, "state": "working", ...}
EOF
/etc/nixos/scripts/claude-hooks/badge-ipc-client.sh create "$WINDOW_ID" "claude-code" --state working
```

Analysis of existing code shows:
- `monitoring_data.py` reads badge state from filesystem (lines 1451-1456)
- IPC is "for fast update, but file is source of truth" per code comments
- EWW uses inotify to watch badge directory (already <15ms latency)
- IPC adds complexity without measurable benefit

### Alternatives Considered

| Approach | Latency | Complexity | Reliability |
|----------|---------|------------|-------------|
| File-only | <15ms (inotify) | Low | High (survives daemon restart) |
| IPC-only | <5ms | Medium | Low (requires daemon) |
| File+IPC (current) | <15ms | High | Medium (dual code paths) |

**Conclusion**: File-only provides sufficient latency (<600ms requirement) with simpler implementation.

### What Gets Removed

- `scripts/claude-hooks/badge-ipc-client.sh` - entire script
- IPC calls in `prompt-submit-notification.sh` (lines 79-84)
- IPC calls in `stop-notification.sh` (lines 93-98)
- Badge IPC handlers in daemon's `ipc_server.py`

---

## R2: Window ID Detection - Single Reliable Method

### Decision: tmux PID → process tree → Sway query only

### Rationale

Current implementation has fallback chain:

```bash
# Method 1: If in tmux, trace from tmux client to find the ghostty window
if [ -n "${TMUX:-}" ]; then
    # ... process tree tracing ...
fi

# Method 2: Fallback to focused window (original behavior)
window_id=$(swaymsg -t get_tree | jq -r '... select(.focused==true) ...')
```

The fallback is dangerous because:
1. Hook fires when Claude Code completes - user may have switched windows
2. "Focused window" at hook time ≠ terminal running Claude Code
3. Fallback masks bugs in primary detection, creating silent failures

### Alternatives Considered

| Approach | Reliability | Failure Mode |
|----------|-------------|--------------|
| tmux PID only | High | Fails if not in tmux |
| Focused window only | Low | Wrong window if user switched |
| Fallback chain (current) | Medium | Silent wrong window |

**Conclusion**: tmux PID method is the correct approach. Remove fallback - if detection fails, fail explicitly (no badge created, user notices).

### What Gets Removed

```bash
# Remove this fallback block from both hook scripts:
# Method 2: Fallback to focused window (original behavior)
window_id=$(swaymsg -t get_tree | jq -r '... select(.focused==true) ...')
```

### Edge Case: Non-tmux Usage

If Claude Code is run outside tmux:
- Primary detection will fail (no `$TMUX` environment variable)
- No badge will be created
- User still gets desktop notification (notify-send)
- Acceptable degradation - tmux is the expected environment

---

## R3: Focus-Aware Badge Dismissal

### Decision: Daemon handles window focus events, clears badge files

### Rationale

Current flow requires user to click notification action:
1. Claude completes → badge shows "stopped"
2. User clicks "Return to Window" → callback clears badge
3. If user manually focuses window (without clicking notification) → badge persists indefinitely

Users expect badge to clear when they return attention to the window.

### Implementation Approach

The daemon already subscribes to Sway IPC events including window focus:

```python
# In handlers.py - add to existing focus handler
async def on_window_focus(self, event):
    window_id = event.container.id

    # Check if window has badge
    badge_file = f"{BADGE_DIR}/{window_id}.json"
    if not os.path.exists(badge_file):
        return

    # Check badge age (prevent immediate dismiss on creation)
    badge_data = json.load(open(badge_file))
    age = time.time() - badge_data.get("timestamp", 0)

    if age > 1.0:  # Minimum 1 second age
        os.remove(badge_file)
```

### Timing Considerations

- **Minimum age**: 1 second prevents race condition where badge is created while window is focused
- **Focus detection latency**: ~50ms (Sway IPC event subscription)
- **Total dismissal time**: <500ms (within spec requirement)

---

## R4: Notification Content Simplification

### Decision: Title + project name only

### Rationale

Current notification is verbose:

```
Title: "Claude Code Ready"
Body: "Task complete - awaiting your input

📁 feature-123

Source: main:0"
```

Problems:
- "Task complete - awaiting your input" is redundant with title
- "Source: main:0" (tmux session:window) is technical detail users don't need
- Multi-line body is harder to scan quickly

### New Format

```
Title: "Claude Code Ready"
Body: "📁 feature-123"
Action: "Return to Window"
```

If no project:
```
Title: "Claude Code Ready"
Body: "Awaiting input"
Action: "Return to Window"
```

### Implementation

```bash
# Simplified message building
if [ -n "$PROJECT_NAME" ]; then
    MESSAGE="📁 ${PROJECT_NAME}"
else
    MESSAGE="Awaiting input"
fi

notify-send \
    -i "robot" \
    -u normal \
    -w \
    -A "focus=Return to Window" \
    "Claude Code Ready" \
    "$MESSAGE"
```

---

## R5: Stale Badge Cleanup Strategy

### Decision: Window existence validation + TTL backup

### Rationale

Current system has no automatic cleanup. Badges persist if:
- Terminal window closes while Claude is working
- System crash/restart leaves orphan badge files
- Bug in hook script prevents proper cleanup

### Implementation

**Primary: Window existence validation** in `monitoring_data.py`:

```python
def cleanup_orphaned_badges(valid_window_ids: set[int]) -> int:
    """Remove badges for windows that no longer exist."""
    badge_dir = os.path.join(XDG_RUNTIME_DIR, "i3pm-badges")
    removed = 0

    for filename in os.listdir(badge_dir):
        if not filename.endswith(".json"):
            continue

        window_id = int(filename.replace(".json", ""))
        if window_id not in valid_window_ids:
            os.remove(os.path.join(badge_dir, filename))
            removed += 1

    return removed
```

Called during each monitoring refresh (~500ms interval).

**Backup: TTL-based cleanup** for edge cases:

```python
MAX_BADGE_AGE = 300  # 5 minutes

def cleanup_stale_badges() -> int:
    """Remove badges older than TTL."""
    now = time.time()
    removed = 0

    for filename in os.listdir(badge_dir):
        badge_data = json.load(open(os.path.join(badge_dir, filename)))
        age = now - badge_data.get("timestamp", 0)

        if age > MAX_BADGE_AGE:
            os.remove(os.path.join(badge_dir, filename))
            removed += 1

    return removed
```

### Cleanup Timing

| Mechanism | Trigger | Latency |
|-----------|---------|---------|
| Window close | Next monitoring refresh | <500ms |
| Orphan detection | Each refresh cycle | <500ms |
| TTL backup | Each refresh cycle | Up to 5 minutes |

Meets spec requirement: "Orphaned badges removed within 30 seconds"

---

## Summary of Decisions

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Badge storage | File-only | Simpler, sufficient latency, survives daemon restart |
| Window detection | tmux PID method only | Reliable, remove silent-failure fallback |
| Focus dismissal | Daemon event handler | Natural UX, 1s minimum age |
| Notification content | Title + project | Concise, scannable |
| Stale cleanup | Existence check + TTL | Robust multi-layer approach |

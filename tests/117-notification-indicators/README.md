# Test Suite: Feature 117 - Improve Notification Progress Indicators

**Feature**: 117-improve-notification-progress-indicators

## Overview

This directory contains tests for the Claude Code notification system improvements.

## Automated Tests

### Run All Tests

```bash
# Python unit tests (badge service)
python3 tests/117-notification-indicators/test_badge_service.py

# Shell script tests (hooks)
bash tests/117-notification-indicators/test_hooks.sh
```

### Test Files

| File | Description |
|------|-------------|
| `test_badge_service.py` | Python unit tests for badge Pydantic models and file utilities |
| `test_hooks.sh` | Shell tests for hook scripts and Feature 117 requirements |

### Test Coverage

- Badge model creation and validation
- Badge state management (working/stopped transitions)
- Badge file read/write operations
- Eww format conversion
- Shell script syntax validation
- Feature 117 requirements (no IPC, no fallback, badge-ipc-client.sh removed)

## Manual Testing

See `specs/117-improve-notification-progress-indicators/quickstart.md` for manual test procedures.

### Quick Verification (requires Sway session)

```bash
# Test badge creation
BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3pm-badges"
WINDOW_ID=$(swaymsg -t get_tree | jq -r '.. | objects | select(.focused==true) | .id')
cat > "$BADGE_DIR/$WINDOW_ID.json" <<EOF
{"window_id": $WINDOW_ID, "state": "working", "source": "test", "timestamp": $(date +%s)}
EOF

# Verify spinner appears in monitoring panel
# After 1 second, focus another window then focus back
# Badge should be dismissed

# Test cleanup
rm -f "$BADGE_DIR/$WINDOW_ID.json"
```

### Success Criteria Verification

| Criterion | How to Verify |
|-----------|---------------|
| SC-001: 600ms latency | Time from prompt submit to spinner visible |
| SC-002: 500ms focus dismiss | Time from focus to badge removal |
| SC-003: 30s orphan cleanup | Close window, check badge removed |
| SC-004: 95% action success | Click notification, verify window focus |
| SC-005: Project in notification | Check notification body content |
| SC-006: No stale after 5 min | Run multiple sessions, check panel |

## Future Automated Tests

Future sway-test framework tests will be added here:
- `test_badge_lifecycle.json` - Badge create/update/cleanup
- `test_focus_dismissal.json` - Focus-aware dismissal timing

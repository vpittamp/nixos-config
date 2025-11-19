# Contract: Daemon to Eww Communication

**Feature**: 083-multi-monitor-window-management
**Date**: 2025-11-19

## Overview

The i3-project-event-daemon pushes monitor state updates to Eww widgets via the `eww update` CLI command.

## Variables

### `monitor_state`

**Type**: JSON object
**Update Frequency**: On profile switch, output change events

```json
{
  "profile_name": "dual",
  "outputs": [
    {
      "name": "HEADLESS-1",
      "short_name": "H1",
      "active": true,
      "workspace_count": 25
    },
    {
      "name": "HEADLESS-2",
      "short_name": "H2",
      "active": true,
      "workspace_count": 20
    },
    {
      "name": "HEADLESS-3",
      "short_name": "H3",
      "active": false,
      "workspace_count": 0
    }
  ]
}
```

**Eww Widget Declaration**:
```lisp
(defvar monitor_state '{"profile_name": "", "outputs": []}')
```

**Update Command**:
```bash
eww update "monitor_state={\"profile_name\":\"dual\",\"outputs\":[...]}"
```

## Latency Requirements

| Metric | Target | Notes |
|--------|--------|-------|
| Update after profile switch | <100ms | From switch completion |
| Update after output event | <100ms | From Sway event received |
| Eww CLI roundtrip | <20ms | Subprocess execution |

## Error Handling

**Daemon Side**:
- Catch subprocess timeouts (2s max)
- Log failures but don't block daemon operation
- Retry once on transient failures

**Widget Side**:
- Default to empty state if variable not set
- Graceful degradation if JSON parse fails

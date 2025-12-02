# Contract: Eww Spinner Variable

**Feature**: 107-fix-progress-indicator | **Version**: 1.0.0

## Overview

Defines the separate Eww variable for spinner animation, decoupled from the main monitoring data stream.

## Variable Definition

```lisp
;; Spinner frame character for "working" badge animation
;; Updated independently from monitoring_data via lightweight poll
(defvar spinner_frame "⠋")
```

## Spinner Frames

Braille dot spinner with 10 frames, cycling at 120ms intervals:

| Index | Frame | Unicode |
|-------|-------|---------|
| 0 | ⠋ | U+280B |
| 1 | ⠙ | U+2819 |
| 2 | ⠹ | U+2839 |
| 3 | ⠸ | U+2838 |
| 4 | ⠼ | U+283C |
| 5 | ⠴ | U+2834 |
| 6 | ⠦ | U+2826 |
| 7 | ⠧ | U+2827 |
| 8 | ⠇ | U+2807 |
| 9 | ⠏ | U+280F |

## Animation Driver

Spinner updates only when at least one "working" badge exists:

```lisp
;; Conditional poll - only runs when working badge detected
(defpoll _spinner_driver
  :interval "120ms"
  :run-while {monitoring_data.has_working_badge ?: false}
  `${spinner-update-script}`)
```

### Spinner Update Script

```bash
#!/usr/bin/env bash
# spinner-update.sh - Updates spinner_frame variable

FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# Calculate frame index based on current time (120ms per frame)
MS=$(date +%s%3N)
IDX=$(( (MS / 120) % 10 ))

echo "${FRAMES[$IDX]}"
```

## Widget Usage

Badge widget reads spinner from variable (not from monitoring_data):

```lisp
;; Before (Feature 095):
:text {(window.badge?.state ?: "stopped") == "working"
  ? (monitoring_data.spinner_frame ?: "⠋")
  : "󰂚 " + (window.badge?.count ?: "")}

;; After (Feature 107):
:text {(window.badge?.state ?: "stopped") == "working"
  ? spinner_frame
  : "󰂚 " + (window.badge?.count ?: "")}
```

## Performance Comparison

| Metric | Before (Feature 095) | After (Feature 107) |
|--------|---------------------|---------------------|
| Update frequency during animation | 50ms (full data) | 120ms (spinner only) |
| Data per update | ~10KB JSON | ~4 bytes (1 char) |
| Daemon IPC calls | 20/sec | 0/sec |
| Eww subprocess spawns | 20/sec | 8/sec |
| CPU overhead | 5-10% | <1% |

## Monitoring Data Flag

The `has_working_badge` flag in monitoring_data controls animation driver:

```python
# In monitoring_data.py:query_monitoring_data()
return {
    "status": "ok",
    "projects": projects,
    # ...
    "has_working_badge": any(
        badge.get("state") == "working"
        for badge in badge_state.values()
    ),
}
```

## Lifecycle

```
1. No working badges
   └─► spinner_frame = "⠋" (static, no updates)
   └─► _spinner_driver not running (run-while = false)

2. UserPromptSubmit hook fires
   └─► Badge created with state="working"
   └─► monitoring_data.has_working_badge = true
   └─► _spinner_driver starts polling
   └─► spinner_frame updates every 120ms

3. Stop hook fires
   └─► Badge state changes to "stopped"
   └─► monitoring_data.has_working_badge = false (if no other working badges)
   └─► _spinner_driver stops polling
   └─► spinner_frame frozen at last value (doesn't matter, badge shows bell now)
```

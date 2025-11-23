# Scratchpad Terminal Mark Duplication Analysis

## Problem Statement

Scratchpad terminals are getting duplicate marks:
- **When visible**: `["scratchpad:PROJECT_NAME"]` (correct)
- **When hidden**: `["scratchpad:PROJECT_NAME", "scoped:PROJECT:WINDOW_ID"]` (incorrect - dual marks)

This dual-mark situation suggests the scratchpad is being treated as both:
1. A scratchpad terminal (via `scratchpad:PROJECT_NAME` mark)
2. A regular scoped window (via `scoped:PROJECT:WINDOW_ID` mark)

## Root Cause Analysis

### The Design Intent

Scratchpad terminals should:
1. **ONLY** have the `scratchpad:PROJECT_NAME` mark
2. Be identified as scoped windows by the `scratchpad:` prefix in their mark
3. Hide/show via the scratchpad manager, NOT via the window filtering logic
4. Remain project-scoped (only visible in their associated project)

### What's Happening

Looking at the code flow:

#### 1. Window Creation (`handlers.py:on_window_new`, lines 991-996)
```python
if is_scratchpad_terminal:
    logger.info(f"Skipping project mark for scratchpad terminal {window_id} (will be marked by scratchpad manager)")
    marks_list = []
    mark = None  # No mark applied yet
else:
    # Apply scoped:PROJECT:WINDOW_ID mark
```

**This is correct** - scratchpad terminals skip the normal marking logic.

#### 2. Scratchpad Manager Marking (`scratchpad_manager.py`, line 255)
```python
await self.sway.command(f'[con_id={window_id}] mark {mark}')
```

**This is correct** - only applies `scratchpad:PROJECT_NAME` mark.

#### 3. Window Filtering Logic (`window_filter.py`, lines 366-378)
```python
for mark in window.marks:
    if mark.startswith("scratchpad:"):
        # Feature 062: Scratchpad terminals are project-scoped
        mark_parts = mark.split(":")
        window_project = mark_parts[1] if len(mark_parts) >= 2 else None
        window_scope = "scoped"  # <-- Sets scope but doesn't add mark
        logger.debug(f"Window {window_id} is scratchpad terminal for project: {window_project}")
        break
    elif mark.startswith("scoped:") or mark.startswith("global:"):
        # Format: SCOPE:PROJECT:WINDOW_ID
        mark_parts = mark.split(":")
        window_scope = mark_parts[0]
        window_project = mark_parts[1] if len(mark_parts) >= 2 else None
        break
```

**This looks correct** - it extracts project from the scratchpad mark and sets scope, but doesn't add a new mark.

### The Mystery: Where is `scoped:PROJECT:WINDOW_ID` Mark Coming From?

The mark is NOT being added by:
- ❌ `on_window_new` (skipped for scratchpad terminals)
- ❌ `window_filter.py:filter_windows_by_project` (only moves to scratchpad, doesn't add marks)
- ❌ `scratchpad_manager.py` (only adds `scratchpad:PROJECT_NAME` mark)
- ❌ `on_window_move` handler (no marking logic)

### Hypothesis: Window Rules or State Manager

The mark must be coming from one of these sources:

1. **Window rules** in `~/.config/sway/window-rules.json` that match scratchpad terminals
2. **State manager** adding marks during some state update
3. **Mark manager** (Feature 076) injecting marks based on environment variables

Let me check for window rules that might affect scratchpad terminals.

## Expected Fix

The fix should ensure that:

1. Scratchpad terminals **NEVER** receive the `scoped:PROJECT:WINDOW_ID` mark
2. Only the `scratchpad:PROJECT_NAME` mark is applied (by scratchpad manager)
3. Window filtering logic correctly identifies scratchpad windows and excludes them from normal scoped window handling
4. The scope derived in `monitoring_data.py` (line 489) correctly identifies scratchpads as "scoped" based on the `scratchpad:` prefix

## Recommended Solution

### Option 1: Explicitly Check for Scratchpad Mark Before Adding Scoped Mark

Wherever `scoped:PROJECT:WINDOW_ID` marks are being added, add a check:

```python
# Before adding scoped mark, check if window is a scratchpad terminal
has_scratchpad_mark = any(mark.startswith("scratchpad:") for mark in window.marks)
if has_scratchpad_mark:
    logger.debug(f"Skipping scoped mark for scratchpad terminal {window_id}")
    return
```

### Option 2: Fix Window Filtering to Skip Scratchpad Terminals

In `window_filter.py:filter_windows_by_project`, after classifying a window as needing to be hidden:

```python
# Check if this is a scratchpad terminal (managed by scratchpad manager, not window filtering)
has_scratchpad_mark = any(mark.startswith("scratchpad:") for mark in window.marks)
if has_scratchpad_mark:
    logger.debug(f"Skipping window filtering for scratchpad terminal {window_id} (managed by scratchpad manager)")
    continue  # Skip this window entirely
```

### Option 3: Fix Scope Derivation in Monitoring Data

The scope field should be derived from **either** `scratchpad:` OR `scoped:` marks:

```python
# monitoring_data.py, line 487-489
marks = window.get("marks", [])
# Check for both scratchpad and scoped marks
is_scoped = any(str(m).startswith("scoped:") or str(m).startswith("scratchpad:") for m in marks)
scope = "scoped" if is_scoped else "global"
```

**This ensures that scratchpad terminals are correctly identified as "scoped" regardless of the dual mark issue.**

## Action Items

1. Find where `scoped:PROJECT:WINDOW_ID` marks are being added
2. Add explicit check to skip scratchpad terminals in that location
3. Verify that window filtering logic does NOT process scratchpad terminals
4. Update scope derivation to handle `scratchpad:` prefix consistently
5. Add tests to ensure scratchpad terminals never get dual marks

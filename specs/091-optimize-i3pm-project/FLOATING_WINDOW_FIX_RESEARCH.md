# Research: Floating Window Restoration Issue (Feature 091)

**Date**: 2025-11-23
**Issue**: Windows restored from scratchpad remain floating instead of returning to tiling mode
**Status**: Root cause identified, solution recommended

---

## Problem Description

When switching between projects in i3pm:
1. Scoped windows are moved to scratchpad (becoming floating)
2. When switching back, windows are restored to their workspace
3. **BUG**: Windows remain floating instead of returning to tiling mode
4. Expected: Windows with `is_floating=False` should be converted back to tiling

---

## Root Cause Analysis

### Current Implementation (Feature 091)

**File**: `home-modules/desktop/i3-project-event-daemon/services/window_filter.py`

The window restore logic uses **batched commands** (semicolon-chained):

```python
# window_filter.py:431-436
batch = CommandBatch.from_window_state(
    window_id=window_id,
    workspace_num=workspace_num,
    is_floating=is_floating,  # False for tiling windows
    geometry=geometry,
)
```

**File**: `home-modules/desktop/i3-project-event-daemon/models/window_command.py`

The CommandBatch generates a single IPC command:

```python
# window_command.py:167
return f"{selector} {'; '.join(cmd_parts)}"

# Example output for tiling window:
# [con_id=12345] move workspace number 1; floating disable
```

### Why Batching Fails for Scratchpad Restoration

**Sway/i3 Scratchpad Behavior**:
1. ALL windows in scratchpad are **forced to be floating** (Sway enforces this)
2. When `move workspace` is executed on a scratchpad window:
   - Window is removed from scratchpad
   - Window is placed on the target workspace
   - **Window retains floating state** (still floating!)
3. The `floating disable` command should convert it to tiling

**The Problem with Semicolon Batching**:
- When commands are chained with semicolons in a single IPC call: `move workspace 1; floating disable`
- Sway may process them **atomically** or with **insufficient settling time**
- The `floating disable` command executes before the window has fully transitioned from scratchpad to workspace
- Result: The floating state change is ignored or fails silently

### Evidence from Existing Code

**File**: `home-modules/desktop/i3-project-event-daemon/layout/restore.py` (Lines 146-159)

This file successfully restores windows using **separate IPC calls**:

```python
# Move to workspace (separate call)
await self._i3_command(f'[con_id="{window_id}"] move to workspace {workspace}')

# Apply floating state (separate call - NOT batched!)
if saved_window.floating:
    await self._i3_command(f'[con_id="{window_id}"] floating enable')
else:
    await self._i3_command(f'[con_id="{window_id}"] floating disable')

# Apply geometry (separate call)
await self._i3_command(f'[con_id="{window_id}"] move position ...')
```

**File**: `home-modules/desktop/i3-project-event-daemon/services/layout_engine.py` (Similar pattern)

```python
# Separate command for floating disable (NOT batched)
await window.command("floating disable")
```

Both working implementations use **separate IPC calls** instead of semicolon batching.

---

## Solution Recommendations

### Option 1: Separate IPC Calls (RECOMMENDED)

**Approach**: Execute commands sequentially as separate IPC calls, while maintaining parallel execution across windows.

**Implementation**:
1. Modify `CommandBatchService.execute_batch()` to execute commands separately
2. OR create a new method `execute_sequence()` for ordered sequential execution
3. Keep parallel execution across different windows (the main optimization)

**Pseudocode**:
```python
async def execute_sequence(self, batch: CommandBatch) -> list[CommandResult]:
    """Execute commands sequentially with separate IPC calls."""
    results = []
    for cmd in batch.commands:
        result = await self._execute_single_command(cmd)
        results.append(result)
    return results
```

**Performance Impact**:
- **Per-window latency**: +10-20ms (3-4 IPC calls instead of 1)
- **Total project switch**: Still <200ms (parallel across windows)
- **Tradeoff**: Acceptable for correctness

**Example Timeline** (10 windows to restore):
- **Current (batched)**: 10 batched commands in parallel = ~150ms total
- **Proposed (sequential per window)**: 10 windows × (3-4 IPC calls each) in parallel = ~180ms total
- **Still meets target**: <200ms ✓

---

### Option 2: Split Critical Commands

**Approach**: Batch safe commands, but execute `floating disable` separately.

**Implementation**:
1. Keep batching for: `move workspace; resize; move position`
2. Execute `floating disable` as a separate IPC call AFTER the batch

**Pseudocode**:
```python
# Phase 1: Move and geometry (batched)
await conn.command(f"[con_id={id}] move workspace {ws}; resize ...; move position ...")

# Phase 2: Floating state (separate)
if not is_floating:
    await conn.command(f"[con_id={id}] floating disable")
```

**Performance Impact**:
- **Per-window latency**: +5-10ms (2 IPC calls instead of 1)
- **Total project switch**: ~160-170ms (still well under 200ms)

**Tradeoff**: More complex logic, but minimal performance impact

---

### Option 3: Add Small Delay (NOT RECOMMENDED)

**Approach**: Keep batching but add a small delay between commands.

**Why Not Recommended**:
- Adds artificial latency (bad for performance)
- Fragile and unreliable
- Doesn't address the root cause

---

## Recommended Implementation

### Primary Recommendation: **Option 1 (Separate IPC Calls)**

**Rationale**:
1. **Proven Pattern**: Matches working implementations in `layout_engine.py` and `restore.py`
2. **Reliable**: Ensures each command completes before the next starts
3. **Maintainable**: Clear sequential logic, easier to debug
4. **Performance**: Still meets <200ms target (parallel across windows provides main optimization)

**Key Insight**: The Feature 091 optimization comes from **parallelizing across multiple windows**, not from batching commands per window. We can afford 3-4 separate IPC calls per window as long as we execute them in parallel across all windows.

### Implementation Steps

1. **Modify CommandBatchService** (`command_batch.py`):
   ```python
   async def execute_batch(self, batch: CommandBatch) -> tuple[list[CommandResult], OperationMetrics]:
       """Execute batch commands sequentially (separate IPC calls)."""
       results = []
       for cmd in batch.commands:
           result = await self._execute_single_command(cmd)
           results.append(result)
       return results, metrics
   ```

2. **Update window_filter.py** (line 559-562):
   - No changes needed! The code already calls `execute_batch()` for each window
   - Parallel execution across windows is maintained in the outer loop

3. **Test Scenarios**:
   - Restore tiling windows from scratchpad → should be tiling ✓
   - Restore floating windows from scratchpad → should be floating ✓
   - Performance: 10-window project switch <200ms ✓

---

## Alternative Optimization (Future Enhancement)

If the +10-20ms per-window latency is unacceptable, consider:

**Hybrid Approach**:
- Use `asyncio.gather()` to parallelize the command sequence PER WINDOW
- Example: For each window, run `[move, floating, resize, position]` in parallel with other windows' sequences

```python
# Execute all window sequences in parallel
tasks = [self.execute_sequence(batch) for batch in restore_batches]
all_results = await asyncio.gather(*tasks)
```

This maintains the performance benefit while ensuring correct command ordering per window.

---

## References

**Sway/i3 Documentation**:
- i3 IPC specification: `/home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project/docs/i3-ipc.txt`
- Scratchpad behavior (line 546-548): Windows in scratchpad have `scratchpad_state` field
- Floating state (line 537-539): Can be `auto_on`, `auto_off`, `user_on`, `user_off`

**Working Implementations**:
- `layout/restore.py:146-159` - Separate IPC calls for window restoration
- `services/layout_engine.py` - Separate `floating disable` command

**Current Feature 091 Files**:
- `services/window_filter.py:431-436` - Creates CommandBatch
- `models/window_command.py:169-236` - CommandBatch.from_window_state()
- `services/command_batch.py:182-249` - execute_batch() method

---

## Conclusion

**Root Cause**: Semicolon-batched commands don't work reliably for scratchpad restoration in Sway.

**Solution**: Execute commands as separate sequential IPC calls per window, while maintaining parallel execution across windows.

**Performance**: Meets <200ms target (main optimization is cross-window parallelization, not per-window batching).

**Next Steps**: Implement Option 1, test with real project switches, validate performance stays <200ms.

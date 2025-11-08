# Next Steps: Live TUI Inspect Integration

**Branch**: `065-i3pm-tree-monitor`
**Date**: 2025-11-08
**Task**: T037 - Integrate event inspection into live streaming TUI

## Summary

The `i3pm tree-monitor live` command currently shows "Enter=inspect" in the help legend, but pressing Enter displays a placeholder error message instead of showing the event detail view. This task completes the integration of the existing detail view component into the live TUI.

## Current State

✅ **Complete**:
- Detail view component (`tree-monitor-detail.ts`) - fully implemented
- Inspect command from CLI (`i3pm tree-monitor inspect <id>`) - works perfectly
- Live TUI navigation and event display - fully functional

❌ **Incomplete**:
- Pressing Enter in live TUI shows placeholder: "Event inspection not yet implemented (Phase 5)"

## Files Updated

1. **`/etc/nixos/specs/065-i3pm-tree-monitor/live-inspect-integration.md`** (NEW)
   - Detailed implementation plan with code examples
   - Two implementation options (inline vs. refactored)
   - Acceptance criteria and testing strategy
   - **Recommendation**: Use Option 1 (inline detail view)

2. **`/etc/nixos/specs/065-i3pm-tree-monitor/tasks.md`** (UPDATED)
   - Marked T037 as incomplete: `[ ] T037 [US3]`
   - Updated Phase 5 status: `⏳ IN PROGRESS | 9/10 tasks`
   - Updated progress: `56/60 tasks (93%)`
   - Added detailed implementation steps to T037

## Implementation Guide

### Quick Implementation (30 minutes)

**File**: `/etc/nixos/home-modules/tools/i3pm/src/ui/tree-monitor-live.ts`
**Lines to modify**: 263-271 (current placeholder)

**What to do**:
1. Read the detailed plan: `/etc/nixos/specs/065-i3pm-tree-monitor/live-inspect-integration.md`
2. Follow Option 1 (inline detail view approach)
3. Replace the placeholder with integration code
4. Test with `i3pm tree-monitor live`, select an event, press Enter

### Key Code Change

**Current (lines 263-271)**:
```typescript
// Enter - inspect (TODO: implement in Phase 5)
if (key[0] === 13) {
  // Placeholder: will implement event inspection in Phase 5
  state.error = "Event inspection not yet implemented (Phase 5)";
  render(state);
  await new Promise((resolve) => setTimeout(resolve, 2000));
  state.error = undefined;
  render(state);
}
```

**Should become**:
```typescript
// Enter - inspect
if (key[0] === 13) {
  if (state.selectedIndex >= 0 && state.selectedIndex < state.events.length) {
    const event = state.events[state.selectedIndex];

    // Show detail view (blocking)
    clearScreen();
    await showEventDetail(client, event.id);

    // Resume live view
    render(state);
  }
}
```

See `live-inspect-integration.md` for the full `showEventDetail()` function implementation.

## Testing

**Manual Test**:
```bash
# Launch live view
i3pm tree-monitor live

# Use arrow keys to select an event
# Press Enter → Should show detailed event information
# Press 'b' → Should return to live view
# Press Enter again
# Press 'q' → Should exit application
```

**Success Criteria**:
- ✅ Enter shows detailed event metadata, correlation, diff, enrichment
- ✅ 'b' key returns to live view with same scroll position
- ✅ 'q' key exits from detail view
- ✅ Empty events list handled gracefully
- ✅ RPC errors show message and return to live view

## After Implementation

1. **Test manually** with the steps above
2. **Mark T037 complete** in `tasks.md`:
   - Change `[ ]` to `[X]`
   - Update Phase 5: `✅ COMPLETE | 10/10 tasks`
   - Update progress: `57/60 tasks (95%)`
3. **Commit**:
   ```bash
   git add home-modules/tools/i3pm/src/ui/tree-monitor-live.ts
   git add specs/065-i3pm-tree-monitor/tasks.md
   git commit -m "feat(065): Integrate event inspection into live TUI

   - Replace placeholder Enter key handler with detail view integration
   - Fetch selected event ID from state.events[state.selectedIndex]
   - Show detail view in blocking mode, restore live view on exit
   - Add error handling for RPC failures and invalid selections
   - Complete User Story 3 (Event Inspection) Phase 5

   Resolves T037"
   ```

## Related Documents

- **Implementation Plan**: `live-inspect-integration.md` (detailed code examples)
- **Original Spec**: `spec.md` User Story 3 (Event Inspection)
- **Task List**: `tasks.md` T037
- **Data Model**: `data-model.md` Event interface
- **Python Reference**: `home-modules/tools/sway-tree-monitor/ui/live_view.py:158-167`

## Python TUI Reference

The Python version shows how to navigate from live view to detail view using Textual's screen navigation:

```python
def action_drill_down(self) -> None:
    """Drill down into selected event - opens detailed diff view"""
    table = self.query_one(DataTable)
    if table.cursor_row is not None:
        row_key = table.get_row_at(table.cursor_row)[0]
        event_id = int(row_key)

        from .diff_view import DiffView
        self.app.push_screen(DiffView(self.rpc_client, event_id))
```

The TypeScript version should mirror this by swapping screens (clear → detail → restore).

## Questions?

If you have questions about the implementation approach:
1. Check `live-inspect-integration.md` for detailed code examples
2. Review the Python reference implementation in `sway-tree-monitor/ui/live_view.py`
3. Test the standalone inspect command: `i3pm tree-monitor inspect <id>` to see expected output
4. Check the detail view component: `src/ui/tree-monitor-detail.ts` for rendering logic

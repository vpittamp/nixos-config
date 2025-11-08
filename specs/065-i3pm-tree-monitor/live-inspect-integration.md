# Live TUI Inspect Integration

**Feature**: 065-i3pm-tree-monitor
**Task**: Integrate event detail inspection into live streaming TUI
**Status**: Not Implemented (incorrectly marked complete in tasks.md)

## Current State

The live TUI (`src/ui/tree-monitor-live.ts`) shows "Enter=inspect" in the help legend but pressing Enter displays a placeholder error:

```typescript
// Lines 263-271
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

## What Exists

1. **Detail View Component**: `src/ui/tree-monitor-detail.ts` (189 lines)
   - Renders event metadata, correlation, field-level diff, enrichment
   - Already works from CLI: `i3pm tree-monitor inspect <id>`
   - Has keyboard navigation ('b' for back, 'q' for quit)

2. **Live View Component**: `src/ui/tree-monitor-live.ts` (384 lines)
   - Full-screen TUI with event table
   - Keyboard navigation (↑↓ for selection)
   - Tracks selected event via `state.selectedIndex`
   - Events array with all event data

## What's Needed

Integrate the existing detail view into the live TUI so pressing Enter:
1. Gets the selected event ID from `state.events[state.selectedIndex]`
2. Calls `renderEventDetail()` from `tree-monitor-detail.ts`
3. Displays the detail view in full-screen mode
4. Returns to live view when user presses 'b' or 'q'

## Implementation Approach

### Option 1: Inline Detail View (Recommended)

Replace the live TUI with the detail view, similar to screen navigation:

```typescript
// In handleInput() function, replace lines 263-271:
if (key[0] === 13) {  // Enter
  if (state.selectedIndex >= 0 && state.selectedIndex < state.events.length) {
    const event = state.events[state.selectedIndex];

    // Hide live view, show detail view
    clearScreen();
    await showEventDetail(client, event.id);

    // After detail view exits, restore live view
    render(state);
  }
}

async function showEventDetail(client: TreeMonitorClient, eventId: string): Promise<void> {
  // Import detail view renderer
  const { renderEventDetail } = await import("./tree-monitor-detail.ts");

  // Fetch event details
  const event = await client.getEvent(eventId);

  // Render detail view
  renderEventDetail(event);

  // Wait for 'b' or 'q' key
  await waitForExitKey();
}

function waitForExitKey(): Promise<void> {
  return new Promise((resolve) => {
    const buf = new Uint8Array(8);
    const loop = async () => {
      const n = await Deno.stdin.read(buf);
      if (n === null) {
        resolve();
        return;
      }

      const key = buf.subarray(0, n);
      // 'b' or 'q' key
      if (key[0] === 98 || key[0] === 113) {
        resolve();
      } else {
        loop();
      }
    };
    loop();
  });
}
```

### Option 2: Refactor Detail View as Module

Extract the detail rendering logic to support both standalone and embedded modes:

```typescript
// In tree-monitor-detail.ts, export rendering function
export function renderDetailView(event: Event): void {
  // Existing rendering logic
  // ...
}

export async function runDetailViewInteractive(
  client: TreeMonitorClient,
  eventId: string
): Promise<void> {
  // Fetch event
  const event = await client.getEvent(eventId);

  // Render
  renderDetailView(event);

  // Wait for exit
  await waitForExitKey();
}

// In tree-monitor-live.ts
import { runDetailViewInteractive } from "./tree-monitor-detail.ts";

// In Enter key handler:
if (key[0] === 13) {
  const event = state.events[state.selectedIndex];

  // Suspend live view
  clearScreen();

  // Show detail view (blocking)
  await runDetailViewInteractive(client, event.id);

  // Resume live view
  render(state);
}
```

## Acceptance Criteria

1. **Given** live view is showing events with at least one event
   **When** user presses Enter on a selected event
   **Then** the detail view displays with full event information

2. **Given** detail view is open from live view
   **When** user presses 'b'
   **Then** live view restores with same scroll position and selection

3. **Given** detail view is open from live view
   **When** user presses 'q'
   **Then** application exits cleanly

4. **Given** live view has no events
   **When** user presses Enter
   **Then** nothing happens (no error)

5. **Given** detail view fails to fetch event (daemon error)
   **When** user presses Enter
   **Then** error message displays briefly, then returns to live view

## Implementation Tasks

**T037-REVISED: Integrate inspect into live TUI** (`src/ui/tree-monitor-live.ts`)

1. Import detail view rendering function from `tree-monitor-detail.ts`
2. Replace placeholder Enter key handler (lines 263-271)
3. Add event ID extraction: `state.events[state.selectedIndex].id`
4. Add guard: check if events exist and index is valid
5. Call detail view with RPC client and event ID
6. Handle detail view exit (restore live view)
7. Add error handling (RPC failure, invalid event ID)
8. Preserve live view state (scroll offset, selection) across transitions
9. Update help text if needed (already shows "Enter=inspect")

**Estimated Effort**: 30 minutes

**Files Modified**:
- `src/ui/tree-monitor-live.ts` (15 lines changed)
- `src/ui/tree-monitor-detail.ts` (possibly refactor to export reusable function)

## Testing

**Manual Test**:
```bash
# Launch live view
i3pm tree-monitor live

# Navigate with arrow keys to select an event
# Press Enter
# Verify detail view displays
# Press 'b'
# Verify live view restores

# Press Enter again
# Press 'q'
# Verify application exits
```

**Edge Cases**:
- Empty events list → Enter does nothing
- Invalid event ID (shouldn't happen, but check)
- RPC error fetching event → Show error, return to live view
- Rapid Enter presses → Debounce or ignore while detail view is open

## Python TUI Reference

The Python version uses Textual's screen navigation:

```python
# In live_view.py
def action_drill_down(self) -> None:
    """Drill down into selected event - opens detailed diff view"""
    table = self.query_one(DataTable)
    if table.cursor_row is not None:
        row_key = table.get_row_at(table.cursor_row)[0]
        event_id = int(row_key)

        from .diff_view import DiffView
        self.app.push_screen(DiffView(self.rpc_client, event_id))
```

The TypeScript version should mirror this behavior using terminal screen swapping.

## Next Steps

1. Choose Option 1 (inline) or Option 2 (refactored module) - **Recommend Option 1** for simplicity
2. Implement changes in `tree-monitor-live.ts`
3. Test manually with running daemon
4. Update tasks.md to mark T037 as complete (when actually done)
5. Commit with message: `feat(065): Integrate event inspection into live TUI`

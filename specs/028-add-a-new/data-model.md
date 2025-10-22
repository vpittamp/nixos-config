# Data Model: Enhanced CLI User Experience

**Feature**: Enhanced CLI User Experience with Real-Time Feedback
**Branch**: `028-add-a-new`
**Date**: 2025-10-22

## Overview

This document defines the data entities and their relationships for the CLI presentation layer enhancements. Since this feature focuses on output formatting and user interaction (presentation layer), most entities are ephemeral display models rather than persistent data structures.

---

## Core Entities

### 1. TerminalCapabilities

Represents the detected capabilities of the current terminal environment.

**Fields**:
- `isTTY: boolean` - Whether output is connected to a terminal (vs. pipe/redirect)
- `colorSupport: ColorLevel` - Level of color support detected
- `supportsUnicode: boolean` - Whether terminal can display Unicode characters
- `width: number` - Current terminal width in columns
- `height: number` - Current terminal height in rows

**Type Definition**:
```typescript
enum ColorLevel {
  None = 0,       // No color support (TERM=dumb or NO_COLOR set)
  Basic = 16,     // 16-color support (xterm)
  Extended = 256, // 256-color support (xterm-256color)
  TrueColor = 16777216 // 24-bit true color
}

interface TerminalCapabilities {
  isTTY: boolean;
  colorSupport: ColorLevel;
  supportsUnicode: boolean;
  width: number;
  height: number;
}
```

**Validation Rules**:
- `width` must be ≥ 40 (minimum supported terminal width per FR-017)
- `height` must be ≥ 10 (minimum usable height)
- If `!isTTY`, then `colorSupport` must be `ColorLevel.None`

**State Transitions**:
```
Detection → Initialized → [SIGWINCH event] → Updated (width/height change)
```

**Relationships**:
- Used by: `OutputFormatter`, `TableRenderer`, `ProgressIndicator`
- Created by: `detectTerminalCapabilities()` function

---

### 2. ColorTheme

Defines semantic color mappings for different terminal backgrounds.

**Fields**:
- `error: string` - Color code for error messages (red)
- `warning: string` - Color code for warnings (yellow/amber)
- `success: string` - Color code for success messages (green)
- `info: string` - Color code for informational text (gray/dimmed)
- `dim: string` - Color code for de-emphasized text
- `bold: string` - Style code for emphasis
- `reset: string` - Reset code to default colors

**Type Definition**:
```typescript
interface ColorTheme {
  error: string;
  warning: string;
  success: string;
  info: string;
  dim: string;
  bold: string;
  reset: string;
}

// Predefined themes
const DarkTheme: ColorTheme = {
  error: "\x1b[91m",    // Bright red (#FF6B6B)
  warning: "\x1b[93m",  // Bright yellow (#FFD43B)
  success: "\x1b[92m",  // Bright green (#51CF66)
  info: "\x1b[37m",     // Gray (#A9A9A9)
  dim: "\x1b[2m",       // Dim/faint
  bold: "\x1b[1m",      // Bold
  reset: "\x1b[0m",     // Reset all
};

const LightTheme: ColorTheme = {
  error: "\x1b[31m",    // Dark red (#C92A2A)
  warning: "\x1b[33m",  // Amber (#F08C00)
  success: "\x1b[32m",  // Dark green (#2B8A3E)
  info: "\x1b[90m",     // Dark gray (#495057)
  dim: "\x1b[2m",
  bold: "\x1b[1m",
  reset: "\x1b[0m",
};
```

**Validation Rules**:
- All color codes must be valid ANSI escape sequences
- All codes must maintain WCAG AA contrast (4.5:1 minimum) per FR-004
- If `capabilities.colorSupport === ColorLevel.None`, use empty strings for all fields

**Relationships**:
- Selected by: `OutputFormatter` based on `TerminalCapabilities`
- Used by: All output functions that apply semantic colors

---

### 3. SymbolSet

Maps semantic symbols to Unicode or ASCII representations.

**Fields**:
- `success: string` - Success indicator (✓ or [OK])
- `error: string` - Error indicator (✗ or [X])
- `warning: string` - Warning indicator (⚠ or [!])
- `info: string` - Information indicator (ℹ or [i])
- `spinner: string[]` - Animation frames for spinners

**Type Definition**:
```typescript
interface SymbolSet {
  success: string;
  error: string;
  warning: string;
  info: string;
  spinner: string[];
}

const UnicodeSymbols: SymbolSet = {
  success: "✓",
  error: "✗",
  warning: "⚠",
  info: "ℹ",
  spinner: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
};

const AsciiSymbols: SymbolSet = {
  success: "[OK]",
  error: "[X]",
  warning: "[!]",
  info: "[i]",
  spinner: ["|", "/", "-", "\\"],
};
```

**Validation Rules**:
- Selected based on `capabilities.supportsUnicode` per FR-012
- `spinner` array must have at least 2 frames
- All symbols must render within reasonable width (≤4 characters for ASCII)

**Relationships**:
- Selected by: `OutputFormatter` based on `TerminalCapabilities`
- Used by: Status messages, progress indicators, live views

---

### 4. ProgressIndicator

Represents the state of a progress bar or spinner.

**Fields**:
- `type: "bar" | "spinner"` - Type of progress indicator
- `current: number` - Current progress value (for bars)
- `total: number | null` - Total expected value (null for unknown duration)
- `message: string` - Description of current operation
- `startTime: number` - Timestamp when operation started (ms)
- `lastUpdate: number` - Timestamp of last render (ms)

**Type Definition**:
```typescript
interface ProgressIndicator {
  type: "bar" | "spinner";
  current: number;
  total: number | null;
  message: string;
  startTime: number;
  lastUpdate: number;
}

// Helper computed properties
interface ProgressIndicatorComputed extends ProgressIndicator {
  readonly percentage: number | null;  // (current / total) * 100 or null
  readonly elapsed: number;             // Date.now() - startTime
  readonly shouldShow: boolean;         // elapsed > 3000ms per FR-001
}
```

**Validation Rules**:
- If `type === "bar"`, then `total` must be non-null
- If `type === "spinner"`, then `total` is ignored (can be null)
- `current` must be ≥ 0
- `total` must be ≥ `current` when non-null
- Updates must occur at minimum 2 Hz (500ms) per FR-002

**State Transitions**:
```
Created → [elapsed < 3s] → Hidden
       → [elapsed ≥ 3s] → Visible → [update] → Visible
                                  → [complete] → Finalized → Removed
```

**Relationships**:
- Rendered by: `ProgressBarRenderer` or `SpinnerRenderer`
- Updated by: Application code via `progress.current += delta`

---

### 5. TableColumn

Defines a column in a tabular display.

**Fields**:
- `key: string` - Data field name
- `header: string` - Display header text
- `alignment: "left" | "right" | "center"` - Text alignment
- `priority: number` - Visibility priority (1=always visible, higher=hide first)
- `minWidth: number` - Minimum column width in characters
- `maxWidth: number | null` - Maximum width (null = no limit)

**Type Definition**:
```typescript
interface TableColumn {
  key: string;
  header: string;
  alignment: "left" | "right" | "center";
  priority: number;
  minWidth: number;
  maxWidth: number | null;
}

// Example column definitions
const WindowTableColumns: TableColumn[] = [
  { key: "id", header: "ID", alignment: "right", priority: 1, minWidth: 8, maxWidth: 12 },
  { key: "class", header: "Class", alignment: "left", priority: 1, minWidth: 10, maxWidth: 20 },
  { key: "title", header: "Title", alignment: "left", priority: 2, minWidth: 15, maxWidth: 40 },
  { key: "workspace", header: "WS", alignment: "center", priority: 3, minWidth: 4, maxWidth: 6 },
  { key: "output", header: "Output", alignment: "left", priority: 4, minWidth: 8, maxWidth: 15 },
  { key: "project", header: "Project", alignment: "left", priority: 5, minWidth: 8, maxWidth: 15 },
];
```

**Validation Rules**:
- `priority` must be ≥ 1
- `minWidth` must be ≥ 4 (enough for header + ellipsis)
- If `maxWidth` is set, must be ≥ `minWidth`
- `alignment: "right"` recommended for numeric fields
- `alignment: "left"` recommended for text fields

**Relationships**:
- Used by: `TableRenderer` to format tabular output
- Defines: Column visibility behavior based on terminal width

---

### 6. TableLayout

Represents the computed layout for a table given terminal width constraints.

**Fields**:
- `columns: TableColumn[]` - Active columns (some may be hidden)
- `columnWidths: number[]` - Computed width for each active column
- `totalWidth: number` - Total table width including separators
- `separator: string` - Column separator string (e.g., " │ ")

**Type Definition**:
```typescript
interface TableLayout {
  columns: TableColumn[];
  columnWidths: number[];
  totalWidth: number;
  separator: string;
}
```

**Validation Rules**:
- `totalWidth` must be ≤ `terminalWidth - 2` (leave margins)
- `columnWidths.length` must equal `columns.length`
- Each `columnWidths[i]` must be between `columns[i].minWidth` and `columns[i].maxWidth`

**State Transitions**:
```
ColumnDefinitions + TerminalWidth → ComputeLayout() → TableLayout
                                   → [SIGWINCH] → RecomputeLayout() → Updated TableLayout
```

**Relationships**:
- Computed by: `calculateTableLayout(columns, data, terminalWidth)`
- Used by: `TableRenderer.render(layout, data)`

---

### 7. SelectionMenuItem

Represents an item in an interactive selection menu.

**Fields**:
- `value: string` - Internal value returned when selected
- `label: string` - Display text shown to user
- `description?: string` - Optional description (shown in multi-line mode)
- `disabled?: boolean` - Whether item can be selected

**Type Definition**:
```typescript
interface SelectionMenuItem {
  value: string;
  label: string;
  description?: string;
  disabled?: boolean;
}

// Example usage
const projectItems: SelectionMenuItem[] = [
  { value: "nixos", label: " NixOS Configuration", description: "/etc/nixos" },
  { value: "stacks", label: " Stacks Project", description: "~/projects/stacks" },
  { value: "personal", label: " Personal", description: "~/personal" },
];
```

**Validation Rules**:
- `value` must be unique within a menu
- `label` must be non-empty
- If `disabled === true`, item cannot be selected (grayed out)

**Relationships**:
- Used by: `promptSelect()`, `promptMultipleSelect()`
- Filtered by: User input during selection

---

### 8. EventStreamState

Tracks state for live event streaming displays.

**Fields**:
- `buffer: Event[]` - Circular buffer of recent events (max 500)
- `bufferSize: number` - Maximum buffer size
- `lastFlush: number` - Timestamp of last display flush
- `flushInterval: number` - Milliseconds between flushes (default 100ms)
- `aggregationEnabled: boolean` - Whether to aggregate duplicate events

**Type Definition**:
```typescript
interface Event {
  timestamp: number;
  type: string;
  payload: unknown;
}

interface EventStreamState {
  buffer: Event[];
  bufferSize: number;
  lastFlush: number;
  flushInterval: number;
  aggregationEnabled: boolean;
}
```

**Validation Rules**:
- `bufferSize` must be ≥ 10 and ≤ 1000
- `flushInterval` must be ≥ 50ms and ≤ 1000ms (to meet <100ms latency requirement)
- Buffer is circular: when full, oldest events are discarded

**State Transitions**:
```
Initialized → Streaming → [event arrives] → Buffered
                       → [flush interval] → Flushed → Display → Streaming
                       → [stop] → Finalized
```

**Relationships**:
- Manages: Stream of events from daemon or i3 IPC
- Used by: Live view mode (`i3pm windows --live`, `i3-project-daemon-events`)

---

## Relationship Diagram

```
TerminalCapabilities
    ↓ (informs)
    ├─→ ColorTheme (selected)
    ├─→ SymbolSet (selected)
    └─→ TableLayout (width constraint)

TableColumn[] + TerminalWidth
    ↓ (computes)
TableLayout
    ↓ (used by)
TableRenderer

ProgressIndicator
    ↓ (rendered by)
ProgressBarRenderer / SpinnerRenderer
    ↓ (uses)
ColorTheme + SymbolSet

SelectionMenuItem[]
    ↓ (displayed by)
promptSelect() / promptMultipleSelect()
    ↓ (uses)
ColorTheme + SymbolSet

EventStreamState
    ↓ (manages)
Event[] buffer
    ↓ (rendered by)
StreamRenderer
    ↓ (uses)
ColorTheme + TerminalCapabilities
```

---

## Computed Fields & Helpers

### ProgressIndicatorComputed

```typescript
function computeProgressFields(p: ProgressIndicator): ProgressIndicatorComputed {
  return {
    ...p,
    percentage: p.total ? (p.current / p.total) * 100 : null,
    elapsed: Date.now() - p.startTime,
    shouldShow: (Date.now() - p.startTime) >= 3000, // FR-001
  };
}
```

### Terminal Width Adaptation

```typescript
function selectVisibleColumns(
  columns: TableColumn[],
  terminalWidth: number
): TableColumn[] {
  // Sort by priority (lowest = most important)
  const sorted = [...columns].sort((a, b) => a.priority - b.priority);

  const selected: TableColumn[] = [];
  let currentWidth = 0;

  for (const col of sorted) {
    const newWidth = currentWidth + col.minWidth + 3; // +3 for separator
    if (newWidth <= terminalWidth - 2) {
      selected.push(col);
      currentWidth = newWidth;
    } else {
      break; // Terminal too narrow, skip remaining columns
    }
  }

  return selected;
}
```

---

## Edge Cases & Constraints

### Terminal Width < 40 Columns (FR-017)
- Show minimal output: single most important column only
- Disable table mode, use list format instead
- Progress bars reduce to spinner

### Non-TTY Output (FR-013)
- `TerminalCapabilities.isTTY = false`
- All colors disabled (ColorTheme uses empty strings)
- No interactive prompts (error with helpful message)
- No progress indicators (silent operation)

### SIGWINCH During Operation (FR-011)
- Update `TerminalCapabilities.width` and `height`
- Recompute `TableLayout` on next render
- Gracefully handle mid-render resize (no crashes)

### Rapid Events (FR-018)
- Buffer events in 100ms windows
- Aggregate duplicates (e.g., repeated focus events)
- Display batch every 100ms or when buffer reaches 10 events
- Never exceed 100ms latency from event to display

---

## Validation Summary

| Entity | Key Validations |
|--------|----------------|
| TerminalCapabilities | width ≥ 40, !isTTY → colorSupport = None |
| ColorTheme | WCAG AA compliance (4.5:1 contrast) |
| SymbolSet | Unicode or ASCII based on terminal support |
| ProgressIndicator | Updates ≥ 2 Hz, show after 3s elapsed |
| TableColumn | priority ≥ 1, minWidth ≥ 4 |
| TableLayout | totalWidth ≤ terminalWidth - 2 |
| SelectionMenuItem | Unique values, non-empty labels |
| EventStreamState | 50ms ≤ flushInterval ≤ 1000ms, buffer ≤ 1000 |

---

**Last Updated**: 2025-10-22
**Status**: Complete - ready for contracts generation

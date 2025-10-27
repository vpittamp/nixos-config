# User Workflows: Walker/Elephant Launcher

**Feature**: 043-get-full-functionality
**Date**: 2025-10-27

## Overview

This document defines the user-facing workflows and interaction patterns for Walker/Elephant launcher system. Each workflow corresponds to a user story from the feature specification.

---

## Workflow 1: Launch Application with Project Context

**User Story**: P1 - Application Launch with Environment Context

**Steps**:
1. User presses `Meta+D` (i3 keybinding)
2. Walker window appears (centered, floating, no border)
3. User types application name (e.g., "code")
4. Walker displays matching applications from i3pm registry
5. User selects application (press Return or click)
6. Walker executes: `app-launcher-wrapper.sh <app-name>`
7. Wrapper queries i3pm daemon for active project context
8. Wrapper injects I3PM_* environment variables
9. Application launches with full LaunchContext (DISPLAY, XDG_*, I3PM_*)
10. Window appears on i3 workspace
11. Walker window closes automatically

**Verification**:
```bash
# Launch VS Code via Walker
# Then check environment:
ps aux | grep code | head -1 | awk '{print $2}'  # Get PID
cat /proc/<PID>/environ | tr '\0' '\n' | grep -E "DISPLAY|I3PM_PROJECT_NAME"

# Expected output:
# DISPLAY=:10
# I3PM_PROJECT_NAME=nixos
# I3PM_PROJECT_DIR=/etc/nixos
```

**Success Criteria**:
- SC-001: 100% success rate for application launches
- SC-005: Walker window appears <100ms after keybinding
- SC-006: 100% accuracy for i3pm project context inheritance

**Error Cases**:
| Error | Symptom | Recovery |
|-------|---------|----------|
| Elephant not running | Walker doesn't show applications | `systemctl --user restart elephant` |
| DISPLAY not set | Application launches but no window | i3 imports DISPLAY, restarts Elephant |
| i3pm daemon down | App launches without project context | `systemctl --user restart i3-project-event-listener` |

---

## Workflow 2: Access Clipboard History

**User Story**: P2 - Clipboard History Management

**Steps**:
1. User copies several text snippets throughout work session
   - `Ctrl+C` in various applications
   - X11 clipboard manager (Elephant) records each copy
2. User needs to paste a previous snippet
3. User presses `Meta+D` to open Walker
4. User types `:` (clipboard provider prefix)
5. Walker displays clipboard history (most recent first)
   - Each entry shows preview (first 100 chars)
   - Images show thumbnail preview
6. User navigates list (arrow keys or type to filter)
7. User selects entry (press Return)
8. Selected content becomes current clipboard
9. User pastes in application (`Ctrl+V`)

**Verification**:
```bash
# Copy test data
echo "First copy" | xclip -selection clipboard
sleep 1
echo "Second copy" | xclip -selection clipboard
sleep 1
echo "Third copy" | xclip -selection clipboard

# Access clipboard history
# Meta+D → type ":" → verify "Third copy" at top, "First copy" at bottom

# Select "First copy" from history → paste → verify "First copy" appears
```

**Success Criteria**:
- SC-003: Clipboard history displays <200ms after typing ":"
- FR-007: Support both text and image clipboard entries
- FR-008: Display entries in reverse chronological order

**User Experience**:
- Fuzzy search: Type additional text after ":" to filter history
- Preview quality: Text previews trim at word boundary (no mid-word cuts)
- Image previews: Thumbnails scaled to fit Walker window width

**Error Cases**:
| Error | Symptom | Recovery |
|-------|---------|----------|
| Clipboard empty | ":" shows "No results" | Copy something first |
| Image too large | Thumbnail load slow or fails | Clipboard provider skips images >1MB |
| xclip missing | Clipboard provider doesn't work | Install xclip package |

---

## Workflow 3: Search and Open Files

**User Story**: P2 - File Search and Navigation

**Steps**:
1. User needs to open a file (e.g., configuration, documentation)
2. User presses `Meta+D` to open Walker
3. User types `/` (file provider prefix)
4. User types search term (e.g., "nixos")
5. Walker searches:
   - User home directory (`$HOME`)
   - Active project directory (`$I3PM_PROJECT_DIR`)
6. Walker displays matching files:
   - Filename match score
   - Full path for disambiguation
   - Last modified time
7. User selects file
   - **Return**: Opens in Ghostty + Neovim
   - **Ctrl+Return**: Opens with default application (xdg-open)
8. Application opens file

**Verification**:
```bash
# Search for .nix files
# Meta+D → type "/walker.nix" → verify home-modules/desktop/walker.nix appears

# Press Return → verify Ghostty opens with Neovim editing walker.nix
# Press Ctrl+Return → verify xdg-open launches (e.g., text editor)
```

**Line Number Navigation**:
If search result includes line number fragment (e.g., `walker.nix#L42`):
- Neovim opens at line 42
- Command: `ghostty -e nvim +42 /path/to/walker.nix`

**Success Criteria**:
- SC-004: File search returns results <500ms for 10k files
- SC-009: Files open at correct line number when fragment provided
- FR-010, FR-011: Support Neovim and default app opening

**Search Optimization**:
- Excludes hidden directories: `.git`, `.cache`, `.nix-profile`
- Excludes build artifacts: `node_modules`, `target`, `result`
- Limits results to 100 matches (sorted by score, then modified time)

**Error Cases**:
| Error | Symptom | Recovery |
|-------|---------|----------|
| File not readable | Search shows file but open fails | Check file permissions |
| Ghostty not found | Neovim open fails | Install Ghostty package |
| Invalid line number | Neovim opens at top of file | Ignore fragment, open normally |

---

## Workflow 4: Web Search

**User Story**: P3 - Web Search Integration

**Steps**:
1. User needs to search web for information
2. User presses `Meta+D` to open Walker
3. User types `@` (websearch provider prefix)
4. User types search query (e.g., "nixos tutorial")
5. Walker displays configured search engines:
   - Google
   - DuckDuckGo
   - GitHub
   - YouTube
   - Wikipedia
6. User selects engine (or presses Return for default)
7. Elephant constructs URL:
   - Template: `https://www.google.com/search?q=%s`
   - Query: `nixos tutorial`
   - Result: `https://www.google.com/search?q=nixos+tutorial`
8. Firefox launches with search results page

**Verification**:
```bash
# Search web
# Meta+D → type "@nixos tutorial" → select Google → verify Firefox opens with Google search

# Check URL in Firefox address bar:
# https://www.google.com/search?q=nixos+tutorial
```

**Default Engine Behavior**:
- User types `@query` and immediately presses Return
- Walker uses default engine (configured in websearch.toml)
- Skips engine selection step

**Success Criteria**:
- SC-007: 100% of searches open browser with correct query
- FR-012: Support multiple search engines
- FR-013: Use configurable default engine

**URL Encoding**:
| Input | Encoded |
|-------|---------|
| Space | `+` |
| C++ | `C%2B%2B` |
| hello world | `hello+world` |
| 日本語 | `%E6%97%A5%E6%9C%AC%E8%AA%9E` |

**Error Cases**:
| Error | Symptom | Recovery |
|-------|---------|----------|
| Firefox not running | Firefox starts first, then loads search | Wait for Firefox startup |
| Invalid URL encoding | Malformed URL in browser | Fix Elephant websearch provider |
| Engine not configured | Walker shows "No engines" | Add engines to websearch.toml |

---

## Workflow 5: Calculator

**User Story**: P3 - Calculator and Symbol Insertion

**Steps** (Calculator):
1. User needs quick calculation
2. User presses `Meta+D` to open Walker
3. User types `=` (calc provider prefix)
4. User types math expression (e.g., "2+2")
5. Walker displays result: "4"
6. User presses Return
7. Result copied to clipboard
8. User pastes in application (`Ctrl+V`)

**Supported Operators** (per FR-014):
- Addition: `+`
- Subtraction: `-`
- Multiplication: `*`
- Division: `/`
- Modulo: `%`
- Exponentiation: `^`

**Example Expressions**:
```
=2+2          → 4
=10*5         → 50
=100/4        → 25
=2^8          → 256
=17%5         → 2
=(2+3)*4      → 20
```

**Verification**:
```bash
# Calculate
# Meta+D → type "=2+2" → verify result "4" appears
# Press Return → paste in terminal → verify "4" pastes
```

**Success Criteria**:
- SC-008: 100% accuracy for standard operators
- FR-014: Evaluate expressions and copy to clipboard

**Error Handling**:
| Input | Result |
|-------|--------|
| `=2+` | Error: Incomplete expression |
| `=abc` | Error: Invalid expression |
| `=sin(45)` | Error: Unsupported function (Out of Scope) |
| `=1/0` | Error: Division by zero |

---

## Workflow 6: Symbol/Emoji Picker

**User Story**: P3 - Calculator and Symbol Insertion

**Steps** (Symbol Picker):
1. User needs to insert special character or emoji
2. User presses `Meta+D` to open Walker
3. User types `.` (symbols provider prefix)
4. User types symbol name (e.g., "lambda")
5. Walker displays matching symbols:
   - λ (Greek lowercase lambda, U+03BB)
   - Λ (Greek uppercase lambda, U+039B)
6. User selects symbol
7. Symbol inserted at cursor position in active application

**Browse Mode**:
- Type `.` without search term
- Walker displays common emoji and symbols
- Categories: emoji, math, arrows, currency, etc.

**Example Searches**:
```
.lambda     → λ, Λ
.heart      → ❤, 💙, 💚, 💛, 🧡
.arrow      → →, ←, ↑, ↓, ⇒, ⇐
.check      → ✓, ✔, ☑
```

**Verification**:
```bash
# Symbol search
# Meta+D → type ".lambda" → verify λ appears
# Select → verify λ inserts in focused application
```

**Success Criteria**:
- FR-015: Display symbols with fuzzy search support
- Symbols insert at cursor position (X11 focus tracking)

**Error Cases**:
| Error | Symptom | Recovery |
|-------|---------|----------|
| No match | "No results" | Try different search term |
| Wrong window focus | Symbol inserts in wrong app | Refocus target app first |

---

## Workflow 7: Shell Command Execution

**User Story**: P3 - Shell Command Execution

**Steps**:
1. User needs to run shell command
2. User presses `Meta+D` to open Walker
3. User types `>` (runner provider prefix)
4. User types command (e.g., "echo hello")
5. User chooses execution mode:
   - **Return**: Background execution (no output visible)
   - **Shift+Return**: Terminal execution (Ghostty window)
6. Command executes

**Background Execution** (Return):
- Command runs detached
- No output visible
- Suitable for: Launching apps, fire-and-forget commands

**Terminal Execution** (Shift+Return):
- Command runs in new Ghostty terminal
- Output visible, interactive
- Suitable for: htop, interactive scripts, long-running commands

**Example Commands**:
```
>echo hello           → (Return) Silent execution
>htop                 → (Shift+Return) Opens htop in terminal
>notify-send "Done"   → (Return) Shows desktop notification
>nixos-rebuild switch → (Shift+Return) Watch rebuild progress
```

**Verification**:
```bash
# Background execution
# Meta+D → type ">notify-send 'Test'" → press Return
# Verify: Desktop notification appears (no terminal)

# Terminal execution
# Meta+D → type ">echo 'Hello from terminal'" → press Shift+Return
# Verify: Ghostty opens with output "Hello from terminal"
```

**Success Criteria**:
- FR-016: Support background (Return) and terminal (Shift+Return) execution
- Terminal uses Ghostty (project standard)

**Interactive Command Handling** (per FR-016):
- Commands requiring user input → Always open terminal
- Long-running commands → Terminal recommended (Shift+Return)

**Error Cases**:
| Error | Symptom | Recovery |
|-------|---------|----------|
| Command not found | Background: Silent fail, Terminal: Error message | Check command spelling |
| Permission denied | Terminal shows "Permission denied" | Use sudo or fix permissions |
| Syntax error | Terminal shows shell error | Fix command syntax |

---

## Cross-Workflow Patterns

### Common Keybindings

| Key | Action |
|-----|--------|
| `Meta+D` | Open Walker |
| `Esc` | Close Walker without action |
| `Return` | Execute default action |
| `Ctrl+Return` | Execute alternate action (e.g., open file with default app) |
| `Shift+Return` | Execute tertiary action (e.g., run command in terminal) |
| `Arrow Up/Down` | Navigate results |
| `Tab` | Cycle through actions |

### Provider Prefixes

| Prefix | Provider | Example |
|--------|----------|---------|
| (none) | applications | "code" → VS Code |
| `:` | clipboard | ": " → show clipboard history |
| `/` | files | "/nixos" → search files |
| `@` | websearch | "@query" → web search |
| `=` | calc | "=2+2" → calculator |
| `.` | symbols | ".lambda" → symbol picker |
| `>` | runner | ">echo" → shell command |
| `;s ` | sesh (plugin) | ";s nixos" → tmux session |
| `;p ` | projects (plugin) | ";p " → i3pm projects |

### Result Display Format

All providers use consistent result format:
```
[Icon] Title
       Subtitle (optional)
```

Examples:
```
Applications:
  📝 VS Code
     Code editing

Clipboard:
  📋 First copy
     Copied 5 minutes ago

Files:
  📄 walker.nix
     ~/etc/nixos/home-modules/desktop/walker.nix

Websearch:
  🔍 Google
     Search "nixos tutorial"
```

### Window Behavior

1. **Open**: Walker window appears centered, floating
2. **Focus**: Keyboard focus automatically on search input
3. **Close**: Window closes after action execution (close_when_open = true)
4. **Visibility**: Window always on top when open (i3 floating rule)

---

## Performance Benchmarks

| Workflow | Target | Measurement |
|----------|--------|-------------|
| Launch application | <100ms | Keybinding to window visible (SC-005) |
| Clipboard history | <200ms | Prefix to results displayed (SC-003) |
| File search | <500ms | Query to results for 10k files (SC-004) |
| Web search | Immediate | URL construction and browser launch |
| Calculator | <100ms | Expression evaluation |
| Symbol search | <100ms | Fuzzy match on 3000+ symbols |
| Shell command | Immediate | Command parsing and execution |

---

## Accessibility

### Keyboard-Only Operation

All workflows support **100% keyboard operation**:
- No mouse required for any action
- Fuzzy search reduces typing (e.g., "vsc" matches "VS Code")
- Arrow keys for navigation
- Return/Ctrl+Return for common actions

### Visual Feedback

- **Search input**: Shows typed text with cursor
- **Results**: Highlighted current selection
- **Icons**: Visual categories for quick identification
- **Previews**: Clipboard, files show content preview

### Error Messages

User-friendly error messages with guidance:
```
❌ No clipboard history
   Copy something first to see it here

❌ No files found
   Try a different search term

❌ Invalid expression
   Example: =2+2 or =10*5
```

---

## Summary

These workflows cover all six user stories (P1-P3) from the feature specification. Each workflow:
1. Defines clear step-by-step user actions
2. Includes verification commands for testing
3. Maps to success criteria from spec
4. Documents error cases and recovery

All workflows share common patterns:
- Keyboard-first interaction (Meta+D to open)
- Prefix-based provider selection
- Consistent result display format
- Automatic window close after action
- Integration with i3pm project context where applicable

The workflows validate that existing Walker/Elephant configuration satisfies all functional requirements (FR-001 through FR-020) without requiring code changes.

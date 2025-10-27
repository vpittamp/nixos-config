# Data Model: Complete Walker/Elephant Launcher Functionality

**Feature**: 043-get-full-functionality
**Date**: 2025-10-27
**Status**: Complete

## Overview

This document defines the data structures and flows for Walker/Elephant launcher system. Since this is a configuration-only feature leveraging existing Walker/Elephant functionality, the data model describes the runtime data structures managed by these external components, not custom implementations.

## Core Entities

### Provider

A Walker/Elephant plugin that supplies searchable items to the launcher UI.

**Attributes**:
- `name` (string): Unique provider identifier ("applications", "clipboard", "files", "websearch", "calc", "symbols", "runner")
- `prefix` (string, optional): Keyboard shortcut to activate provider (":", "/", "@", "=", ".", ">")
- `enabled` (boolean): Whether provider is active in Walker configuration
- `items` (list): Collection of searchable items provided by this provider (dynamic, query-time)

**State**: Managed by Elephant service backend, queried by Walker UI on-demand

**Relationships**:
- Provider → Items (one-to-many, ephemeral)
- Provider → Actions (one-to-many, configured)

---

### Clipboard Entry

A clipboard history item stored by Elephant's clipboard provider.

**Attributes**:
- `content` (string | binary): Clipboard content (text or image data)
- `content_type` (enum): "text" or "image"
- `timestamp` (datetime): When item was copied to clipboard
- `preview` (string): Short preview for display in Walker UI (first 100 chars for text, thumbnail for images)
- `index` (integer): Position in history (0 = most recent)

**Validation Rules**:
- Content must not exceed 1MB (per edge case requirement)
- Text content must be valid UTF-8
- Image content must be valid PNG/JPEG/GIF format

**State Transitions**:
1. **New Copy** → Entry created with index=0, existing entries increment index
2. **History Full** → Oldest entry (index=N) removed when limit reached
3. **Selection** → Entry content becomes current clipboard (no history modification)

**Storage**: Ephemeral (in-memory only, managed by Elephant process)

**Relationships**:
- ClipboardEntry → User (many-to-one, implicit via user session)

---

### File Result

A file search result returned by Elephant's file provider.

**Attributes**:
- `path` (string): Absolute file path
- `filename` (string): File basename for display
- `directory` (string): Parent directory path
- `modified_time` (datetime): Last modification timestamp (for sorting)
- `fragment` (string, optional): Line number or position hint (e.g., "L42" for line 42)
- `match_score` (float): Fuzzy match relevance (0.0-1.0, higher = better match)

**Validation Rules**:
- Path must exist and be readable by user
- Fragment must be valid line number if present (format: "L<number>")
- Match score must be 0.0-1.0

**Search Scope**:
- User home directory (`$HOME`)
- Active project directory (from i3pm context, if available)
- Excludes: `.git`, `node_modules`, `.nix-profile`, `result` symlinks

**Relationships**:
- FileResult → OpenAction (one-to-many: Neovim, default app)

---

### Search Engine

A web search configuration for Elephant's websearch provider.

**Attributes**:
- `name` (string): Display name for engine ("Google", "DuckDuckGo", etc.)
- `url` (string): URL template with `%s` placeholder for query
- `is_default` (boolean): Whether this is the default search engine

**Validation Rules**:
- URL must contain exactly one `%s` placeholder
- URL must be valid HTTPS URL
- Exactly one engine must be marked as default

**Configuration**: Loaded from `~/.config/elephant/websearch.toml` (home-manager generated)

**Relationships**:
- SearchEngine → BrowserLaunch (one-to-one per query)

---

### Launch Context

Environment variables passed from Elephant service to launched applications.

**Attributes**:
- `DISPLAY` (string): X11 display identifier (e.g., ":10")
- `PATH` (string): Executable search paths (includes ~/.local/bin for app-launcher-wrapper.sh)
- `XDG_DATA_DIRS` (string): Application data directories (isolated to i3pm-applications)
- `XDG_RUNTIME_DIR` (string): Runtime directory for sockets, temp files
- `I3PM_PROJECT_NAME` (string, optional): Active project name from i3pm daemon
- `I3PM_PROJECT_DIR` (string, optional): Active project directory path
- `I3PM_APP_NAME` (string, optional): Application name from registry
- `I3PM_SCOPE` (string, optional): "scoped" or "global"

**Source**:
- DISPLAY: Imported from systemd user environment (set by X11/xrdp)
- PATH, XDG_*: Explicitly set in Elephant systemd service definition
- I3PM_*: Injected by app-launcher-wrapper.sh at application launch time

**Validation Rules**:
- DISPLAY must match pattern `:<number>` or `<hostname>:<number>`
- PATH must include ~/.local/bin for wrapper script execution
- XDG_DATA_DIRS must include i3pm-applications directory
- I3PM_PROJECT_NAME must match existing project in i3pm registry (if present)

**Lifecycle**: Created at application launch, persists in `/proc/<pid>/environ` for process lifetime

**Relationships**:
- LaunchContext → Application Process (one-to-one)
- LaunchContext → i3pm Daemon (many-to-one query for project context)

---

### Calculator Result

An evaluated mathematical expression result from the calc provider.

**Attributes**:
- `expression` (string): User-entered math expression
- `result` (number | string): Evaluated result or error message
- `is_error` (boolean): Whether evaluation failed
- `result_text` (string): Formatted result for display and clipboard

**Validation Rules**:
- Expression must contain only valid math operators: +, -, *, /, %, ^ (per FR-014)
- Result must be valid number or error message

**State**: Ephemeral (computed on-demand, copied to clipboard on selection)

**Relationships**:
- CalculatorResult → Clipboard (one-to-one on selection)

---

### Symbol Entry

A Unicode symbol/emoji from the symbols provider.

**Attributes**:
- `character` (string): The actual Unicode character
- `name` (string): Human-readable name for fuzzy search (e.g., "lambda", "heart", "checkmark")
- `unicode_code` (string): Unicode code point (e.g., "U+03BB")
- `category` (string, optional): Symbol category ("emoji", "math", "arrows", etc.)

**Search**: Fuzzy matching on `name` field

**State**: Static database (provided by Walker/Elephant package)

**Relationships**:
- SymbolEntry → TextInsertion (one-to-one on selection)

---

### Runner Command

A shell command executed by the runner provider.

**Attributes**:
- `command` (string): Shell command to execute
- `execution_mode` (enum): "background" (Return) or "terminal" (Shift+Return)
- `terminal` (string): Terminal emulator to use ("ghostty" from environment)
- `exit_code` (integer, optional): Command exit status (for terminal execution)
- `output` (string, optional): Command output (for debugging, not displayed)

**Validation Rules**:
- Command must be valid shell syntax
- Execution mode must be "background" or "terminal"

**State Transitions**:
1. **Background execution**: Command runs detached, no output visible
2. **Terminal execution**: Command runs in new Ghostty window, output visible, interactive

**Relationships**:
- RunnerCommand → Process (one-to-one)
- RunnerCommand → Terminal Window (one-to-one for terminal mode)

---

## Data Flows

### Application Launch Flow

```
User Input (Meta+D)
  ↓
Walker UI (GTK4 window)
  ↓
Elephant Service (query applications provider)
  ↓
Desktop Files (from XDG_DATA_DIRS = i3pm-applications)
  ↓
User Selection
  ↓
Exec Command: app-launcher-wrapper.sh <app>
  ↓
Wrapper Script:
  ├─ Query i3pm daemon for active project
  ├─ Inject I3PM_* environment variables
  └─ Execute application
  ↓
Application Process (inherits LaunchContext environment)
  ↓
Window appears on i3 workspace
```

**Environment Variables at Each Stage**:
1. **Elephant Service**: DISPLAY, PATH, XDG_DATA_DIRS (from systemd)
2. **Walker UI**: Inherits from Elephant via IPC
3. **app-launcher-wrapper.sh**: Adds I3PM_* variables
4. **Application**: Full LaunchContext (all environment variables)

---

### Clipboard History Flow

```
User Copies Text/Image
  ↓
X11 Clipboard (CLIPBOARD selection)
  ↓
Elephant Clipboard Provider (monitors clipboard changes)
  ↓
ClipboardEntry created (content, timestamp, preview)
  ↓
Entry added to history buffer (max 100-500 items, FIFO)
  ↓
User Types ":" in Walker
  ↓
Walker queries Elephant clipboard provider
  ↓
Elephant returns ClipboardEntry list (reverse chronological)
  ↓
Walker displays entries with previews
  ↓
User Selects Entry
  ↓
Entry content → X11 Clipboard (current selection)
  ↓
User pastes in application
```

**State Management**:
- Clipboard history: In-memory circular buffer (Elephant process)
- Oldest entry evicted when buffer full
- No persistence across Elephant restarts

---

### File Search Flow

```
User Types "/" in Walker
  ↓
User Enters Search Term ("nixos")
  ↓
Walker sends query to Elephant file provider
  ↓
Elephant searches:
  ├─ $HOME/**/* (recursive)
  └─ $I3PM_PROJECT_DIR/**/* (if project active)
  ↓
Fuzzy match: filename contains "nixos"
  ↓
Results sorted by match score, then modified_time
  ↓
Walker displays FileResult list with paths
  ↓
User Selection:
  ├─ Return → walker-open-in-nvim script
  │   └─ Ghostty + Neovim (with line number if fragment)
  └─ Ctrl+Return → xdg-open (default app)
```

**Search Optimization**:
- Excludes hidden directories (.git, .cache)
- Excludes build artifacts (node_modules, target, result)
- Limits results to first 100 matches for performance

---

### Web Search Flow

```
User Types "@" in Walker
  ↓
User Enters Search Terms ("nixos tutorial")
  ↓
Walker queries Elephant websearch provider
  ↓
Elephant loads engines from ~/.config/elephant/websearch.toml
  ↓
Walker displays engine list (Google, DuckDuckGo, GitHub, YouTube, Wikipedia)
  ↓
User Selects Engine (or presses Return for default)
  ↓
Elephant constructs URL:
  template.url.replace("%s", urlencode(query))
  → "https://www.google.com/search?q=nixos+tutorial"
  ↓
Launch Firefox with URL
  ↓
Firefox opens new tab with search results
```

**URL Encoding**: Query terms URL-encoded by Elephant (spaces → +, special chars → %XX)

---

### Calculator Flow

```
User Types "=" in Walker
  ↓
User Enters Expression ("2+2")
  ↓
Walker sends to Elephant calc provider
  ↓
Elephant evaluates expression:
  ├─ Parse expression
  ├─ Validate operators (+, -, *, /, %, ^)
  └─ Compute result
  ↓
Result displayed in Walker ("4")
  ↓
User Presses Return
  ↓
Result copied to X11 clipboard
  ↓
User pastes in application
```

**Error Handling**: Invalid expressions show error message in Walker, no clipboard copy

---

## Configuration Files

### Walker Config (~/.config/walker/config.toml)

```toml
# X11 window mode (not Wayland layer shell)
as_window = true
force_keyboard_focus = false

# Provider modules
[modules]
applications = true
calc = true
clipboard = true
files = true
menus = true
runner = true
symbols = true
websearch = true

# Provider prefixes
[[providers.prefixes]]
prefix = ":"
provider = "clipboard"

[[providers.prefixes]]
prefix = "/"
provider = "files"

[[providers.prefixes]]
prefix = "@"
provider = "websearch"

[[providers.prefixes]]
prefix = "="
provider = "calc"

[[providers.prefixes]]
prefix = "."
provider = "symbols"

[[providers.prefixes]]
prefix = ">"
provider = "runner"
```

### Elephant Websearch Config (~/.config/elephant/websearch.toml)

```toml
[[engines]]
name = "Google"
url = "https://www.google.com/search?q=%s"

[[engines]]
name = "DuckDuckGo"
url = "https://duckduckgo.com/?q=%s"

[[engines]]
name = "GitHub"
url = "https://github.com/search?q=%s"

[[engines]]
name = "YouTube"
url = "https://www.youtube.com/results?search_query=%s"

[[engines]]
name = "Wikipedia"
url = "https://en.wikipedia.org/wiki/Special:Search?search=%s"

default = "Google"
```

---

## State Management

### Elephant Service State

**Process State**:
- Service runs continuously as systemd user service
- Auto-restarts on failure (Restart=on-failure, RestartSec=1)
- Monitors X11 clipboard for changes (clipboard provider)
- Indexes file system on-demand (file provider search query)

**Environment State** (inherited at service start):
- DISPLAY: Imported from systemd user environment
- PATH: Explicitly set to include ~/.local/bin
- XDG_DATA_DIRS: Set to i3pm-applications directory
- XDG_RUNTIME_DIR: Set via %t specifier (e.g., /run/user/1000)

**Health Checks**:
- Service active: `systemctl --user is-active elephant`
- DISPLAY available: `systemctl --user show-environment | grep DISPLAY`
- IPC socket: Check for Walker ↔ Elephant communication

### Walker UI State

**Window State**:
- Floating window, centered, no border (i3 for_window rule)
- Marked with "_global_ui" (prevents project-scoped filtering)
- Hidden when not in use (close_when_open = true)

**Query State** (ephemeral):
- Current search query
- Active provider (based on prefix or default)
- Filtered results from Elephant
- Selected item index

---

## Error Scenarios

### DISPLAY Not Available

**Symptom**: Elephant service fails to start or applications don't display windows

**Cause**: DISPLAY not imported into systemd user environment before Elephant starts

**Recovery**:
1. i3 imports DISPLAY via `systemctl --user import-environment DISPLAY`
2. i3 restarts Elephant via `systemctl --user restart elephant.service`
3. Elephant picks up DISPLAY from environment

**Prevention**: i3 config ensures DISPLAY import before Elephant restart (existing configuration)

---

### Clipboard Provider Not Working

**Symptom**: Typing ":" in Walker shows no results or empty list

**Possible Causes**:
1. Elephant service not running
2. X11 clipboard manager conflict (KDE Klipper interfering)
3. xclip not available in PATH

**Diagnosis**:
```bash
systemctl --user status elephant  # Check service running
echo "test" | xclip -selection clipboard  # Test xclip
xclip -selection clipboard -o  # Verify clipboard read
```

**Resolution**: Ensure Elephant running, disable conflicting clipboard managers

---

### File Search Returns No Results

**Symptom**: Typing "/" in Walker shows "No results" even for known files

**Possible Causes**:
1. Search scope excludes target directory (not in $HOME or $I3PM_PROJECT_DIR)
2. File permissions prevent read access
3. File provider disabled in Walker config

**Diagnosis**:
```bash
# Check file provider enabled
grep "files = true" ~/.config/walker/config.toml

# Check file readable
ls -la /path/to/file

# Check search scope
echo $HOME
i3pm project current  # Check active project directory
```

---

### Web Search URL Encoding Issues

**Symptom**: Special characters in search query break URL or produce incorrect results

**Cause**: Elephant should URL-encode query, but edge case characters may not be handled

**Example**: Searching for "C++ tutorial" should encode as "C%2B%2B+tutorial"

**Validation**: Check actual URL opened in Firefox address bar

---

## Performance Considerations

### Clipboard History Size

**Current**: No explicit limit in configuration
**Recommendation**: 100-500 items based on spec edge case (<1MB content limit)
**Impact**: Larger history consumes more memory but improves utility

### File Search Performance

**Target**: <500ms for 10k files (SC-004)
**Optimization**: Elephant indexes file system on-demand, caches results during query session
**Bottleneck**: Large directories (node_modules, nix store) - excluded via default ignore patterns

### Calculator Evaluation

**Target**: <100ms for standard expressions
**Complexity**: O(n) parsing where n = expression length
**Limitation**: No advanced functions (trig, log) per spec Out of Scope

---

## Data Model Summary

| Entity | Storage | Lifecycle | Size |
|--------|---------|-----------|------|
| Provider | Config (TOML) | Persistent | N/A |
| ClipboardEntry | Memory (Elephant) | Ephemeral | 100-500 items |
| FileResult | Memory (query-time) | Ephemeral | <100 results |
| SearchEngine | Config (TOML) | Persistent | 5 engines |
| LaunchContext | Environment | Process lifetime | Per-process |
| CalculatorResult | Memory (ephemeral) | Ephemeral | 1 result |
| SymbolEntry | Static DB | Persistent | ~3000 symbols |
| RunnerCommand | Memory (ephemeral) | Ephemeral | 1 command |

**Total Memory Footprint** (Elephant service): ~15-30MB baseline + clipboard history (variable)

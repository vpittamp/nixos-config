# CLI Command Contracts

**Branch**: `020-update-our-spec` | **Date**: 2025-10-21 | **Plan**: [../plan.md](../plan.md)

## Overview

This document specifies the command-line interface contracts for all new and modified i3pm commands supporting app discovery and auto-classification.

---

## Command: `i3pm app-classes add-pattern`

**Purpose**: Add a new pattern rule for automatic window class classification.

**Usage**:
```bash
i3pm app-classes add-pattern <pattern> <scope> [options]
```

**Arguments**:
| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `pattern` | `str` | Yes | Pattern string with optional prefix (glob:, regex:, or literal) |
| `scope` | `str` | Yes | Classification scope: "scoped" or "global" |

**Options**:
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--priority` | `int` | `0` | Precedence for matching (higher = evaluated first) |
| `--description` | `str` | `""` | Human-readable description |
| `--test` | `str` | - | Test pattern against window class before adding |

**Examples**:
```bash
# Add glob pattern for PWAs
i3pm app-classes add-pattern "glob:pwa-*" global --priority=100 --description="All PWAs are global"

# Add regex pattern for Vim variants
i3pm app-classes add-pattern "regex:^(neo)?vim$" scoped --priority=90

# Test pattern before adding
i3pm app-classes add-pattern "glob:Code*" scoped --test="Code-insiders"
# Output: ✓ Pattern matches "Code-insiders" (would be classified as scoped)
```

**Exit Codes**:
- `0`: Pattern added successfully
- `1`: Invalid pattern syntax (regex error, empty pattern, etc.)
- `2`: Invalid scope value (not "scoped" or "global")
- `3`: Pattern conflicts with existing pattern (same raw pattern)

**Output Format**:
```
✓ Added pattern rule:
  Pattern:     glob:pwa-*
  Scope:       global
  Priority:    100
  Description: All PWAs are global

Configuration updated: ~/.config/i3/app-classes.json
Daemon reloaded: i3-project-event-listener
```

**Error Examples**:
```bash
# Invalid regex
i3pm app-classes add-pattern "regex:^[invalid" scoped
# Error: Invalid regex pattern '^[invalid': unbalanced bracket

# Empty pattern
i3pm app-classes add-pattern "" scoped
# Error: Pattern cannot be empty

# Conflicting pattern
i3pm app-classes add-pattern "glob:pwa-*" scoped  # Already exists with scope=global
# Error: Pattern 'glob:pwa-*' already exists with scope=global (use remove-pattern first)
```

---

## Command: `i3pm app-classes list-patterns`

**Purpose**: List all configured pattern rules with precedence order.

**Usage**:
```bash
i3pm app-classes list-patterns [options]
```

**Options**:
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--format` | `str` | `"table"` | Output format: "table", "json", or "plain" |
| `--sort` | `str` | `"priority"` | Sort by: "priority", "pattern", "scope" |

**Examples**:
```bash
# Default table format
i3pm app-classes list-patterns

# JSON format for scripting
i3pm app-classes list-patterns --format=json

# Sort by pattern alphabetically
i3pm app-classes list-patterns --sort=pattern
```

**Output Format (table)**:
```
Pattern Rules (3 total):

Priority  Pattern             Scope    Description
────────  ──────────────────  ───────  ─────────────────────────
100       glob:pwa-*          global   All PWAs are global apps
90        regex:^(neo)?vim$   scoped   Neovim and Vim are project-scoped
50        Ghostty             scoped   Literal match for Ghostty

Precedence order: Priority (descending) → First match wins
Configuration: ~/.config/i3/app-classes.json
```

**Output Format (json)**:
```json
{
  "patterns": [
    {
      "pattern": "glob:pwa-*",
      "scope": "global",
      "priority": 100,
      "description": "All PWAs are global apps"
    },
    {
      "pattern": "regex:^(neo)?vim$",
      "scope": "scoped",
      "priority": 90,
      "description": "Neovim and Vim are project-scoped"
    },
    {
      "pattern": "Ghostty",
      "scope": "scoped",
      "priority": 50,
      "description": "Literal match for Ghostty"
    }
  ],
  "total": 3,
  "config_file": "/home/user/.config/i3/app-classes.json"
}
```

**Exit Codes**:
- `0`: Success (even if no patterns configured)
- `1`: Configuration file read error

---

## Command: `i3pm app-classes remove-pattern`

**Purpose**: Remove a pattern rule from configuration.

**Usage**:
```bash
i3pm app-classes remove-pattern <pattern>
```

**Arguments**:
| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `pattern` | `str` | Yes | Exact pattern string to remove (must match verbatim) |

**Examples**:
```bash
# Remove glob pattern
i3pm app-classes remove-pattern "glob:pwa-*"

# Remove regex pattern
i3pm app-classes remove-pattern "regex:^(neo)?vim$"
```

**Output Format**:
```
✓ Removed pattern rule:
  Pattern: glob:pwa-*
  Scope:   global

Configuration updated: ~/.config/i3/app-classes.json
Daemon reloaded: i3-project-event-listener
```

**Exit Codes**:
- `0`: Pattern removed successfully
- `1`: Pattern not found in configuration
- `2`: Configuration file write error

---

## Command: `i3pm app-classes test-pattern`

**Purpose**: Test a pattern against window classes without modifying configuration.

**Usage**:
```bash
i3pm app-classes test-pattern <pattern> <window_class> [options]
```

**Arguments**:
| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `pattern` | `str` | Yes | Pattern to test (glob:, regex:, or literal) |
| `window_class` | `str` | Yes | Window class to test against |

**Options**:
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--all-classes` | `flag` | - | Test pattern against all known window classes |

**Examples**:
```bash
# Test single window class
i3pm app-classes test-pattern "glob:pwa-*" "pwa-youtube"
# Output: ✓ Pattern matches "pwa-youtube"

# Test all known classes
i3pm app-classes test-pattern "glob:pwa-*" --all-classes
# Output:
# Testing pattern: glob:pwa-*
# Matches (5):
#   - pwa-youtube
#   - pwa-spotify
#   - pwa-slack
#   - pwa-chatgpt
#   - pwa-claude
#
# No matches (47 other classes)
```

**Exit Codes**:
- `0`: Pattern matches window class
- `1`: Pattern does not match window class
- `2`: Invalid pattern syntax

---

## Command: `i3pm app-classes detect`

**Purpose**: Detect window classes for applications using Xvfb isolation.

**Usage**:
```bash
i3pm app-classes detect [options] [desktop_files...]
```

**Arguments**:
| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `desktop_files` | `list[str]` | No | Specific .desktop files to detect (default: all missing) |

**Options**:
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--all-missing` | `flag` | - | Detect all apps without known WM_CLASS |
| `--isolated` | `flag` | - | Use Xvfb isolation (default if xvfb-run available) |
| `--timeout` | `int` | `10` | Timeout in seconds per app |
| `--cache` | `flag` | - | Cache detection results to `~/.cache/i3pm/detected-classes.json` |
| `--verbose` | `flag` | - | Show detailed detection progress |

**Examples**:
```bash
# Detect all apps without WM_CLASS
i3pm app-classes detect --all-missing --isolated

# Detect specific app
i3pm app-classes detect /usr/share/applications/slack.desktop --verbose

# Detect with caching
i3pm app-classes detect --all-missing --cache
```

**Output Format**:
```
Detecting window classes for 10 applications...

[1/10] Visual Studio Code...
  Desktop file: /usr/share/applications/code.desktop
  Detection:    xvfb (isolated)
  Detected:     Code
  Confidence:   100%
  Duration:     2.3s

[2/10] Slack...
  Desktop file: /usr/share/applications/slack.desktop
  Detection:    xvfb (isolated)
  Detected:     Slack
  Confidence:   100%
  Duration:     3.1s

...

Summary:
  Successful: 8/10
  Failed:     2/10
  Total time: 34.2s
  Cache:      ~/.cache/i3pm/detected-classes.json
```

**Exit Codes**:
- `0`: All detections successful
- `1`: Some detections failed (partial success)
- `2`: All detections failed
- `3`: Xvfb not available (when --isolated specified)

---

## Command: `i3pm app-classes wizard`

**Purpose**: Launch interactive TUI wizard for visual classification.

**Usage**:
```bash
i3pm app-classes wizard [options]
```

**Options**:
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--filter` | `str` | `"all"` | Initial filter: "all", "unclassified", "scoped", "global" |
| `--sort` | `str` | `"name"` | Initial sort: "name", "class", "status", "confidence" |
| `--auto-accept` | `flag` | - | Auto-accept high-confidence suggestions (>90%) |

**Examples**:
```bash
# Launch wizard with default settings
i3pm app-classes wizard

# Show only unclassified apps
i3pm app-classes wizard --filter=unclassified

# Auto-accept high-confidence suggestions
i3pm app-classes wizard --auto-accept
```

**Interactive Mode**: See [tui-wizard.md](tui-wizard.md) for detailed TUI interaction contracts.

**Exit Codes**:
- `0`: Wizard completed and saved changes
- `1`: Wizard exited without saving (user pressed Escape)
- `2`: Wizard error (TUI initialization failed, config write error, etc.)

---

## Command: `i3pm app-classes inspect`

**Purpose**: Launch window inspector for real-time property inspection.

**Usage**:
```bash
i3pm app-classes inspect [options] [window_identifier]
```

**Arguments**:
| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `window_identifier` | `int` | No | Specific window ID (con_id) to inspect |

**Options**:
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--click` | `flag` | Default | Click to select window (xdotool selectwindow) |
| `--focused` | `flag` | - | Inspect currently focused window |
| `--live` | `flag` | - | Enable live updates (subscribe to i3 events) |

**Examples**:
```bash
# Click to select window
i3pm app-classes inspect --click

# Inspect focused window
i3pm app-classes inspect --focused

# Inspect specific window with live updates
i3pm app-classes inspect 94489280512 --live
```

**Interactive Mode**: See [tui-inspector.md](tui-inspector.md) for detailed TUI interaction contracts.

**Exit Codes**:
- `0`: Inspector exited normally
- `1`: Window selection canceled (user pressed Escape in click mode)
- `2`: Inspector error (window not found, i3 IPC error, etc.)

---

## Modified Command: `i3pm app-classes list`

**Purpose**: List all discovered applications with classification status (EXTENDED).

**NEW Columns**:
- `Source`: How classification was determined (explicit, pattern, heuristic, unclassified)
- `Pattern`: Matched pattern rule (if source=pattern)

**Usage**:
```bash
i3pm app-classes list [options]
```

**Options** (NEW):
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--show-source` | `flag` | - | Include Source and Pattern columns |
| `--filter` | `str` | `"all"` | Filter: "all", "explicit", "pattern", "heuristic", "unclassified" |

**Output Format (with --show-source)**:
```
Discovered Applications (52 total):

Name                  Class          Scope         Source        Pattern
────────────────────  ─────────────  ────────────  ────────────  ──────────────────
Visual Studio Code    Code           scoped        explicit      -
Firefox               firefox        global        explicit      -
YouTube PWA           pwa-youtube    global        pattern       glob:pwa-*
Spotify PWA           pwa-spotify    global        pattern       glob:pwa-*
Ghostty Terminal      Ghostty        scoped        explicit      -
Neovim                nvim           scoped        pattern       regex:^(neo)?vim$
Slack                 Slack          unclassified  -             -
K9s                   K9s            global        heuristic     -

...
```

---

## Shell Completion

**Bash Completion** (argcomplete):
```bash
# Install completion
i3pm --install-completion bash

# Test completion
i3pm app-classes <TAB>
# Suggests: add-pattern, list-patterns, remove-pattern, test-pattern, detect, wizard, inspect, list
```

**Completion Behavior**:
- Command names: All subcommands
- Pattern prefixes: `glob:`, `regex:` (suggests prefix syntax)
- Scope values: `scoped`, `global`
- Filter values: `all`, `unclassified`, `scoped`, `global`
- Sort values: `name`, `class`, `status`, `confidence`
- .desktop files: Completes from `/usr/share/applications/*.desktop`

---

## Configuration Reload

**Daemon Integration**: All commands that modify `app-classes.json` automatically trigger daemon reload:
```python
def reload_daemon():
    """Trigger daemon to reload app-classes.json."""
    # Send tick event to i3 (daemon subscribed)
    i3 = Connection()
    i3.command('nop "i3pm:reload-config"')
```

**Reload Confirmation**:
```
Configuration updated: ~/.config/i3/app-classes.json
Daemon reloaded: i3-project-event-listener (PID 12345)
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Phase**: 1 (Contracts) - IN PROGRESS

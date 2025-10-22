# Quickstart Guide: Dynamic Window Rules

**Feature**: 024-update-replace-test
**Last Updated**: 2025-10-22

## Overview

The dynamic window rules system automatically assigns windows to workspaces based on configurable rules instead of static i3 configuration. This gives you the power to:

- **Automatically place windows** on specific workspaces when they open (terminal → WS1, browser → WS3)
- **Create project-specific rules** that override global defaults
- **Match windows flexibly** using exact matches, regex patterns, or wildcards
- **Control multiple aspects** of window behavior (workspace, layout, floating state, marks)
- **Update rules on-the-fly** without restarting i3 or the daemon

**Benefits over static i3 config:**
- Rules live in JSON files you can edit and reload instantly
- First-match evaluation gives predictable behavior
- Priority levels (project/global/default) for clean rule organization
- Rich pattern matching beyond basic class names
- Integration with the existing event-driven i3 project management system

---

## Installation & Setup

### Prerequisites

- NixOS with i3 window manager v4.20+
- i3-project-event-daemon running (from Feature 015)
- home-manager enabled

**Check prerequisites:**
```bash
# Verify i3 version
i3 --version
# Should show: i3 version 4.20 or higher

# Check daemon is running
systemctl --user status i3-project-event-listener
# Should show: Active: active (running)
```

### Enabling Dynamic Rules

The feature is enabled by default when the i3-project-event-daemon is running. No additional configuration needed!

**Verification steps:**

1. **Check configuration directory exists:**
   ```bash
   ls -la ~/.config/i3/
   # Should show window-rules.json or window-rules-default.json
   ```

2. **Verify daemon recognizes window rules:**
   ```bash
   i3-project-daemon-status
   # Look for: "Rules loaded: X" in output
   ```

3. **Test with a simple rule** (see next section)

---

## Creating Your First Rule

### Basic Example: Terminal to Workspace 1

Let's create a rule that automatically sends all Ghostty terminals to workspace 1.

**Step 1: Create or edit your rules file**

```bash
# Create the file if it doesn't exist
touch ~/.config/i3/window-rules.json

# Edit with your preferred editor
vi ~/.config/i3/window-rules.json
```

**Step 2: Add the rule**

```json
{
  "version": "1.0",
  "rules": [
    {
      "name": "terminal-workspace-1",
      "match_criteria": {
        "class": {
          "pattern": "Ghostty",
          "match_type": "exact",
          "case_sensitive": true
        }
      },
      "actions": [
        {
          "type": "workspace",
          "target": 1
        }
      ],
      "priority": "global",
      "focus": false,
      "enabled": true
    }
  ],
  "defaults": {
    "workspace": "current",
    "focus": true
  }
}
```

**Step 3: Test the rule**

```bash
# Validate syntax (if available)
i3pm validate-rules

# Test without opening a window
i3pm test-rule --class Ghostty
# Output: Would match rule: terminal-workspace-1
#         Actions: Move to workspace 1

# Reload daemon to apply changes
systemctl --user restart i3-project-event-listener

# Launch terminal and verify it opens on workspace 1
ghostty
```

### Testing the Rule

You can test rules before applying them using the `i3pm test-rule` command:

```bash
# Test by window class
i3pm test-rule --class Ghostty

# Test by multiple criteria
i3pm test-rule --class Firefox --title "YouTube"

# See which rule would match
i3pm test-rule --class Code --title "main.py - Visual Studio Code"
```

This shows which rule would match without actually opening a window, helping you debug rule ordering and patterns.

---

## Rule Configuration Format

### JSON Structure

Every window rules file has three main sections:

```json
{
  "version": "1.0",          // Schema version (always "1.0")
  "rules": [ /* ... */ ],    // Array of WindowRule objects
  "defaults": { /* ... */ }  // Fallback behavior
}
```

**WindowRule structure:**

```json
{
  "name": "unique-rule-name",           // Required: Unique identifier
  "match_criteria": { /* ... */ },      // Required: What to match
  "actions": [ /* ... */ ],             // Required: What to do
  "priority": "global",                 // Required: "project" | "global" | "default"
  "focus": false,                       // Optional: Switch workspace after move?
  "enabled": true                       // Optional: Rule active?
}
```

### Match Criteria

Match windows based on their properties. **At least one criterion required.** All specified criteria must match (AND logic).

**Available properties:**

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `class` | PatternMatch | Window class (WM_CLASS) | `"firefox"`, `"Code"` |
| `instance` | PatternMatch | Window instance | `"Navigator"`, `"code"` |
| `title` | PatternMatch | Window title | `"main.py - VS Code"` |
| `window_role` | PatternMatch | Window role (WM_WINDOW_ROLE) | `"browser-window"` |
| `window_type` | String literal | Window type | `"normal"`, `"dialog"`, `"utility"` |
| `transient_for` | Integer | Parent window ID (for dialogs) | `2097153` |

**PatternMatch structure:**

```json
{
  "pattern": "string or regex",    // The pattern to match
  "match_type": "exact|regex|wildcard",  // How to match
  "case_sensitive": true           // Optional, default: true
}
```

**Match type behavior:**

- **`exact`**: Literal string match
  - Pattern: `"Code"` matches `"Code"` but not `"Code-insiders"`

- **`regex`**: Regular expression (Python syntax)
  - Pattern: `"^Code.*"` matches `"Code"`, `"Code-insiders"`, `"CodeEdit"`

- **`wildcard`**: Shell-style glob patterns
  - Pattern: `"FFPWA-*"` matches `"FFPWA-01ABC"`, `"FFPWA-XYZ"`

**Examples:**

```json
// Match Firefox exactly (case-insensitive)
{
  "class": {
    "pattern": "firefox",
    "match_type": "exact",
    "case_sensitive": false
  }
}

// Match any Code-like editor using regex
{
  "class": {
    "pattern": "^(Code|VSCodium|code-insiders)$",
    "match_type": "regex",
    "case_sensitive": true
  }
}

// Match all Firefox PWAs
{
  "class": {
    "pattern": "FFPWA-*",
    "match_type": "wildcard"
  },
  "title": {
    "pattern": ".*YouTube.*",
    "match_type": "regex"
  }
}

// Match dialog windows
{
  "window_type": "dialog"
}
```

### Actions

Define what happens when a rule matches. **At least one action required.** Actions execute in order.

**Available action types:**

#### 1. Workspace Assignment

Move window to specific workspace (1-9).

```json
{
  "type": "workspace",
  "target": 2
}
```

#### 2. Window Marking

Add i3 mark for identification and tracking.

```json
{
  "type": "mark",
  "value": "terminal"
}
```

Marks must be alphanumeric with underscores/hyphens only: `[a-zA-Z0-9_-]+`

#### 3. Floating Control

Set window floating or tiled state.

```json
{
  "type": "float",
  "enable": true
}
```

#### 4. Layout Assignment

Set container layout mode.

```json
{
  "type": "layout",
  "mode": "tabbed"
}
```

Valid modes: `"tabbed"`, `"stacked"`, `"splitv"`, `"splith"`

**Multiple actions example:**

```json
{
  "name": "vscode-tabbed-workspace-2",
  "match_criteria": {
    "class": {"pattern": "Code", "match_type": "exact"}
  },
  "actions": [
    {"type": "workspace", "target": 2},
    {"type": "layout", "mode": "tabbed"},
    {"type": "mark", "value": "editor"}
  ],
  "priority": "global",
  "focus": true,
  "enabled": true
}
```

### Priority Levels

Rules are evaluated in priority order (highest to lowest). **First matching rule wins** - evaluation stops.

| Priority | Numeric Value | Use Case |
|----------|---------------|----------|
| `"project"` | 500 | Project-specific overrides (highest) |
| `"global"` | 200 | Standard rules for all contexts |
| `"default"` | 100 | Fallback rules (lowest) |

**Example priority hierarchy:**

```json
{
  "rules": [
    // Evaluated first: Project-specific terminal rule
    {
      "name": "nixos-terminal-workspace-1",
      "match_criteria": {"class": {"pattern": "Ghostty", "match_type": "exact"}},
      "actions": [{"type": "workspace", "target": 1}],
      "priority": "project"  // 500 - checked first
    },

    // Evaluated second: Global terminal rule (won't match if project rule matches)
    {
      "name": "global-terminal-workspace-2",
      "match_criteria": {"class": {"pattern": "Ghostty", "match_type": "exact"}},
      "actions": [{"type": "workspace", "target": 2}],
      "priority": "global"   // 200 - checked after project
    },

    // Evaluated last: Default floating for all dialogs
    {
      "name": "floating-dialogs",
      "match_criteria": {"window_type": "dialog"},
      "actions": [{"type": "float", "enable": true}],
      "priority": "default"  // 100 - checked last
    }
  ]
}
```

### Focus Control

The `focus` field controls whether switching to the target workspace is automatic.

```json
{
  "focus": false  // Move window silently (recommended for background apps)
}
```

```json
{
  "focus": true   // Move window AND switch to that workspace
}
```

**Use `focus: false` when:**
- Window should open in background (terminals, background jobs)
- You don't want to lose your current workspace context
- Opening multiple windows at once

**Use `focus: true` when:**
- Window needs immediate attention (dialogs, critical apps)
- You explicitly want to switch context (launching main work application)

**Note**: `focus: true` requires at least one `workspace` action, otherwise validation fails.

---

## Common Patterns

### Pattern 1: Browser to Specific Workspace

Send Firefox to workspace 3 (browser workspace).

```json
{
  "name": "firefox-workspace-3",
  "match_criteria": {
    "class": {
      "pattern": "firefox",
      "match_type": "exact",
      "case_sensitive": false
    }
  },
  "actions": [
    {
      "type": "workspace",
      "target": 3
    }
  ],
  "priority": "global",
  "focus": false,
  "enabled": true
}
```

### Pattern 2: Project-Scoped Terminal

Terminal that only applies when working on a specific project.

```json
{
  "name": "nixos-project-terminal",
  "match_criteria": {
    "class": {
      "pattern": "Ghostty",
      "match_type": "exact"
    }
  },
  "actions": [
    {
      "type": "workspace",
      "target": 1
    },
    {
      "type": "mark",
      "value": "project:nixos"
    }
  ],
  "priority": "project",
  "focus": false,
  "enabled": true
}
```

This rule has higher priority than global rules and includes project marking for integration with i3pm project switching.

### Pattern 3: Floating Dialogs

Make all dialog windows float automatically.

```json
{
  "name": "floating-dialogs",
  "match_criteria": {
    "window_type": "dialog"
  },
  "actions": [
    {
      "type": "float",
      "enable": true
    }
  ],
  "priority": "default",
  "focus": false,
  "enabled": true
}
```

### Pattern 4: Regex Title Matching

Match VS Code windows with specific file patterns.

```json
{
  "name": "vscode-python-files",
  "match_criteria": {
    "class": {
      "pattern": "Code",
      "match_type": "exact"
    },
    "title": {
      "pattern": ".*\\.py - Visual Studio Code$",
      "match_type": "regex",
      "case_sensitive": true
    }
  },
  "actions": [
    {
      "type": "workspace",
      "target": 2
    },
    {
      "type": "layout",
      "mode": "tabbed"
    }
  ],
  "priority": "global",
  "focus": false,
  "enabled": true
}
```

### Pattern 5: Progressive Web Apps

Match PWAs with wildcard class and exact title.

```json
{
  "name": "youtube-pwa",
  "match_criteria": {
    "class": {
      "pattern": "FFPWA-*",
      "match_type": "wildcard"
    },
    "title": {
      "pattern": "YouTube",
      "match_type": "exact"
    }
  },
  "actions": [
    {
      "type": "workspace",
      "target": 4
    },
    {
      "type": "mark",
      "value": "pwa-youtube"
    }
  ],
  "priority": "global",
  "focus": false,
  "enabled": true
}
```

---

## Rule Priority & First-Match Semantics

### How Rules Are Evaluated

The system uses **first-match semantics**: evaluation stops at the first matching rule.

**Evaluation order:**

1. **Sort by priority** (project → global → default)
2. **Within same priority**, preserve file order
3. **Check each rule's criteria** against window properties
4. **First match wins** - execute actions and stop
5. **No match?** Apply default actions

**Pseudocode:**

```python
sorted_rules = sort_by_priority(rules)  # High to low
for rule in sorted_rules:
    if rule.enabled and rule.match_criteria.matches(window):
        execute_actions(rule.actions)
        return  # Stop evaluation

# No match - apply defaults
execute_defaults()
```

### Ordering Your Rules

**Best practices:**

1. **Most specific rules first** (within same priority)
   ```json
   // Good: Specific before general
   {"name": "vscode-python", "priority": "global"}  // Matches "Code" + "*.py"
   {"name": "vscode-all", "priority": "global"}     // Matches "Code"
   ```

2. **Use priority levels appropriately**
   ```json
   // Project-specific override
   {"name": "nixos-terminal", "priority": "project"}  // 500

   // Standard rule
   {"name": "all-terminals", "priority": "global"}    // 200

   // Catch-all fallback
   {"name": "floating-dialogs", "priority": "default"} // 100
   ```

3. **Catch-all rules at the end**
   ```json
   // Specific rules first
   {"name": "firefox-youtube", "match": {"title": "YouTube"}}
   {"name": "firefox-all", "match": {"class": "firefox"}}

   // General rule last
   {"name": "all-browsers", "match": {"class": ".*browser.*", "match_type": "regex"}}
   ```

4. **Enable/disable for testing**
   ```json
   {
     "name": "experimental-rule",
     "enabled": false,  // Temporarily disable
     // ... rest of rule
   }
   ```

**Common mistake: Overlapping rules**

```json
// BAD: Second rule will never match!
{
  "rules": [
    {
      "name": "all-terminals",
      "match_criteria": {"class": {"pattern": ".*", "match_type": "regex"}},
      "priority": "global"
    },
    {
      "name": "specific-terminal",  // Never reached!
      "match_criteria": {"class": {"pattern": "Ghostty", "match_type": "exact"}},
      "priority": "global"
    }
  ]
}
```

```json
// GOOD: Specific rule first
{
  "rules": [
    {
      "name": "specific-terminal",
      "match_criteria": {"class": {"pattern": "Ghostty", "match_type": "exact"}},
      "priority": "global"
    },
    {
      "name": "other-terminals",
      "match_criteria": {"class": {"pattern": "Alacritty", "match_type": "exact"}},
      "priority": "global"
    }
  ]
}
```

---

## Testing & Validation

### Validating Rule Syntax

Check rules for errors before applying:

```bash
# Validate current rules file
i3pm validate-rules

# Output (success):
# ✓ Configuration valid
# ✓ Loaded 5 rules
# ✓ All patterns compile successfully

# Output (errors):
# ✗ Validation failed:
#   - Rule "terminal-workspace-1": Invalid regex pattern in class match
#   - Rule "vscode-workspace-2": Duplicate rule name
#   - Rule "firefox-browser": focus=true requires workspace action
```

### Testing Individual Rules

See which rule would match without opening a window:

```bash
# Test by class
i3pm test-rule --class Firefox

# Output:
# Matched rule: firefox-workspace-3
# Priority: global (200)
# Actions:
#   - Move to workspace 3
# Focus: false

# Test with multiple criteria
i3pm test-rule --class "Code" --title "main.py - VS Code"

# No match
i3pm test-rule --class "Unknown"
# Output: No rule matches these criteria
```

**Test all your common applications:**

```bash
# Terminal
i3pm test-rule --class Ghostty

# Editor
i3pm test-rule --class Code

# Browser
i3pm test-rule --class firefox --title "YouTube"

# Dialog
i3pm test-rule --window-type dialog
```

### Debugging Rule Matching

Use daemon logs and events to see what's happening in real-time:

```bash
# Watch events as windows open
i3-project-daemon-events --limit=20 --type=window

# Output:
# 2025-10-22 10:35:12  window::new    class=Code       con_id=12345  ✓
# 2025-10-22 10:35:12  rule_matched   rule=vscode-workspace-2
# 2025-10-22 10:35:12  action_exec    type=workspace   target=2      ✓
# 2025-10-22 10:35:12  action_exec    type=mark        value=editor  ✓

# Check daemon status
i3-project-daemon-status

# Real-time logs (more verbose)
journalctl --user -u i3-project-event-listener -f
```

**Debug mode (verbose logging):**

Enable in home-manager config:
```nix
services.i3ProjectEventListener.logLevel = "DEBUG";
```

Then rebuild and check logs:
```bash
sudo nixos-rebuild switch --flake .#hetzner
journalctl --user -u i3-project-event-listener -n 100
```

---

## Troubleshooting

### Common Issues

#### Problem 1: Window not matching rule

**Symptom**: Window opens but doesn't go to expected workspace.

**Diagnosis:**

```bash
# 1. Check window properties
i3-msg -t get_tree | jq '.. | select(.window?) | {class: .window_class, title: .name}'

# 2. Test rule matching
i3pm test-rule --class <actual-class>

# 3. Check rule is enabled
cat ~/.config/i3/window-rules.json | jq '.rules[] | select(.name=="your-rule") | .enabled'
```

**Common causes:**

- **Wrong class name**: Window class might be different than expected
  - Use `xprop` to check: Click window after running `xprop WM_CLASS`
  - Example: "Code" vs "code" vs "Code-insiders"

- **Case sensitivity**: Rule uses `case_sensitive: true` but class doesn't match case
  - Solution: Set `case_sensitive: false` or fix pattern

- **Rule priority**: Another rule matches first
  - Solution: Increase priority or reorder rules

- **Invalid regex**: Pattern doesn't compile
  - Solution: Validate with `i3pm validate-rules`

**Solutions:**

```bash
# Fix wrong class name
xprop WM_CLASS  # Click window, note output
# Example output: WM_CLASS(STRING) = "code", "Code"
#                                      ^instance  ^class

# Update rule to match actual class
vi ~/.config/i3/window-rules.json

# Reload daemon
systemctl --user restart i3-project-event-listener

# Test again
i3pm test-rule --class Code
```

#### Problem 2: Wrong workspace assigned

**Symptom**: Window goes to workspace 5 but rule says workspace 2.

**Diagnosis:**

```bash
# Check which rule matched
i3-project-daemon-events --limit=10 | grep rule_matched

# Test with exact window properties
i3pm test-rule --class <class> --title <title>
```

**Common causes:**

- **First-match semantics**: An earlier rule matched instead
  - Example: General "all terminals" rule before specific "ghostty" rule

- **Multiple rules with same priority**: File order matters
  - Solution: Reorder rules or change priority

**Solutions:**

```bash
# Check rule evaluation order
i3pm test-rule --class Ghostty --verbose
# Shows all rules evaluated and why they matched/didn't match

# Reorder rules (move specific before general)
vi ~/.config/i3/window-rules.json

# Or change priority
{
  "name": "specific-rule",
  "priority": "project"  // Changed from "global"
}
```

#### Problem 3: Focus not working as expected

**Symptom**: Window moves to workspace but doesn't switch view.

**Diagnosis:**

```bash
# Check rule focus setting
cat ~/.config/i3/window-rules.json | jq '.rules[] | select(.name=="your-rule") | .focus'
```

**Common causes:**

- **Focus set to false**: Default is `false` to avoid disrupting workflow
- **No workspace action**: `focus: true` requires workspace action

**Solutions:**

```json
// Enable focus for rule
{
  "name": "important-app",
  "match_criteria": {"class": {"pattern": "ImportantApp", "match_type": "exact"}},
  "actions": [
    {"type": "workspace", "target": 5}  // Required for focus: true
  ],
  "priority": "global",
  "focus": true,  // Changed from false
  "enabled": true
}
```

#### Problem 4: Performance issues

**Symptom**: Window assignment takes >500ms or daemon uses high CPU.

**Diagnosis:**

```bash
# Check daemon resource usage
i3-project-daemon-status
# Look for: CPU usage, memory usage, event processing time

# Check number of rules
cat ~/.config/i3/window-rules.json | jq '.rules | length'

# Monitor event processing time
i3-project-daemon-events --limit=50 | grep -E "window::new|action_exec"
```

**Common causes:**

- **Too many rules**: 100+ rules with complex regex patterns
  - Target: <100 rules, <200μs evaluation time

- **Complex regex**: Backtracking in regex patterns
  - Example: `.*.*.*something.*` is inefficient

- **Excessive rule overlap**: Many rules checked before match

**Solutions:**

```bash
# Simplify regex patterns
# Bad:  "pattern": ".*Code.*|.*VSCodium.*|.*code-insiders.*"
# Good: "pattern": "^(Code|VSCodium|code-insiders)$"

# Use exact match when possible (10x faster than regex)
{
  "pattern": "Code",
  "match_type": "exact"  // Much faster than regex
}

# Consolidate rules
# Bad:  5 separate rules for different Code window titles
# Good: 1 rule matching class "Code" (title doesn't matter)

# Disable unused rules
{
  "enabled": false  // Skipped during evaluation
}
```

**Performance targets:**

| Metric | Target | Acceptable | Action Needed |
|--------|--------|------------|---------------|
| Rule evaluation | <200μs | <500μs | Optimize patterns |
| Window detection | <100ms | <500ms | Check daemon health |
| Daemon memory | <20MB | <50MB | Restart daemon |
| Daemon CPU (idle) | <1% | <5% | Check for errors |

---

## Advanced Topics

### Integration with Project Management

Dynamic window rules integrate seamlessly with i3pm project switching:

**Project-scoped rules example:**

```json
{
  "name": "nixos-project-terminal",
  "match_criteria": {
    "class": {"pattern": "Ghostty", "match_type": "exact"}
  },
  "actions": [
    {"type": "workspace", "target": 1},
    {"type": "mark", "value": "project:nixos"}  // Integration point
  ],
  "priority": "project",
  "focus": false,
  "enabled": true
}
```

When you run `i3pm switch stacks`, the daemon:
1. Hides windows with mark `project:nixos`
2. Shows windows with mark `project:stacks`
3. New windows get marked with `project:stacks` automatically

**Active project affects rule priority:**

- Rules in `~/.config/i3/projects/{project}/window-rules.json` have priority 500
- Rules in `~/.config/i3/window-rules.json` have priority 200
- Default fallbacks have priority 100

### Multi-Monitor Configuration

Rules can consider monitor configuration for workspace assignment.

**Example: Distribute workspaces across monitors**

```json
{
  "name": "terminal-primary-monitor",
  "match_criteria": {
    "class": {"pattern": "Ghostty", "match_type": "exact"}
  },
  "actions": [
    {"type": "workspace", "target": 1}  // Always on primary
  ],
  "priority": "global",
  "focus": false,
  "enabled": true
}
```

When monitors change, i3 automatically redistributes workspaces:
- **1 monitor**: All workspaces on primary
- **2 monitors**: WS 1-2 on primary, WS 3-9 on secondary
- **3 monitors**: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

The window rules remain the same - i3 handles workspace-to-monitor mapping.

### State Restoration

When the daemon restarts, it automatically restores window management state:

**Restoration process:**

1. **Reconnect to i3** via IPC
2. **Load configuration** from files
3. **Query i3 for existing windows** (GET_TREE)
4. **Re-evaluate rules** for windows without marks
5. **Resume event processing** (<2 seconds total)

**What's preserved:**
- Window marks (stored by i3)
- Workspace assignments (stored by i3)
- Active project (stored in `~/.config/i3/active-project.json`)

**What's re-evaluated:**
- Windows without marks
- New rules added while daemon was down

**Manual restoration (if needed):**

```bash
# Check current state
i3-project-daemon-status

# If windows lost marks, switch projects to re-mark
i3pm switch nixos  # Re-marks all nixos windows
i3pm switch stacks # Re-marks all stacks windows
```

### Migrating from Static i3 Config

Replace static `for_window` and `assign` directives with dynamic rules.

**Before (in `~/.config/i3/config`):**

```
for_window [class="firefox"] move container to workspace number 3
for_window [class="Code"] move container to workspace number 2, layout tabbed
for_window [class="Ghostty"] move container to workspace number 1
assign [class="thunderbird"] $ws4
for_window [window_type="dialog"] floating enable
```

**After (in `~/.config/i3/window-rules.json`):**

```json
{
  "version": "1.0",
  "rules": [
    {
      "name": "firefox-workspace-3",
      "match_criteria": {
        "class": {"pattern": "firefox", "match_type": "exact", "case_sensitive": false}
      },
      "actions": [{"type": "workspace", "target": 3}],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "vscode-workspace-2",
      "match_criteria": {
        "class": {"pattern": "Code", "match_type": "exact"}
      },
      "actions": [
        {"type": "workspace", "target": 2},
        {"type": "layout", "mode": "tabbed"}
      ],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "terminal-workspace-1",
      "match_criteria": {
        "class": {"pattern": "Ghostty", "match_type": "exact"}
      },
      "actions": [{"type": "workspace", "target": 1}],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "thunderbird-workspace-4",
      "match_criteria": {
        "class": {"pattern": "thunderbird", "match_type": "exact"}
      },
      "actions": [{"type": "workspace", "target": 4}],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "floating-dialogs",
      "match_criteria": {"window_type": "dialog"},
      "actions": [{"type": "float", "enable": true}],
      "priority": "default",
      "focus": false,
      "enabled": true
    }
  ],
  "defaults": {
    "workspace": "current",
    "focus": true
  }
}
```

**Migration steps:**

1. **Extract rules** from i3 config
2. **Convert to JSON** using patterns above
3. **Validate** with `i3pm validate-rules`
4. **Test** with `i3pm test-rule`
5. **Comment out** static rules in i3 config (keep for rollback)
6. **Reload i3** with `i3-msg reload`
7. **Restart daemon** with `systemctl --user restart i3-project-event-listener`
8. **Test** by opening applications

**Conversion script available:**

```bash
# (Future feature - not yet implemented)
i3pm migrate-rules --from ~/.config/i3/config --to ~/.config/i3/window-rules.json
```

---

## Reference

### Available Commands

**Validation & Testing:**

```bash
i3pm validate-rules              # Validate rule configuration syntax
i3pm test-rule <criteria>        # Test which rule would match
i3pm reload-rules                # Reload rules without daemon restart
```

**Daemon Management:**

```bash
i3-project-daemon-status         # Show daemon health and statistics
i3-project-daemon-events         # Show recent daemon events
systemctl --user restart i3-project-event-listener  # Restart daemon
systemctl --user status i3-project-event-listener   # Check daemon status
journalctl --user -u i3-project-event-listener -f   # View daemon logs
```

**Project Management:**

```bash
i3pm switch <project>            # Switch to project (alias: pswitch)
i3pm current                     # Show active project (alias: pcurrent)
i3pm list                        # List all projects (alias: plist)
i3pm create                      # Create new project
```

### Configuration Files

**Main configuration:**
- `~/.config/i3/window-rules.json` - User rules (highest priority)
- `~/.config/i3/window-rules-default.json` - System defaults

**Project configurations:**
- `~/.config/i3/projects/{project-name}.json` - Project metadata
- `~/.config/i3/projects/{project-name}/window-rules.json` - Project-specific rules (optional)

**Application classifications:**
- `~/.config/i3/app-classes.json` - Scoped vs global application classes

**State files:**
- `~/.config/i3/active-project.json` - Current active project (daemon is authoritative)

### JSON Schema

Full JSON schema available at:
- `/etc/nixos/specs/024-update-replace-test/contracts/window-rule-schema.json`

Use for IDE validation and autocomplete:

```json
{
  "$schema": "/etc/nixos/specs/024-update-replace-test/contracts/window-rule-schema.json",
  "version": "1.0",
  "rules": [
    // Your rules with autocomplete!
  ]
}
```

### Further Reading

**Feature documentation:**
- `data-model.md` - Complete entity reference and relationships
- `spec.md` - Feature specification and requirements
- `contracts/window-rule-schema.json` - JSON schema for validation
- `contracts/i3-ipc-patterns.md` - Technical i3 IPC integration details

**Related features:**
- `/etc/nixos/specs/015-create-a-new/quickstart.md` - Event-based project management
- `/etc/nixos/docs/I3_IPC_PATTERNS.md` - i3 IPC integration patterns
- `/etc/nixos/docs/PYTHON_DEVELOPMENT.md` - Python development standards

---

## Examples Gallery

### Complete Configuration Template

```json
{
  "version": "1.0",
  "rules": [
    {
      "name": "terminal-workspace-1",
      "match_criteria": {
        "class": {"pattern": "Ghostty", "match_type": "exact"}
      },
      "actions": [
        {"type": "workspace", "target": 1}
      ],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "vscode-workspace-2-tabbed",
      "match_criteria": {
        "class": {"pattern": "Code", "match_type": "exact"}
      },
      "actions": [
        {"type": "workspace", "target": 2},
        {"type": "layout", "mode": "tabbed"},
        {"type": "mark", "value": "editor"}
      ],
      "priority": "global",
      "focus": true,
      "enabled": true
    },
    {
      "name": "firefox-workspace-3",
      "match_criteria": {
        "class": {"pattern": "firefox", "match_type": "exact", "case_sensitive": false}
      },
      "actions": [
        {"type": "workspace", "target": 3}
      ],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "pwas-workspace-4",
      "match_criteria": {
        "class": {"pattern": "FFPWA-*", "match_type": "wildcard"}
      },
      "actions": [
        {"type": "workspace", "target": 4},
        {"type": "mark", "value": "pwa"}
      ],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "file-manager-workspace-5",
      "match_criteria": {
        "title": {"pattern": "^Yazi:", "match_type": "regex"}
      },
      "actions": [
        {"type": "workspace", "target": 5},
        {"type": "mark", "value": "file-manager"}
      ],
      "priority": "global",
      "focus": false,
      "enabled": true
    },
    {
      "name": "floating-dialogs",
      "match_criteria": {
        "window_type": "dialog"
      },
      "actions": [
        {"type": "float", "enable": true}
      ],
      "priority": "default",
      "focus": false,
      "enabled": true
    },
    {
      "name": "floating-utility-windows",
      "match_criteria": {
        "window_type": "utility"
      },
      "actions": [
        {"type": "float", "enable": true}
      ],
      "priority": "default",
      "focus": false,
      "enabled": true
    }
  ],
  "defaults": {
    "workspace": "current",
    "focus": true
  }
}
```

---

**Feature Version**: 1.0.0
**Last Updated**: 2025-10-22
**Documentation**: `/etc/nixos/specs/024-update-replace-test/`

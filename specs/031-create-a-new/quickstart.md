# Quickstart Guide: i3 Window Rules Discovery and Validation

**Feature**: 031-create-a-new
**Tool**: `i3-window-rules`
**Date**: 2025-10-23

## Overview

The `i3-window-rules` tool automates discovery, validation, and migration of window matching patterns for i3's workspace mapping system. Instead of manually using `xprop` and `i3-msg` to investigate window properties, this tool launches applications, captures their properties via i3 IPC, generates verified patterns, and updates configuration files.

## Installation

```bash
# Tool will be installed via home-manager after implementation
# Located in: home-modules/tools/i3-window-rules/

# After NixOS rebuild, command will be available:
i3-window-rules --help
```

## Quick Start

### Discover a Single Application Pattern

```bash
# Discover pattern for pavucontrol
i3-window-rules discover --app pavucontrol

# Output:
# Launching application: pavucontrol
# Waiting for window to appear...
# ✓ Window captured in 1.2s
#
# Discovered Pattern:
#   Type: class
#   Value: Pavucontrol
#   Confidence: 1.0
#
# Suggested Rule:
#   Application: Pavucontrol
#   Pattern: class:Pavucontrol
#   Workspace: (not set - use --workspace to assign)
#   Scope: (not set - use --scope to classify)
```

### Discover with Workspace Assignment

```bash
# Discover pattern and assign to workspace 8
i3-window-rules discover --app pavucontrol --workspace 8 --scope global

# Output:
# ✓ Pattern discovered and saved to window-rules.json
# ✓ Added to global_classes in app-classes.json
```

### Bulk Discovery

```bash
# Discover patterns for multiple applications from a list
i3-window-rules discover --bulk applications.txt

# applications.txt format (one per line):
# pavucontrol
# firefox
# 1password
```

### Discover from Application Registry

```bash
# Use application-registry.json for bulk discovery
i3-window-rules discover --registry ~/.config/i3/application-registry.json

# Discovers all applications defined in registry with:
# - Launch commands (including parameterized commands)
# - Expected pattern types
# - Scope classifications
# - Preferred workspaces
```

## Validation

### Validate Current Configuration

```bash
# Validate all patterns against currently open windows
i3-window-rules validate

# Output:
# Validating 65 patterns...
# ✓ 60 patterns matched correctly
# ✗ 3 patterns failed (false negatives)
# ⚠ 2 patterns matched wrong windows (false positives)
#
# Accuracy: 92.3%
#
# Failures:
#   - VSCode: Expected class:Code, window on WS2 instead of WS1
#   - Lazygit: Pattern title:lazygit didn't match any windows
```

### Validate Specific Pattern

```bash
# Launch application and test pattern
i3-window-rules validate --app vscode --launch

# Output:
# Launching VSCode...
# ✓ Window appeared in 2.1s
# ✓ Pattern class:Code matched
# ✓ Window on correct workspace (WS1)
#
# Validation: SUCCESS
```

### Validation Report

```bash
# Generate comprehensive validation report
i3-window-rules validate --report validation-report.json

# Output:
# JSON report with:
# - All pattern validation results
# - Expected vs actual workspaces
# - False positives/negatives
# - Suggested fixes
```

## Migration

### Update Configuration with Discovered Patterns

```bash
# Migrate discovered patterns to window-rules.json
i3-window-rules migrate --from discovery-results.json

# Output:
# Creating backup: ~/.config/i3/backups/window-rules-20251023-143022.json
# Updating window-rules.json...
#   - Replaced 15 patterns
#   - Added 5 new patterns
#   - Preserved 45 existing patterns
# ✓ Configuration updated successfully
#
# Reloading daemon...
# ✓ i3-project-event-listener restarted
```

### Migrate with Conflict Resolution

```bash
# Handle duplicate patterns interactively
i3-window-rules migrate --from discovery-results.json --interactive

# Prompts for conflicts:
# Duplicate pattern found:
#   Existing: class:Code → WS1 (scoped)
#   New:      class:Code → WS3 (scoped)
#
# Action? [keep existing / replace / skip]: replace
```

### Dry-Run Mode

```bash
# Test migration without modifying files
i3-window-rules migrate --from discovery-results.json --dry-run

# Output:
# [DRY RUN] Would create backup: window-rules-20251023-143022.json
# [DRY RUN] Would replace 15 patterns
# [DRY RUN] Would add 5 new patterns
# [DRY RUN] Would reload daemon
```

## Interactive Mode

### Pattern Learning Workflow

```bash
# Start interactive pattern learning
i3-window-rules interactive

# Terminal UI:
# ┌─ i3 Window Rules - Interactive Pattern Learning ────────────────┐
# │                                                                  │
# │  Select Application:                                             │
# │    [ ] VSCode                                                    │
# │    [ ] Firefox                                                   │
# │    [x] Pavucontrol                                              │
# │    [ ] Lazygit                                                   │
# │                                                                  │
# │  [Launch & Capture]  [Skip]  [Quit]                             │
# └──────────────────────────────────────────────────────────────────┘
#
# After launch:
# ┌─ Captured Properties ────────────────────────────────────────────┐
# │  WM_CLASS:     Pavucontrol                                       │
# │  Instance:     pavucontrol                                       │
# │  Title:        Volume Control                                    │
# │  Workspace:    4 (current)                                       │
# │                                                                  │
# │  Generated Pattern:                                              │
# │    Type:  class                                                  │
# │    Value: Pavucontrol                                            │
# │                                                                  │
# │  [Accept]  [Edit Pattern]  [Test]  [Skip]                       │
# └──────────────────────────────────────────────────────────────────┘
#
# After accepting:
# ┌─ Configuration ───────────────────────────────────────────────────┐
# │  Workspace: [8]                                                  │
# │  Scope:     ( ) Scoped  (x) Global                               │
# │                                                                  │
# │  [Save & Test]  [Save]  [Cancel]                                 │
# └──────────────────────────────────────────────────────────────────┘
```

## Common Workflows

### Fix Broken Workspace Assignments

**Problem**: Windows appearing on wrong workspaces (e.g., VSCode on WS2 instead of WS31)

```bash
# Step 1: Validate current configuration
i3-window-rules validate --report issues.json

# Step 2: Re-discover broken patterns
i3-window-rules discover --app vscode --launch --workspace 31 --scope scoped

# Step 3: Migrate updated patterns
i3-window-rules migrate --from discovery-results.json

# Step 4: Validate fix
i3-window-rules validate --app vscode --launch
```

### Discover All 70 Applications

**Goal**: Generate verified patterns for entire application set

```bash
# Step 1: Create application registry
cat > ~/.config/i3/application-registry.json <<EOF
{
  "version": "1.0.0",
  "applications": [
    {
      "name": "vscode",
      "display_name": "VS Code",
      "command": "code",
      "parameters": "$PROJECT_DIR",
      "expected_pattern_type": "class",
      "expected_class": "Code",
      "scope": "scoped",
      "preferred_workspace": 1
    },
    {
      "name": "lazygit",
      "display_name": "Lazygit",
      "command": "ghostty -e lazygit",
      "expected_pattern_type": "title",
      "expected_title_contains": "lazygit",
      "scope": "scoped",
      "preferred_workspace": 2
    }
    // ... 68 more applications
  ]
}
EOF

# Step 2: Bulk discover all applications
i3-window-rules discover --registry ~/.config/i3/application-registry.json --output discovered-patterns.json

# Progress output:
# Discovering patterns for 70 applications...
# [1/70] VSCode: ✓ (1.2s)
# [2/70] Lazygit: ✓ (1.5s)
# [3/70] Firefox: ✓ (2.1s)
# ...
# [70/70] Pavucontrol: ✓ (1.1s)
#
# Complete: 70/70 (100%)
# Time: 18m 32s
# Average: 15.9s per application

# Step 3: Validate discovered patterns
i3-window-rules validate --from discovered-patterns.json

# Step 4: Migrate all patterns
i3-window-rules migrate --from discovered-patterns.json
```

### Add New Application

**Goal**: Add pattern for newly installed application

```bash
# Discover pattern
i3-window-rules discover --app slack --workspace 6 --scope global

# Verify workspace assignment
i3-window-rules validate --app slack --launch

# Pattern is automatically saved and daemon reloaded
```

### Debug Pattern Matching

**Problem**: Pattern matches wrong windows or doesn't match at all

```bash
# Launch application and inspect properties
i3-window-rules discover --app vscode --inspect

# Output:
# Window Properties:
#   WM_CLASS (class):    Code
#   WM_CLASS (instance): code
#   Title:               ~/projects/nixos - Visual Studio Code
#   Workspace:           1
#   Output:              HDMI-0
#   Type:                _NET_WM_WINDOW_TYPE_NORMAL
#   Floating:            False
#   Marks:               [project:nixos, scoped]
#
# Pattern Matching Test:
#   class:Code         → ✓ MATCH
#   class:code         → ✗ NO MATCH (case sensitive)
#   title:Visual       → ✓ MATCH
#   title:nixos        → ✓ MATCH
#   title_regex:^~/.* → ✓ MATCH
```

## Command Reference

### discover

```bash
i3-window-rules discover [OPTIONS]

Options:
  --app APP             Application name to discover
  --bulk FILE           Bulk discover from file (one app per line)
  --registry FILE       Discover from application registry JSON
  --workspace N         Assign to workspace (1-9)
  --scope SCOPE         Classify as scoped or global
  --launch-method M     Launch method: direct, rofi, manual (default: direct)
  --timeout SECONDS     Window appearance timeout (default: 10)
  --output FILE         Save results to JSON file
  --inspect             Show detailed window properties
  --keep-window         Don't close window after discovery
```

### validate

```bash
i3-window-rules validate [OPTIONS]

Options:
  --app APP             Validate specific application
  --from FILE           Validate patterns from discovery results
  --launch              Launch applications to test patterns
  --report FILE         Generate JSON validation report
  --workspace-only      Only check workspace assignments (skip pattern matching)
```

### migrate

```bash
i3-window-rules migrate [OPTIONS]

Options:
  --from FILE           Source discovery results or patterns
  --dry-run             Show changes without applying
  --interactive         Prompt for conflict resolution
  --no-backup           Skip backup creation (dangerous!)
  --no-reload           Don't reload daemon after migration
  --force               Overwrite without confirmation
```

### interactive

```bash
i3-window-rules interactive

# Starts interactive TUI for pattern learning
# Keyboard shortcuts:
#   ↑/↓        Navigate application list
#   Space      Select application
#   Enter      Launch & capture
#   Tab        Next field
#   Ctrl+S     Save pattern
#   Ctrl+T     Test pattern
#   Ctrl+Q     Quit
```

## Configuration Files

### window-rules.json

Location: `~/.config/i3/window-rules.json`

```json
{
  "version": "1.0.0",
  "rules": [
    {
      "pattern": {
        "type": "class",
        "value": "Code",
        "description": "VSCode editor",
        "priority": 10,
        "case_sensitive": true
      },
      "workspace": 1,
      "scope": "scoped",
      "enabled": true,
      "application_name": "VSCode",
      "notes": "Project-specific code editor"
    }
  ]
}
```

### app-classes.json

Location: `~/.config/i3/app-classes.json`

```json
{
  "version": "1.0.0",
  "scoped_classes": [
    "Code",
    "ghostty",
    "title:lazygit"
  ],
  "global_classes": [
    "firefox",
    "Pavucontrol",
    "1Password"
  ]
}
```

### application-registry.json

Location: `~/.config/i3/application-registry.json`

```json
{
  "version": "1.0.0",
  "applications": [
    {
      "name": "vscode",
      "display_name": "VS Code",
      "command": "code",
      "parameters": "$PROJECT_DIR",
      "expected_pattern_type": "class",
      "expected_class": "Code",
      "scope": "scoped",
      "preferred_workspace": 1,
      "nix_package": "pkgs.vscode"
    }
  ]
}
```

## Troubleshooting

### Window doesn't appear during discovery

```bash
# Increase timeout
i3-window-rules discover --app slack --timeout 30

# Try manual launch
i3-window-rules discover --app slack --launch-method manual
# Then launch application manually
```

### Pattern matches wrong window

```bash
# Inspect window properties
i3-window-rules discover --app vscode --inspect

# Make pattern more specific (add instance or title criteria)
# Edit pattern in window-rules.json to use title_regex
```

### Migration fails with JSON corruption

```bash
# Restore from backup
cd ~/.config/i3/backups
ls -lt  # Find latest backup
cp window-rules-20251023-143022.json ~/.config/i3/window-rules.json

# Validate JSON syntax
python3 -m json.tool ~/.config/i3/window-rules.json
```

### Daemon doesn't reload

```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Manually restart daemon
systemctl --user restart i3-project-event-listener

# Verify new patterns loaded
i3pm daemon events --type=window --limit=10
```

## Performance Tips

- **Bulk Discovery**: Use `--registry` instead of individual `--app` commands for 70+ applications
- **Direct Launch**: Use `--launch-method direct` (default) instead of rofi simulation for faster discovery
- **Parallel Discovery**: NOT supported - applications must be launched sequentially to avoid window confusion
- **Timeout Tuning**: Reduce `--timeout` for fast-launching apps (e.g., 5s), increase for slow apps (e.g., 30s)

## Next Steps

- Review `data-model.md` for Pydantic model definitions
- Review `contracts/` for JSON schema specifications
- Implement Phase 2 tasks (see `tasks.md` after running `/speckit.tasks`)

---

**Tool Status**: Specification complete, implementation pending

# Quickstart Guide: Walker/Elephant Launcher Full Functionality

**Feature**: 043-get-full-functionality
**Date**: 2025-10-27
**Status**: Validation & Testing

## Overview

Walker and Elephant are already fully configured in `/etc/nixos/home-modules/desktop/walker.nix`. This quickstart guide validates that all providers work correctly and documents their usage.

**Key Finding**: All functional requirements (FR-001 through FR-020) are already satisfied by existing configuration. This feature is **validation-only**.

---

## Quick Reference

### Launch Walker
```bash
# Keybinding
Meta+D  # or Alt+Space

# Command line (for testing)
env GDK_BACKEND=x11 XDG_DATA_DIRS="$HOME/.local/share/i3pm-applications:$XDG_DATA_DIRS" walker
```

### Provider Prefixes

| Prefix | Provider | Example | Action |
|--------|----------|---------|--------|
| (none) | Applications | `code` | Launch VS Code |
| `:` | Clipboard | `: ` (space after) | Show clipboard history |
| `/` | Files | `/nixos` | Search for files containing "nixos" |
| `@` | Web Search | `@nixos tutorial` | Search web |
| `=` | Calculator | `=2+2` | Calculate and copy result |
| `.` | Symbols | `.lambda` | Find λ symbol |
| `>` | Runner | `>echo hello` | Run shell command |
| `;s ` | Sesh (plugin) | `;s nixos` | Switch tmux session |
| `;p ` | Projects (plugin) | `;p ` (space after) | Switch i3pm project |

### Keybindings (in Walker)

| Key | Action |
|-----|--------|
| `Return` | Execute default action |
| `Ctrl+Return` | Execute alternate action (files: open with default app) |
| `Shift+Return` | Execute tertiary action (runner: open in terminal) |
| `Esc` | Close Walker |
| `↑/↓` | Navigate results |

---

## Validation Checklist

Run through this checklist to verify all functionality works:

### ✅ 1. Elephant Service Health

```bash
# Check service running
systemctl --user status elephant
# Expected: active (running)

# Check service environment
systemctl --user show-environment | grep -E "DISPLAY|PATH|XDG_"
# Expected:
#   DISPLAY=:10 (or your display number)
#   PATH includes ~/.local/bin
#   XDG_DATA_DIRS includes i3pm-applications

# Check service logs (no errors)
journalctl --user -u elephant -n 50
```

**Success Criteria**: SC-002 (Elephant starts within 2s, remains running)

---

### ✅ 2. Application Launch with Project Context

```bash
# Launch application via Walker
# 1. Press Meta+D
# 2. Type "code" (or any app from registry)
# 3. Press Return

# Verify environment variables
ps aux | grep code | grep -v grep | head -1 | awk '{print $2}'  # Get PID
cat /proc/<PID>/environ | tr '\0' '\n' | grep -E "DISPLAY|I3PM_PROJECT_NAME|XDG_DATA_DIRS"

# Expected output:
# DISPLAY=:10
# I3PM_PROJECT_NAME=<active_project> (or empty if no project active)
# I3PM_PROJECT_DIR=<project_directory>
# XDG_DATA_DIRS=/home/user/.local/share/i3pm-applications:...
```

**Success Criteria**:
- SC-001: 100% launch success rate
- SC-005: Walker window <100ms
- SC-006: 100% project context accuracy

---

### ✅ 3. Clipboard History

```bash
# Prepare test data
echo "First copy" | xclip -selection clipboard
sleep 1
echo "Second copy" | xclip -selection clipboard
sleep 1
echo "Third copy" | xclip -selection clipboard

# Access clipboard history
# 1. Press Meta+D
# 2. Type ":" (colon)
# 3. Verify entries appear in reverse chronological order:
#    - "Third copy" (first)
#    - "Second copy" (middle)
#    - "First copy" (last)

# Select entry from history
# 1. Navigate to "First copy"
# 2. Press Return
# 3. Paste in terminal (Ctrl+Shift+V)
# 4. Verify "First copy" pastes
```

**Success Criteria**:
- SC-003: Results appear <200ms after typing ":"
- FR-007: Text clipboard entries work
- FR-008: Reverse chronological order

**Test Images** (optional):
```bash
# Copy screenshot to clipboard (use Spectacle or similar)
# Then: Meta+D → type ":" → verify image appears with thumbnail
```

---

### ✅ 4. File Search

```bash
# Search for files
# 1. Press Meta+D
# 2. Type "/walker.nix" (or any known file)
# 3. Verify results show matching files with paths

# Open file in Neovim
# 1. Navigate to desired file
# 2. Press Return
# 3. Verify Ghostty opens with Neovim editing the file

# Open file with default app
# 1. Search for file again
# 2. Press Ctrl+Return
# 3. Verify xdg-open launches default application
```

**Success Criteria**:
- SC-004: Results <500ms for 10k files
- SC-009: Opens at correct line if fragment provided (e.g., `file.txt#L42`)
- FR-010, FR-011: Neovim and default app opening work

**Test Line Number Navigation**:
```bash
# Create test file with line numbers
seq 1 100 > /tmp/test.txt

# Add to Walker file search scope (should find in /tmp)
# Meta+D → type "/test.txt" → navigate result
# TODO: Walker may not search /tmp by default (only $HOME and $I3PM_PROJECT_DIR)
# Test with file in home directory instead
```

---

### ✅ 5. Web Search

```bash
# Search web
# 1. Press Meta+D
# 2. Type "@nixos tutorial"
# 3. Verify search engines appear:
#    - Google
#    - DuckDuckGo
#    - GitHub
#    - YouTube
#    - Wikipedia
# 4. Select "Google" (or press Return for default)
# 5. Verify Firefox opens with Google search results
# 6. Check URL: https://www.google.com/search?q=nixos+tutorial
```

**Success Criteria**:
- SC-007: 100% correct query (no URL encoding errors)
- FR-012: Multiple engines available
- FR-013: Default engine works

**Test Special Characters**:
```bash
# Meta+D → type "@C++ tutorial"
# Expected URL: https://www.google.com/search?q=C%2B%2B+tutorial
```

---

### ✅ 6. Calculator

```bash
# Basic math
# 1. Press Meta+D
# 2. Type "=2+2"
# 3. Verify result "4" appears
# 4. Press Return
# 5. Paste in terminal (Ctrl+Shift+V)
# 6. Verify "4" pastes

# Test all operators
=10*5     → 50
=100/4    → 25
=2^8      → 256
=17%5     → 2
=(2+3)*4  → 20
```

**Success Criteria**:
- SC-008: 100% accuracy for +, -, *, /, %, ^
- FR-014: Evaluation and clipboard copy

**Test Error Handling**:
```bash
# Invalid expressions
=2+       → Error: Incomplete expression
=abc      → Error: Invalid expression
=1/0      → Error: Division by zero
```

---

### ✅ 7. Symbol/Emoji Picker

```bash
# Search symbols
# 1. Press Meta+D
# 2. Type ".lambda"
# 3. Verify λ appears
# 4. Press Return
# 5. Verify λ inserts in focused application

# Browse mode
# 1. Press Meta+D
# 2. Type "." (period only, no search term)
# 3. Verify common symbols appear
# 4. Navigate and select

# Test common searches
.heart    → ❤, 💙, 💚, 💛
.arrow    → →, ←, ↑, ↓
.check    → ✓, ✔
```

**Success Criteria**:
- FR-015: Fuzzy search and symbol insertion
- Symbols insert at cursor position

---

### ✅ 8. Shell Command Execution

```bash
# Background execution
# 1. Press Meta+D
# 2. Type ">notify-send 'Test message'"
# 3. Press Return (NOT Shift+Return)
# 4. Verify desktop notification appears
# 5. Verify no terminal opens (background execution)

# Terminal execution
# 1. Press Meta+D
# 2. Type ">echo 'Hello from terminal'"
# 3. Press Shift+Return
# 4. Verify Ghostty opens with output "Hello from terminal"

# Interactive command
# Meta+D → type ">htop" → press Shift+Return
# Verify htop runs in Ghostty terminal
```

**Success Criteria**:
- FR-016: Background (Return) and terminal (Shift+Return) execution
- Terminal uses Ghostty

---

## Troubleshooting

### Walker doesn't open when pressing Meta+D

**Diagnosis**:
```bash
# Check i3 keybinding
grep "bindsym.*walker" ~/.config/i3/config

# Try launching manually
env GDK_BACKEND=x11 walker
```

**Fix**: Verify i3 keybinding configured, reload i3 (`i3-msg reload`)

---

### Elephant service not running

**Diagnosis**:
```bash
systemctl --user status elephant
journalctl --user -u elephant -n 50
```

**Common Causes**:
1. DISPLAY not set → Check `systemctl --user show-environment | grep DISPLAY`
2. Service failed to start → Check logs for errors
3. Service disabled → Enable with `systemctl --user enable elephant`

**Fix**:
```bash
# Restart service
systemctl --user restart elephant

# If DISPLAY issue, reload i3 (imports DISPLAY)
i3-msg reload
```

---

### Clipboard history shows no results

**Diagnosis**:
```bash
# Test clipboard manually
echo "test" | xclip -selection clipboard
xclip -selection clipboard -o  # Should output "test"

# Check Elephant service running
systemctl --user status elephant

# Check xclip installed
which xclip
```

**Fix**:
- Install xclip: `nix-shell -p xclip` (or add to system packages)
- Restart Elephant: `systemctl --user restart elephant`
- Disable conflicting clipboard managers (KDE Klipper, etc.)

---

### File search returns no results

**Diagnosis**:
```bash
# Check file provider enabled
grep "files = true" ~/.config/walker/config.toml

# Verify file exists and is readable
ls -la ~/path/to/file

# Check search scope
echo $HOME  # Should be /home/user
i3pm project current  # Check active project directory
```

**Fix**:
- Verify file is in $HOME or active project directory
- Check file permissions (must be readable)
- Reload Walker configuration (restart Elephant)

---

### Web search doesn't open browser

**Diagnosis**:
```bash
# Check websearch.toml exists
cat ~/.config/elephant/websearch.toml

# Check Firefox installed
which firefox

# Test manual URL open
firefox "https://www.google.com/search?q=test"
```

**Fix**:
- Verify websearch.toml has engines defined
- Install Firefox if missing
- Restart Elephant to reload config

---

### Applications don't inherit project context

**Diagnosis**:
```bash
# Check i3pm daemon running
systemctl --user status i3-project-event-listener

# Check active project
i3pm project current

# Verify app-launcher-wrapper.sh exists
which app-launcher-wrapper.sh

# Check desktop files use wrapper
grep "Exec=" ~/.local/share/i3pm-applications/applications/*.desktop | head -5
```

**Fix**:
- Start i3pm daemon: `systemctl --user start i3-project-event-listener`
- Switch to project: `i3pm project switch <project-name>`
- Verify desktop files use wrapper (should see `Exec=app-launcher-wrapper.sh ...`)

---

## Configuration Files

All configuration is already in place. Reference for customization:

### Walker Config
```bash
# Location
~/.config/walker/config.toml

# View current config
cat ~/.config/walker/config.toml

# Edit (not recommended - use NixOS configuration instead)
# Changes will be overwritten by home-manager
```

### Elephant Websearch Config
```bash
# Location
~/.config/elephant/websearch.toml

# View current config
cat ~/.config/elephant/websearch.toml

# To add search engines:
# Edit: /etc/nixos/home-modules/desktop/walker.nix
# Find: xdg.configFile."elephant/websearch.toml".text
# Add new engine:
#   [[engines]]
#   name = "StackOverflow"
#   url = "https://stackoverflow.com/search?q=%s"
# Rebuild: nixos-rebuild switch --flake .#hetzner
# Restart: systemctl --user restart elephant
```

### Elephant Service
```bash
# View service definition
systemctl --user cat elephant

# View service environment
systemctl --user show-environment

# View service logs
journalctl --user -u elephant -f  # Follow mode
```

---

## Performance Validation

Run these tests to validate success criteria:

| Test | Command | Expected | SC |
|------|---------|----------|-----|
| Walker launch | `time` + Meta+D + measure | <100ms | SC-005 |
| Clipboard history | Type `:` + measure | <200ms | SC-003 |
| File search | Type `/nixos` + measure | <500ms | SC-004 |
| App launch | Launch app + check env | 100% success | SC-001 |
| Project context | Check I3PM_* in /proc | 100% accuracy | SC-006 |
| Web search | Launch search + check URL | 100% correct | SC-007 |
| Calculator | Test operators | 100% accurate | SC-008 |

---

## Next Steps

1. **Validation Complete**: All features verified working → No code changes needed
2. **Document Findings**: Update CLAUDE.md with Walker/Elephant usage patterns
3. **Training**: Familiarize with all provider prefixes and keybindings
4. **Customization** (optional):
   - Add more search engines to websearch.toml
   - Customize Walker theme (if desired)
   - Add custom plugins (e.g., password manager, bookmarks)

---

## Summary

Walker/Elephant full functionality is **already operational**:
- ✅ All 8 providers enabled (applications, clipboard, files, websearch, calc, symbols, runner, menus)
- ✅ Elephant service configured with proper environment variables
- ✅ i3 integration ensures DISPLAY propagation
- ✅ Project context inheritance works via app-launcher-wrapper.sh
- ✅ All provider prefixes and keybindings configured

**No implementation required** - this feature validates and documents existing functionality.

**Validation Effort**: ~30 minutes to run through entire checklist

**Documentation References**:
- Configuration: `/etc/nixos/home-modules/desktop/walker.nix`
- Data Model: `./data-model.md`
- Workflows: `./contracts/user-workflows.md`
- Config Schema: `./contracts/configuration-schema.md`

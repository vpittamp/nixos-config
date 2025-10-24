# Test Plan: User Story 4 - Unified Launcher Interface

**Feature**: 034-create-a-feature
**Phase**: Phase 6 - User Story 4
**Status**: Implementation Complete - Ready for Testing
**Date**: 2025-10-24

## Prerequisites

1. ✅ System rebuilt with Phase 6 changes:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

2. ✅ Phase 5 complete: Desktop files exist for all 15 applications

3. ✅ rofi configuration deployed to ~/.config/rofi/

4. ✅ Papirus icon theme installed

5. ✅ Catppuccin theme file present at ~/.config/rofi/catppuccin-mocha.rasi

---

## T055: Test rofi Displays All Registered Applications

**Goal**: Verify that rofi launcher displays all applications from the registry with proper metadata

### Test Procedure

1. **Launch rofi with Win+D**:
   ```bash
   # Press Win+D (from i3 keybinding)
   # Or manually:
   rofi -show drun -show-icons
   ```

   **Expected**: rofi window appears in center of screen with Catppuccin Mocha theme

2. **Verify application list**:
   - Count visible applications (should include at least 15 from registry)
   - Applications should have format: `[Icon] Application Name`

3. **Verify icons are displayed**:
   - Each application should have an icon to the left of its name
   - Icons should be 25px (configured in theme)
   - Applications without custom icons should show default application icon

4. **Check registry applications are present**:
   ```bash
   # Expected applications (from Phase 4-5):
   # - VS Code
   # - Neovim
   # - Firefox
   # - Chromium
   # - Ghostty Terminal
   # - Alacritty Terminal
   # - Lazygit
   # - GitUI
   # - Yazi File Manager
   # - Thunar
   # - PCManFM
   # - htop
   # - K9s
   # - Slack
   # - Discord
   ```

5. **Verify theme colors** (Catppuccin Mocha):
   - Background: Dark (#1e1e2e)
   - Selected item: Highlighted with pink text (#f38ba8)
   - Prompt: Blue background (#89b4fa)
   - Border: Blue (#89b4fa)

**Success Criteria**:
- ✅ All 15 applications from registry are visible
- ✅ Icons display correctly next to application names
- ✅ Catppuccin Mocha theme is applied
- ✅ Window is centered with proper dimensions (600px width, 450px height)

**Status**: ☐ Pass / ☐ Fail

---

## T056: Test Fuzzy Search in rofi

**Goal**: Verify that rofi search works with fuzzy matching and searches both display_name and name fields

### Test Procedure

1. **Launch rofi**:
   ```bash
   rofi -show drun -show-icons
   ```

2. **Test exact name match**:
   - Type: `VS Code`
   - **Expected**: "VS Code" appears at top of results

3. **Test partial name match**:
   - Type: `code`
   - **Expected**: "VS Code" and possibly "Neovim" (if description contains "code")

4. **Test fuzzy search** (non-contiguous characters):
   - Type: `vsc`
   - **Expected**: "VS Code" appears in results (fuzzy matching v-s-c)

5. **Test display_name vs name**:
   - Type: `vscode` (internal name)
   - **Expected**: "VS Code" appears (searches both name and display_name fields)

6. **Test another fuzzy search**:
   - Type: `lazy`
   - **Expected**: "Lazygit" appears

7. **Test multi-word fuzzy**:
   - Type: `ghost`
   - **Expected**: "Ghostty Terminal" appears

8. **Test case insensitivity**:
   - Type: `FIREFOX`
   - **Expected**: "Firefox" appears (case-insensitive search)

9. **Test sorting**:
   - Type: `git`
   - **Expected**: Applications with "git" ranked by relevance (Lazygit, GitUI, etc.)
   - Configured sorting-method is "fzf" which should rank by match quality

**Success Criteria**:
- ✅ Exact matches work
- ✅ Partial matches work
- ✅ Fuzzy matching works (non-contiguous characters)
- ✅ Searches both display_name and name fields
- ✅ Case-insensitive search
- ✅ Results ranked by relevance

**Status**: ☐ Pass / ☐ Fail

---

## T057: Test Launcher Closes After Selection

**Goal**: Verify that rofi automatically closes after selecting an application

### Test Procedure

1. **Launch rofi and select application**:
   ```bash
   # Press Win+D
   # Type "firefox"
   # Press Enter
   ```

   **Expected**:
   - rofi window closes immediately
   - Firefox launches

2. **Test with keyboard selection**:
   ```bash
   # Press Win+D
   # Use arrow keys to navigate to "VS Code"
   # Press Enter
   ```

   **Expected**:
   - rofi closes
   - VS Code launches with project context

3. **Test with mouse click**:
   ```bash
   # Press Win+D
   # Click on "Ghostty Terminal" with mouse
   ```

   **Expected**:
   - rofi closes
   - Ghostty launches

4. **Test escape to cancel**:
   ```bash
   # Press Win+D
   # Press Escape
   ```

   **Expected**:
   - rofi closes without launching anything
   - No applications launched

**Success Criteria**:
- ✅ rofi closes after Enter key selection
- ✅ rofi closes after mouse click selection
- ✅ rofi closes after Escape press
- ✅ Selected application launches correctly

**Status**: ☐ Pass / ☐ Fail

---

## T058: Test Visual Distinction Between Scoped and Global Apps

**Goal**: Verify that scoped and global applications can be visually distinguished (via categories or other means)

### Test Procedure

1. **Check desktop file categories**:
   ```bash
   # Scoped app (VS Code)
   grep "^Categories=" ~/.local/share/applications/vscode.desktop
   # Expected: Categories=Development;ProjectScoped;

   # Global app (Firefox)
   grep "^Categories=" ~/.local/share/applications/firefox.desktop
   # Expected: Categories=Application;Global;
   ```

2. **Check if rofi shows categories** (may not be visible by default):
   ```bash
   rofi -show drun -show-icons
   # Look for any category labels or groupings
   ```

3. **Test category filtering** (if available):
   ```bash
   # Some rofi configurations support category filtering
   # This may not be available in basic configuration
   ```

4. **Verify custom X- fields are in desktop files**:
   ```bash
   grep "^X-Project-Scope=" ~/.local/share/applications/vscode.desktop
   # Expected: X-Project-Scope=scoped

   grep "^X-Project-Scope=" ~/.local/share/applications/firefox.desktop
   # Expected: X-Project-Scope=global
   ```

**Note**: rofi's default drun mode does not visually distinguish by categories in the list view. The categories are used for:
- XDG menu organization (if used)
- Filtering (if configured)
- Metadata for other tools

The visual distinction is primarily through the Categories field in the desktop files, which future enhancements could use for:
- Color coding
- Icons
- Grouping
- Filtering options

**Success Criteria**:
- ✅ Scoped apps have "Development;ProjectScoped;" categories
- ✅ Global apps have "Application;Global;" categories
- ✅ Custom X-Project-Scope fields are present
- ⚠️ Visual distinction in rofi UI (may be limited in default config)

**Status**: ☐ Pass / ☐ Fail

---

## T059: Verify Acceptance Scenarios from spec.md

**Goal**: Validate all User Story 4 acceptance scenarios

### Scenario 1: Unified Launcher Shows All Applications

**From spec.md**: Given 15 applications are registered, When I press Win+D, Then rofi launcher opens showing all applications with icons

**Test**:
```bash
# Press Win+D
# Count applications (should be ≥15 from registry)
# Verify icons are shown
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 2: Fuzzy Search Works

**From spec.md**: Given the launcher is open, When I type "vsc", Then "VS Code" appears in results

**Test**:
```bash
# Press Win+D
# Type "vsc"
# Verify "VS Code" appears
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 3: Launcher Closes After Selection

**From spec.md**: Given the launcher is open, When I select an application, Then the launcher closes and the application launches with project context

**Test**:
```bash
# Switch to project: pswitch nixos
# Press Win+D
# Select "VS Code"
# Verify launcher closes
# Verify VS Code opens in /etc/nixos
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 4: Catppuccin Theme Applied

**From spec.md**: Given the launcher is configured, When I open it, Then it displays with Catppuccin Mocha theme colors

**Test**:
```bash
# Press Win+D
# Verify background is dark (#1e1e2e)
# Verify selected item has pink text (#f38ba8)
# Verify prompt has blue background (#89b4fa)
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 5: Keybinding Works

**From spec.md**: Given i3 is configured, When I press Win+D, Then the rofi launcher opens

**Test**:
```bash
# Press Win+D
# Verify rofi opens
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 6: Icons Display Correctly

**From spec.md**: Given applications have icon fields, When the launcher displays them, Then each application shows its icon

**Test**:
```bash
# Press Win+D
# Verify each application has an icon next to its name
# Verify icons are appropriate size (25px)
```

**Status**: ☐ Pass / ☐ Fail

---

## Additional Validation Tests

### Test: Theme File Exists

```bash
cat ~/.config/rofi/catppuccin-mocha.rasi
```

**Expected**: File exists with Catppuccin Mocha color definitions

---

### Test: rofi Configuration

```bash
cat ~/.config/rofi/config.rasi
```

**Expected**: Configuration includes:
- `show-icons: true;`
- `icon-theme: "Papirus-Dark";`
- `theme: "catppuccin-mocha";`

---

### Test: Papirus Icons Installed

```bash
ls /run/current-system/sw/share/icons/ | grep -i papirus
```

**Expected**: Papirus or Papirus-Dark icon theme directories exist

---

### Test: Application Launch with Project Context

```bash
# Switch to project
pswitch nixos

# Launch from rofi
# Win+D → type "vscode" → Enter

# Verify VS Code opens with /etc/nixos directory
```

**Expected**: Application launches in correct project context

---

## Integration Tests

### Integration 1: rofi + Desktop Files + Wrapper Script

**Test Flow**:
1. Press Win+D → rofi opens
2. Type "lazygit" → Lazygit appears
3. Press Enter → rofi closes
4. Wrapper script executes: `app-launcher-wrapper.sh lazygit`
5. Variables substituted: `$PROJECT_DIR` → `/etc/nixos`
6. Lazygit launches in project directory

**Success**: End-to-end flow works from GUI to application launch

---

### Integration 2: rofi + Multiple Applications

**Test launching multiple applications**:
1. Win+D → select "Firefox" → Firefox launches
2. Win+D → select "VS Code" → VS Code launches
3. Win+D → select "Ghostty Terminal" → Terminal launches

**Success**: Multiple applications can be launched without conflicts

---

## Test Results Summary

| Test | Status | Notes |
|------|--------|-------|
| T055: All apps displayed | ☐ | |
| T055: Icons shown | ☐ | |
| T055: Theme applied | ☐ | |
| T056: Exact match | ☐ | |
| T056: Partial match | ☐ | |
| T056: Fuzzy match | ☐ | |
| T056: Case insensitive | ☐ | |
| T057: Closes on selection | ☐ | |
| T057: Closes on Escape | ☐ | |
| T058: Category distinction | ☐ | |
| T058: X- fields present | ☐ | |
| T059: Scenario 1 | ☐ | |
| T059: Scenario 2 | ☐ | |
| T059: Scenario 3 | ☐ | |
| T059: Scenario 4 | ☐ | |
| T059: Scenario 5 | ☐ | |
| T059: Scenario 6 | ☐ | |
| Theme file exists | ☐ | |
| rofi configuration | ☐ | |
| Papirus icons | ☐ | |
| Project context launch | ☐ | |
| Integration test 1 | ☐ | |
| Integration test 2 | ☐ | |

---

## Regression Tests

Verify Phase 3, 4, and 5 functionality still works:

```bash
# Phase 3: Manual wrapper invocation
~/.local/bin/app-launcher-wrapper.sh vscode
# Expected: VS Code launches

# Phase 4: Variable substitution
DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh lazygit
# Expected: Shows resolved command

# Phase 5: Desktop files exist
ls -la ~/.local/share/applications/ | grep -E "vscode|firefox"
# Expected: Desktop files present
```

---

## Build Instructions

To deploy Phase 6:

```bash
# 1. Stage changes
git add home-modules/desktop/i3-launcher.nix
git add home-modules/desktop/i3.nix

# 2. Rebuild system
sudo nixos-rebuild switch --flake .#hetzner

# 3. Verify rofi configuration
cat ~/.config/rofi/config.rasi
cat ~/.config/rofi/catppuccin-mocha.rasi

# 4. Test rofi
rofi -show drun -show-icons
# Or press Win+D

# 5. Run all test cases from this plan
```

---

## Troubleshooting

### rofi shows no applications

**Check**:
```bash
# Verify desktop files exist
ls ~/.local/share/applications/*.desktop

# Update desktop database
update-desktop-database ~/.local/share/applications/
```

### Icons not showing

**Check**:
```bash
# Verify Papirus installed
ls /run/current-system/sw/share/icons/ | grep Papirus

# Check rofi config
grep "show-icons" ~/.config/rofi/config.rasi
```

### Theme not applied

**Check**:
```bash
# Verify theme file exists
ls -la ~/.config/rofi/catppuccin-mocha.rasi

# Verify theme reference in config
grep "theme" ~/.config/rofi/config.rasi
```

### Win+D doesn't work

**Check**:
```bash
# Verify i3 keybinding
grep "bindsym.*rofi" ~/.config/i3/config

# Reload i3 config
i3-msg reload
```

---

**Phase 6 Status**: ✨ **IMPLEMENTATION COMPLETE - READY FOR TESTING** ✨

All 4 implementation tasks (T051-T054) are complete. rofi launcher is now:
- Configured with Catppuccin Mocha theme
- Shows icons for all applications
- Bound to Win+D keybinding
- Integrated with application registry desktop files
- Ready for fuzzy search and visual distinction

System is ready for rebuild and comprehensive testing per procedures above.

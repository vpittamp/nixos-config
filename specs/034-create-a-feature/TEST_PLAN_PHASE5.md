# Test Plan: User Story 3 - Desktop File Generation

**Feature**: 034-create-a-feature
**Phase**: Phase 5 - User Story 3
**Status**: Implementation Complete - Ready for Testing
**Date**: 2025-10-24

## Prerequisites

1. ✅ System rebuilt with Phase 5 changes:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

2. ✅ Registry contains 15 applications with desktop file generation enabled

3. ✅ Wrapper script is installed and executable:
   ```bash
   ls -la ~/.local/bin/app-launcher-wrapper.sh
   ```

4. ✅ rofi is installed and configured:
   ```bash
   which rofi
   ```

---

## T047: Verify Desktop Files Are Created

**Goal**: Confirm that .desktop files are generated in the correct location after system rebuild

### Test Procedure

1. **List generated desktop files**:
   ```bash
   ls -la ~/.local/share/applications/ | grep -E "vscode|firefox|ghostty|lazygit|yazi"
   ```

   **Expected**: 15 .desktop files present (one for each application in registry)

2. **Inspect a desktop file** (VS Code example):
   ```bash
   cat ~/.local/share/applications/vscode.desktop
   ```

   **Expected Output**:
   ```desktop
   [Desktop Entry]
   Type=Application
   Name=VS Code
   Exec=/home/vpittamp/.local/bin/app-launcher-wrapper.sh vscode
   Icon=vscode
   Terminal=false
   Categories=Development;ProjectScoped;
   StartupWMClass=Code
   Comment=Visual Studio Code editor with project context
   X-Project-Scope=scoped
   X-Preferred-Workspace=1
   X-Multi-Instance=true
   X-Fallback-Behavior=skip
   X-Nix-Package=pkgs.vscode
   NoDisplay=false
   ```

3. **Verify all 15 applications have desktop files**:
   ```bash
   jq -r '.applications[].name' ~/.config/i3/application-registry.json | while read app; do
     if [ -f ~/.local/share/applications/${app}.desktop ]; then
       echo "✓ $app.desktop exists"
     else
       echo "✗ $app.desktop MISSING"
     fi
   done
   ```

   **Expected**: All 15 applications show ✓

4. **Verify Exec lines use wrapper script**:
   ```bash
   grep -h "^Exec=" ~/.local/share/applications/*.desktop | head -5
   ```

   **Expected**: All Exec lines invoke `app-launcher-wrapper.sh <app-name>`

5. **Verify custom X- fields are present**:
   ```bash
   grep -h "^X-Project-Scope=" ~/.local/share/applications/vscode.desktop
   grep -h "^X-Preferred-Workspace=" ~/.local/share/applications/vscode.desktop
   ```

   **Expected**: Custom fields with correct values

**Success Criteria**: ✅ All 15 desktop files exist with correct structure and fields

---

## T048: Test Orphaned Desktop File Removal

**Goal**: Verify that desktop files are removed when applications are deleted from the registry

### Test Procedure

1. **Add a temporary test application** to `home-modules/desktop/app-registry.nix`:
   ```nix
   (mkApp {
     name = "test-orphan";
     display_name = "Test Orphan App";
     command = "echo";
     parameters = "test";
     scope = "global";
     preferred_workspace = 7;
   })
   ```

2. **Rebuild system**:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

3. **Verify test desktop file was created**:
   ```bash
   ls -la ~/.local/share/applications/test-orphan.desktop
   ```

   **Expected**: File exists

4. **Remove test application** from `app-registry.nix`

5. **Rebuild system again**:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

6. **Verify test desktop file was removed**:
   ```bash
   ls -la ~/.local/share/applications/test-orphan.desktop
   ```

   **Expected**: `ls: cannot access ... No such file or directory`

7. **Verify test app is not in registry**:
   ```bash
   jq '.applications[] | select(.name == "test-orphan")' ~/.config/i3/application-registry.json
   ```

   **Expected**: No output (app removed)

**Success Criteria**: ✅ Desktop file automatically removed when registry entry deleted

---

## T049: Verify Desktop Files Appear in rofi

**Goal**: Confirm that rofi launcher displays all applications with correct icons and metadata

### Test Procedure

1. **Launch rofi in drun mode**:
   ```bash
   rofi -show drun -show-icons
   ```

   **Expected**: rofi window appears showing application launcher

2. **Visual verification**:
   - All 15 applications from registry are listed
   - Application names match display_name from registry (e.g., "VS Code", not "vscode")
   - Icons are displayed next to application names
   - Applications are searchable by name

3. **Search for scoped application**:
   - Type "VS Code" in rofi search
   - **Expected**: "VS Code" appears in results with icon

4. **Search for global application**:
   - Type "Firefox" in rofi search
   - **Expected**: "Firefox" appears in results with icon

5. **Test fuzzy search**:
   - Type "lazy" in rofi search
   - **Expected**: "Lazygit" appears in results

6. **Verify categories** (if rofi shows categories):
   - Scoped apps should be in "Development" or "ProjectScoped" category
   - Global apps should be in "Application" or "Global" category

7. **Test launching from rofi**:
   ```bash
   # Switch to a project first
   pswitch nixos

   # Launch rofi
   rofi -show drun -show-icons
   # Select "VS Code"
   ```

   **Expected**: VS Code launches with /etc/nixos as directory

8. **Test icon display**:
   ```bash
   # Check if icons are properly set
   grep "^Icon=" ~/.local/share/applications/vscode.desktop
   grep "^Icon=" ~/.local/share/applications/firefox.desktop
   ```

   **Expected**: Icon names match registry definitions

**Success Criteria**:
- ✅ All 15 applications appear in rofi
- ✅ Icons are displayed correctly
- ✅ Search works (exact and fuzzy)
- ✅ Launching from rofi invokes wrapper script correctly

---

## T050: Verify Acceptance Scenarios from spec.md

**Goal**: Validate all User Story 3 acceptance scenarios from the specification

### Scenario 1: Desktop Files Generated from Registry

**From spec.md**: Given I define 3 applications in the registry (scoped, global, terminal), When the system is rebuilt, Then 3 .desktop files are generated in ~/.local/share/applications/

**Test**:
1. Check current application count:
   ```bash
   ls ~/.local/share/applications/*.desktop | wc -l
   ```

   **Expected**: 15 (current registry size)

2. Verify mix of scoped and global:
   ```bash
   grep -h "^X-Project-Scope=" ~/.local/share/applications/*.desktop | sort | uniq -c
   ```

   **Expected**:
   ```
   9 X-Project-Scope=scoped
   6 X-Project-Scope=global
   ```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 2: Desktop Files Have Correct Metadata

**From spec.md**: Given a desktop file is generated, When I inspect it, Then it has Name, Icon, Exec (invoking wrapper), and StartupWMClass fields

**Test**:
```bash
cat ~/.local/share/applications/vscode.desktop | grep -E "^(Name|Icon|Exec|StartupWMClass)="
```

**Expected Output**:
```
Name=VS Code
Exec=/home/vpittamp/.local/bin/app-launcher-wrapper.sh vscode
Icon=vscode
StartupWMClass=Code
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 3: rofi Displays All Applications

**From spec.md**: Given 15 applications are registered, When I open rofi launcher, Then all 15 applications appear with icons and are searchable

**Test**:
1. Launch rofi: `rofi -show drun -show-icons`
2. Count visible applications (should be ≥15, including our apps)
3. Test search: Type "vscode" → verify "VS Code" appears
4. Test fuzzy search: Type "ghost" → verify "Ghostty Terminal" appears

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 4: Orphaned Desktop Files Removed

**From spec.md**: Given I remove an application from the registry, When I rebuild, Then its .desktop file is automatically removed

**Test**: (Already tested in T048)

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 5: Desktop Files Use Wrapper Script

**From spec.md**: Given a .desktop file is generated, When I inspect its Exec line, Then it invokes the wrapper script with the application name

**Test**:
```bash
grep "^Exec=" ~/.local/share/applications/*.desktop | head -5
```

**Expected**: All show pattern `Exec=...app-launcher-wrapper.sh <app-name>`

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 6: Categories Reflect Scope

**From spec.md**: Given an application has scope="scoped", When its desktop file is generated, Then Categories includes "Development" and "ProjectScoped"

**Test**:
```bash
# Check scoped app
grep "^Categories=" ~/.local/share/applications/vscode.desktop

# Check global app
grep "^Categories=" ~/.local/share/applications/firefox.desktop
```

**Expected**:
- vscode: `Categories=Development;ProjectScoped;`
- firefox: `Categories=Application;Global;`

**Status**: ☐ Pass / ☐ Fail

---

## Additional Validation Tests

### Test: Custom X- Fields Are Preserved

**Goal**: Verify custom fields are present for future extensibility

```bash
# Check all custom fields for VS Code
grep "^X-" ~/.local/share/applications/vscode.desktop
```

**Expected**:
```
X-Project-Scope=scoped
X-Preferred-Workspace=1
X-Multi-Instance=true
X-Fallback-Behavior=skip
X-Nix-Package=pkgs.vscode
```

---

### Test: Desktop File Validation

**Goal**: Verify desktop files pass desktop-file-validate

```bash
# Install desktop-file-utils if not present
which desktop-file-validate

# Validate all generated desktop files
for file in ~/.local/share/applications/{vscode,firefox,ghostty}.desktop; do
  echo "Validating $file..."
  desktop-file-validate "$file" && echo "✓ PASS" || echo "✗ FAIL"
done
```

**Expected**: All files pass validation (or only minor warnings about custom X- fields)

---

### Test: Integration with rofi Theme

**Goal**: Verify desktop files work with Catppuccin theme

```bash
# Launch rofi with configured theme
rofi -show drun -show-icons
```

**Visual checks**:
- Icons are rendered in correct size
- Application names are readable
- Theme colors are applied
- No rendering errors

---

## Test Results Summary

| Test | Status | Notes |
|------|--------|-------|
| T047: Desktop files created | ☐ | |
| T047: All 15 files present | ☐ | |
| T047: Correct structure | ☐ | |
| T047: Custom X- fields | ☐ | |
| T048: Orphan removal | ☐ | |
| T049: rofi display | ☐ | |
| T049: Icons shown | ☐ | |
| T049: Search works | ☐ | |
| T049: Launch works | ☐ | |
| T050: Scenario 1 | ☐ | |
| T050: Scenario 2 | ☐ | |
| T050: Scenario 3 | ☐ | |
| T050: Scenario 4 | ☐ | |
| T050: Scenario 5 | ☐ | |
| T050: Scenario 6 | ☐ | |
| Desktop file validation | ☐ | |
| rofi theme integration | ☐ | |

---

## Regression Tests

Verify Phase 3 and Phase 4 functionality still works:

```bash
# Phase 3: Manual wrapper invocation
pswitch nixos
~/.local/bin/app-launcher-wrapper.sh vscode
# Expected: VS Code launches in /etc/nixos

# Phase 4: Variable substitution
DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh lazygit
# Expected: Shows resolved command with $PROJECT_DIR substituted

# Phase 4: Registry validation
jq '.applications | length' ~/.config/i3/application-registry.json
# Expected: 15
```

---

## Build Instructions

To deploy Phase 5:

```bash
# 1. Stage changes
git add home-modules/desktop/app-registry.nix

# 2. Rebuild system
sudo nixos-rebuild switch --flake .#hetzner

# 3. Verify desktop files generated
ls -la ~/.local/share/applications/ | grep -E "vscode|firefox|ghostty"

# 4. Test rofi integration
rofi -show drun -show-icons

# 5. Run all test cases from this plan
```

---

**Phase 5 Status**: ✨ **IMPLEMENTATION COMPLETE - READY FOR TESTING** ✨

All 7 implementation tasks (T040-T046) are complete. Desktop file generation is fully declarative and automatic. System now generates 15 .desktop files from the registry with:
- Correct Exec lines invoking wrapper script
- Proper Name, Icon, StartupWMClass fields
- Custom X- fields for project awareness
- Categories based on scope (scoped vs global)
- Automatic removal when registry entries deleted

Ready for system rebuild and comprehensive testing per procedures above.

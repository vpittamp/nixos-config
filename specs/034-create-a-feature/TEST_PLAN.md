# Test Plan: User Story 1 - Project-Aware Application Launching

**Feature**: 034-create-a-feature
**Phase**: Phase 3 - User Story 1 (MVP)
**Status**: Ready for Testing
**Date**: 2025-10-24

## Prerequisites

Before running these tests, ensure:

1. ✅ System has been rebuilt with new configuration:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

2. ✅ Registry file exists and is valid:
   ```bash
   cat ~/.config/i3/application-registry.json | jq .
   ```

3. ✅ Wrapper script is installed and executable:
   ```bash
   ls -la ~/.local/bin/app-launcher-wrapper.sh
   ```

4. ✅ i3pm daemon is running:
   ```bash
   systemctl --user status i3-project-event-listener
   ```

5. ✅ Test applications are installed:
   ```bash
   which code  # VS Code
   which ghostty  # Ghostty terminal
   which firefox  # Firefox
   ```

---

## T027: Test Manual Wrapper Invocation (Project Active)

**Goal**: Verify wrapper script launches applications with project context

### Test Case 1: VS Code with nixos project

**Setup**:
```bash
# Activate nixos project
i3pm project switch nixos
# or: pswitch nixos

# Verify project is active
i3pm project current
# Expected output: nixos (/etc/nixos)
```

**Test**:
```bash
# Enable debug mode to see variable substitution
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh vscode
```

**Expected Behavior**:
- ✅ Script queries daemon successfully
- ✅ PROJECT_DIR is set to /etc/nixos
- ✅ Variable $PROJECT_DIR is substituted in parameters
- ✅ VS Code launches with command: `code /etc/nixos`
- ✅ VS Code opens with /etc/nixos as workspace

**Verification**:
```bash
# Check launch log
tail -20 ~/.local/state/app-launcher.log

# Expected log entries:
# [timestamp] INFO Launching: vscode
# [timestamp] DEBUG Project name: nixos
# [timestamp] DEBUG Project directory: /etc/nixos
# [timestamp] DEBUG Substituted $PROJECT_DIR -> /etc/nixos
# [timestamp] INFO Resolved command: code /etc/nixos
```

**Success Criteria**: VS Code opens to /etc/nixos directory without manual navigation

---

### Test Case 2: Ghostty Terminal with nixos project

**Setup**: Same as Test Case 1 (nixos project active)

**Test**:
```bash
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh ghostty
```

**Expected Behavior**:
- ✅ $SESSION_NAME substituted to "nixos"
- ✅ Ghostty launches with: `ghostty -e sesh nixos`
- ✅ Terminal opens with sesh session for nixos project

**Success Criteria**: Terminal opens with correct sesh session

---

### Test Case 3: Firefox (Global Application)

**Setup**: Any project state (doesn't matter for global apps)

**Test**:
```bash
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh firefox
```

**Expected Behavior**:
- ✅ No parameters (empty string)
- ✅ Firefox launches with: `firefox`
- ✅ No project context used

**Success Criteria**: Firefox opens normally, ignores project context

---

## T028: Test Wrapper Without Active Project (Fallback Behaviors)

**Goal**: Verify fallback behaviors when no project is active

### Test Case 1: VS Code with "skip" fallback (no project)

**Setup**:
```bash
# Clear active project
i3pm project clear
# or: pclear

# Verify no project active
i3pm project current
# Expected: "No project active" or similar
```

**Test**:
```bash
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh vscode
```

**Expected Behavior**:
- ✅ Wrapper detects no project active
- ✅ Applies "skip" fallback (removes $PROJECT_DIR parameter)
- ✅ VS Code launches with: `code` (no arguments)
- ✅ VS Code opens with last workspace or welcome screen

**Verification**:
```bash
tail -20 ~/.local/state/app-launcher.log | grep -i fallback
# Expected: "WARN No project active for vscode, applying fallback: skip"
```

**Success Criteria**: VS Code opens without error, uses default behavior

---

### Test Case 2: Yazi with "use_home" fallback (no project)

**Setup**: Same as Test Case 1 (no project active)

**Test**:
```bash
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh yazi
```

**Expected Behavior**:
- ✅ Wrapper detects no project active
- ✅ Applies "use_home" fallback (substitutes $HOME for $PROJECT_DIR)
- ✅ Yazi launches with: `yazi /home/vpittamp` (or your home directory)
- ✅ Yazi opens in home directory

**Success Criteria**: Yazi opens to home directory instead of failing

---

### Test Case 3: Lazygit with "error" fallback (no project)

**Setup**: Same as Test Case 1 (no project active)

**Test**:
```bash
~/.local/bin/app-launcher-wrapper.sh lazygit
```

**Expected Behavior**:
- ✅ Wrapper detects no project active
- ✅ Recognizes "error" fallback behavior
- ✅ Displays error message about requiring project context
- ✅ Exit code 1 (error)
- ✅ Lazygit does NOT launch

**Verification**:
```bash
echo $?  # Should be 1 (error exit code)

tail -20 ~/.local/state/app-launcher.log | grep -i error
# Expected: "ERROR No project active and fallback behavior is 'error'"
```

**Success Criteria**: Script exits with error, provides clear message about needing project

---

## T029: Test Project with Spaces in Directory Path

**Goal**: Verify variable substitution handles special characters safely

### Test Case 1: Create test project with spaces

**Setup**:
```bash
# Create test directory with spaces
mkdir -p "$HOME/Test Projects/my-app"
cd "$HOME/Test Projects/my-app"
git init

# Create test project
i3pm project create \
  --name test-spaces \
  --dir "$HOME/Test Projects/my-app" \
  --display-name "Test Spaces" \
  --icon ""

# Activate test project
i3pm project switch test-spaces
```

**Test**:
```bash
DEBUG=1 ~/.local/bin/app-launcher-wrapper.sh vscode
```

**Expected Behavior**:
- ✅ PROJECT_DIR is correctly set to path with spaces
- ✅ Variable substitution preserves spaces
- ✅ Argument array prevents word splitting
- ✅ VS Code launches with: `code "/home/vpittamp/Test Projects/my-app"`
- ✅ VS Code opens correct directory despite spaces

**Success Criteria**: VS Code opens to directory with spaces, no path errors

---

### Test Case 2: Path with dollar sign (literal)

**Setup**:
```bash
# Create directory with dollar sign in name
mkdir -p /tmp/test-\$project
cd /tmp/test-\$project
git init

# Create test project
i3pm project create \
  --name test-dollar \
  --dir "/tmp/test-\$project" \
  --display-name "Test Dollar" \
  --icon ""

i3pm project switch test-dollar
```

**Test**:
```bash
DEBUG=1 DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh vscode
```

**Expected Behavior**:
- ✅ Literal dollar sign in path is preserved
- ✅ No variable expansion of literal $project in path
- ✅ Command resolves to: `code /tmp/test-$project`

**Success Criteria**: Literal dollar signs in paths are not treated as variables

---

## T030: Verify All Acceptance Scenarios from Spec

**Goal**: Complete acceptance criteria validation from spec.md

### Acceptance Scenario 1: VS Code in nixos project

**Spec Reference**: spec.md User Story 1, Scenario 1

**Given**: I have the "nixos" project active with directory `/etc/nixos`

**When**: I launch the application launcher and select "VS Code"

**Then**: VS Code opens with `/etc/nixos` as the workspace directory

**Test**:
```bash
# Setup
pswitch nixos

# Execute
~/.local/bin/app-launcher-wrapper.sh vscode

# Verify
# - VS Code window appears
# - File tree shows /etc/nixos contents
# - Title bar shows /etc/nixos path
```

**Status**: ☐ Pass / ☐ Fail

---

### Acceptance Scenario 2: Ghostty in stacks project

**Spec Reference**: spec.md User Story 1, Scenario 2

**Given**: I have the "stacks" project active with directory `~/projects/stacks`

**When**: I launch "Ghostty Terminal"

**Then**: Ghostty opens with a sesh session named "stacks" in the `~/projects/stacks` directory

**Test**:
```bash
# Setup
pswitch stacks  # If stacks project exists

# Execute
~/.local/bin/app-launcher-wrapper.sh ghostty

# Verify
# - Ghostty opens
# - Session name is "stacks" (check with: echo $SESH_SESSION or similar)
# - Current directory is ~/projects/stacks (check with: pwd)
```

**Status**: ☐ Pass / ☐ Fail

---

### Acceptance Scenario 3: VS Code with no active project

**Spec Reference**: spec.md User Story 1, Scenario 3

**Given**: I have no active project (global mode)

**When**: I launch "VS Code"

**Then**: VS Code opens without any directory specified, using its default behavior

**Test**:
```bash
# Setup
pclear  # Clear active project

# Execute
~/.local/bin/app-launcher-wrapper.sh vscode

# Verify
# - VS Code opens
# - Shows welcome screen or last workspace
# - No directory in title bar
```

**Status**: ☐ Pass / ☐ Fail

---

### Acceptance Scenario 4: Firefox (global application)

**Spec Reference**: spec.md User Story 1, Scenario 4

**Given**: I have the "nixos" project active

**When**: I launch a global application like Firefox

**Then**: Firefox opens normally without any project context (no directory parameters)

**Test**:
```bash
# Setup
pswitch nixos

# Execute
~/.local/bin/app-launcher-wrapper.sh firefox

# Verify
# - Firefox opens
# - Behaves identically to manual `firefox` command
# - No project-specific behavior
```

**Status**: ☐ Pass / ☐ Fail

---

## Dry-Run Testing

Before running actual launches, use DRY_RUN mode to verify command resolution:

```bash
# Test each application in dry-run mode
for app in vscode ghostty firefox lazygit yazi; do
  echo "=== Testing: $app ==="
  DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh "$app"
  echo ""
done
```

**Expected Output** (example for vscode with nixos project):
```
[DRY RUN] Would execute:
  Command: code
  Arguments: /etc/nixos
  Project: nixos (/etc/nixos)
  Full command: code /etc/nixos
```

---

## Troubleshooting

### Issue: Registry file not found

**Error**: `Registry file not found: /home/user/.config/i3/application-registry.json`

**Solution**:
```bash
# Rebuild system to generate registry
sudo nixos-rebuild switch --flake .#hetzner

# Verify registry exists
cat ~/.config/i3/application-registry.json | jq .
```

---

### Issue: Daemon not responding

**Error**: `Failed to query daemon`

**Solution**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# Restart daemon if needed
systemctl --user restart i3-project-event-listener

# Verify daemon responds
i3pm daemon status
```

---

### Issue: Command not found

**Error**: `Command not found: code`

**Solution**:
```bash
# Check if package is installed
which code

# If not installed, ensure package is in home.packages or install manually
# For testing, you can temporarily set a valid command in registry
```

---

## Test Results Summary

| Test | Status | Notes |
|------|--------|-------|
| T027: VS Code with project | ☐ | |
| T027: Ghostty with project | ☐ | |
| T027: Firefox global | ☐ | |
| T028: VS Code skip fallback | ☐ | |
| T028: Yazi use_home fallback | ☐ | |
| T028: Lazygit error fallback | ☐ | |
| T029: Path with spaces | ☐ | |
| T029: Path with dollar sign | ☐ | |
| T030: Scenario 1 (VS Code) | ☐ | |
| T030: Scenario 2 (Ghostty) | ☐ | |
| T030: Scenario 3 (No project) | ☐ | |
| T030: Scenario 4 (Firefox) | ☐ | |

---

## Next Steps After Testing

1. ✅ Mark T027-T030 as complete in tasks.md
2. ✅ Document any bugs or issues found
3. ✅ Move to Phase 4: User Story 2 (Declarative Registry)
4. ✅ Continue with remaining implementation phases

---

**Testing Responsibility**: These tests should be executed after system rebuild by the user or CI/CD system.

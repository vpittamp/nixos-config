# Test Plan: User Story 2 - Declarative Registry with Variables

**Feature**: 034-create-a-feature
**Phase**: Phase 4 - User Story 2
**Status**: Ready for Testing
**Date**: 2025-10-24

## Prerequisites

1. ✅ System rebuilt with Phase 4 changes:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner
   ```

2. ✅ Registry contains 15 applications:
   ```bash
   jq '.applications | length' ~/.config/i3/application-registry.json
   # Expected: 15
   ```

3. ✅ Verify validation is active:
   ```bash
   cat /etc/nixos/home-modules/desktop/app-registry.nix | grep validateParameters
   ```

---

## T036: Test Adding New Application Without Code Changes

**Goal**: Verify that adding an application to registry and rebuilding works without modifying any code

### Test Procedure

1. **Add a new application** to `home-modules/desktop/app-registry.nix`:

```nix
(mkApp {
  name = "test-app";
  display_name = "Test Application";
  command = "echo";
  parameters = "Testing from $PROJECT_NAME in $PROJECT_DIR";
  scope = "scoped";
  expected_class = "TestApp";
  preferred_workspace = 7;
  icon = "applications-other";
  nix_package = "pkgs.coreutils";
  multi_instance = true;
  fallback_behavior = "skip";
  description = "Test application for validation";
})
```

2. **Rebuild system**:
```bash
sudo nixos-rebuild switch --flake .#hetzner
```

3. **Verify application appears in registry**:
```bash
jq '.applications[] | select(.name == "test-app")' ~/.config/i3/application-registry.json
```

Expected output:
```json
{
  "name": "test-app",
  "display_name": "Test Application",
  "command": "echo",
  "parameters": "Testing from $PROJECT_NAME in $PROJECT_DIR",
  ...
}
```

4. **Test launching** (with active project):
```bash
pswitch nixos
DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh test-app
```

Expected output:
```
[DRY RUN] Would execute:
  Command: echo
  Arguments: Testing from nixos in /etc/nixos
  Project: nixos (/etc/nixos)
```

5. **Actual launch** (verify it works):
```bash
~/.local/bin/app-launcher-wrapper.sh test-app
```

Expected: Prints "Testing from nixos in /etc/nixos"

**Success Criteria**: ✅ New application works without touching wrapper script or any TypeScript code

---

## T037: Test All Variable Substitutions

**Goal**: Verify all 7 variables substitute correctly in different contexts

### Test Case 1: All project variables (with active project)

**Setup**:
```bash
pswitch nixos
```

**Create test application** (add to registry):
```nix
(mkApp {
  name = "var-test-all";
  display_name = "Variable Test All";
  command = "echo";
  parameters = "NAME=$PROJECT_NAME DIR=$PROJECT_DIR SESSION=$SESSION_NAME WS=$WORKSPACE HOME=$HOME DISPLAY=$PROJECT_DISPLAY_NAME ICON=$PROJECT_ICON";
  scope = "scoped";
  preferred_workspace = 5;
  fallback_behavior = "skip";
})
```

**Rebuild and test**:
```bash
sudo nixos-rebuild switch --flake .#hetzner
~/.local/bin/app-launcher-wrapper.sh var-test-all
```

**Expected Output**:
```
NAME=nixos DIR=/etc/nixos SESSION=nixos WS=5 HOME=/home/vpittamp DISPLAY=NixOS ICON=
```

**Success Criteria**: ✅ All variables substituted correctly

---

### Test Case 2: $WORKSPACE in parameters

**Create test with workspace variable**:
```nix
(mkApp {
  name = "ws-test";
  display_name = "Workspace Test";
  command = "echo";
  parameters = "Target workspace is $WORKSPACE";
  preferred_workspace = 3;
})
```

**Test**:
```bash
sudo nixos-rebuild switch --flake .#hetzner
~/.local/bin/app-launcher-wrapper.sh ws-test
```

**Expected**: "Target workspace is 3"

---

### Test Case 3: Variables with fallback behaviors

**Test skip fallback** (removes project variables):
```bash
pclear  # No active project
~/.local/bin/app-launcher-wrapper.sh var-test-all
```

**Expected**: `NAME= DIR= SESSION= WS=5 HOME=/home/vpittamp DISPLAY= ICON=`
(Project variables removed, non-project variables preserved)

**Test use_home fallback**:
```bash
pclear
~/.local/bin/app-launcher-wrapper.sh yazi  # Has use_home fallback
```

**Expected**: Yazi launches with $HOME substituted for $PROJECT_DIR

---

## T038: Test Parameter Safety (Metacharacter Blocking)

**Goal**: Verify build fails when parameters contain shell metacharacters

### Test Case 1: Semicolon (command separator)

**Add malicious application** to registry:
```nix
(mkApp {
  name = "malicious-semicolon";
  command = "echo";
  parameters = "hello; rm -rf ~";  # Should be blocked!
  scope = "global";
})
```

**Attempt rebuild**:
```bash
sudo nixos-rebuild switch --flake .#hetzner
```

**Expected Behavior**:
- ❌ Build FAILS
- Error message: `Invalid parameters 'hello; rm -rf ~': contains shell metacharacters (;|&`)`
- System remains on previous configuration

**Success Criteria**: ✅ Build fails with clear error message

---

### Test Case 2: Pipe (command chaining)

**Add to registry**:
```nix
(mkApp {
  name = "malicious-pipe";
  command = "echo";
  parameters = "test | cat /etc/passwd";
})
```

**Expected**: Build fails with error about pipe character

---

### Test Case 3: Command substitution

**Add to registry**:
```nix
(mkApp {
  name = "malicious-subst";
  command = "echo";
  parameters = "$(malicious command)";
})
```

**Expected**: Build fails with error about command substitution

---

### Test Case 4: Parameter expansion

**Add to registry**:
```nix
(mkApp {
  name = "malicious-expand";
  command = "echo";
  parameters = "${MALICIOUS}";
})
```

**Expected**: Build fails with error about parameter expansion

---

### Test Case 5: Valid parameters (should pass)

**Add to registry**:
```nix
(mkApp {
  name = "safe-params";
  command = "echo";
  parameters = "--flag=value $PROJECT_DIR --another-flag";
})
```

**Expected**: ✅ Build succeeds (no metacharacters)

---

## T039: Verify Acceptance Scenarios from Spec

**Goal**: Validate all User Story 2 acceptance scenarios

### Scenario 1: Registry with parameters (spec.md US2, Scenario 1)

**Spec**: Given I define `{"name": "vscode", "command": "code", "parameters": "$PROJECT_DIR"}`, When the system is rebuilt, Then launching VS Code substitutes the active project's directory

**Test**:
```bash
# Application already exists in registry
pswitch nixos
~/.local/bin/app-launcher-wrapper.sh vscode
```

**Expected**: VS Code launches with `/etc/nixos` as directory

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 2: Complex parameters with multiple variables (spec.md US2, Scenario 2)

**Spec**: Given `{"name": "lazygit", "parameters": "--work-tree=$PROJECT_DIR"}`, When launched from "nixos" project, Then command is `ghostty -e lazygit --work-tree=/etc/nixos`

**Test**:
```bash
pswitch nixos
DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh lazygit
```

**Expected Output**:
```
[DRY RUN] Would execute:
  Command: ghostty
  Arguments: -e lazygit --work-tree=/etc/nixos
```

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 3: Multiple variable types (spec.md US2, Scenario 3)

**Spec**: Given I define multiple variable types: `$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`, When I launch an application, Then each variable is replaced with the corresponding value

**Test**: Use var-test-all from T037

**Status**: ☐ Pass / ☐ Fail

---

### Scenario 4: Registry update takes effect (spec.md US2, Scenario 4)

**Spec**: Given I update the registry to change VS Code's parameters, When I rebuild the system, Then the next launch uses the updated parameters

**Test**:
1. Change VS Code parameters in registry to `--reuse-window $PROJECT_DIR`
2. Rebuild
3. Test launch

**Expected**: VS Code uses new parameters

**Status**: ☐ Pass / ☐ Fail

---

## Additional Validation Tests

### Test: Duplicate name detection

**Add duplicate** to registry (same name twice):
```nix
applications = [
  (mkApp { name = "test"; ... })
  (mkApp { name = "test"; ... })  # Duplicate!
  ...
];
```

**Expected**: Build fails with "Duplicate application names found: test"

---

### Test: Invalid workspace number

**Add app with invalid workspace**:
```nix
(mkApp {
  name = "bad-workspace";
  preferred_workspace = 15;  # Must be 1-9!
  ...
})
```

**Expected**: Build fails with "Invalid workspace numbers"

---

### Test: Invalid name format

**Add app with uppercase/special chars**:
```nix
(mkApp {
  name = "Invalid_Name_123";  # Must be kebab-case!
  ...
})
```

**Expected**: Build fails with "Invalid application names (must be kebab-case)"

---

## Test Results Summary

| Test | Status | Notes |
|------|--------|-------|
| T036: Add new app | ☐ | |
| T037: All variables | ☐ | |
| T037: $WORKSPACE | ☐ | |
| T037: Fallback behaviors | ☐ | |
| T038: Semicolon blocked | ☐ | |
| T038: Pipe blocked | ☐ | |
| T038: $() blocked | ☐ | |
| T038: ${} blocked | ☐ | |
| T038: Valid params pass | ☐ | |
| T039: Scenario 1 | ☐ | |
| T039: Scenario 2 | ☐ | |
| T039: Scenario 3 | ☐ | |
| T039: Scenario 4 | ☐ | |
| Duplicate name detection | ☐ | |
| Invalid workspace | ☐ | |
| Invalid name format | ☐ | |

---

## Regression Tests

Verify Phase 3 functionality still works:

```bash
# All tests from TEST_PLAN.md should still pass
# No regressions introduced by registry expansion
```

---

**Phase 4 Status**: ✨ Implementation Complete - Ready for Testing ✨

All 15 applications are defined with comprehensive build-time validation. System will reject invalid configurations at build time, preventing runtime errors.

# Quickstart: M1 Configuration Alignment with Hetzner-Sway

**Feature Branch**: `051-the-hetzner-sway`
**Date**: 2025-10-30
**Estimated Time**: 1-2 hours

## Overview

This guide walks you through aligning the M1 MacBook Pro NixOS configuration with the hetzner-sway reference implementation. The alignment involves three main changes:

1. **Add missing system service modules** to configurations/m1.nix
2. **Fix Sway workspace-mode-handler** hardcoded output names
3. **Simplify home-manager structure** to match hetzner-sway's clean imports

## Prerequisites

- M1 MacBook Pro running NixOS with Sway/Wayland
- Administrator access (`sudo` privileges)
- Git configured for commits
- Current working directory: `/etc/nixos`
- Branch: `051-the-hetzner-sway` (should already be checked out)

## Phase 1: Add Missing System Service Modules (30 minutes)

### Step 1.1: Add i3-project-daemon Module

**Why**: This system service is CRITICAL for Features 037, 049 (project switching, window filtering, workspace intelligence). Without it, i3pm commands will fail.

**Edit**: `configurations/m1.nix`

**Location**: After line 28 (`../modules/services/onepassword.nix`)

**Add these lines**:
```nix
    ../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon
```

**Full context** (lines 23-33):
```nix
    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon  [ADD THIS LINE]
    ../modules/services/onepassword-password-management.nix
    ../modules/services/speech-to-text-safe.nix
```

### Step 1.2: Configure i3-project-daemon Service

**Edit**: `configurations/m1.nix`

**Location**: After line 60 (`services.sway.enable = true;`)

**Add this block**:
```nix
  # i3 Project Daemon (Feature 037) - System service for cross-namespace access
  # NOTE: Daemon is Sway-compatible (Feature 045), no code changes needed
  services.i3ProjectDaemon = {
    enable = true;
    user = "vpittamp";
    logLevel = "INFO";  # Or "DEBUG" for troubleshooting
  };
```

### Step 1.3: Add 1Password Automation Module (Optional but Recommended)

**Why**: Enables service account automation for unattended Git/CI operations.

**Edit**: `configurations/m1.nix`

**Location**: After the i3-project-daemon import you just added

**Add this line**:
```nix
    ../modules/services/onepassword-automation.nix  # Service account automation  [ADD THIS LINE]
```

**Full context** (lines 23-34):
```nix
    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/i3-project-daemon.nix       # Feature 037: Project management daemon
    ../modules/services/onepassword-automation.nix  # Service account automation  [ADD THIS LINE]
    ../modules/services/onepassword-password-management.nix
    ../modules/services/speech-to-text-safe.nix
```

**Configure the service** (add after i3ProjectDaemon block, around line 70):
```nix
  # Enable 1Password automation with service account
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  };
```

**Note**: This requires a 1Password service account token. If you don't have one yet, you can skip this step and enable it later.

### Step 1.4: Test Configuration Build

**Run**:
```bash
cd /etc/nixos
sudo nixos-rebuild dry-build --flake .#m1 --impure
```

**Expected output**:
```
building the system configuration...
these derivations will be built:
  ...
building '/nix/store/...-nixos-system-nixos-m1-25.11...'
```

**If errors occur**:
- Check for syntax errors (missing commas, brackets)
- Verify module paths are correct (tab completion works in nix files)
- Use `--show-trace` for detailed error messages

**Success criteria**: Build completes without errors.

---

## Phase 2: Fix Sway Workspace Mode Handler (30 minutes)

### Step 2.1: Understand the Problem

**Current**: workspace-mode-handler.sh hardcodes HEADLESS-1/2/3 output names
**Impact**: M1 workspace mode switching fails because eDP-1/HDMI-A-1 outputs don't exist as "HEADLESS-*"
**Fix**: Dynamic output detection via `swaymsg -t get_outputs`

### Step 2.2: Apply the Patch

**Edit**: `home-modules/desktop/sway-config-manager.nix`

**Location**: Lines 44-147 (workspace-mode-handler.sh script)

**Find** (around line 54):
```bash
  # Get current mode
  CURRENT_MODE=$(cat ~/.config/sway/workspace-mode 2>/dev/null || echo "single")

  # Handle mode parameter
```

**Replace with** (insert BEFORE "Handle mode parameter"):
```bash
  # Get current mode
  CURRENT_MODE=$(cat ~/.config/sway/workspace-mode 2>/dev/null || echo "single")

  # Dynamically detect available outputs
  OUTPUTS=($(${pkgs.sway}/bin/swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[].name' | sort))
  OUTPUT_COUNT=''${#OUTPUTS[@]}

  # Validate we have outputs
  if [ "$OUTPUT_COUNT" -eq 0 ]; then
    echo "ERROR: No outputs detected. Cannot configure workspace mode." >&2
    exit 1
  fi

  # Assign outputs dynamically based on count
  # For 1 output: PRIMARY=output1
  # For 2 outputs: PRIMARY=output1, SECONDARY=output2
  # For 3+ outputs: PRIMARY=output1, SECONDARY=output2, TERTIARY=output3
  PRIMARY="''${OUTPUTS[0]}"
  SECONDARY="''${OUTPUTS[1]:-$PRIMARY}"  # Default to PRIMARY if only 1 output
  TERTIARY="''${OUTPUTS[2]:-$SECONDARY}"  # Default to SECONDARY if only 2 outputs

  # Handle mode parameter
```

### Step 2.3: Replace Hardcoded Outputs

**Find and replace throughout the case statement**:

**Single mode** (lines ~99-109):
```bash
# OLD:
${pkgs.sway}/bin/swaymsg "workspace 1; move workspace to output HEADLESS-1"
${pkgs.sway}/bin/swaymsg "workspace 2; move workspace to output HEADLESS-1"
...

# NEW:
${pkgs.sway}/bin/swaymsg "workspace 1; move workspace to output $PRIMARY"
${pkgs.sway}/bin/swaymsg "workspace 2; move workspace to output $PRIMARY"
...
```

**Dual mode** (lines ~111-120):
```bash
# OLD:
${pkgs.sway}/bin/swaymsg "workspace 1; move workspace to output HEADLESS-1"
${pkgs.sway}/bin/swaymsg "workspace 2; move workspace to output HEADLESS-1"
${pkgs.sway}/bin/swaymsg "workspace 3; move workspace to output HEADLESS-2"
...

# NEW:
${pkgs.sway}/bin/swaymsg "workspace 1; move workspace to output $PRIMARY"
${pkgs.sway}/bin/swaymsg "workspace 2; move workspace to output $PRIMARY"
${pkgs.sway}/bin/swaymsg "workspace 3; move workspace to output $SECONDARY"
...
```

**Tri mode** (lines ~122-132):
```bash
# OLD:
${pkgs.sway}/bin/swaymsg "workspace 1; move workspace to output HEADLESS-1"
${pkgs.sway}/bin/swaymsg "workspace 2; move workspace to output HEADLESS-1"
${pkgs.sway}/bin/swaymsg "workspace 3; move workspace to output HEADLESS-2"
${pkgs.sway}/bin/swaymsg "workspace 4; move workspace to output HEADLESS-2"
${pkgs.sway}/bin/swaymsg "workspace 5; move workspace to output HEADLESS-2"
${pkgs.sway}/bin/swaymsg "workspace 6; move workspace to output HEADLESS-3"
...

# NEW:
${pkgs.sway}/bin/swaymsg "workspace 1; move workspace to output $PRIMARY"
${pkgs.sway}/bin/swaymsg "workspace 2; move workspace to output $PRIMARY"
${pkgs.sway}/bin/swaymsg "workspace 3; move workspace to output $SECONDARY"
${pkgs.sway}/bin/swaymsg "workspace 4; move workspace to output $SECONDARY"
${pkgs.sway}/bin/swaymsg "workspace 5; move workspace to output $SECONDARY"
${pkgs.sway}/bin/swaymsg "workspace 6; move workspace to output $TERTIARY"
...
```

**Tip**: Use a text editor's find-and-replace:
- Find: `HEADLESS-1` → Replace: `$PRIMARY`
- Find: `HEADLESS-2` → Replace: `$SECONDARY`
- Find: `HEADLESS-3` → Replace: `$TERTIARY`

**Full patch available**: See `contracts/sway-fixes.patch` for complete before/after comparison

### Step 2.4: Test Home Manager Build

**Run**:
```bash
home-manager build --flake .#vpittamp@m1
```

**Expected output**:
```
building the user environment...
/nix/store/...-home-manager-generation
```

**If errors occur**:
- Check bash syntax (unclosed quotes, missing semicolons)
- Verify variable names (PRIMARY, SECONDARY, TERTIARY)
- Check bash array syntax (''${OUTPUTS[0]} with proper escaping)

**Success criteria**: Build completes and generates home-manager-generation link.

---

## Phase 3: Simplify Home Manager Structure (Optional, 20 minutes)

This step is optional but recommended for long-term maintainability. It aligns M1's home-manager structure with hetzner-sway's clean import pattern.

### Option A: Minimal Fix (5 minutes)

**Goal**: Remove incorrect system service import, add missing module

**Edit**: `home-manager/base-home.nix`

**Find and remove** (if present):
```nix
../modules/services/i3-project-daemon.nix  # REMOVE - this is a system service!
```

**Add** (if missing):
```nix
../home-modules/desktop/declarative-cleanup.nix  # Automatic XDG cleanup
```

**Test**:
```bash
home-manager build --flake .#vpittamp@m1
```

### Option B: Full Restructure (20 minutes)

**Goal**: Match hetzner-sway's explicit import structure

**Step 1**: Create shared profile
```bash
touch home-modules/profiles/base.nix
```

**Edit**: `home-modules/profiles/base.nix`
```nix
# Shared home-manager profile for all platforms
{ config, lib, pkgs, ... }:
{
  imports = [
    # Shell environment
    ../shell/bash.nix

    # Editors
    ../editors/neovim.nix

    # Terminal tools
    ../terminal/tmux.nix

    # Desktop applications
    ../desktop/sway.nix
    ../desktop/walker.nix
    ../desktop/sway-config-manager.nix
    ../desktop/declarative-cleanup.nix

    # Developer tools
    ../tools/i3pm
    ../tools/git

    # AI assistants
    ../ai-assistants/claude.nix
  ];
}
```

**Step 2**: Update M1 home-manager to use profile

**Edit**: `home-manager/base-home.nix`
```nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ../home-modules/profiles/base.nix  # Shared configuration
  ];

  # M1-specific overrides (if any)
  home.packages = with pkgs; [
    # M1-specific packages only
  ];
}
```

**Test**:
```bash
home-manager build --flake .#vpittamp@m1
```

---

## Phase 4: Apply Changes and Rebuild (15 minutes)

### Step 4.1: Commit Changes

**Before rebuilding**, commit your changes to Git:

```bash
cd /etc/nixos
git add configurations/m1.nix home-modules/desktop/sway-config-manager.nix
git commit -m "feat(051): Align M1 configuration with hetzner-sway

- Add i3-project-daemon system service for project management (Feature 037)
- Add 1Password automation for service account operations
- Fix workspace-mode-handler hardcoded outputs (dynamic detection)
- Align home-manager imports with hetzner-sway structure

Resolves Feature 051: M1 Configuration Alignment with Hetzner-Sway"
```

### Step 4.2: Rebuild NixOS System

**Test build first** (dry-run):
```bash
sudo nixos-rebuild dry-build --flake .#m1 --impure
```

**If successful, apply changes**:
```bash
sudo nixos-rebuild switch --flake .#m1 --impure
```

**Expected output**:
```
building the system configuration...
activating the configuration...
setting up /etc...
reloading systemd units...
starting the following units: i3-project-event-listener.service
```

**Duration**: 5-10 minutes (depends on cached packages)

### Step 4.3: Rebuild Home Manager

**Run**:
```bash
home-manager switch --flake .#vpittamp@m1
```

**Expected output**:
```
Starting Home Manager activation
...
Activating workspace-mode-handler
```

**Duration**: 2-5 minutes

### Step 4.4: Restart User Services

**Restart i3pm daemon**:
```bash
systemctl --user restart i3-project-event-listener
```

**Restart Sway session** (reload configuration):
```bash
swaymsg reload
```

---

## Phase 5: Verification (15 minutes)

### Step 5.1: Verify i3pm Daemon

**Check daemon status**:
```bash
systemctl --user status i3-project-event-listener
```

**Expected**: `Active: active (running)`

**Check daemon health**:
```bash
i3pm daemon status
```

**Expected output**:
```
✓ Daemon Status: Running
✓ Version: 1.8.3
✓ Uptime: 5 seconds
✓ i3 IPC: Connected
...
```

**Test project switching**:
```bash
# List projects
i3pm project list

# Switch to a project (if you have any configured)
i3pm project switch nixos
```

**Expected**: No errors, project switching works

### Step 5.2: Verify Workspace Mode Handler

**Check detected outputs**:
```bash
swaymsg -t get_outputs | jq -r '.[].name'
```

**Expected output** (M1 with external monitor):
```
HDMI-A-1
eDP-1
```

**Or** (M1 without external monitor):
```
eDP-1
```

**Test workspace mode switching**:
```bash
# Test single mode (all workspaces on one display)
workspace-mode single

# Test dual mode (workspaces 1-2 on primary, 3-9 on secondary)
workspace-mode dual

# Check current mode
cat ~/.config/sway/workspace-mode
```

**Expected**: Commands execute without errors, workspaces move to correct outputs

**Verify workspace distribution**:
```bash
swaymsg -t get_workspaces | jq '.[] | {num: .num, output: .output}'
```

**Expected** (dual mode, 2 outputs):
```
{"num": 1, "output": "HDMI-A-1"}
{"num": 2, "output": "HDMI-A-1"}
{"num": 3, "output": "eDP-1"}
...
```

### Step 5.3: Verify 1Password Automation (if enabled)

**Check service status**:
```bash
systemctl --user status onepassword-automation
```

**Expected**: `Active: active (running)` or inactive if token not configured yet

**Test op CLI**:
```bash
op whoami
```

**Expected**: Your 1Password account info or instructions to sign in

### Step 5.4: Verify Home Manager Changes

**Check XDG config files**:
```bash
ls -la ~/.config/sway/
```

**Expected**:
```
keybindings.toml
window-rules.json
appearance.json
workspace-assignments.json
workspace-mode
config  (generated)
```

**Check walker configuration**:
```bash
systemctl --user status walker
```

**Expected**: `Active: active (running)`

---

## Rollback Procedures

If something goes wrong, you can rollback using NixOS's generation system.

### Rollback System Configuration

**List generations**:
```bash
sudo nixos-rebuild list-generations
```

**Rollback to previous generation**:
```bash
sudo nixos-rebuild switch --rollback
```

**Or boot into previous generation**:
```bash
sudo nixos-rebuild boot --rollback
sudo reboot
```

### Rollback Home Manager

**List generations**:
```bash
home-manager generations
```

**Rollback**:
```bash
/nix/store/...-home-manager-generation/activate
```

(Copy the path from the generations list)

### Rollback Git Changes

```bash
cd /etc/nixos
git log  # Find commit to revert
git revert <commit-hash>
sudo nixos-rebuild switch --flake .#m1 --impure
```

---

## Troubleshooting

### Issue: i3pm daemon not starting

**Symptoms**: `systemctl --user status i3-project-event-listener` shows failed/inactive

**Diagnosis**:
```bash
journalctl --user -u i3-project-event-listener -n 50
```

**Common causes**:
- i3/Sway not running (daemon requires Sway IPC socket)
- Python dependencies missing (should be installed automatically)
- Configuration errors in module

**Fix**:
1. Ensure Sway is running: `pgrep sway`
2. Check Sway IPC socket: `ls -la $SWAYSOCK`
3. Restart daemon: `systemctl --user restart i3-project-event-listener`

### Issue: Workspace mode switching fails

**Symptoms**: `workspace-mode dual` command fails or doesn't move workspaces

**Diagnosis**:
```bash
# Check detected outputs
swaymsg -t get_outputs | jq '.'

# Test manual workspace move
swaymsg "workspace 1; move workspace to output eDP-1"
```

**Common causes**:
- Output names changed (check with swaymsg -t get_outputs)
- Bash script syntax errors (check home-manager rebuild logs)
- Sway configuration not reloaded (run swaymsg reload)

**Fix**:
1. Verify workspace-mode-handler script is updated
2. Rebuild home-manager: `home-manager switch --flake .#vpittamp@m1`
3. Reload Sway: `swaymsg reload`
4. Test again: `workspace-mode single`

### Issue: Build fails with "module not found"

**Symptoms**: `nixos-rebuild dry-build` fails with "file 'modules/services/i3-project-daemon.nix' not found"

**Diagnosis**:
```bash
# Check if module exists
ls -la /etc/nixos/modules/services/i3-project-daemon.nix
```

**Common causes**:
- Incorrect relative path in import
- Module file doesn't exist (check spelling)
- Wrong working directory (must be in /etc/nixos)

**Fix**:
1. Verify you're in `/etc/nixos` directory
2. Check module path: `realpath modules/services/i3-project-daemon.nix`
3. Fix import statement if path is wrong

### Issue: Home manager build fails

**Symptoms**: `home-manager build` fails with Nix evaluation errors

**Diagnosis**:
```bash
home-manager build --flake .#vpittamp@m1 --show-trace
```

**Common causes**:
- Syntax errors in nix files (missing semicolons, brackets)
- Conflicting module imports
- Incorrect bash script escaping in sway-config-manager.nix

**Fix**:
1. Use `--show-trace` for detailed error location
2. Check recent edits for syntax errors
3. Validate bash script escaping (''${ for nix string interpolation)

---

## Success Criteria

After completing all steps, verify:

- ✅ `i3pm daemon status` shows healthy daemon
- ✅ `i3pm project list` works without errors
- ✅ `workspace-mode dual` moves workspaces to correct outputs
- ✅ `swaymsg -t get_workspaces` shows workspaces on eDP-1/HDMI-A-1
- ✅ `systemctl --user status walker` shows active service
- ✅ `systemctl --user status sway-config-manager` shows file watcher running
- ✅ No errors in `nixos-rebuild switch` or `home-manager switch`
- ✅ Sway session works normally (keybindings, window management, etc.)

---

## Next Steps

After successful alignment:

1. **Test Workflows**: Verify project switching, window filtering, workspace management
2. **Update CLAUDE.md**: Add M1-specific sections (separate task/PR)
3. **Monitor Services**: Watch daemon logs for any issues over next few days
4. **Report Issues**: If problems arise, check troubleshooting section above

## Documentation Updates (Separate Task)

These documentation updates are NOT part of this feature implementation but should be done afterward:

- Add M1-specific quick start section to CLAUDE.md
- Document i3pm daemon service configuration for M1
- Create troubleshooting section for M1-specific issues
- Document workspace mode handler behavior on different output configurations

---

## Estimated Timeline

- Phase 1 (System modules): 30 minutes
- Phase 2 (Sway fixes): 30 minutes
- Phase 3 (Home manager): 20 minutes (optional)
- Phase 4 (Rebuild): 15 minutes
- Phase 5 (Verification): 15 minutes
- **Total**: 1-2 hours

---

## Additional Resources

- Feature specification: `specs/051-the-hetzner-sway/spec.md`
- Research findings: `specs/051-the-hetzner-sway/research.md`
- Data model: `specs/051-the-hetzner-sway/data-model.md`
- Implementation plan: `specs/051-the-hetzner-sway/plan.md`
- Contract files: `specs/051-the-hetzner-sway/contracts/`

---

**Last Updated**: 2025-10-30
**Feature Branch**: `051-the-hetzner-sway`
**Status**: Ready for implementation

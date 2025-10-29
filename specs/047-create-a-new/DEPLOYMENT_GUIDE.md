# Sway Config Manager Deployment Guide

## Current Status

All configuration changes have been committed to branch `047-create-a-new` (commit `d482785`).

### What Was Done

1. ✅ **Enabled sway-config-manager** in `home-modules/hetzner-sway.nix`
2. ✅ **Created default keybindings** in `sway-default-keybindings.toml`
3. ✅ **Created automated test script** at `specs/047-create-a-new/test-sway-config-manager.sh`
4. ✅ **Updated sway-config-manager.nix** to use external keybindings file
5. ✅ **All changes committed** and ready for deployment

### What Needs to Be Done

The system rebuild could not be completed in the current session due to sudo permission issues in the environment. The following manual steps are required:

## Deployment Steps

### Step 1: Apply NixOS Configuration

From a session with proper sudo access, run:

```bash
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hetzner-sway
```

This will:
- Install the sway-config-manager daemon
- Create configuration files in `~/.config/sway/`
- Start the daemon as a systemd user service
- Install the `swayconfig` CLI tool

Expected output:
```
building the system configuration...
activating the configuration...
setting up /etc...
reloading user units for vpittamp...
starting the following units: sway-config-manager.service
```

### Step 2: Verify Daemon Status

Check if the daemon is running:

```bash
systemctl --user status sway-config-manager
```

Expected output:
```
● sway-config-manager.service - Sway Configuration Manager Daemon
     Loaded: loaded
     Active: active (running)
```

If not running, check the logs:

```bash
journalctl --user -u sway-config-manager -n 50
```

### Step 3: Verify Configuration Files

Check that configuration files were created:

```bash
ls -la ~/.config/sway/
```

Expected files:
```
~/.config/sway/
├── keybindings.toml                # Workspace keybindings (Mod+1 through Mod+0)
├── window-rules.json               # Window management rules
├── workspace-assignments.json      # Workspace assignments
├── projects/                       # Project-specific configs
└── schemas/                        # JSON schemas for validation
```

Verify keybindings content:

```bash
head -20 ~/.config/sway/keybindings.toml
```

Should show:
```toml
# Sway Default Keybindings Configuration
# Feature 047: Dynamic Configuration Management

[keybindings]
# ========== WORKSPACE NAVIGATION ==========
"Mod+1" = { command = "workspace number 1", description = "Focus workspace 1" }
"Mod+2" = { command = "workspace number 2", description = "Focus workspace 2" }
...
```

### Step 4: Test IPC Communication

Verify daemon is responsive:

```bash
swayconfig ping
```

Expected output:
```
✅ Daemon is responsive
```

### Step 5: Run Automated Test Suite

Execute the comprehensive test script:

```bash
/etc/nixos/specs/047-create-a-new/test-sway-config-manager.sh
```

Expected output:
```
========================================
Sway Configuration Manager Test Suite
Feature 047: Dynamic Configuration Management
========================================

[INFO] Test 1: Daemon is running
[PASS] Daemon is running
[INFO] Test 2: CLI command is available
[PASS] CLI command 'swayconfig' is available
...
========================================
Test Summary
========================================
Tests Run:    11
Tests Passed: 11
Tests Failed: 0

✅ All tests passed!
```

If any tests fail, review the error messages and check daemon logs.

### Step 6: Test Workspace Keybindings

Manually test the workspace navigation keybindings:

1. Press `Mod+1` - should switch to workspace 1
2. Press `Mod+2` - should switch to workspace 2
3. Open a window and press `Mod+Shift+3` - should move window to workspace 3
4. Verify all keybindings work (Mod+1 through Mod+0 for workspaces 1-10)

### Step 7: Test Configuration Hot-Reload

Test the hot-reload functionality:

```bash
# Edit keybindings file
vi ~/.config/sway/keybindings.toml

# Add a test keybinding
# "Mod+t" = { command = "exec notify-send 'Test'", description = "Test keybinding" }

# Validate configuration
swayconfig validate

# Reload configuration
swayconfig reload

# Test the new keybinding
# Press Mod+t to verify it works
```

### Step 8: Test File Watcher Auto-Reload

Test automatic reload on file save:

```bash
# Make a small change to keybindings.toml
echo '# Test comment' >> ~/.config/sway/keybindings.toml

# Wait 500ms (debounce delay)
sleep 1

# Check daemon logs for reload
journalctl --user -u sway-config-manager -n 20 | grep -i reload
```

Expected log entry:
```
Oct 29 03:45:12 sway-config-manager[1234]: File change detected: keybindings.toml
Oct 29 03:45:12 sway-config-manager[1234]: Debounce timer started (500ms)
Oct 29 03:45:13 sway-config-manager[1234]: Configuration reloaded successfully
```

## Troubleshooting

### Daemon Won't Start

```bash
# Check service status
systemctl --user status sway-config-manager

# Check for errors
journalctl --user -u sway-config-manager -n 100

# Common issues:
# - Python dependencies missing: rebuild system
# - Sway not running: start Sway compositor
# - Socket permission error: check ~/.config/sway/ permissions
```

### Configuration Validation Fails

```bash
# Check validation errors
swayconfig validate

# Common issues:
# - TOML syntax error: check keybindings.toml syntax
# - JSON parse error: validate JSON files
# - Semantic error: check command syntax
```

### Hot-Reload Not Working

```bash
# Check daemon is running
systemctl --user is-active sway-config-manager

# Test manual reload
swayconfig reload

# Check file watcher is enabled
systemctl --user show-environment | grep SWAY_CONFIG

# Check daemon logs
journalctl --user -u sway-config-manager -f
```

### Keybindings Not Responding

```bash
# Check Sway configuration
swaymsg -t get_config

# Reload Sway configuration manually
swaymsg reload

# Verify keybindings are applied
swayconfig show | grep -A 20 keybindings
```

## Success Criteria

System is successfully deployed when:

- ✅ Daemon starts automatically on login
- ✅ All 11 automated tests pass
- ✅ Workspace keybindings work (Mod+1 through Mod+0)
- ✅ `swayconfig` CLI commands work
- ✅ Configuration hot-reload works
- ✅ File watcher auto-reloads on save
- ✅ Configuration validation catches errors
- ✅ Rollback functionality works

## Post-Deployment Tasks

After successful deployment:

1. **Document Usage Patterns**
   - Track which keybindings are most used
   - Identify any conflicts with existing bindings
   - Gather user feedback on configuration workflow

2. **Monitor Performance**
   - Check daemon CPU/memory usage: `systemd-cgtop -u vpittamp`
   - Monitor reload latency: `journalctl --user -u sway-config-manager | grep latency`
   - Verify <100ms target for reload operations

3. **Test Edge Cases**
   - Rapid file changes (multiple edits within debounce window)
   - Large configuration files (100+ keybindings)
   - Invalid TOML/JSON syntax (verify validation catches errors)
   - Concurrent reloads (multiple swayconfig reload commands)

4. **Plan Phase 4 Features**
   - User Story 2: Project-scoped configurations
   - User Story 3: Multi-layer configuration merging
   - UI/TUI for configuration management

## Related Documentation

- **Feature Specification**: `/etc/nixos/specs/047-create-a-new/spec.md`
- **Implementation Summary**: `/etc/nixos/specs/047-create-a-new/IMPLEMENTATION_SUMMARY.md`
- **User Guide**: `/etc/nixos/docs/SWAY_CONFIG_MANAGEMENT.md`
- **Completion Report**: `/etc/nixos/specs/047-create-a-new/COMPLETION_REPORT.md`
- **Testing Script**: `/etc/nixos/specs/047-create-a-new/test-sway-config-manager.sh`

---

**Last Updated**: 2025-10-29
**Branch**: 047-create-a-new
**Commit**: d482785
**Status**: Ready for deployment

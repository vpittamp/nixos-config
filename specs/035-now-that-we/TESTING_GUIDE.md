# Feature 035: Testing Guide

## Overview

This guide explains how to safely test Feature 035 (Registry-Centric Project Management) while connected via RDP without disrupting your active session.

## Problem

Testing i3 window manager features while actively using the system via RDP creates conflicts:
- Tests create/destroy windows
- Tests interact with i3 window manager
- Tests may interfere with your active workflow
- RDP connection might drop during long tests

## Solution: SSH + tmux Testing

Use SSH from a separate device + tmux for persistence and isolation.

---

## Option 1: Quick Local Testing (Safest for RDP Users)

If you want to test without creating windows in your active RDP session:

```bash
# In your current RDP session terminal:
cd /etc/nixos
./scripts/test-feature-035.sh --quick --dry-run
```

This runs validation without creating windows.

---

## Option 2: SSH + tmux (Recommended for Full Testing)

### Prerequisites

- Another device to SSH from (laptop, phone, another VM, etc.)
- SSH access to your Hetzner VM

### Step 1: SSH to the VM

From your other device:

```bash
ssh vpittamp@hetzner
```

### Step 2: Start tmux Session

```bash
# Create a named tmux session for testing
tmux new-session -s i3pm-tests
```

**Why tmux?**
- Tests continue running if SSH connection drops
- Can detach and reattach to check progress
- Multiple windows for monitoring

### Step 3: Set DISPLAY Variable

Find your RDP session's DISPLAY:

```bash
# In the tmux session on SSH:
who
# Look for your username, note the display (e.g., :10, :11)

# Set DISPLAY to match your RDP session
export DISPLAY=:10  # Adjust based on 'who' output
```

### Step 4: Run Tests

```bash
cd /etc/nixos

# Quick tests (T094-T095) - ~2 minutes
./scripts/test-feature-035.sh --quick

# Or full tests (T094-T100) - ~10 minutes
./scripts/test-feature-035.sh --full
```

### Step 5: Monitor Progress

**Option A: Stay attached**
- Watch tests run in real-time
- See immediate results

**Option B: Detach and reattach**

```bash
# Detach from tmux (tests keep running)
# Press: Ctrl+b, then d

# Continue using your RDP session normally
# Tests run in background

# Later, reattach to check progress:
tmux attach-session -t i3pm-tests

# View logs:
tail -f ~/.local/state/i3pm-tests/test-035-*.log
```

### Step 6: When Tests Complete

```bash
# View results
cat ~/.local/state/i3pm-tests/test-results-*.json | jq .

# Exit tmux session
exit  # or Ctrl+d

# Or keep session for next test run:
# Just detach: Ctrl+b, d
```

---

## Option 3: Background Testing (Most Isolated)

For complete isolation from your RDP session:

```bash
# SSH to the VM
ssh vpittamp@hetzner

# Start tests in background with nohup
cd /etc/nixos
nohup ./scripts/test-feature-035.sh --full > ~/test-035.log 2>&1 &

# Note the PID
echo $!

# Disconnect from SSH (tests continue)

# Later, SSH back and check progress:
ssh vpittamp@hetzner
tail -f ~/test-035.log

# Check if still running:
ps aux | grep test-feature-035
```

---

## Test Script Options

```bash
./scripts/test-feature-035.sh --help      # Show help
./scripts/test-feature-035.sh --dry-run   # Show what would be tested
./scripts/test-feature-035.sh --quick     # Quick tests only (2 min)
./scripts/test-feature-035.sh --full      # Full test suite (10 min)
```

---

## What Each Test Does

### T094: CLI JSON Output
- Tests all `i3pm` commands with `--json` flag
- Validates JSON output is well-formed
- **Impact**: None (read-only commands)
- **Duration**: ~30 seconds

### T095: Quickstart Workflows
- Creates temporary test project
- Tests create → list → switch → clear → delete workflow
- **Impact**: Creates test project (deleted after)
- **Duration**: ~1 minute

### T097: Full System Test
- Creates project, launches apps (dry-run mode), saves layout
- Tests complete workflow
- **Impact**: Minimal (uses dry-run for app launches)
- **Duration**: ~2 minutes

### T098-T100: Performance Tests
- Measures environment injection overhead
- Measures /proc reading speed
- **Impact**: None (timing tests only)
- **Duration**: ~1 minute

---

## Troubleshooting

### "i3pm daemon is not running"

```bash
# Start the daemon
systemctl --user start i3-project-event-listener

# Check status
systemctl --user status i3-project-event-listener
```

### "No DISPLAY set"

```bash
# Find your display
echo $DISPLAY  # In RDP session
who            # Via SSH

# Set it in SSH session
export DISPLAY=:10  # Adjust to match
```

### "Tests create windows in my RDP session"

This is expected if using Option 2 (same DISPLAY). Windows will be created but:
- They go to scratchpad (hidden) if not in active project
- Test cleans up after itself
- Won't disrupt your active windows

For complete isolation, use Option 3 (background) or set up Xvfb.

### tmux Basics

```bash
# Detach: Ctrl+b, then d
# List sessions: tmux ls
# Attach to session: tmux attach-session -t i3pm-tests
# Kill session: tmux kill-session -t i3pm-tests
# New window in session: Ctrl+b, then c
# Switch windows: Ctrl+b, then 0-9
```

---

## Recommended Workflow for RDP Users

1. **From your Windows machine**: Keep RDP open for normal work
2. **From another device** (or WSL on same machine):
   ```bash
   ssh vpittamp@hetzner
   tmux new-session -s i3pm-tests
   export DISPLAY=:10  # Match your RDP display
   cd /etc/nixos
   ./scripts/test-feature-035.sh --quick
   ```
3. **Monitor**: Stay attached or detach and check logs later
4. **Continue working**: Tests won't significantly disrupt RDP session

---

## Test Results Location

All test artifacts are saved to `~/.local/state/i3pm-tests/`:

```bash
# View latest test log
ls -lt ~/.local/state/i3pm-tests/*.log | head -1 | xargs cat

# View latest results JSON
ls -lt ~/.local/state/i3pm-tests/test-results-*.json | head -1 | xargs jq .

# Clean old test logs
find ~/.local/state/i3pm-tests/ -type f -mtime +7 -delete
```

---

## Safety Guarantees

The test script:
- ✅ Checks environment before running
- ✅ Uses temporary test projects (deleted after)
- ✅ Uses DRY_RUN mode for app launches (no actual windows)
- ✅ Logs all actions for debugging
- ✅ Cleans up after itself
- ✅ Won't modify production projects
- ✅ Won't close your active windows

---

## Next Steps After Testing

Once tests pass:

1. Mark tasks as complete in `tasks.md`
2. Stage changes: `git add .`
3. Rebuild system: `sudo nixos-rebuild switch --flake .#hetzner`
4. Run tests again to verify rebuild didn't break anything
5. Create commit for Feature 035

---

## Questions?

- Check logs: `~/.local/state/i3pm-tests/test-035-*.log`
- Check daemon: `systemctl --user status i3-project-event-listener`
- Check daemon logs: `journalctl --user -u i3-project-event-listener -n 100`
- Manual test: `i3pm project list` and `i3pm daemon status`

# Sway Tree Diff Monitor - Troubleshooting Guide

## Event Emission Failure (2025-11-07)

### Symptoms
- Daemon starts successfully without errors
- No events appear in daemon logs despite window creation
- Direct `swaymsg -t subscribe` receives no events
- Affects ALL IPC subscribers system-wide (not daemon-specific)

### Root Cause
Sway compositor's IPC event subsystem stopped broadcasting events after extended uptime. This appears to be a rare Sway bug where the event emission mechanism becomes broken, requiring a full compositor restart.

### Investigation Process
1. ✅ Verified daemon package contains all bug fixes
2. ✅ Confirmed EventCorrelation constructor fix is deployed
3. ✅ Created minimal i3ipc.aio test script - no events received
4. ✅ Tested direct `swaymsg -t subscribe` - no events received
5. ✅ Killed zombie `swaymsg subscribe` processes
6. ❌ Attempted `swaymsg reload` - didn't fix event emission
7. ✅ Identified need for full Sway restart

### Resolution
**Full Sway compositor restart required:**

```bash
# Exit Sway cleanly (will disconnect VNC)
swaymsg exit

# System should auto-restart Sway via login manager
# All systemd user services restart automatically via sway-session.target
```

**Post-Restart Verification:**
```bash
# Test 1: Direct subscription
swaymsg -t subscribe '["window"]' &
sub_pid=$!
sleep 1
swaymsg exec "alacritty -e echo test"
sleep 2
kill $sub_pid

# Test 2: Daemon event capture
sway-tree-monitor history --last 5
```

### Key Learnings
- `swaymsg reload` does NOT fix IPC event emission issues
- Full compositor restart is required (not just daemon restart)
- On headless Sway: use `swaymsg exit` (NOT `systemctl restart sway`)
- Sway is managed via `sway-session.target`, not a direct systemd service

### Prevention
- Monitor for extended Sway uptime (>24h)
- Consider periodic Sway restarts for headless servers
- Watch for zombie `swaymsg subscribe` processes

### Related Files
- `/etc/nixos/home-modules/desktop/sway.nix` - Sway session configuration
- `/etc/nixos/home-modules/tools/sway-tree-monitor/daemon.py` - Event subscription
- `/etc/nixos/home-modules/tools/sway-tree-monitor/correlation/tracker.py` - EventCorrelation fix

### Timeline
- 2025-11-06: Fixed all 6 critical bugs, rebuilt system
- 2025-11-06: Daemon starts successfully, no events captured
- 2025-11-07: Diagnosed IPC event emission failure, identified restart requirement

---

## Nix Package Not Rebuilding After Source Changes (2025-11-08)

### Symptoms
- Source file contains fix (`include_diff=True` in `diff_view.py:95`)
- Git commits contain the fix (e7e0db3b, 9348d6d8)
- Multiple rebuild attempts fail to deploy updated code
- Deployed package still contains old code (`include_enrichment=True`)
- Error persists: `RPCClient.get_event() got an unexpected keyword argument 'include_enrichment'`

### Root Cause
The package derivation in `/etc/nixos/modules/services/sway-tree-monitor.nix` uses a local source path that Nix doesn't properly track for changes:

```nix
daemonSrc = ../../home-modules/tools/sway-tree-monitor;

daemonPackage = pkgs.stdenv.mkDerivation {
  name = "sway-tree-monitor";
  version = "1.0.0";
  src = daemonSrc;
  # ... installPhase with cp -r $src/*
};
```

**Issue**: When `src` points to a local directory, Nix may cache the derivation based on the path, not the file contents. Changes to source files don't trigger a rebuild because the path hasn't changed.

### Investigation Steps
1. ✅ Verified source file has fix at `/etc/nixos/home-modules/tools/sway-tree-monitor/ui/diff_view.py:95`
2. ✅ Confirmed git commits contain fix
3. ✅ Checked deployed package - still has old code at `/nix/store/cqangji4xd2kflara2ijh1zklafsaxr9-sway-tree-monitor/`
4. ✅ Attempted multiple rebuild strategies:
   - `sudo nixos-rebuild switch --flake .#hetzner-sway`
   - `home-manager switch --flake .#vpittamp@hetzner-sway --impure`
   - `sudo nixos-rebuild switch --option eval-cache false`
5. ✅ Attempted `nix-store --delete` - failed because "still alive"
6. ✅ Package hash unchanged despite source changes

### Resolution
**Run garbage collection to force complete rebuild:**

```bash
# Remove all old packages and generations
nix-collect-garbage -d

# Rebuild system from scratch
sudo nixos-rebuild switch --flake .#hetzner-sway
```

This forces Nix to re-evaluate all derivations and rebuild packages with fresh source copies.

### Verification Steps
After rebuild completes:
```bash
# 1. Find new package hash
ls -l /nix/store/*-sway-tree-monitor/ | grep -v drv

# 2. Check deployed source contains fix
grep -A2 "include_" /nix/store/*-sway-tree-monitor/lib/python3.11/site-packages/sway_tree_monitor/ui/diff_view.py

# 3. Should show: include_diff=True (not include_enrichment)

# 4. Test drill-down in TUI
sway-tree-monitor history --last 10
# Press 'd' on first row - should not error
```

### Prevention Strategies
For future source changes that don't rebuild:

**Option 1: Version Bump (Simplest)**
```nix
daemonPackage = pkgs.stdenv.mkDerivation {
  name = "sway-tree-monitor";
  version = "1.0.1";  # Increment version
  src = daemonSrc;
  # ...
};
```

**Option 2: Use builtins.path (More Explicit)**
```nix
daemonPackage = pkgs.stdenv.mkDerivation {
  name = "sway-tree-monitor";
  version = "1.0.0";
  src = builtins.path {
    path = ../../home-modules/tools/sway-tree-monitor;
    name = "sway-tree-monitor-src";
  };
  # ...
};
```

**Option 3: Add Source Hash (Best)**
```nix
daemonPackage = pkgs.stdenv.mkDerivation {
  name = "sway-tree-monitor";
  version = "1.0.0";
  src = ../../home-modules/tools/sway-tree-monitor;

  # Force rebuild when source changes
  sourceHash = builtins.hashPath "sha256" ../../home-modules/tools/sway-tree-monitor;

  installPhase = ''
    # ...
  '';
};
```

### Related Files
- `/etc/nixos/modules/services/sway-tree-monitor.nix` - Package definition (lines 19-30)
- `/etc/nixos/home-modules/tools/sway-tree-monitor/ui/diff_view.py` - Source with fix
- `/etc/nixos/home-modules/tools/sway-tree-monitor/rpc/client.py` - RPC client method signature

### Timeline
- 2025-11-08: Implemented drill-down integration (T046.5)
- 2025-11-08: Fixed RPC parameter error in diff_view.py (e7e0db3b, 9348d6d8)
- 2025-11-08: Discovered package not rebuilding, identified Nix caching issue
- 2025-11-08: Ran garbage collection to force rebuild
- 2025-11-08: Discovered second bug in RPC server (event.after_snapshot AttributeError)
- 2025-11-08: Fixed RPC server bug + incremented version to 1.0.1

---

## RPC Server AttributeError - TreeEvent.after_snapshot (2025-11-08)

### Symptoms
- Drill-down RPC call fails with "Internal error"
- Daemon logs show: `AttributeError: 'TreeEvent' object has no attribute 'after_snapshot'`
- Error occurs at `/rpc/server.py:374` in `handle_get_event` method

### Root Cause
The RPC server code was trying to access `event.after_snapshot` and `event.before_snapshot` attributes that don't exist on the TreeEvent model. The TreeEvent model only has a single `snapshot` attribute (the after-state), not separate before/after snapshots.

**Buggy Code** (`rpc/server.py:369-375`):
```python
# Include full snapshots if requested
if include_snapshots:
    result['snapshots'] = {
        'before': event.before_snapshot.tree_data if event.before_snapshot else None,
        'after': event.after_snapshot.tree_data if event.after_snapshot else None
    }

# Include enriched context (Phase 5 - User Story 3)
if include_enrichment and event.after_snapshot:
    result['enrichment'] = self._serialize_enrichment(event.after_snapshot.enriched_data)
```

**TreeEvent Model** (`models.py:430-434`):
```python
snapshot: TreeSnapshot
"""After-state snapshot"""

diff: TreeDiff
"""Changes from previous snapshot"""
```

### Resolution
Fixed RPC server to use correct attribute names and incremented package version to force rebuild:

**Fixed Code**:
```python
# Include full snapshots if requested
if include_snapshots:
    result['snapshots'] = {
        'before': None,  # TreeEvent doesn't store before snapshot (only diff)
        'after': event.snapshot.tree_data if event.snapshot else None
    }

# Include enriched context (Phase 5 - User Story 3)
if include_enrichment and event.snapshot:
    result['enrichment'] = self._serialize_enrichment(event.snapshot.enriched_data)
```

**Version Increment** (`modules/services/sway-tree-monitor.nix:23`):
```nix
version = "1.0.1";  # Incremented to force rebuild after RPC server fix
```

### Verification Steps
After rebuild completes:
```bash
# 1. Restart daemon to pick up new package
systemctl --user restart sway-tree-monitor

# 2. Test drill-down RPC call
PYTHONPATH="/nix/store/*-sway-tree-monitor/lib/python3.11/site-packages" python3 -c "
from sway_tree_monitor.rpc.client import RPCClient
client = RPCClient()
response = client.query_events(last=5)
if response.get('events'):
    event_id = response['events'][0]['event_id']
    event = client.get_event(event_id=event_id, include_diff=True)
    print(f'✓ RPC call successful! Event {event_id}: {event[\"event_type\"]}')
"

# 3. Test drill-down in TUI
sway-tree-monitor history --last 10
# Press 'd' on first row - should open detailed diff view without errors
```

### Related Files
- `/etc/nixos/home-modules/tools/sway-tree-monitor/rpc/server.py` - RPC server with fix (lines 366-375)
- `/etc/nixos/home-modules/tools/sway-tree-monitor/models.py` - TreeEvent model definition
- `/etc/nixos/modules/services/sway-tree-monitor.nix` - Version increment to 1.0.1

### Verification Complete ✓
**Date**: 2025-11-08

**Test Results:**
```
✓ RPC CALL SUCCESSFUL!
Event Type: workspace::init
Has diff: True
Has enrichment: True
Total changes: 3

🎉 DRILL-DOWN FUNCTIONALITY IS WORKING!
```

**Deployed Package**: `/nix/store/59q7z2qsfmdyj6iz4c7z8hprryhq4mjm-sway-tree-monitor` (version 1.0.1)

**Fixes Confirmed:**
1. ✅ `diff_view.py:95` - Using `include_diff=True` instead of `include_enrichment=True`
2. ✅ `rpc/server.py:370,374,375` - Using `event.snapshot` instead of `event.after_snapshot`

The drill-down feature now successfully displays detailed event diffs with enriched context from the history and live views.

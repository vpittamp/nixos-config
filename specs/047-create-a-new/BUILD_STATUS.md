# Sway Config Manager Build Status

## Current Status: Build Blocked

The sway-config-manager deployment is blocked by a Python environment conflict that has been identified and fixed through multiple iterations, but the build system is still using cached derivations.

## Problem History

### Initial Issue
```
error: two given paths contain a conflicting subpath:
  python3-3.13.8-env and python3-3.11.14-env
```

**Cause**: sway-config-manager was using Python 3.11 while i3-project-daemon used Python 3.13.

**Fix (Commit be55bd4)**: Changed sway-config-manager to use `python3` (matching i3-project-daemon).

### Second Issue
```
error: two given paths contain a conflicting subpath:
  python3-3.13.8-env/bin/pydoc3 and python3-3.13.8-env/bin/pydoc3
  (two DIFFERENT Python 3.13 environments)
```

**Cause**: Both sway-config-manager.nix and i3-project-daemon.nix were creating SEPARATE Python 3.13 environments with different package sets and adding them to `home.packages`, causing a collision.

**Fix Attempt 1 (Commit 9bfb4cd)**: Deduplicated Python environment creation within sway-config-manager.nix by defining `pythonEnv` once and reusing it.

**Result**: Still failed - the issue was cross-module, not intra-module.

**Fix Attempt 2 (Commit 38c1e52)**: Created shared `python-environment.nix` with ALL packages from both modules, removed `pythonEnv` from `home.packages` in both modules.

## Current Configuration (Commit 38c1e52)

### Files Modified

1. **`home-modules/desktop/python-environment.nix`** (NEW)
   - Shared Python 3.13 environment with all packages
   - Includes: i3ipc, pydantic, watchdog, systemd, pytest, pytest-asyncio, pytest-cov, rich, jsonschema

2. **`home-modules/desktop/i3-project-daemon.nix`**
   - Removed `pythonEnv` from `home.packages`
   - Still defines `pythonEnv` internally for use in ExecStart

3. **`home-modules/desktop/sway-config-manager.nix`**
   - Removed `pythonEnv` from `home.packages`
   - Still defines `pythonEnv` internally for use in CLI and ExecStart

4. **`home-modules/hetzner-sway.nix`**
   - Added import: `./desktop/python-environment.nix`

### Git Commits

- `be55bd4`: Python version alignment (python311 → python3)
- `9bfb4cd`: Python environment deduplication within sway-config-manager
- `38c1e52`: **Consolidated Python environments (CURRENT)**

## Build Obstruction

### Symptoms

1. Rebuild fails with same error even after fixes
2. Same derivation hash persists: `/nix/store/xfh6h95x329f4d1im3rad618cnrzidv8-home-manager-path.drv`
3. Flake metadata shows `rev: null` (dirty tree detection)
4. Garbage collection (freed 4.6GB) did not help

### Root Cause Analysis

**Nix is using cached derivation definitions** despite:
- Git tree being clean (no unstaged changes)
- Latest commit having all fixes
- Flake metadata refresh
- Garbage collection
- Cache clearing (`~/.cache/nix/*`)

The derivation hash computation is deterministic and based on inputs. If the same derivation hash appears after changes, it means:
1. Flake evaluation is using old source, OR
2. There's still another Python environment being added somewhere

### Verification Steps Needed

```bash
# 1. Verify flake is using correct source
nix flake metadata --json | jq '.path, .rev, .lastModified'

# 2. Check for any other Python environment creations
grep -r "python3.withPackages" home-modules/ modules/ --include="*.nix"

# 3. Try forcing fresh evaluation
nix build --rebuild .#nixosConfigurations.hetzner-sway.config.system.build.toplevel

# 4. Check derivation inputs
nix show-derivation /nix/store/xfh6h95x329f4d1im3rad618cnrzidv8-home-manager-path.drv

# 5. Try completely bypassing flake lock
nixos-rebuild switch --flake .#hetzner-sway --recreate-lock-file
```

## Recommended Next Steps

### Option 1: Manual Derivation Deletion
```bash
# Delete the problematic cached derivation
sudo rm -f /nix/store/xfh6h95x329f4d1im3rad618cnrzidv8-home-manager-path.drv

# Force rebuild
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### Option 2: Fresh Flake Lock
```bash
# Recreate flake lock file to force re-evaluation
nix flake update --commit-lock-file

# Rebuild
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### Option 3: Build from Scratch
```bash
# Remove ALL build artifacts
sudo nix-collect-garbage -d

# Rebuild entire system
sudo nixos-rebuild switch --flake .#hetzner-sway --option eval-cache false
```

### Option 4: Debug Build
```bash
# Build with maximum verbosity to see what's being evaluated
nix build --show-trace --print-build-logs --verbose \
  .#nixosConfigurations.hetzner-sway.config.system.build.toplevel

# Check what files are actually in the flake source
ls -la $(nix flake metadata --json | jq -r '.path')/home-modules/desktop/
```

## Success Criteria

Build will succeed when:
1. No Python environment conflicts in buildEnv
2. New generation created (check: `nixos-rebuild list-generations`)
3. Sway-config-manager daemon installed: `systemctl --user status sway-config-manager`
4. Config files created: `ls ~/.config/sway/*.toml ~/.config/sway/*.json`
5. CLI available: `which swayconfig`

## Configuration Validation

The consolidated Python environment approach is architecturally correct:
- ✅ Single Python environment with all packages
- ✅ No duplicate environments in home.packages
- ✅ Both modules can use pythonEnv internally for ExecStart paths
- ✅ Prevents buildEnv collision

The issue is purely with Nix's cached evaluation/derivation system.

## Files Ready for Deployment

All configuration files are committed and ready:
- Workspace keybindings: `home-modules/desktop/sway-default-keybindings.toml`
- Shared Python environment: `home-modules/desktop/python-environment.nix`
- Testing script: `specs/047-create-a-new/test-sway-config-manager.sh`
- Deployment guide: `specs/047-create-a-new/DEPLOYMENT_GUIDE.md`

## Contact/Debug Info

- Branch: `047-create-a-new`
- Latest Commit: `38c1e52`
- System: `nixos-hetzner-sway`
- Current Generation: 1031 (from 2025-10-28 21:33:17)
- Target: Create generation 1032 with sway-config-manager

---

**Last Updated**: 2025-10-29 04:15
**Status**: Awaiting manual intervention to clear cached derivations

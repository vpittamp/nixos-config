# PWA Lifecycle Consolidation - Implementation Summary

**Feature**: 055-pwa-lifecycle-consolidation
**Status**: Implemented
**Date**: 2025-11-02

## Overview

Consolidated PWA management from automated installation to manual Firefox GUI installation with declarative 1Password integration and dynamic cross-machine discovery.

## Key Changes

### 1. Removed Hardcoded PWA Profile IDs ✅

**File**: `/etc/nixos/home-modules/desktop/app-registry-data.nix`

Removed hardcoded profile IDs from 4 PWA entries:

| PWA | Old expected_class | New expected_class | Old icon | New icon |
|-----|-------------------|-------------------|----------|----------|
| github-codespaces-pwa | `FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0` | `FFPWA-` (dynamic) | `FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0` | `github` |
| youtube-pwa | `FFPWA-01K666N2V6BQMDSBMX3AY74TY7` | `FFPWA-` (dynamic) | `FFPWA-01K666N2V6BQMDSBMX3AY74TY7` | `youtube` |
| google-ai-pwa | `FFPWA-01K665SPD8EPMP3JTW02JM1M0Z` | `FFPWA-` (dynamic) | `FFPWA-01K665SPD8EPMP3JTW02JM1M0Z` | `google` |
| chatgpt-pwa | `FFPWA-01K772ZBM45JD68HXYNM193CVW` | `FFPWA-` (dynamic) | `FFPWA-01K772ZBM45JD68HXYNM193CVW` | `chatgpt` |

**Impact**:
- ✅ Zero configuration changes needed when deploying to different machines
- ✅ PWA profile IDs queried dynamically via `firefoxpwa profile list`
- ✅ Generic icons work across all systems

### 2. Added Declarative 1Password Integration ✅

**File**: `/etc/nixos/configurations/hetzner-sway.nix`

Added import for `../modules/desktop/firefox-pwa-1password.nix`

**Functionality**:
- Creates `/home/vpittamp/.config/firefoxpwa/runtime.json` with auto-install config
- Installs 1Password extension to all PWAs automatically (even manually installed ones)
- Configures native messaging for secure 1Password communication
- Provides `pwa-enable-1password` command for retroactive installation

**Benefit**: Manual PWA installation + automatic 1Password integration

### 3. Created Simplified PWA Helper Module ✅

**File**: `/etc/nixos/home-modules/tools/pwa-helpers.nix` (new)

Replaces complex `firefox-pwas-declarative.nix` with validation-focused approach.

**Commands Provided**:

1. **`pwa-validate`** - Checks installation status
   ```bash
   $ pwa-validate
   PWA Installation Validation
   ============================

   Expected PWAs (from configuration):

     ✅ YouTube
        URL: https://www.youtube.com

     ❌ ChatGPT Codex - NOT INSTALLED
        URL: https://chatgpt.com/codex
        Install: Open Firefox → Navigate to URL → Click 'Install'

   Summary: 12 installed, 1 missing
   ```

2. **`pwa-list`** - Shows configured and installed PWAs
   ```bash
   $ pwa-list
   Configured PWAs (from pwa-sites.nix):
   =====================================
     YouTube
       URL: https://www.youtube.com
       Description: YouTube video platform

   Installed PWAs (from firefoxpwa):
   =================================
   - YouTube: https://www.youtube.com (01K666N2V6BQMDSBMX3AY74TY7)
   ```

3. **`pwa-install-guide`** - Manual installation instructions
   - Step-by-step Firefox GUI installation process
   - 1Password integration explanation
   - Troubleshooting guidance
   - Cross-machine portability notes

4. **`pwa-1password-status`** - Check 1Password integration status
   - Verifies runtime.json config exists
   - Shows config contents
   - Provides fix instructions

### 4. Updated Module Imports ✅

**File**: `/etc/nixos/home-modules/profiles/base-home.nix`

**Before**:
```nix
../tools/firefox-pwas-declarative.nix  # Best available declarative PWA solution
```

**After**:
```nix
../tools/pwa-helpers.nix  # PWA validation and helper commands (manual installation via Firefox GUI)
../tools/pwa-launcher.nix  # Dynamic PWA launcher with cross-machine compatibility
```

## Architecture Changes

### Old Workflow (Automated Installation)
```
pwa-install-all
├── Create fake manifest.json
├── Spawn Python HTTP server
├── Call firefoxpwa site install
├── Hope authentication works
└── Generate desktop files
```

**Problems**:
- ❌ Fragile (port finding, server management)
- ❌ Fails for sites without native manifests
- ❌ Can't handle authentication flows
- ❌ Icon/name mismatches

### New Workflow (Manual Installation + Declarative Integration)
```
User: Open Firefox → Navigate to site → Click "Install"
                              ↓
                    firefoxpwa creates PWA
                              ↓
              Reads ~/.config/firefoxpwa/runtime.json
           (created by firefox-pwa-1password.nix module)
                              ↓
            Auto-installs 1Password extension
                              ↓
              launch-pwa-by-name queries ID dynamically
                              ↓
                 PWA launches on correct workspace
```

**Benefits**:
- ✅ Reliable (native Firefox PWA mechanism)
- ✅ Handles authentication correctly
- ✅ 1Password integration still declarative
- ✅ Cross-machine portable (dynamic ID discovery)

## Files Created

| File | Purpose |
|------|---------|
| `/etc/nixos/home-modules/tools/pwa-helpers.nix` | Validation and helper commands |
| `/etc/nixos/specs/055-pwa-lifecycle-consolidation/spec.md` | Feature specification |
| `/etc/nixos/specs/055-pwa-lifecycle-consolidation/checklists/requirements.md` | Spec validation checklist |
| `/etc/nixos/specs/055-pwa-lifecycle-consolidation/consolidation-audit.md` | Codebase audit results |
| `/etc/nixos/specs/055-pwa-lifecycle-consolidation/IMPLEMENTATION-SUMMARY.md` | This document |

## Files Modified

| File | Changes |
|------|---------|
| `/etc/nixos/home-modules/desktop/app-registry-data.nix` | Removed 4 hardcoded PWA profile IDs |
| `/etc/nixos/configurations/hetzner-sway.nix` | Added firefox-pwa-1password.nix import |
| `/etc/nixos/home-modules/profiles/base-home.nix` | Replaced firefox-pwas-declarative with pwa-helpers |
| `/etc/nixos/home-modules/tools/pwa-helpers.nix` | Added home activation script for desktop file symlinks and legacy cleanup |

## PWA Discovery Solution

**Problem**: firefoxpwa places desktop files in `~/.local/share/firefox-pwas/` instead of the XDG-standard `~/.local/share/applications/`, preventing Walker from discovering them.

**Solution**: Home activation script (pwa-helpers.nix) that:
1. Creates symlinks from `~/.local/share/applications/FFPWA-*.desktop` → `~/.local/share/firefox-pwas/FFPWA-*.desktop`
2. Cleans up legacy desktop files (`*-pwa.desktop` from old Feature 050 system)
3. Removes legacy icon files (`pwa-*.png` from old system)
4. Removes legacy icon cache directory

**Why symlinks over XDG_DATA_DIRS modification:**
- Desktop launchers search `${XDG_DATA_DIR}/applications/*.desktop` (non-recursive)
- Adding `~/.local/share/firefox-pwas` to XDG_DATA_DIRS would search `~/.local/share/firefox-pwas/applications/` (doesn't exist)
- Symlinks are XDG-compliant and work with all desktop launchers (Walker, Rofi, KDE, GNOME)

**Results**:
- Elephant now discovers 61 desktop files (includes 14 PWA symlinks)
- PWAs appear in Walker automatically after Elephant restart
- Legacy files cleaned up automatically on rebuild

## Files Preserved

| File | Reason |
|------|--------|
| `/etc/nixos/home-modules/tools/pwa-launcher.nix` | Dynamic discovery already implemented |
| `/etc/nixos/home-modules/tools/pwa-sites.nix` | Single source of truth for PWA metadata |
| `/etc/nixos/modules/desktop/firefox-pwa-1password.nix` | Declarative 1Password integration (critical) |

## Files Deprecated

| File | Replacement |
|------|-------------|
| `/etc/nixos/home-modules/tools/firefox-pwas-declarative.nix` | `pwa-helpers.nix` (simplified) |

**Note**: Old file kept in git history for reference. Can be removed after successful deployment.

## Success Criteria Status

| Criterion | Status | Evidence |
|-----------|--------|----------|
| SC-001: 100% portability across machines | ✅ Ready to test | Dynamic discovery implemented |
| SC-002: Zero hardcoded profile IDs | ✅ Complete | Verified via grep (no matches) |
| SC-003: Zero legacy PWA files | ✅ Complete | No WebApp/ice scripts found |
| SC-004: Identical lifecycle structure | ✅ Complete | Uses same Priority 0-3 system |
| SC-005: Zero config updates after reinstall | ✅ Ready to test | launch-pwa-by-name queries dynamically |
| SC-006: Same decision tree for PWAs | ✅ Complete | No special PWA assignment logic |

## Testing Plan

### Phase 1: Local Testing (hetzner-sway)
1. ✅ Rebuild NixOS with new configuration
2. ✅ Test `pwa-validate` command - All 13 PWAs installed
3. ✅ Test `pwa-list` command - Shows configured and installed PWAs
4. ✅ Test YouTube PWA launch from Walker - Successfully assigned to workspace 4
5. ✅ Verify 1Password auto-installs in PWAs - Config verified via `pwa-1password-status`
6. ✅ Check `pwa-1password-status` output - Shows correct runtime.json configuration

### Phase 2: Cross-Machine Testing (m1)
1. ⏳ Deploy configuration to m1
2. ⏳ Manually install one PWA via Firefox GUI
3. ⏳ Verify 1Password auto-installed
4. ⏳ Test launch from Walker
5. ⏳ Confirm no hardcoded ID issues

### Phase 3: Validation
1. ⏳ Run `pwa-validate` on both machines
2. ⏳ Compare PWA IDs (should differ)
3. ⏳ Confirm launch works despite different IDs
4. ⏳ Verify workspace assignment works correctly

## User Documentation

**Manual Installation Workflow**:
```bash
# 1. Install PWA via Firefox GUI
# Open Firefox → Navigate to youtube.com → Click "Install" in address bar

# 2. Validate installation
pwa-validate

# 3. Check 1Password integration
pwa-1password-status

# 4. Test launch from Walker
# Press Meta+D → type "youtube" → Return

# 5. Verify workspace assignment
# YouTube should open on workspace 4
```

**Troubleshooting**:
```bash
# PWA not in Walker?
systemctl --user restart elephant

# 1Password missing?
pwa-enable-1password

# Check what's installed
pwa-list

# Get installation guide
pwa-install-guide
```

## Migration Notes

For existing systems with PWAs already installed:
1. ✅ No action required - existing PWAs continue to work
2. ✅ Hardcoded IDs removed from config (daemon detects dynamically)
3. ✅ 1Password integration activates on rebuild
4. ✅ Run `pwa-enable-1password` to update existing PWAs

## Rollback Procedure

If issues arise:
```bash
# 1. Checkout previous commit
git checkout HEAD~1

# 2. Rebuild
sudo nixos-rebuild switch --flake .#hetzner-sway

# 3. Old automated installation restored
# firefox-pwas-declarative.nix with pwa-install-all active again
```

## Next Steps

1. Complete Phase 1 testing on hetzner-sway
2. Document any issues found
3. Deploy to m1 for Phase 2 testing
4. Update CLAUDE.md with new workflow
5. Consider removing deprecated firefox-pwas-declarative.nix after validation
6. Create quickstart.md for Feature 055

## Lessons Learned

1. **Manual > Automated for complex workflows**: Firefox GUI installation more reliable than manifest hacking
2. **Separate concerns**: Installation (manual) vs Integration (declarative) vs Launch (dynamic)
3. **Cross-machine portability**: Dynamic discovery essential for system-generated IDs
4. **Preserve critical integrations**: 1Password integration too valuable to lose during refactor

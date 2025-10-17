# Project Activities Removal Plan

**Date**: 2025-10-17
**Context**: Removing KDE Plasma-specific project activities system during i3wm migration

## Overview

The project activities system is deeply integrated with KDE Plasma and incompatible with i3wm. This document tracks the careful removal of this functionality.

## Components to Remove

### 1. Core Project Activities Module
- **Path**: `home-modules/desktop/project-activities/`
- **Files**:
  - `default.nix` - Main orchestrator (410 lines)
  - `data.nix` - Activity definitions
  - `panels.nix` - KDE panel configuration with PWA integration
  - `desktop-widgets.nix` - Desktop folder widgets
- **Dependencies**: KDE Activities, kactivitymanagerd, plasma-manager
- **Impact**: High - Core of activity system

### 2. Activity-Aware Applications
- **Path**: `home-modules/desktop/activity-aware-apps-native.nix`
- **Purpose**: Launches apps (konsole, code, dolphin) in activity-specific directories
- **Features**:
  - Activity-aware launchers (konsole-activity, code-activity, etc.)
  - KWin window rules for activity assignment
  - Yakuake activity sync
  - Desktop entry overrides
- **Impact**: Medium - Workflow convenience, not essential

### 3. Imports and References
- **plasma-home.nix**: Line 9 imports project-activities
- **plasma-home.nix**: Line 10 imports activity-aware-apps-native.nix
- **PWA documents**: References in PWA_PARAMETERIZATION.md, PWA_COMPARISON.md, etc.

## Dependencies Analysis

### What Depends on Project Activities?
1. **plasma-home.nix** - Direct import
2. **panels.nix** - References PWA IDs (e.g., tailscaleId) for taskbar pinning
3. **KDE window rules** - Activity assignment rules
4. **Sesh integration** - Activity-aware session management (home-modules/terminal/sesh.nix)

### What Does NOT Depend on It?
✅ **firefox-pwas-declarative.nix** - Standalone PWA system
✅ **i3wm configuration** - Completely independent
✅ **clipcat** - Clipboard manager works without activities
✅ **1Password** - Authentication system independent
✅ **xrdp** - Remote desktop independent

## Removal Strategy

### Phase 1: Disable Imports (Safe)
1. Comment out imports in plasma-home.nix
2. Test build to identify any broken references
3. Fix broken references progressively

### Phase 2: Archive (Reversible)
1. Move project-activities/ to archived/
2. Move activity-aware-apps-native.nix to archived/
3. Keep in git history for reference

### Phase 3: Clean Documentation (Final)
1. Update docs to remove activity references
2. Mark activity-specific docs as obsolete
3. Create migration notes

## Known Issues to Address

### M1 Build Error
- **Error**: Missing tailscaleId in panels.nix:53
- **Root Cause**: panels.nix references PWA IDs from project-activities/data.nix
- **Solution**: Remove panels.nix reference OR define fallback PWA IDs
- **Priority**: HIGH - Blocks M1 builds

### Sesh Integration
- **File**: home-modules/terminal/sesh.nix
- **Issue**: May reference activity directories
- **Solution**: Verify and remove activity dependencies

## Testing Checklist

After removal:
- [ ] hetzner-i3 builds successfully
- [ ] m1 builds successfully (fix tailscaleId issue)
- [ ] container builds successfully
- [ ] Firefox PWAs still work (declarative system)
- [ ] No references to project-activities in active modules
- [ ] Documentation updated

## Preserved Functionality

✅ Firefox PWAs (via firefox-pwas-declarative.nix)
✅ Clipboard management (clipcat)
✅ Remote desktop (xrdp)
✅ 1Password integration
✅ Basic workspace management (i3wm workspaces replace activities)

## Migration Notes

Users who relied on project activities should:
1. Use i3wm workspaces (Ctrl+1-9) instead of activities
2. Manually organize projects in directories
3. Use tmux sessions for project context switching
4. Consider tools like `zoxide` or `sesh` for directory navigation

---

**Status**: Planning Complete
**Next**: Execute removal in plasma-home.nix

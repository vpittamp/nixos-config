# Plasma Configuration Strategy

## Overview

This NixOS configuration uses a **hybrid approach** for managing KDE Plasma settings:
- **Declarative configuration** for portable, machine-independent settings
- **Runtime snapshots** for discovery and reference
- **Smart filtering** to avoid managing system-generated IDs

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    KDE Plasma GUI                       │
│              (User makes changes here)                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ├─→ Writes to ~/.config/*rc files
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
┌───────────────┐         ┌──────────────────┐
│  plasma-sync  │         │ Declarative Nix  │
│   snapshot    │         │  Configuration   │
└───────┬───────┘         └────────┬─────────┘
        │                          │
        ├─→ plasma-rc2nix         │
        │   export tool           │
        │                          │
        ▼                          ▼
┌─────────────────────────────────────────┐
│  generated/plasma-rc2nix.nix            │
│  (Reference/Analysis Only)              │
│  • Contains ALL settings                │
│  • Includes system-generated IDs        │
│  • Used for comparison                  │
└──────────┬──────────────────────────────┘
           │
           ├─→ Analyzed by plasma-snapshot-analysis.nix
           │   • Filters system IDs
           │   • Identifies unmanaged settings
           │   • Provides recommendations
           │
           └─→ Selectively imported by:
               • kwin-window-rules.nix (transforms UUIDs)
               • plasma-config.nix (explicit settings only)
```

## Decision Tree: What Goes Where?

### ✅ ALWAYS Manage Declaratively

These settings are **portable** and **reproducible** across machines:

1. **Keyboard Shortcuts** ([plasma-config.nix](../home-modules/desktop/plasma-config.nix:177-221))
   - KWin shortcuts (window management)
   - Activity shortcuts
   - Application launchers
   - Screenshot tools (Spectacle)

2. **Theme and Appearance**
   - Global theme (`workspace.theme`)
   - Icon theme (`workspace.iconTheme`)
   - Color schemes
   - Fonts and DPI

3. **Window Behavior**
   - Focus policy
   - Click to raise
   - Window placement
   - Compositing settings

4. **Desktop Effects**
   - Blur, transparency
   - Overview effect
   - Animations
   - Screen edges (hot corners)

5. **Session Settings**
   - Login mode (empty session)
   - Wallet configuration
   - Logout confirmation

6. **Activity Definitions** ([project-activities/data.nix](../home-modules/desktop/project-activities/data.nix:83-213))
   - Activity names, icons, descriptions
   - Canonical UUIDs (for window rules)
   - Directory associations
   - Color schemes per activity

### ❌ NEVER Manage Declaratively

These are **system-generated** or **runtime state** - let KDE manage them:

1. **Virtual Desktop UUIDs**
   ```nix
   # BAD - Don't manage these
   Id_1 = "591120e4-308d-4d9e-8ebb-5ea1c30f227d";
   Id_2 = "91e013fb-57bf-4e10-8849-e176e71ba3e5";

   # GOOD - Manage count/layout only
   Number = 2;
   Rows = 1;
   ```

2. **Activity Runtime State**
   ```nix
   # BAD - Don't manage these
   currentActivity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
   runningActivities = "...";

   # GOOD - Activities are bootstrapped by default.nix
   ```

3. **Subsession/Tiling UUIDs**
   ```nix
   # BAD - These are generated dynamically
   "SubSession: a8f3c9d2-7b4e-4d6f-9e2a-1c5b8d3f6a9e" = {...};
   "Tiling/7672d168-2ff3-5755-8864-62ce0326032c" = {...};
   ```

4. **Timestamps**
   ```nix
   ViewPropsTimestamp = "2025,9,27,10,23,24.483";
   ```

5. **Database Versions**
   ```nix
   dbVersion = 2;
   ```

### 🤔 Hybrid: Analyze Then Decide

Consider managing these based on your needs:

1. **Application Preferences**
   - **Kate** ([plasma-config.nix](../home-modules/desktop/plasma-config.nix:124-132)): Editor preferences ✅ Managed
   - **Dolphin** ([plasma-config.nix](../home-modules/desktop/plasma-config.nix:112-121)): File manager settings ✅ Managed
   - **Konsole**: Terminal profiles (consider managing)

2. **Window Rules** ([kwin-window-rules.nix](../home-modules/desktop/kwin-window-rules.nix:1-119))
   - ✅ **Already handled**: Uses transformer to map UUIDs
   - Imports snapshot, replaces machine-specific UUIDs with canonical ones from data.nix

3. **Panel Configurations** ([project-activities/panels.nix](../home-modules/desktop/project-activities/panels.nix:1-316))
   - ✅ **Managed declaratively** using plasma-manager's `programs.plasma.panels` API
   - High-level Nix options (location, widgets, config) instead of raw INI
   - Automatic JavaScript/layout.js generation and cleanup
   - PWA IDs still require machine-specific mapping (as expected)
   - Much cleaner than previous 400+ line INI approach

4. **Notification Settings**
   - Consider managing if you want consistent behavior
   - Currently: Not managed (inherits KDE defaults)

## Workflow: Adopting GUI Changes

### Step 1: Make Changes in GUI
```bash
# Configure your KDE settings using System Settings GUI
# Make window rules, change themes, adjust keyboard shortcuts, etc.
```

### Step 2: Export Snapshot
```bash
# Export current KDE config to snapshot file
plasma-export

# This automatically:
#  - Runs scripts/plasma-rc2nix.sh
#  - Saves to home-modules/desktop/generated/plasma-rc2nix.nix
#  - Creates timestamped backup of previous version
#  - Shows next steps

# Note: rc2nix does NOT export panel configurations
# Panels are managed via programs.plasma.panels in panels.nix
```

### Step 3: Analyze Changes
```bash
# Quick summary of what changed
plasma-diff-summary

# View full diff
plasma-diff

# Or use git directly
git diff home-modules/desktop/generated/plasma-rc2nix.nix

# See which config files changed
/etc/nixos/scripts/plasma-diff.sh --config-files
```

### Step 4: Decide What to Adopt

**For portable settings (keyboard shortcuts, themes, etc.):**
```bash
# Edit the declarative config
$EDITOR home-modules/desktop/plasma-config.nix

# Add the setting explicitly:
configFile."kwinrc".Windows = {
  FocusPolicy = "ClickToFocus";  # Found in snapshot, now declarative
};
```

**For system-generated items (UUIDs, IDs):**
```bash
# Don't add to declarative config
# These are managed automatically by:
#   - kwin-window-rules.nix (for window rules)
#   - project-activities/default.nix (for activities)
```

### Step 5: Rebuild and Test
```bash
# Test the configuration
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply if successful
sudo nixos-rebuild switch --flake .#hetzner
```

### Step 6: Commit Both Files
```bash
# Commit declarative changes
git add home-modules/desktop/plasma-config.nix
git commit -m "feat: Add click-to-focus window policy"

# Also commit snapshot for reference
git add home-modules/desktop/generated/plasma-rc2nix.nix
git commit -m "chore: Update plasma snapshot"
```

## Current Configuration Status

### Managed Declaratively

| Category | File | Sections |
|----------|------|----------|
| Window behavior | `kwinrc` | Compositing, Windows, Plugins, Effects |
| Shortcuts | `kwinrc` | All KWin shortcuts |
| Activities | `plasmashell` | Activity switching shortcuts |
| Screenshots | `spectaclerc` | Spectacle shortcuts |
| Wallet | `kwalletrc` | Wallet settings |
| Session | `ksmserverrc` | Login/logout behavior |
| Indexing | `baloofilerc` | File indexing (disabled) |
| File manager | `dolphinrc` | Dolphin preferences |
| Text editor | `katerc` | Kate preferences |
| Window rules | `kwinrulesrc` | Via transformer (UUIDs mapped) |

### Not Managed (Runtime State)

| Category | File | Reason |
|----------|------|--------|
| Virtual desktop IDs | `kwinrc` | System-generated UUIDs |
| Activity state | `kactivitymanagerdrc` | Runtime (current/running activities) |
| Tiling layouts | `kwinrc` | Dynamic layout UUIDs |
| Timestamps | Various | Temporal data |

### Reference Only (Snapshot)

| File | Purpose |
|------|---------|
| `generated/plasma-rc2nix.nix` | Full export for analysis/comparison |
| Via `plasma-snapshot-analysis.nix` | Filtered view, recommendations |

## Tools and Commands

### Snapshot Management
```bash
# Export current KDE config to snapshot (recommended workflow)
plasma-export
# - Exports to generated/plasma-rc2nix.nix
# - Creates timestamped backup
# - Shows next steps

# View changes in snapshot
plasma-diff-summary           # Quick summary
plasma-diff                   # Full diff
/etc/nixos/scripts/plasma-diff.sh --config-files  # List changed files

# Alternative: Full workflow with plasma-sync
plasma-sync                    # Interactive TUI menu
plasma-sync snapshot          # Take snapshot only
plasma-sync diff              # View snapshot diff
plasma-sync git-diff          # View git diff
plasma-sync full              # Snapshot + activate
```

### Analysis
```bash
# View what's in snapshot but not managed
nix eval .#nixosConfigurations.hetzner.config.home-manager.users.vpittamp.plasma.analysis.unmanaged

# View recommended settings to manage
nix eval .#nixosConfigurations.hetzner.config.home-manager.users.vpittamp.plasma.analysis.recommendations

# Summary statistics
nix eval .#nixosConfigurations.hetzner.config.home-manager.users.vpittamp.plasma.analysis.summary
```

### Configuration Management
```bash
# Test changes
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner

# For home-manager only
home-manager switch --flake .#vpittamp
```

## Best Practices

### 1. Use Snapshots for Discovery
- Export snapshots after making GUI changes
- Use diff to see what changed
- Manually adopt settings into declarative config
- Don't auto-apply snapshots

### 2. Keep Declarative Config Clean
- Only add settings you understand
- Document why you're managing each setting
- Use comments to explain non-obvious values
- Group related settings together

### 3. Commit Both Declarative and Snapshots
- Declarative config: Your intent
- Snapshot: Current state for reference
- Commits should explain what changed and why

### 4. Handle Machine-Specific Settings
```nix
# Use osConfig.networking.hostName for machine-specific values
configFile."kcmfonts".General.forceFontDPI =
  if osConfig.networking.hostName == "nixos-m1"
  then 180  # HiDPI for M1 Mac
  else 100; # Normal DPI for Hetzner
```

### 5. Leave Complexity to KDE
- Don't try to manage every setting declaratively
- Panel widget IDs: Too complex, manage via GUI
- Activity runtime state: Let KDE handle it
- Focus on settings that improve reproducibility

## Troubleshooting

### Problem: Settings Reset After Rebuild
**Symptom**: GUI changes disappear after `nixos-rebuild`

**Cause**: `overrideConfig = true` would reset files, but we use `immutableByDefault = false`

**Solution**: Check if setting is in declarative config with different value
```bash
# Find conflicts
plasma-sync diff
git diff home-modules/desktop/plasma-config.nix
```

### Problem: Window Rules Not Working
**Symptom**: Window rules don't match windows

**Cause**: Activity UUIDs in rules don't match system UUIDs

**Solution**: Transformer should handle this automatically
```bash
# Verify transformer is working
grep "activity.*=" home-modules/desktop/generated/plasma-rc2nix.nix
grep "uuid.*=" home-modules/desktop/project-activities/data.nix
```

### Problem: Can't Find Where Setting Lives
**Symptom**: Made GUI change, can't find it in snapshot

**Cause**: Not all settings go in `*rc` files

**Solution**:
1. Export snapshot: `plasma-export`
2. Search snapshot: `rg "setting-name" home-modules/desktop/generated/plasma-rc2nix.nix`
3. Check KDE config: `ls ~/.config/*rc`

### Problem: Too Many System-Generated IDs in Snapshot
**Symptom**: Snapshot diff is noisy with UUIDs

**Cause**: Normal - KDE generates many dynamic IDs

**Solution**: Use analysis module to filter
```bash
# View filtered snapshot (IDs removed)
nix eval .#nixosConfigurations.hetzner.config.home-manager.users.vpittamp.plasma.analysis.filtered
```

## Migration Guide

### From Pure GUI Config
If you're coming from manual KDE configuration:

1. Export current state: `plasma-export`
2. Review snapshot: `plasma-sync diff`
3. Identify settings you want reproducible
4. Add to `plasma-config.nix` incrementally
5. Test on second machine to verify portability

### From Pure Declarative
If you're trying to make everything declarative:

1. Accept you can't manage everything
2. Focus on high-value settings (shortcuts, themes, behavior)
3. Use snapshots for reference, not application
4. Let KDE manage runtime state and complex GUIs

### To Another Machine
When setting up a new machine:

1. Clone nixos repo
2. Run `nixos-rebuild switch --flake .#<target>`
3. Declarative settings apply automatically
4. Activities bootstrap via activation script
5. Window rules use canonical UUIDs (work everywhere)
6. Panel layout may need manual tweaking (widget IDs)

## References

- [plasma-manager README](https://github.com/nix-community/plasma-manager)
- [PLASMA_MANAGER.md](PLASMA_MANAGER.md) - Snapshot workflow
- [kwin-window-rules.nix](../home-modules/desktop/kwin-window-rules.nix) - UUID transformer
- [project-activities/data.nix](../home-modules/desktop/project-activities/data.nix) - Activity definitions
- [plasma-config.nix](../home-modules/desktop/plasma-config.nix) - Declarative config

## Contributing

When adding new declarative settings:

1. Test on at least one machine
2. Document why the setting should be managed
3. Explain any non-obvious values in comments
4. Verify portability (doesn't break on other hosts)
5. Update this document if adding new category

---

**Last Updated**: 2025-10 (Initial strategy documentation)

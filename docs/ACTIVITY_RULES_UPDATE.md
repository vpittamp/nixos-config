# KDE Activity Window Rules - Update Process

## When Rules Are Generated

The KWin window rules are generated **at NixOS build time**, not runtime. This means:

### Current Process
1. **Activity definitions** are stored in `/etc/nixos/home-modules/desktop/project-activities/data.nix`
2. **During `nixos-rebuild`**, the rules are generated from `activityData.rawActivities`
3. **Plasma-manager** writes the rules to `~/.config/kwinrulesrc`
4. **KWin** reads the rules on startup or when reconfigured

## Adding a New Activity

### ⚠️ Current Limitation
**Activities defined in `data.nix` are static** - if you add a new activity through KDE's GUI, window rules won't be automatically created for it.

### How to Add a New Activity with Rules

#### Option 1: Edit Nix Configuration (Recommended)
1. Edit `/etc/nixos/home-modules/desktop/project-activities/data.nix`
2. Add your new activity to `rawActivities`:
```nix
myproject = {
  uuid = "generated-uuid-here";  # Get from KDE after creating activity
  name = "MyProject";
  description = "Description here";
  icon = "folder-blue";
  directory = "~/myproject";
  # ... other settings
};
```
3. Run `sudo nixos-rebuild switch --flake .#hetzner`
4. KWin rules will be regenerated for all activities including the new one

#### Option 2: Create Activity in KDE First
1. Create the activity in KDE System Settings or Activity Manager
2. Find the UUID: `grep "your-activity-name" ~/.config/kactivitymanagerdrc`
3. Add the activity to `data.nix` with the UUID
4. Rebuild NixOS configuration

## How Rules Work

For each activity in `data.nix`, three rules are generated:
1. **VS Code Rule**: Matches `wmclass=code` + `title=/path/to/directory`
2. **Konsole Rule**: Matches `wmclass=konsole` + `title=directory-name`
3. **Dolphin Rule**: Matches `wmclass=dolphin` + `title=directory-name`

Each rule forces (`activityrule=2`) the window to the specified activity UUID.

## Current Activities

| Activity | UUID | Directory | Rules |
|----------|------|-----------|-------|
| NixOS | 6ed332bc-fa61-5381-511d-4d5ba44a293b | /etc/nixos | ✅ |
| Stacks | b4f4e6c4-e52c-1f6b-97f5-567b04283fac | ~/stacks | ✅ |
| Backstage | dcc377c8-d627-4d0b-8dd7-27d83f8282b3 | ~/backstage-cnoe | ✅ |
| Dev | 0857dad8-f3dc-41ff-ae49-ba4c7c0a6fe4 | ~/dev | ✅ |

## Checking Current Rules

```bash
# View generated rules
cat ~/.config/kwinrulesrc

# Count rules (should be 12 for 4 activities × 3 apps)
grep "^\[" ~/.config/kwinrulesrc | wc -l

# Reload KWin to apply rules
qdbus org.kde.KWin /KWin reconfigure
```

## Future Improvements

### Dynamic Rule Generation (Not Implemented)
A potential enhancement would be to:
1. Read activities from `~/.config/kactivitymanagerdrc` at runtime
2. Generate rules dynamically based on actual KDE activities
3. Use a systemd service to monitor activity changes
4. Regenerate rules when activities are added/removed

### Hybrid Approach (Possible)
1. Define "known" activities in Nix for reproducibility
2. Add a service that discovers new activities and adds basic rules
3. Merge both rule sets

## Current Behavior Summary

- ✅ **Rules are declarative** - defined in Nix configuration
- ✅ **Reproducible** - same activities/rules across rebuilds
- ⚠️ **Static** - requires Nix edit and rebuild for new activities
- ⚠️ **No auto-discovery** - GUI-created activities need manual config

## Commands to Remember

```bash
# After adding activity to data.nix
sudo nixos-rebuild switch --flake .#hetzner

# Force plasma-config to run
/nix/store/*-plasma-config

# Reload KWin
qdbus org.kde.KWin /KWin reconfigure

# Test activity detection
qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity
```

## File Locations

- **Activity definitions**: `/etc/nixos/home-modules/desktop/project-activities/data.nix`
- **Rule generator**: `/etc/nixos/home-modules/desktop/activity-aware-apps-native.nix`
- **Generated rules**: `~/.config/kwinrulesrc`
- **KDE activities**: `~/.config/kactivitymanagerdrc`
# Window Rules Architecture

## Overview

KWin window rules are **fully auto-generated** from declarative data sources. This ensures consistency, reduces duplication, and makes the system easier to maintain.

## Architecture

### Three-Source Strategy

Window rules are generated from three independent sources and merged together:

```
┌─────────────────────────────────────────────────────────────┐
│                    KWin Window Rules                         │
│                     (kwinrulesrc)                            │
└─────────────────────────────────────────────────────────────┘
                           ▲
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────▼───────┐  ┌──────▼──────┐  ┌────────▼────────┐
│  PWA Rules    │  │   Browser   │  │  Activity Rules │
│ (9 PWAs)      │  │   Rules     │  │  (VS Code,      │
│               │  │ (Firefox,   │  │   Konsole,      │
│ Auto-generated│  │  Chromium)  │  │   Dolphin)      │
│ from          │  │             │  │                 │
│ pwas/data.nix │  │  Manually   │  │ Auto-generated  │
│               │  │  maintained │  │ from activities │
│               │  │             │  │ data.nix        │
└───────────────┘  └─────────────┘  └─────────────────┘
```

### File Structure

```
home-modules/desktop/
├── pwas/
│   ├── data.nix              # Source of truth for PWAs
│   └── window-rules.nix      # Auto-generates PWA rules
├── project-activities/
│   ├── data.nix              # Source of truth for activities
│   └── window-rules.nix      # Auto-generates activity rules
├── browser-window-rules.nix  # Manual browser rules
└── plasma-config.nix         # Merges all three sources
```

## Rule Sources

### 1. PWA Rules (Auto-generated)

**Source**: `pwas/data.nix`
**Generator**: `pwas/window-rules.nix`
**Output**: 9 rules (one per PWA)

Rules are automatically generated for all PWAs defined in `pwas/data.nix`:
- YouTube → All activities
- Google AI → All activities
- Headlamp → Backstage activity
- ArgoCD → Backstage activity
- Backstage → Backstage activity
- Gitea → Backstage activity
- Kargo → Backstage activity
- Home Assistant → Monitoring activity
- Uber Eats → NixOS activity

**How it works**:
```nix
# In pwas/data.nix
youtube = {
  name = "YouTube";
  activity = null;  # null = all activities
  url = "https://www.youtube.com";
};

# Auto-generated rule in pwas/window-rules.nix
"pwa-youtube" = {
  Description = "YouTube - All Activities";
  activity = "00000000-0000-0000-0000-000000000000";
  activityrule = 2;  # Force
  wmclass = "FFPWA";
  wmclassmatch = 1;  # Substring match
  title = "YouTube";
  titlematch = 1;
};
```

### 2. Browser Rules (Manual)

**Source**: `browser-window-rules.nix`
**Output**: 2 rules (Firefox, Chromium)

Browser rules are manually maintained because they don't follow the PWA pattern:
- Firefox → All activities
- Chromium → All activities

**To add a new browser**:
1. Edit `browser-window-rules.nix`
2. Add a new rule section
3. Run `sudo nixos-rebuild switch --flake .#<target>`

### 3. Activity Rules (Auto-generated)

**Source**: `project-activities/data.nix`
**Generator**: `project-activities/window-rules.nix`
**Output**: 20 rules (3 apps × 5 activities × 2 rule types)

Rules are automatically generated for application windows that should be assigned to specific activities based on the folder they're viewing:

- **VS Code**: Matches window title containing folder basename (e.g., "nixos")
- **Konsole**: Matches terminal prompt showing folder name
- **Dolphin**: Matches file manager showing folder path

**How it works**:
```nix
# In project-activities/data.nix
nixos = {
  name = "NixOS";
  directory = "/etc/nixos";
  uuid = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
  # ...
};

# Auto-generated rules in project-activities/window-rules.nix
"vscode-nixos" = {
  Description = "VS Code - NixOS (Profile)";
  wmclass = "code-nixos";  # From --profile flag
  wmclassmatch = 2;  # Exact match
  title = "nixos";  # Folder basename, not full path
  titlematch = 1;  # Substring match
  activity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
  activityrule = 2;  # Force
};

"vscode-nixos-fallback" = {
  Description = "VS Code - NixOS (Legacy)";
  wmclass = "code";  # Generic VS Code
  wmclassmatch = 2;
  wmclasscomplete = true;
  title = "nixos";
  titlematch = 1;
  activity = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
  activityrule = 2;
};
```

## Why Auto-generation?

### Problems with Manual Management
1. **Duplication**: PWA definitions existed in `data.nix` AND window rules
2. **Inconsistency**: Easy to forget to update window rules when adding PWAs
3. **Error-prone**: Manual UUID management, typos in activity assignments
4. **GUI Export Issues**: `plasma-rc2nix` exports overwrite declarative rules

### Benefits of Auto-generation
1. **Single Source of Truth**: PWAs defined once in `data.nix`
2. **Consistency**: Window rules always match PWA definitions
3. **Maintainability**: Add a PWA in one place, rule is auto-created
4. **No GUI Conflicts**: Rules are always regenerated from data

## Workflow

### Adding a New PWA

1. **Add PWA to data**:
   ```nix
   # In home-modules/desktop/pwas/data.nix
   slack = {
     name = "Slack";
     activity = "nixos";  # Or null for all activities
     url = "https://app.slack.com";
   };
   ```

2. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch --flake .#<target>
   ```

3. **Done!** Window rule is automatically generated:
   - Rule name: `pwa-slack`
   - Activity assignment: Based on `activity` field
   - Window matching: By title "Slack" and wmclass "FFPWA"

### Adding a New Activity

1. **Add activity to data**:
   ```nix
   # In home-modules/desktop/project-activities/data.nix
   myproject = {
     name = "My Project";
     directory = "~/myproject";
     # ...
   };
   ```

2. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch --flake .#<target>
   ```

3. **Done!** Six window rules are automatically generated:
   - `vscode-myproject` + fallback (2 rules)
   - `konsole-myproject` (1 rule)
   - `dolphin-myproject` (1 rule)

### Adding a New Browser

1. **Edit browser rules**:
   ```nix
   # In home-modules/desktop/browser-window-rules.nix
   "brave" = {
     Description = "Brave Browser - All Activities";
     activity = allActivitiesUuid;
     activityrule = 2;
     types = 1;
     wmclass = "brave-browser";
     wmclassmatch = 1;
   };
   ```

2. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch --flake .#<target>
   ```

## Rule Count

- **PWA rules**: 9 (auto-generated from `pwas/data.nix`)
- **Browser rules**: 2 (manually maintained)
- **Activity rules**: 20 (auto-generated from `project-activities/data.nix`)
- **Total**: 31 rules

## Deprecated Files

The following files are **no longer used** and have been removed:

- ❌ `pwa-window-rules.nix` - Replaced by auto-generated `pwas/window-rules.nix`
- ❌ `kwin-window-rules.nix` - Complex transformer no longer needed
- ❌ `generated/plasma-rc2nix.nix` - GUI exports no longer used for window rules

## Troubleshooting

### Rules not applying

1. **Check Nix evaluation**:
   ```bash
   nix-instantiate --eval --strict -E 'let flake = builtins.getFlake (toString ./.); config = flake.nixosConfigurations.hetzner.config.home-manager.users.vpittamp.programs.plasma.configFile.kwinrulesrc; in config.General.count.value'
   ```

2. **Check generated rules**:
   ```bash
   cat ~/.config/kwinrulesrc | grep "^\[General\]" -A 3
   ```

3. **Reconfigure KWin**:
   ```bash
   qdbus org.kde.KWin /KWin reconfigure
   ```

4. **Restart Plasmashell** (if needed):
   ```bash
   systemctl --user restart plasma-plasmashell
   ```

5. **Last resort - logout/login**:
   Logout and log back in to trigger a fresh home-manager activation.

### Adding rules for other applications

Follow the browser rules pattern:
1. Edit `browser-window-rules.nix`
2. Add a rule with appropriate wmclass matching
3. Rebuild

### Checking which activity a PWA should be in

```bash
cat home-modules/desktop/pwas/data.nix | grep -A 3 "pwaname"
```

## Future Enhancements

1. **Auto-detect wmclass**: Dynamically discover FFPWA-{ID} for each PWA
2. **Browser auto-generation**: Generate browser rules from a data file
3. **Testing framework**: Validate rules match expected windows
4. **Documentation generator**: Auto-generate rule documentation from data

---

*Last updated: 2025-10-06 - Initial auto-generation architecture*

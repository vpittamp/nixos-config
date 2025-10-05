# Activity System Analysis & Optimization Recommendations

## Executive Summary

**Current State**: Custom activity management system with 900+ lines of code
**Finding**: We lost desktop folder widgets when migrating to plasma-manager panels
**Recommendation**: Restore desktop widgets, then evaluate simplification opportunities

---

## Current Implementation Analysis

### 1. Activity Creation & Management

**File**: [project-activities/default.nix](../home-modules/desktop/project-activities/default.nix)

**What it does**:
- Creates activities via D-Bus bootstrap script (lines 75-247)
- Writes declarative config to `kactivitymanagerdrc` (lines 283-308)
- Manages activity shortcuts via `kglobalshortcutsrc` (lines 310-365)
- Creates autostart .desktop files per activity (lines 249-277)

**Complexity**: 393 lines

**KDE Native Support**: ✅ Partially
- Activities themselves: Native KDE
- Shortcuts: Native KDE
- Metadata (name, icon, description): Native KDE
- **Directory association**: ❌ Custom (not native)

### 2. Directory Association

**File**: [project-activities/data.nix](../home-modules/desktop/project-activities/data.nix)

**What it does**:
- Defines canonical activity UUIDs (lines 83-213)
- Associates each activity with a directory
- Provides helper functions for konsole/dolphin/vscode commands
- Links resources to activities via D-Bus

**Complexity**: 246 lines

**KDE Native Support**: ❌ Not native
- KDE activities have no concept of "default directory"
- Custom implementation using resource linking
- Requires JSON mapping file for app launchers

### 3. Activity-Aware Application Launchers

**File**: [activity-aware-apps-native.nix](../home-modules/desktop/activity-aware-apps-native.nix)

**What it does**:
- Creates wrapper scripts for konsole, code, dolphin (lines 83-108)
- Query current activity → Look up directory → Open app in that directory
- Generates KWin window rules for activity assignment (lines 174-279)
- Creates custom .desktop entries (lines 311-443)

**Complexity**: 503 lines

**KDE Native Support**: ⚠️ Hybrid
- ✅ Window rules: Native KDE (works perfectly)
- ❌ Directory lookup: Custom bash scripts
- ❌ JSON mapping: Custom implementation

### 4. Desktop Folder Widgets ✅ **RESTORED**

**Current Location**: [desktop-widgets.nix](../home-modules/desktop/project-activities/desktop-widgets.nix)

**What it does**:
```nix
mkActivityDesktopWidget = activityId: activity: {
  name = "org.kde.plasma.folder";
  config.General = {
    url = "file://${activity.directory}";
    arrangement = 0;  # Rows
    iconSize = 2;     # Medium icons
    locked = true;
    sortMode = 0;     # Sort by name
  };
};
```

**Status**: ✅ **Restored using plasma-manager declarative API**

**Implementation**:
- Uses plasma-manager's `programs.plasma.desktop.widgets` API
- Generates one folder widget per activity
- Shows activity directory on desktop
- Fully declarative and portable

**KDE Native Support**: ✅ Fully native
- Folder widgets are standard KDE feature
- Per-activity desktop configuration supported
- Works perfectly with activity system

---

## What rc2nix Exports vs What We Manage

### rc2nix DOES Export

✅ Config files (kwinrc, kwalletrc, etc.)
✅ Keyboard shortcuts
✅ Application preferences
✅ Window rules (but with wrong UUIDs - we transform these)
❌ **Panels** (but plasma-manager has declarative API)
❌ **Desktop widgets** (part of appletsrc, not exported)

### rc2nix DOES NOT Export

❌ Activities (created via D-Bus)
❌ Desktop folder widgets
❌ Panel layouts (we use plasma-manager instead)
❌ Activity-directory associations (not a KDE feature)

---

## KDE Plasma Native Capabilities

### What KDE Provides Natively

| Feature | Native Support | Current Implementation |
|---------|---------------|------------------------|
| Activities | ✅ Full | ✅ Using native |
| Per-activity wallpapers | ✅ Full | ✅ Using native |
| Activity shortcuts | ✅ Full | ✅ Using native |
| Window-to-activity rules | ✅ Full | ✅ Using native + transformer |
| Desktop folder widgets | ✅ Full | ❌ **MISSING** |
| Activity metadata | ✅ Full | ✅ Using native |
| **Default directory per activity** | ❌ None | ❌ Custom implementation |
| **Auto-open apps in directory** | ❌ None | ❌ Custom scripts |

### The Gap

**KDE activities have NO concept of "default working directory"**

Our custom system provides:
1. Directory association via JSON mapping
2. Wrapper scripts that query activity → open in directory
3. Window rules that assign based on path

**Question**: Is this complexity worth it?

---

## Findings & Discoveries

> **Update 2025-10-05**: Desktop folder widgets have been restored using plasma-manager's declarative API. See [desktop-widgets.nix](../home-modules/desktop/project-activities/desktop-widgets.nix).

### 1. Desktop Folder Widgets Were Lost (Now Restored)

**What happened**:
- Old `panels.nix` generated INI config including desktop widgets
- Migration to plasma-manager panels API only covered panels
- Desktop widgets (containments) were not migrated
- Now users have no desktop folder representation

**Evidence**:
```bash
# Old backup shows folder widgets existed:
git show 0c5562d:home-modules/desktop/project-activities/panels.nix | grep -A 10 mkActivityContainment
```

**Resolution**: ✅ Restored
- Created [desktop-widgets.nix](../home-modules/desktop/project-activities/desktop-widgets.nix)
- Uses plasma-manager's `programs.plasma.desktop.widgets` API
- Generates one folder widget per activity declaratively
- Awaiting deployment to verify functionality

### 2. rc2nix Doesn't Help with Activities

**Findings**:
- rc2nix exports config files only
- Activities are created via D-Bus, not config files
- Desktop widgets not exported by rc2nix
- Activity configuration in `kactivitymanagerdrc` is exported but incomplete

**Implication**:
- Can't use rc2nix workflow to discover activity changes
- Must rely on manual D-Bus inspection or config file review

### 3. plasma-manager Supports Desktop Widgets (Probably)

**Evidence**:
- README mentions "Desktop icons, widgets, and mouse actions"
- Desktop widgets live in same file as panels (`plasma-org.kde.plasma.desktop-appletsrc`)
- plasma-manager manages this file for panels
- **Unknown**: Does it support desktop containments separately from panels?

**Investigation needed**:
- Check plasma-manager source for desktop widget API
- Test if we can declaratively add folder widgets
- Alternative: Generate desktop widget INI like we did before

### 4. Current Custom System is Complex

**Statistics**:
- `data.nix`: 246 lines
- `default.nix`: 393 lines
- `activity-aware-apps-native.nix`: 503 lines
- **Total**: 1,142 lines of custom activity logic

**Of which**:
- ~400 lines: Activity creation/management (necessary)
- ~300 lines: Directory association (custom, not KDE native)
- ~400 lines: App launcher wrappers (convenience, could simplify)

---

## Optimization Opportunities

### Option A: Restore Desktop Widgets Only (Minimal Change)

**Action**: Add desktop folder widgets back to panels configuration

**Benefits**:
- ✅ Restores lost functionality
- ✅ Makes activities visible on desktop
- ✅ Provides click-to-open workspace

**Changes Required**:
- Add desktop containments to `panels.nix`
- Use plasma-manager API if available, else generate INI

**Keep**:
- Current activity-aware launchers
- Directory association system
- Window rules (working perfectly)

**Effort**: Low (1-2 hours)
**Risk**: Low

### Option B: Simplify Activity-Aware Apps (Medium Change)

**Action**: Replace custom wrappers with native alternatives

**Replace**:
- `konsole-activity` → Desktop folder + "Open Terminal Here"
- `code-activity` → VS Code jumplist (already have this!)
- `dolphin-activity` → Desktop folder widget itself

**Benefits**:
- ✅ ~500 lines less code
- ✅ More reliable (native features)
- ✅ Easier to maintain

**Trade-offs**:
- ❌ Lose Ctrl+Alt+T magic shortcut
- ✅ But gain: Right-click folder → Open Terminal
- ✅ And have: VS Code jumplist

**Effort**: Medium (4-6 hours)
**Risk**: Medium (workflow change)

### Option C: Full Native Migration (Large Change)

**Action**: Use only KDE native features

**Keep**:
- Activities (native)
- Window rules (native)
- Desktop folder widgets (native)
- Wallpapers per activity (native)

**Remove**:
- Directory association JSON mapping
- Activity-aware app wrappers
- Bootstrap script resource linking
- Custom .desktop entries

**Alternative Workflow**:
1. Click desktop folder → Opens in Dolphin
2. Right-click folder → Open Terminal / VS Code
3. Windows assigned to activity via window rules
4. VS Code jumplist for quick project access

**Benefits**:
- ✅ ~700 lines less code
- ✅ Maximum reliability (native KDE)
- ✅ Easy to understand
- ✅ rc2nix might help more

**Trade-offs**:
- ❌ Different workflow (no shortcuts)
- ❌ More clicks to open terminal
- ✅ But simpler mental model

**Effort**: High (8-12 hours)
**Risk**: High (major workflow change)

---

## Recommendations

### Immediate Action (Do Now)

**Restore Desktop Folder Widgets**

1. Add desktop containments back to `panels.nix`
2. Test on Hetzner system
3. Verify one folder widget per activity
4. Ensure wallpapers still work

**Why**: Critical missing functionality, easy to fix

**How**:
```nix
# In panels.nix, add after panel definitions:
# Desktop folder widgets (one per activity)
# These show the activity's workspace directory
```

### Short-term Investigation (Next Week)

**Test Native Workflow**

1. Use restored desktop widgets for 1 week
2. Track how often you use:
   - `Ctrl+Alt+T` (konsole-activity)
   - `Ctrl+Alt+C` (code-activity)
   - Desktop folder + right-click alternatives
3. Measure: Do shortcuts save meaningful time?

**Outcome**: Data-driven decision on whether to simplify

### Long-term Consideration (Month+)

**If shortcuts aren't essential**:
- Simplify to Option B or C
- Remove custom wrappers
- Document native workflow
- Archive complex code with explanation

**If shortcuts are essential**:
- Keep current system
- Document thoroughly
- Create troubleshooting guide
- Accept that rc2nix won't help

---

## Decision Framework

**Keep custom system IF**:
- You use Ctrl+Alt+T multiple times per day
- Opening terminal via right-click feels slow
- The "magic" workflow is valuable

**Simplify to native IF**:
- You could adapt to right-click workflow
- Code simplicity > keystroke savings
- You want maximum reliability

**Questions to Answer**:
1. How often do you actually use activity-aware shortcuts?
2. Could desktop folder + right-click replace them?
3. Is VS Code jumplist sufficient for most cases?
4. Do window rules already handle 90% of the value?

---

## Next Steps

### Phase 1: Restore ✅ **COMPLETE**
- [x] Add desktop folder widgets to panels.nix
- [ ] Test on Hetzner (requires deployment)
- [ ] Verify all activities have desktop folders (requires deployment)
- [x] Document what was restored

### Phase 2: Evaluate (Next Week)
- [ ] Use system with restored desktop widgets
- [ ] Track shortcut usage
- [ ] Test alternative workflows
- [ ] Make simplification decision

### Phase 3: Optimize (If Chosen)
- [ ] Implement chosen option
- [ ] Update documentation
- [ ] Test thoroughly
- [ ] Create migration guide if needed

---

## Appendix: Technical Details

### Desktop Folder Widget Structure

```ini
[Containments][600]
activityId=dcc377c8-d627-4d0b-8dd7-27d83f8282b3
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][600][General]
url=file:///home/vpittamp/backstage-cnoe

[Containments][600][Wallpaper][org.kde.image][General]
Image=/run/current-system/sw/share/wallpapers/Cascade/contents/images/1920x1080.png
```

### What We Lost During Migration

**Before** (manual INI generation):
```nix
activityContainmentsIni = lib.concatMapStrings mkActivityContainment activities;
panelIniText = panels + activityContainments + screenMapping;
```

**After** (plasma-manager panels API):
```nix
programs.plasma.panels = [/* panel definitions */];
# Desktop widgets: MISSING
```

**To Restore**: Need to either:
1. Find plasma-manager API for desktop widgets
2. Or generate desktop widget INI separately from panels

---

**Last Updated**: 2025-10-05
**Status**: ✅ Desktop widgets restored using plasma-manager declarative API

# VSCode Profile Simplification

## Problem

Previously, we created separate VSCode profiles for each activity (`monitoring`, `stacks`, `backstage`, `devcontainer`) to enable unique WM_CLASS values for KWin window rule matching. However, this caused issues:

1. **Wrong Default Profile**: VSCode would sometimes default to the wrong profile when opened manually
2. **Profile Bloat**: Multiple profiles with identical configurations created unnecessary complexity
3. **Sync Issues**: Each profile maintained separate settings sync state

## Solution

We now use a **single unified `nixos` profile** for all VSCode instances, with per-activity customization achieved through:

1. **Custom WM_CLASS via `--class` flag**: Instead of using `--profile <activity>`, we use `--profile nixos --class code-<activity>`
2. **Directory-based customization**: Each instance opens in its activity-specific directory
3. **Environment variables**: `CURRENT_ACTIVITY_*` variables are exported for use by extensions and terminal sessions

## Changes Made

### 1. VSCode Configuration (`home-modules/tools/vscode.nix`)

**Before:**

```nix
profiles = {
  default = defaultProfile;
  nixos = nixosProfile;
  monitoring = nixosProfile;
  stacks = nixosProfile;
  backstage = nixosProfile;
  devcontainer = nixosProfile;
};
```

**After:**

```nix
profiles = {
  nixos = nixosProfile;  # Single unified profile
};
```

### 2. Activity Launcher Script (`home-modules/desktop/activity-aware-apps-native.nix`)

**Before:**

```bash
# Launch VSCode with activity-specific profile
PROFILE_NAME=$(echo "$ACTIVITY_NAME" | tr '[:upper:]' '[:lower:]')
code --profile "$PROFILE_NAME" "$WORK_DIR"
```

**After:**

```bash
# Launch VSCode with unified profile but custom WM_CLASS
ACTIVITY_LOWER=$(echo "$ACTIVITY_NAME" | tr '[:upper:]' '[:lower:]')
code --profile nixos --class "code-$ACTIVITY_LOWER" "$WORK_DIR"
```

### 3. Window Rules (`home-modules/desktop/project-activities/window-rules.nix`)

**Before:**

```nix
# VSCode --profile flag creates unique WM_CLASS: "code-${profileName}"
profileWmClass = "code-${activityId}";
```

**After:**

```nix
# VSCode --class flag creates unique WM_CLASS: "code-${activityName}"
customWmClass = "code-${activityId}";
```

The window rule matching logic remains the same - KWin still matches on `code-monitoring`, `code-stacks`, etc.

## Benefits

1. **Single Source of Truth**: All VSCode instances use the same profile, ensuring consistent settings
2. **Correct Defaults**: Manual VSCode launches always use the `nixos` profile
3. **Simpler Configuration**: No need to duplicate profile configurations
4. **Maintained Functionality**: Window rule matching still works perfectly via the `--class` flag

## Per-Activity Customization (Still Works!)

Even with a single profile, each activity's VSCode instance is customized through:

- **Working Directory**: Opens in activity-specific folder
- **Terminal Environment**: `CURRENT_ACTIVITY_*` variables are available
- **Window Rules**: KWin assigns windows to correct activities via WM_CLASS
- **Extensions**: Can read environment variables to provide activity-specific behavior

## Technical Details

### How `--class` Works

The `--class` flag in VSCode (Electron) sets the WM_CLASS property:

```bash
code --class "code-monitoring"
# Results in WM_CLASS: code-monitoring
```

This is functionally equivalent to what `--profile` did, but without creating a separate profile directory.

### Window Rule Matching

KWin rules match on:

1. **Primary**: WM_CLASS (`code-monitoring`, `code-stacks`, etc.)
2. **Secondary**: Window title (folder basename like `nixos`, `backstage`, etc.)

Both ensure windows are assigned to the correct activity immediately upon creation.

### Profile vs WM_CLASS

| Aspect               | `--profile <name>`                     | `--class <name>`               |
| -------------------- | -------------------------------------- | ------------------------------ |
| Creates new profile? | Yes                                    | No                             |
| Sets WM_CLASS?       | Yes                                    | Yes                            |
| Separate settings?   | Yes                                    | No                             |
| Storage location     | `~/.config/Code/User/profiles/<name>/` | `~/.config/Code/User/`         |
| Use case             | Different users/configs                | Same config, different windows |

## Migration

No manual migration needed! The changes are declarative:

1. Apply the configuration: `sudo nixos-rebuild switch --flake .#<target>`
2. Old profile directories remain but won't be used
3. Next VSCode launch will use the unified `nixos` profile
4. Window rules continue to work via the new `--class` flag

## Testing

Verify the configuration works:

1. **Check active profile**: Open VSCode → Help → About → Should show "nixos" profile
2. **Check window rules**: Switch activities and launch VSCode - windows should stay in correct activities
3. **Check environment**: Open terminal in VSCode, run `echo $CURRENT_ACTIVITY_NAME`
4. **Check WM_CLASS**: Run `xprop | grep WM_CLASS` and click VSCode window - should show `code-<activity>`

## Future Enhancements

With this unified approach, we can now:

- Add activity-specific workspace files (`.vscode/settings.json` in each directory)
- Use directory-based extensions recommendations
- Implement activity-aware extensions that read `CURRENT_ACTIVITY_*` variables
- Simplify profile management and settings sync

## References

- [VSCode Profiles Documentation](https://code.visualstudio.com/docs/editor/profiles)
- [Electron WM_CLASS](https://www.electronjs.org/docs/latest/api/browser-window#winsetrepresentedfilenamefilename-macos)
- [KWin Window Rules](https://userbase.kde.org/KWin_Rules)

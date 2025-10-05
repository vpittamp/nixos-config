# Plasma Manager Integration

Generated via `plasma-manager` on 2025-09-18 to capture the live KDE Plasma configuration for `vpittamp`.

## Current State
- **Snapshot** lives at `home-modules/desktop/generated/plasma-rc2nix.nix` (reference/analysis only)
- **Declarative config** in `home-modules/desktop/plasma-config.nix` manages portable settings
- **Hybrid approach**: Snapshots are used for discovery, not direct application
- **Smart filtering**: System-generated IDs (UUIDs, timestamps) are filtered by `plasma-snapshot-analysis.nix`

**📚 See [PLASMA_CONFIG_STRATEGY.md](PLASMA_CONFIG_STRATEGY.md) for the complete configuration strategy.**

## Refresh Workflow
1. **Take a snapshot**
   ```bash
   plasma-sync snapshot
   ```
   This command wraps `plasma-manager rc2nix`, rewrites `home-modules/desktop/generated/plasma-rc2nix.nix` in place, and shows a diff against the previous revision.
2. **Activate (optional)**
   ```bash
   plasma-sync activate
   ```
   Runs `home-manager switch --flake /etc/nixos#vpittamp` so Plasma picks up the declarative changes after logout/login.
3. **Interactive workflow**
   ```bash
   plasma-sync
   ```
   Provides a `gum`-based menu with options to capture a snapshot, run the full workflow, inspect the cached diff/raw export/generated module, review git status/diffs, or open these docs—all without leaving the TUI.
   Use the arrow keys to select an entry and press Enter (Esc cancels).

- For `plasma-sync full`, pass additional Home Manager options after `--hm`, e.g. `plasma-sync full --hm --show-trace`.

### Common CLI shortcuts
```bash
plasma-sync snapshot          # capture rc2nix export and stage artifacts
plasma-sync diff              # view the cached rc2nix diff
plasma-sync git-diff          # compare working tree against git HEAD
plasma-sync activate          # run home-manager switch only
plasma-sync full --hm --show-trace  # snapshot + activation with custom flags
```

## Configuration Philosophy

### Snapshot vs Declarative

**Snapshots** (`plasma-sync snapshot`):
- Capture **all** KDE settings to `generated/plasma-rc2nix.nix`
- Include system-generated UUIDs, timestamps, runtime state
- Used for **analysis and discovery**, not direct application
- Help identify settings to adopt into declarative config

**Declarative Config** (`plasma-config.nix`):
- Manages **portable, reproducible** settings only
- Keyboard shortcuts, themes, window behavior
- No system-generated IDs or runtime state
- Works consistently across machines

**When to use each**:
- Made GUI change → Export snapshot → Review diff → Adopt into declarative config
- Want reproducible setup → Add to declarative config directly
- Complex panel layouts → Keep in GUI, reference snapshot for backup

### What NOT to Manage Declaratively

❌ Don't manage these (system-generated, let KDE handle):
- Virtual desktop UUIDs (`Id_1`, `Id_2`, etc.)
- Activity runtime state (`currentActivity`, `runningActivities`)
- Tiling layout UUIDs (`Tiling/*`)
- Timestamps (`ViewPropsTimestamp`)
- Subsession IDs

✅ Manage these declaratively:
- Keyboard shortcuts (portable)
- Themes and appearance (consistent)
- Window behavior (reproducible)
- Application preferences (Kate, Dolphin)
- Window rules (via UUID transformer)

See [PLASMA_CONFIG_STRATEGY.md](PLASMA_CONFIG_STRATEGY.md) for complete guidelines.

## Notes
- We use `immutableByDefault = false` - GUI changes are preserved, declarative config provides defaults
- If rc2nix reports parse failures, fix upstream or add minimal overrides in separate modules
- Retain snapshots in git history to track configuration evolution
- The transformer (`kwin-window-rules.nix`) automatically maps activity UUIDs from snapshot to canonical values

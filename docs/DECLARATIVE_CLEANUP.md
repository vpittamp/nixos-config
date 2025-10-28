# Declarative Cleanup Pattern

## Problem

Home-manager creates backup files when it encounters conflicts:
- `.backup` files when a regular file exists
- `.backup-before-home-manager` for files managed by other tools
- Stale runtime sockets (e.g., wayvnc control socket)
- Old systemd service files

These backups prevent subsequent home-manager activations from succeeding, requiring manual cleanup.

## Solution

We use a **home-manager activation script** that runs *before* home-manager applies the configuration. This script declaratively removes known backup patterns and stale resources.

### Implementation

**Module**: `home-modules/profiles/declarative-cleanup.nix`

**What it cleans**:
1. Home-manager backup files (`.backup`, `.backup-before-home-manager`)
2. Stale runtime sockets (`/run/user/$UID/wayvncctl`)
3. Old `.desktop` file backups in i3pm-applications
4. Systemd service backup files
5. Stale lock files (older than 7 days)

**Activation order**:
```
cleanupBeforeActivation → checkLinkTargets → writeBoundary → ... → home-manager applies files
```

### Usage

**Add to any home-manager configuration**:

```nix
{
  imports = [
    ./profiles/declarative-cleanup.nix  # Enable declarative cleanup
    # ... other imports
  ];
}
```

**Verify cleanup runs**:

```bash
# Rebuild and watch output
sudo nixos-rebuild switch --flake .#hetzner-sway 2>&1 | grep cleanup

# Check for remaining backup files (should be empty)
find ~/.config -name "*.backup" 2>/dev/null
```

## Benefits

### ✅ Truly Declarative

No manual intervention needed. Every rebuild starts with a clean state.

### ✅ Idempotent

Running the cleanup multiple times has the same effect as running it once.

### ✅ Safe

- Uses `|| true` to ignore errors (files may not exist)
- Only removes known backup patterns
- Never touches actual configuration files (only symlinks)

### ✅ Transparent

Logs cleanup actions during activation:
```
=== Running declarative cleanup ===
Cleaning up home-manager backup files...
Cleaning up stale runtime sockets...
Cleaning up old desktop file backups...
Cleaning up systemd service backups...
Cleaning up stale lock files...
=== Cleanup complete ===
```

## When to Use

**Always use** for:
- Headless configurations (hetzner-sway, etc.)
- Configurations with systemd user services
- Configurations with complex file management

**Optional** for:
- Minimal configurations
- Configurations that rarely change

## Extending

To add custom cleanup patterns, edit `declarative-cleanup.nix`:

```nix
# Add custom cleanup step
echo "Cleaning up my custom files..."
rm -f $HOME/.my-app/*.old 2>/dev/null || true
```

## Alternative: Force Overwrite

For individual files that frequently conflict, use `force = true`:

```nix
home.file.".config/my-app/config.toml" = {
  source = ./config.toml;
  force = true;  # Always overwrite, don't create backups
};
```

**Note**: Use sparingly - declarative cleanup is safer and more maintainable.

## Troubleshooting

**Cleanup not running?**

Check activation script is imported:
```bash
grep -r "declarative-cleanup" ~/.config/nixpkgs/ 2>/dev/null
grep -r "cleanupBeforeActivation" /nix/store/*-home-manager-generation/activate 2>/dev/null | head -1
```

**Files still conflicting?**

Check if files are created by another process after cleanup:
```bash
# Monitor file creation during rebuild
inotifywait -m ~/.config &
sudo nixos-rebuild switch --flake .#hetzner-sway
```

**Need more aggressive cleanup?**

Add custom patterns to the cleanup script or use `force = true` on specific files.

## Related

- Home-manager manual: https://nix-community.github.io/home-manager/
- Activation scripts: https://nix-community.github.io/home-manager/index.xhtml#sec-usage-activation
- NixOS options search: https://search.nixos.org/options

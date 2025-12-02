# Quickstart: Portable NixOS Configuration

**Feature**: 106-make-nixos-config-portable
**Status**: Implemented

## Overview

Build NixOS configuration from any directory (git worktrees, main repo, or any checkout) with identical results.

## Quick Usage

### Building from Any Directory

```bash
# From a worktree
cd ~/repos/nixos-config/106-make-nixos-config-portable
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# From /etc/nixos (if symlinked)
cd /etc/nixos
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Both produce identical derivations
```

### Verify Portability

```bash
# Build from worktree
cd ~/repos/nixos-config/my-worktree
WORKTREE_DRV=$(nix path-info --derivation .#nixosConfigurations.hetzner-sway.config.system.build.toplevel)

# Build from /etc/nixos
cd /etc/nixos
MAIN_DRV=$(nix path-info --derivation .#nixosConfigurations.hetzner-sway.config.system.build.toplevel)

# Compare
[[ "$WORKTREE_DRV" == "$MAIN_DRV" ]] && echo "✅ Identical" || echo "❌ Different"
```

## Environment Variables

### NH_FLAKE / NH_OS_FLAKE

These variables control where `nh os switch` looks for the flake.

**Automatic Detection** (default behavior after Feature 106):

When you start a shell in a git repository containing `flake.nix`, the shell
initialization automatically sets `NH_FLAKE` and `NH_OS_FLAKE` to the git root.

```bash
# Shell automatically detects git repo on startup
cd ~/repos/nixos-config/my-feature
echo $NH_FLAKE  # /home/user/repos/nixos-config/my-feature
nh os switch    # Uses current directory's flake automatically!
```

**Default Values** (outside git repos):
```bash
# When not in a git repo with flake.nix, defaults to /etc/nixos
cd /tmp
echo $NH_FLAKE  # /etc/nixos
```

**Manual Override**:
```bash
# Point to specific worktree (overrides automatic detection)
export NH_FLAKE=~/repos/nixos-config/106-feature
nh os switch
```

### FLAKE_ROOT

Used by development scripts and internal tools to find the repository root.
Set automatically alongside NH_FLAKE during shell initialization.

**Automatic** (in git repos):
```bash
cd ~/repos/nixos-config/any-worktree
echo $FLAKE_ROOT  # /home/user/repos/nixos-config/any-worktree
./scripts/run-tests.sh  # Scripts use $FLAKE_ROOT for paths
```

**Manual** (outside git or for override):
```bash
export FLAKE_ROOT=/path/to/nixos-config
./scripts/run-tests.sh
```

### Detection Priority

The shell initialization uses this priority order:

1. **Existing environment variable** - If already set, don't override
2. **Git repository detection** - `git rev-parse --show-toplevel`
3. **Default fallback** - `/etc/nixos`

## Common Workflows

### Working with Git Worktrees

```bash
# Create a worktree for feature development
cd /etc/nixos
git worktree add ../feature-123 -b 123-my-feature

# Build from worktree
cd ../feature-123
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Test and iterate...
sudo nixos-rebuild switch --flake .#hetzner-sway

# When done, clean up
cd /etc/nixos
git worktree remove ../feature-123
```

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
      - name: Build all targets
        run: |
          nix build .#nixosConfigurations.hetzner-sway.config.system.build.toplevel
          nix build .#nixosConfigurations.m1.config.system.build.toplevel
          nix build .#nixosConfigurations.wsl.config.system.build.toplevel
```

### Testing Scripts

```bash
# Run tests from any worktree
cd ~/repos/nixos-config/feature-xyz
pytest tests/  # Scripts automatically find FLAKE_ROOT

# Or explicitly set it
FLAKE_ROOT=$(pwd) pytest tests/
```

## Troubleshooting

### "Path does not exist" during build

**Symptom**: Build fails with `/etc/nixos/...` not found

**Cause**: Hardcoded path in a Nix file

**Fix**: Check the error path and update to use relative path or store reference

### Scripts fail after building from worktree

**Symptom**: Runtime scripts (keybindings, daemons) fail

**Cause**: Script references `/etc/nixos` directly

**Fix**: Scripts should be packaged via `pkgs.writeShellApplication` in Nix

### NH commands use wrong flake

**Symptom**: `nh os switch` uses different config than expected

**Cause**: NH_FLAKE environment variable not set

**Fix**:
```bash
# Check current value
echo $NH_FLAKE

# Set to current directory
export NH_FLAKE=$(git rev-parse --show-toplevel)
nh os switch
```

### Assets (icons) not showing

**Symptom**: UI elements missing icons after worktree build

**Cause**: Icons referenced with `/etc/nixos/assets/...`

**Fix**: Icons should be in Nix store via assets package

## Technical Details

### How Portability Works

1. **Assets**: Copied to Nix store during build (`/nix/store/xxx-nixos-config-assets/`)
2. **Scripts**: Packaged as derivations (`/nix/store/xxx-script-name/bin/script`)
3. **Imports**: Use Nix's relative path resolution from flake root
4. **Dev scripts**: Use git discovery (`git rev-parse --show-toplevel`)

### Verification Checklist

After implementation, verify:

- [ ] `nixos-rebuild dry-build` succeeds from worktree
- [ ] Derivation hash matches when built from different locations
- [ ] `Mod+D` (Walker) opens with icons visible
- [ ] `i3pm project switch` works correctly
- [ ] Test suite runs from worktree directory
- [ ] No `/etc/nixos` paths in `grep -r` of scripts/

## Related Documentation

- [spec.md](./spec.md) - Full requirements
- [research.md](./research.md) - Technical decisions
- [data-model.md](./data-model.md) - Path categories

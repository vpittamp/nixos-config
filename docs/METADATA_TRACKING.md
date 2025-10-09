# NixOS Generation Metadata Tracking

This configuration tracks comprehensive build metadata for every NixOS generation, allowing you to trace each generation back to its exact source code state.

## What's Tracked

Each generation now includes:

### Git Information
- **Full commit hash**: Exact git revision used for the build
- **Short commit hash**: First 7 characters for display
- **Dirty flag**: Whether uncommitted changes were present
- **Last modified date**: When the source was last changed
- **Source URL**: Direct link to GitHub commit

### Flake Input Revisions
- **nixpkgs revision**: Exact nixpkgs commit
- **nixpkgs narHash**: Content hash for verification
- **home-manager revision**: Exact home-manager commit

### System Information
- **Hostname**: Target system name
- **Architecture**: x86_64-linux, aarch64-linux, etc.
- **Build date**: When the generation was created
- **Flake URL**: Direct flake reference for rebuilding

## Usage

### View Current Generation Metadata

```bash
# Show metadata for current generation
nixos-metadata

# Show metadata for specific generation
nixos-metadata 42

# View just the git revision
nixos-version --configuration-revision

# Or directly
cat /run/current-system/configuration-revision
```

### View All Generations with Metadata

```bash
# List all generations with their git commits
for gen in /nix/var/nix/profiles/system-*-link; do
  num=$(basename "$gen" | sed 's/system-\(.*\)-link/\1/')
  rev=$(cat "$gen/configuration-revision" 2>/dev/null || echo "unknown")
  echo "Generation $num: $rev"
done
```

### Reproduce a Specific Generation

```bash
# View metadata
nixos-metadata 42

# Source the metadata file
source /nix/var/nix/profiles/system-42-link/etc/nixos-metadata

# Checkout the exact git commit
git checkout $GIT_COMMIT

# Rebuild from that exact state
sudo nixos-rebuild switch --flake $FLAKE_URL
```

### Compare Generations

```bash
# Show what changed between two generations
gen1=42
gen2=43
diff \
  /nix/var/nix/profiles/system-$gen1-link/etc/nixos-metadata \
  /nix/var/nix/profiles/system-$gen2-link/etc/nixos-metadata
```

## How It Works

The flake automatically embeds metadata into each system build:

1. **`system.configurationRevision`**: Sets the official NixOS configuration revision
2. **`/etc/nixos-metadata`**: Creates a file with comprehensive build metadata
3. **`nixos-metadata` script**: Provides an easy interface to view the metadata

## Metadata File Format

The `/etc/nixos-metadata` file is a simple shell-sourceable format:

```bash
# Git Information
GIT_COMMIT=8bebe8d...
GIT_SHORT_COMMIT=8bebe8d
GIT_DIRTY=false
GIT_LAST_MODIFIED=20250109
GIT_SOURCE_URL=https://github.com/vpittamp/nixos-config/tree/8bebe8d...

# Flake Input Revisions
NIXPKGS_REV=abc123...
NIXPKGS_NARHASH=sha256-...
HOME_MANAGER_REV=def456...

# System Information
HOSTNAME=nixos-hetzner
SYSTEM=x86_64-linux
BUILD_DATE=20250109
FLAKE_URL=github:vpittamp/nixos-config/8bebe8d...
```

## Benefits

1. **Reproducibility**: Rebuild any generation from its exact source
2. **Debugging**: Trace issues to specific code changes
3. **Auditing**: Know exactly what code is running on your system
4. **Rollback**: Return to known-good configurations with confidence
5. **Documentation**: Self-documenting system history

## Examples

### Find when a specific change was deployed

```bash
# Search for when a file was added/modified
for gen in /nix/var/nix/profiles/system-*-link; do
  source "$gen/etc/nixos-metadata" 2>/dev/null || continue
  if git show "$GIT_COMMIT:configurations/hetzner.nix" 2>/dev/null | grep -q "some-setting"; then
    echo "Found in generation $(basename $gen): $GIT_COMMIT"
  fi
done
```

### Audit what versions of nixpkgs you've used

```bash
for gen in /nix/var/nix/profiles/system-*-link; do
  source "$gen/etc/nixos-metadata" 2>/dev/null || continue
  echo "Generation $(basename $gen): nixpkgs@${NIXPKGS_REV:0:7}"
done | sort -u
```

---

*Created: 2025-01-09*
*Last Updated: 2025-01-09*

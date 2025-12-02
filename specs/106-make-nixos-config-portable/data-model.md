# Data Model: Make NixOS Config Portable

**Feature**: 106-make-nixos-config-portable
**Date**: 2025-12-01

## Overview

This feature doesn't introduce new data structures but rather transforms how existing path references are resolved. The "data model" describes the path categories and their resolution strategies.

## Path Categories

### 1. Build-Time Paths (Nix Expression Evaluation)

Paths resolved during `nix build` or `nixos-rebuild`:

| Entity | Current Pattern | Target Pattern | Scope |
|--------|-----------------|----------------|-------|
| Module imports | `./modules/...` | `./modules/...` (unchanged) | Relative to flake.nix |
| Local file reads | `/etc/nixos/...` | `${./.}/...` or relative | Relative to current file |
| Asset sources | `/etc/nixos/assets/...` | `${./assets}/...` | Relative to source |

**Resolution Strategy**: Use Nix's built-in relative path resolution from flake root. No changes needed for most imports.

### 2. Runtime Asset Paths (Nix Store)

Static assets that must be available after system activation:

| Entity | Current Pattern | Target Pattern | Files Affected |
|--------|-----------------|----------------|----------------|
| Icon paths | `/etc/nixos/assets/icons/*.svg` | `${assetsPackage}/icons/*.svg` | app-registry-data.nix, pwa-sites.nix |
| Script paths | `/etc/nixos/scripts/*.sh` | `${scriptPackage}/bin/*` | sway.nix, i3.nix |
| Documentation | `file:///etc/nixos/specs/...` | Removed or store path | i3-project-daemon.nix |

**Resolution Strategy**: Copy assets to Nix store using `pkgs.runCommand` and reference store paths.

**Assets Package Definition**:
```nix
# lib/assets.nix
{ pkgs }:
pkgs.runCommand "nixos-config-assets" {} ''
  mkdir -p $out/icons
  cp -r ${../assets/icons}/* $out/icons/
''
```

### 3. Runtime Script Execution Paths (Shell)

Scripts executed at runtime via keybindings or daemons:

| Entity | Current Pattern | Target Pattern | Timing |
|--------|-----------------|----------------|--------|
| Keybinding scripts | `exec /etc/nixos/scripts/foo.sh` | `exec ${fooScript}/bin/foo` | Runtime |
| Daemon helpers | `/etc/nixos/scripts/helper.sh` | `${helperScript}/bin/helper` | Runtime |
| Claude hooks | `/etc/nixos/scripts/claude-hooks/*.sh` | `${hooksPackage}/bin/*` | Runtime |

**Resolution Strategy**: Convert inline script references to Nix store packages using `pkgs.writeShellApplication`.

### 4. Development Script Paths (Git Discovery)

Scripts that only run during development (never in production):

| Entity | Current Pattern | Target Pattern | Context |
|--------|-----------------|----------------|---------|
| Test runners | `cd /etc/nixos && pytest` | `cd "$FLAKE_ROOT" && pytest` | Development |
| Cleanup scripts | `DAEMON_DIR = Path("/etc/nixos/...")` | `get_flake_root() / "..."` | Development |
| Build wrappers | `--flake /etc/nixos` | `--flake "$FLAKE_ROOT"` | Development |

**Resolution Strategy**: Use `FLAKE_ROOT` environment variable with git discovery fallback.

### 5. Environment Variables

User-facing variables for flake location:

| Variable | Current Value | Target Behavior | File |
|----------|---------------|-----------------|------|
| `NH_FLAKE` | `/etc/nixos` (hardcoded) | Git discovery with fallback | nix.nix |
| `NH_OS_FLAKE` | `/etc/nixos` (hardcoded) | Git discovery with fallback | nix.nix |
| `FLAKE_ROOT` | (new) | Git discovery or manual | shell init |

**Resolution Strategy**: Use `lib.mkDefault` with shell-based dynamic detection.

## Entity Relationships

```
┌──────────────────┐
│   flake.nix      │
│  (entry point)   │
└────────┬─────────┘
         │ imports (relative paths, unchanged)
         ▼
┌──────────────────┐     ┌──────────────────┐
│  Nix Modules     │────▶│  Assets Package  │
│  (*.nix files)   │     │  (Nix store)     │
└────────┬─────────┘     └────────┬─────────┘
         │ reference                │ contains
         ▼                         ▼
┌──────────────────┐     ┌──────────────────┐
│ Runtime Scripts  │     │  Icons/Assets    │
│ (Nix store pkgs) │     │  (/nix/store/...)│
└──────────────────┘     └──────────────────┘
         │ executed by
         ▼
┌──────────────────┐
│  Window Manager  │
│  (Sway/i3)       │
└──────────────────┘
```

## Validation Rules

### Path Resolution Validation

| Rule | Validation | Error |
|------|------------|-------|
| No `/etc/nixos` in runtime code | grep -r "/etc/nixos" in scripts | "Hardcoded path detected" |
| Assets exist in store | `test -f ${assetsPackage}/icons/*.svg` | "Asset not found in store" |
| Scripts executable | `test -x ${script}/bin/name` | "Script not executable" |

### Build Parity Validation

| Rule | Validation | Success Criteria |
|------|------------|------------------|
| Identical derivation | Compare `nix path-info` output | Same store path hash |
| All targets build | `nixos-rebuild dry-build --flake .#<all>` | Exit code 0 |
| No path errors | Check build logs | No "path does not exist" errors |

## State Transitions

Not applicable - this feature modifies path resolution at build time, not runtime state.

## Migration Notes

### From Hardcoded to Portable

1. **Icons**: `/etc/nixos/assets/icons/x.svg` → `${assetsPackage}/icons/x.svg`
2. **Scripts**: `/etc/nixos/scripts/x.sh` → `${xScript}/bin/x`
3. **Env vars**: Hardcoded string → `lib.mkDefault` with dynamic detection

### Backward Compatibility

Per Constitution Principle XII (Forward-Only Development): No backward compatibility layer. All hardcoded paths are replaced completely in a single change.

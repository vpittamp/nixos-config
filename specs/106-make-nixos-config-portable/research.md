# Research: Make NixOS Config Portable

**Feature**: 106-make-nixos-config-portable
**Date**: 2025-12-01
**Status**: Complete

## Research Topics

### 1. Nix Store Paths for Runtime Assets

**Decision**: Use `pkgs.writeText`/`pkgs.copyPathToStore` to copy assets into the Nix store during build

**Rationale**:
- Assets in `/nix/store` are immutable and available regardless of source directory
- Nix automatically handles deduplication
- Store paths are deterministic based on content hash, ensuring reproducibility
- This is the standard Nix pattern for runtime resources

**Alternatives Considered**:
- **Git-based discovery at runtime**: Rejected - requires git repo to exist at runtime, breaks after worktree deletion
- **Environment variable pointing to assets**: Rejected - requires manual configuration, error-prone
- **Home-manager symlinks**: Rejected - creates dependency on home-manager activation order

**Implementation Pattern**:
```nix
# In a Nix module
let
  assetsDir = pkgs.runCommand "nixos-assets" {} ''
    mkdir -p $out/icons
    cp -r ${./assets/icons}/* $out/icons/
  '';
in {
  # Reference: ${assetsDir}/icons/youtube.svg
}
```

### 2. Script Path Resolution Strategy

**Decision**: Use a combination of Nix store paths (for scripts bundled with config) and git discovery (for development scripts)

**Rationale**:
- **Production scripts** (keybindings, daemons): Should be in Nix store for reliability
- **Development scripts** (tests, cleanup): Can use git discovery since they only run in dev context

**Implementation Patterns**:

**Pattern A - Nix Store Scripts (Production)**:
```nix
let
  myScript = pkgs.writeShellApplication {
    name = "my-script";
    runtimeInputs = [ pkgs.jq pkgs.sway ];
    text = ''
      # Script contents here
    '';
  };
in {
  home.packages = [ myScript ];
  # Or for keybindings: bindsym $mod+x exec ${myScript}/bin/my-script
}
```

**Pattern B - Git Discovery (Development)**:
```bash
#!/usr/bin/env bash
# For dev/test scripts only
FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "/etc/nixos")}"
```

**Alternatives Considered**:
- **All scripts via git discovery**: Rejected - breaks if git repo not present after deployment
- **All scripts via Nix store**: Rejected - development scripts need to reference local files for testing
- **Hardcoded fallback paths**: Rejected - violates Forward-Only Development principle

### 3. Environment Variable Strategy

**Decision**: Use `lib.mkDefault` for NH_FLAKE/NH_OS_FLAKE with git discovery in shell initialization

**Rationale**:
- `mkDefault` allows user override via home-manager
- Shell initialization can detect git repo and set variable dynamically
- Supports both worktree development and standalone deployment

**Implementation Pattern**:
```nix
# home-modules/tools/nix.nix
home.sessionVariables = {
  # Default to git repo detection, fallback to /etc/nixos
  NH_FLAKE = lib.mkDefault "$(git rev-parse --show-toplevel 2>/dev/null || echo /etc/nixos)";
};

# Or via shell rc file:
programs.bash.initExtra = ''
  export NH_FLAKE="''${NH_FLAKE:-$(git rev-parse --show-toplevel 2>/dev/null || /etc/nixos)}"
'';
```

**Alternatives Considered**:
- **Always hardcode /etc/nixos**: Rejected - the problem we're solving
- **Always require manual setting**: Rejected - poor developer experience
- **Remove NH_FLAKE entirely**: Rejected - breaks nh tool workflow

### 4. Icon Path Resolution

**Decision**: Copy icons to Nix store and reference store paths in app-registry-data.nix and pwa-sites.nix

**Rationale**:
- Icons are static assets that don't change at runtime
- Nix store provides content-addressed, reproducible paths
- Eww, Walker, and other UI tools can read from any path including /nix/store

**Implementation Pattern**:
```nix
# lib/helpers.nix or similar
let
  assetsPackage = pkgs.runCommand "nixos-config-assets" {} ''
    mkdir -p $out/icons
    cp -r ${../assets/icons}/* $out/icons/
  '';
in {
  # Export for use in other modules
  inherit assetsPackage;
}

# In app-registry-data.nix
{
  name = "youtube";
  icon = "${assetsPackage}/icons/youtube.svg";
}
```

### 5. Python Script Path Discovery

**Decision**: Use a standardized `get_flake_root()` function with git discovery fallback

**Rationale**:
- Centralizes path discovery logic
- Consistent behavior across all Python scripts
- Supports both development (git) and deployment (fallback) scenarios

**Implementation Pattern**:
```python
from pathlib import Path
import subprocess

def get_flake_root() -> Path:
    """Get the flake root directory using git discovery with fallback."""
    # Check environment variable first
    if flake_root := os.environ.get("FLAKE_ROOT"):
        return Path(flake_root)

    # Try git discovery
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # Fallback to /etc/nixos
    return Path("/etc/nixos")
```

### 6. Test Script Portability

**Decision**: All test scripts should use `FLAKE_ROOT` environment variable with git discovery

**Rationale**:
- Tests always run in development context (git repo present)
- Environment variable allows CI/CD override
- Consistent with shell script pattern

**Implementation Pattern**:
```bash
#!/usr/bin/env bash
set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel)}"
cd "$FLAKE_ROOT"

# Run tests relative to FLAKE_ROOT
pytest tests/
```

## Summary

| Category | Strategy | Reason |
|----------|----------|--------|
| Icons/Assets | Nix store (`pkgs.runCommand`) | Immutable, content-addressed, always available |
| Production Scripts | Nix store (`pkgs.writeShellApplication`) | Reliable, no runtime dependencies |
| Dev/Test Scripts | Git discovery + env var | Flexibility for development workflows |
| Environment Variables | `mkDefault` + shell init | Overridable, auto-detected in git repos |
| Python Paths | Centralized `get_flake_root()` | Consistent discovery across scripts |

## Files Requiring Changes (Prioritized)

### High Priority (Build-Breaking)
1. `home-modules/desktop/app-registry-data.nix` - Icon paths
2. `shared/pwa-sites.nix` - Icon paths
3. `home-modules/desktop/sway.nix` - Script exec paths
4. `home-modules/tools/nix.nix` - Environment variables

### Medium Priority (Runtime Scripts)
5. `scripts/fzf-launcher.sh` - FLAKE_PATH default
6. `scripts/emergency-recovery.sh` - cd /etc/nixos
7. `scripts/claude-hooks/stop-notification.sh` - Callback paths

### Low Priority (Development/Testing)
8. `scripts/code-cleanup-check.py` - DAEMON_DIR constant
9. `tests/i3pm/integration/run_*.sh` - Test paths
10. Python scripts in `scripts/` - Path constants

## No Outstanding Clarifications

All technical decisions have been resolved through research. Ready for Phase 1 design.

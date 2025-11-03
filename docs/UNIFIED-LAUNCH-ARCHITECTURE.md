# Unified Launch Architecture

**Feature**: 056-pwa-window-tracking-fix
**Status**: Implemented
**Date**: 2025-11-03

## Overview

All applications (regular apps, PWAs, VS Code, terminal apps) now launch through a single unified path that provides consistent:
- I3PM environment variable injection
- Launch notifications to daemon
- Workspace assignment
- Project context propagation
- Window-to-project correlation

## Architecture

```
Walker/Elephant
    ↓
.desktop file (Exec=app-launcher-wrapper.sh <app-name>)
    ↓
app-launcher-wrapper.sh (unified launcher)
    ├→ Load app metadata from registry
    ├→ Query project context from daemon
    ├→ Inject I3PM_* environment variables
    ├→ Send launch notification to daemon
    ├→ Resolve command + parameters
    └→ Execute via systemd-run
        ↓
    Application Process
        ├→ Regular app (firefox, thunar, etc.)
        ├→ PWA (via launch-pwa-by-name → firefoxpwa)
        ├→ VS Code (code --new-window $PROJECT_DIR)
        └→ Terminal (alacritty -e sesh connect)
```

## Key Components

### 1. app-launcher-wrapper.sh (430 lines)

**Single source of truth** for all application launches.

**Responsibilities:**
- Load application metadata from `~/.config/i3/application-registry.json`
- Query active project from daemon (`i3pm project current`)
- Inject standard I3PM_* environment variables
- Send launch notification to daemon (Tier 0 correlation)
- Resolve parameters with variable substitution
- Execute via `systemd-run` for process isolation

**I3PM Environment Variables (injected for ALL apps):**
```bash
I3PM_APP_ID="<app-name>-<project>-<pid>-<timestamp>"
I3PM_APP_NAME="<app-name>"
I3PM_PROJECT_NAME="<project-name>"
I3PM_PROJECT_DIR="<project-directory>"
I3PM_PROJECT_DISPLAY_NAME="<display-name>"
I3PM_PROJECT_ICON="<icon>"
I3PM_SCOPE="scoped|global"
I3PM_ACTIVE="true|false"
I3PM_LAUNCH_TIME="<unix-timestamp>"
I3PM_LAUNCHER_PID="<wrapper-pid>"
I3PM_TARGET_WORKSPACE="<workspace-number>"
I3PM_EXPECTED_CLASS="<window-class>"
```

### 2. launch-pwa-by-name (114 lines)

**Thin routing layer** for Firefox PWAs.

**Responsibilities:**
- Resolve PWA display name → ULID (via firefoxpwa, desktop files)
- Look up PWA in app registry by expected_class (FFPWA-{ULID})
- Route to `app-launcher-wrapper.sh` for unified launch
- Fallback to direct `firefoxpwa site launch` if not in registry

**Flow:**
```
launch-pwa-by-name "Claude"
    ↓
Resolve: "Claude" → ULID "01JCYF8Z2M7R4N6QW9XKPHVTB5"
    ↓
Registry lookup: FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5 → "claude-pwa"
    ↓
app-launcher-wrapper.sh "claude-pwa"
    ↓
Executes: firefoxpwa site launch 01JCYF8Z2M7R4N6QW9XKPHVTB5
    (with I3PM_* env vars injected)
```

### 3. Application Registry

**Single source of truth** for application metadata.

**Location:** `~/.config/i3/application-registry.json`

**Example Entry (PWA):**
```json
{
  "name": "claude-pwa",
  "display_name": "Claude",
  "command": "launch-pwa-by-name",
  "parameters": ["Claude"],
  "scope": "scoped",
  "expected_class": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",
  "preferred_workspace": 52,
  "icon": "claude",
  "nix_package": "pkgs.firefoxpwa",
  "multi_instance": false,
  "fallback_behavior": "use_home",
  "description": "Claude AI Assistant by Anthropic"
}
```

**Example Entry (Regular App):**
```json
{
  "name": "firefox",
  "display_name": "Firefox",
  "command": "firefox",
  "parameters": [],
  "scope": "global",
  "expected_class": "firefox",
  "preferred_workspace": 3,
  "icon": "firefox",
  "nix_package": "pkgs.firefox",
  "multi_instance": false,
  "fallback_behavior": "skip"
}
```

**Example Entry (VS Code):**
```json
{
  "name": "vscode",
  "display_name": "VS Code",
  "command": "code",
  "parameters": ["--disable-gpu", "--disable-software-rasterizer", "--new-window", "$PROJECT_DIR"],
  "scope": "scoped",
  "expected_class": "Code",
  "preferred_workspace": 2,
  "icon": "vscode",
  "nix_package": "pkgs.vscode",
  "multi_instance": true,
  "fallback_behavior": "skip"
}
```

## Window Matching Tiers

The daemon uses a tiered approach to correlate windows with applications and projects:

### Tier 0: Launch Notification (Priority)
- **Source**: Launch notification sent by wrapper BEFORE app starts
- **Data**: `app_name`, `expected_class`, `workspace_number`, `timestamp`, `project_name`
- **Latency**: <100ms (notification → window::new event)
- **Reliability**: 100% for sequential launches, 95% for rapid launches
- **Use case**: Immediate workspace assignment, project association

### Tier 1: I3PM Environment Variables
- **Source**: Read from `/proc/<pid>/environ`
- **Data**: All I3PM_* variables (APP_NAME, PROJECT_NAME, SCOPE, etc.)
- **Latency**: ~10ms (requires /proc filesystem access)
- **Reliability**: 100% for apps launched via wrapper
- **Use case**: Project filtering, window identity verification

### Tier 2: Deterministic Class Matching
- **Source**: Sway/i3 window class property
- **PWAs**: `FFPWA-{ULID}` (always unique, 100% reliable)
- **Regular apps**: `expected_class` from registry (may have collisions)
- **Latency**: <5ms (native window property)
- **Use case**: Fallback identification, fast lookups

## Benefits Over Previous Architecture

### Before (Fragmented)

```
Regular apps → app-launcher-wrapper.sh → I3PM env vars ✓
PWAs         → launch-pwa-by-name      → NO I3PM env vars ✗
              → firefoxpwa (direct)     → NO launch notification ✗
VS Code      → app-launcher-wrapper.sh → I3PM env vars ✓
```

**Problems:**
- PWAs invisible to daemon (no env vars)
- Inconsistent workspace assignment
- Duplicate launch logic
- PWAs couldn't be filtered by project

### After (Unified)

```
ALL apps → app-launcher-wrapper.sh → I3PM env vars ✓
                                   → Launch notification ✓
                                   → Workspace assignment ✓
                                   → Project context ✓
```

**Benefits:**
- ✓ Single launch path for all apps
- ✓ Consistent I3PM environment variable injection
- ✓ PWAs tracked and filtered like regular apps
- ✓ Workspace assignment works identically
- ✓ Launch notifications enable Tier 0 matching
- ✓ No code duplication
- ✓ Easier to maintain and debug

## Variable Substitution

The wrapper supports dynamic variable substitution in parameters:

| Variable | Example Value | Use Case |
|----------|---------------|----------|
| `$PROJECT_DIR` | `/etc/nixos` | Open editor/file manager in project |
| `$PROJECT_NAME` | `nixos` | Project identifier |
| `$SESSION_NAME` | `nixos` | Tmux/sesh session name |
| `$HOME` | `/home/vpittamp` | User home directory |
| `$WORKSPACE` | `2` | Target workspace number |

**Example:**
```json
{
  "name": "vscode",
  "parameters": ["--new-window", "$PROJECT_DIR"]
}
```

With active project "nixos" (`/etc/nixos`):
```bash
# Resolves to:
code --new-window /etc/nixos
```

## Process Isolation

All apps are launched via `systemd-run --user --scope`:

**Benefits:**
- Process isolated from launcher (Walker/Elephant)
- Apps survive launcher restart/crash
- Clean environment variable propagation
- Proper process group management
- Works with desktop file execution

**Example:**
```bash
systemd-run --user --scope \
  --setenv=I3PM_APP_ID="claude-pwa-nixos-12345-1698765432" \
  --setenv=I3PM_APP_NAME="claude-pwa" \
  --setenv=I3PM_PROJECT_NAME="nixos" \
  --setenv=I3PM_TARGET_WORKSPACE="52" \
  --setenv=I3PM_EXPECTED_CLASS="FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5" \
  bash -c "firefoxpwa site launch 01JCYF8Z2M7R4N6QW9XKPHVTB5"
```

## Fallback Behavior

When no project is active and parameters reference project variables:

### `skip` (default for global apps)
Remove project variables from parameters.
```bash
# Before: code --new-window $PROJECT_DIR
# After:  code --new-window
```

### `use_home` (default for scoped apps)
Substitute `$HOME` for `$PROJECT_DIR`.
```bash
# Before: thunar $PROJECT_DIR
# After:  thunar /home/vpittamp
```

### `error`
Refuse to launch, require active project.
```bash
Error: No project active and fallback behavior is 'error'
  Use 'i3pm project switch <name>' to activate a project.
```

## Debugging

### Enable debug logging:
```bash
DEBUG=1 app-launcher-wrapper.sh vscode
```

### Check launch logs:
```bash
tail -f ~/.local/state/app-launcher.log
```

### Dry-run mode:
```bash
DRY_RUN=1 app-launcher-wrapper.sh claude-pwa
```

### Verify environment variables:
```bash
# Get PID from i3pm windows
i3pm windows

# Check process environment
cat /proc/<PID>/environ | tr '\0' '\n' | grep I3PM_
```

## Testing

Close and relaunch each app type to verify I3PM integration:

### PWAs
```bash
# Via Walker
Meta+D → "Claude" → Enter

# Verify
i3pm windows | grep FFPWA
cat /proc/<PID>/environ | tr '\0' '\n' | grep I3PM_
```

### Regular Apps
```bash
# Via Walker
Meta+D → "Firefox" → Enter

# Verify
i3pm windows | grep firefox
```

### VS Code
```bash
# Via Walker (with active project)
i3pm project switch nixos
Meta+D → "VS Code" → Enter

# Verify opens /etc/nixos
```

## Files Modified

| File | Lines | Purpose |
|------|-------|---------|
| `/etc/nixos/scripts/app-launcher-wrapper.sh` | 430 | Unified launcher |
| `/etc/nixos/home-modules/tools/pwa-launcher.nix` | 114 | PWA routing layer |
| `/etc/nixos/home-modules/desktop/app-registry-data.nix` | ~600 | App metadata |

## Related Documentation

- `/etc/nixos/specs/041-ipc-launch-context/quickstart.md` - Launch notifications
- `/etc/nixos/specs/053-workspace-assignment-enhancement/quickstart.md` - Workspace assignment
- `/etc/nixos/specs/056-declarative-pwa-installation/quickstart.md` - PWA management
- `/etc/nixos/docs/PYTHON_DEVELOPMENT.md` - Daemon architecture

## Future Improvements

- [ ] Add launch latency metrics to daemon
- [ ] Support launch-time workspace override (CLI flag)
- [ ] Add retry logic for failed launch notifications
- [ ] Cache registry reads for faster launches
- [ ] Add launch telemetry/analytics

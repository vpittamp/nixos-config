# Sway Configuration Research Summary

Research Date: 2025-10-30
Task: Analyze Sway compositor configuration differences between hetzner-sway and M1, identify unified components, and recommend improvements.

## Key Finding

**The Sway configuration is already well-unified across both platforms.** A single home-manager module (`home-modules/desktop/sway.nix`) handles both headless (VNC) and physical display configurations using conditional logic based on hostname detection.

## Configuration Overview

### Unified Architecture

```
┌─────────────────────────────────┐
│  Single Sway Home-Manager       │
│  Module: sway.nix              │
│                                 │
│  let isHeadless =              │
│    hostname == "hetzner-sway"  │
│                                 │
│  if isHeadless then             │
│    ▶ Headless outputs (3)       │
│    ▶ VNC services               │
│    ▶ Software rendering         │
│  else                            │
│    ▶ Physical outputs (2)        │
│    ▶ GPU rendering              │
│    ▶ Apple touchpad             │
└─────────────────────────────────┘
```

### Platforms Covered

1. **Hetzner-Sway (Cloud VM)**
   - Headless Wayland (no physical displays)
   - 3 virtual outputs via WayVNC
   - Software rendering (pixman for Sway, cairo for GTK4)
   - VNC remote access on ports 5900-5902
   - Tailscale audio streaming

2. **M1 (Apple Silicon MacBook Pro)**
   - Physical displays: Retina builtin + HDMI external
   - GPU rendering (Intel on M1)
   - Native Wayland with XWayland
   - Apple-specific input (touchpad, keyboard)

## What's Unified

| Component | Status | Evidence |
|-----------|--------|----------|
| **Sway Module** | ✓ Unified | Both use `home-modules/desktop/sway.nix` |
| **Keybindings** | ✓ Unified | TOML-based system via sway-config-manager (Feature 047) |
| **Appearance** | ✓ Unified | JSON-based appearance config, shared defaults |
| **Status Bars** | ✓ Unified | Same structure, conditional output count/names |
| **Window Rules** | ✓ Unified | Same JSON schema, conditional system UI rules |
| **Core Sway Config** | ✓ Unified | Output/workspace/keybindings all conditional |
| **Display Manager** | ⚠ Inconsistent | Hetzner: shell wrapper, M1: tuigreet UI |
| **Environment Vars** | ⚠ Scattered | Common vars unified, headless-specific vars duplicated |

## What Needs Fixing

### Priority 1: Workspace Mode Handler (HIGH RISK)

**File**: `home-modules/desktop/sway-config-manager.nix:44-147`

**Problem**: `workspace-mode-handler.sh` hardcoded for Hetzner's HEADLESS-1/2/3 outputs
```bash
case $WORKSPACE in
    1|2) swaymsg "focus output HEADLESS-1; workspace number $WORKSPACE";;
    3|4|5) swaymsg "focus output HEADLESS-2; workspace number $WORKSPACE";;
```

**Impact**: On M1 with eDP-1/HDMI-A-1, this script would try to focus non-existent HEADLESS outputs

**Solution**: Query actual outputs dynamically from Sway

### Priority 2: Platform Detection (MEDIUM RISK)

**File**: `home-modules/desktop/sway.nix:101-107`

**Current**: Hostname-based detection
```nix
isHeadless = osConfig.networking.hostName == "nixos-hetzner-sway"
```

**Problems**:
- Breaks if hostname changes
- No way to test M1 config on another machine
- Duplicated in multiple files (sway.nix, swaybar.nix)

**Solution**: Add explicit feature flag to configurations

### Priority 3: Environment Variables (LOW RISK)

**Files**: Scattered across 3 locations
- `modules/desktop/sway.nix` (system-level)
- `configurations/hetzner-sway.nix` (greetd script)
- Duplicated in greetd shell wrapper

**Solution**: Centralize in dedicated `modules/desktop/sway-environment.nix`

## Configuration Comparison

### Environment Variables

**Headless-Only**:
- `WLR_BACKENDS=headless` (no physical displays)
- `WLR_HEADLESS_OUTPUTS=3` (three virtual outputs)
- `WLR_LIBINPUT_NO_DEVICES=1` (no input devices)
- `WLR_RENDERER=pixman` (software rendering for cloud VM)
- `GSK_RENDERER=cairo` (CRITICAL: GTK4 software rendering for Walker)

**Identical**:
- `QT_QPA_PLATFORM=wayland` (Qt Wayland support)
- `GDK_BACKEND=wayland` (GTK Wayland support)
- `XDG_SESSION_TYPE=wayland` (Wayland session)
- `XDG_CURRENT_DESKTOP=sway` (Desktop identification)

**M1-Specific Environment** (in home-manager):
- `XCURSOR_SIZE=48` (HiDPI cursor size)
- `_JAVA_OPTIONS=-Dsun.java2d.uiScale=2.0` (Java scaling)

### Output Configuration

**Headless**:
- 3 outputs: HEADLESS-1, HEADLESS-2, HEADLESS-3
- Resolution: 1920x1200@60Hz (VNC-friendly, 16:10 aspect ratio)
- Scale: 1.0 (no scaling, VNC client handles it)
- Layout: Horizontal (0,0), (1920,0), (3840,0)

**M1**:
- 2 outputs: eDP-1 (builtin), HDMI-A-1 (external)
- Resolution: 2560x1600@60Hz (Retina), 1920x1080@60Hz (external)
- Scale: 2.0 (Retina), 1.0 (external)
- Layout: Horizontal (0,0), (1280,0) - offset for Retina scaling

### Input Devices

**Headless**: None (disabled with `WLR_LIBINPUT_NO_DEVICES=1`)

**M1**: Apple-specific configuration
```nix
input = {
  "type:touchpad" = {
    natural_scroll = "enabled";
    tap = "enabled";
    tap_button_map = "lrm";        # Two-finger right-click
    dwt = "enabled";                # Disable while typing
    middle_emulation = "enabled";  # Three-finger middle-click
  };
  "type:keyboard" = {
    xkb_layout = "us";
    repeat_delay = "300";
    repeat_rate = "50";
  };
};
```

### Workspace Distribution

**Headless (3 outputs)**:
- Output 1: Workspaces 1-2
- Output 2: Workspaces 3-5
- Output 3: Workspaces 6-9

**M1 (2 outputs)**:
- eDP-1: Workspaces 1-2
- HDMI-A-1: Workspace 3+

### VNC Services

**Headless Only** (`home-modules/desktop/sway.nix:461-535`):
- 3 wayvnc systemd services (one per output)
- Port 5900: HEADLESS-1
- Port 5901: HEADLESS-2
- Port 5902: HEADLESS-3
- Firewall rules in `configurations/hetzner-sway.nix`

**M1**: No VNC services (physical display)

## Files Analyzed

### Core Configuration Files
- `/etc/nixos/home-modules/desktop/sway.nix` (main, 580 lines)
- `/etc/nixos/home-modules/desktop/swaybar.nix` (status bars, 358 lines)
- `/etc/nixos/home-modules/desktop/sway-config-manager.nix` (dynamic config, 560 lines)
- `/etc/nixos/configurations/hetzner-sway.nix` (headless-specific, 242 lines)
- `/etc/nixos/configurations/m1.nix` (M1-specific, 337 lines)
- `/etc/nixos/modules/desktop/sway.nix` (system-level, 99 lines)
- `/etc/nixos/modules/desktop/wayvnc.nix` (VNC module, 73 lines)

### Default Configuration Files
- `/etc/nixos/home-modules/desktop/sway-default-keybindings.toml`
- `/etc/nixos/home-modules/desktop/sway-default-appearance.json`

### Dynamic Configuration System (sway-config-manager)
- Python daemon with config validation, hot-reload, git version control
- Templates in `~/.local/share/sway-config-manager/templates/`
- User config in `~/.config/sway/` (hot-reloadable)
- Generated config cached locally with git tracking

## Documentation Generated

1. **SWAY_CONFIGURATION_UNIFICATION_ANALYSIS.md** (675 lines)
   - Detailed comparison of all configuration components
   - Environment variables analysis with tables
   - Output configuration differences
   - Recommendations for unification
   - Implementation priority list

2. **SWAY_UNIFICATION_QUICK_REFERENCE.md** (271 lines)
   - Executive summary
   - Top 3 issues to fix with priority levels
   - Effort/impact estimates
   - Testing checklist
   - Quick wins (no risk)

3. **SWAY_ARCHITECTURE_DIAGRAM.md** (365 lines)
   - 4-layer configuration stack (runtime → generated → home-manager → system)
   - Configuration decision tree
   - Platform-specific initialization flows
   - Template file dependencies
   - Problem areas annotated

## Recommendations (By Priority)

### Priority 1: Fix workspace-mode-handler.sh (30 minutes)
- Query actual Sway outputs dynamically
- Distribute workspaces based on detected output count
- Support 1, 2, 3+, or custom output configurations
- **Impact**: Fixes M1 multi-output workspace navigation

### Priority 2: Replace hostname detection (1 hour)
- Add `sway.platform` option to configurations
- Update all conditionals to use feature flag
- Improve code clarity and robustness
- **Impact**: Decouples configuration from hostname

### Priority 3: Centralize environment variables (1.5 hours)
- Create `modules/desktop/sway-environment.nix`
- Single source of truth for all platform-specific vars
- Eliminate duplication in greetd script
- **Impact**: Easier to maintain, single point of change

## Architecture Quality Assessment

| Aspect | Grade | Notes |
|--------|-------|-------|
| **Unification** | A | Single module handles both platforms |
| **Clarity** | B | Hostname detection could be more explicit |
| **Robustness** | B | Hardcoded output names in modes.conf is risky |
| **Maintainability** | B+ | Well-structured, but scattered env vars |
| **Documentation** | A | Feature 047 and 048 well-documented |
| **Extensibility** | B | Easy to add new platforms with feature flag |

## Conclusion

The Sway configuration demonstrates **excellent unification** between headless and physical display setups. The use of a single home-manager module with conditional logic is the right approach and works well in practice. The main opportunities for improvement are:

1. **Making workspace modes platform-agnostic** (currently Hetzner-specific)
2. **Using explicit feature flags** instead of hostname detection
3. **Centralizing environment variables** to a single source

These are incremental improvements, not architectural changes. The foundation is solid.

## Next Steps

1. Review this research with team
2. Prioritize which fixes to implement
3. Start with Priority 1 (workspace modes) if fixes are approved
4. Test thoroughly on both platforms after each change
5. Update documentation as changes are made

---

**Generated**: 2025-10-30  
**Analysis Tool**: Claude Code Research  
**Scope**: Sway Compositor Configuration Unification  
**Status**: Complete with 3 detailed analysis documents

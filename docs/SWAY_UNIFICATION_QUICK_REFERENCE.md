# Sway Configuration Unification - Quick Reference

## Current State: Already Unified!

Both Hetzner-Sway and M1 use the **same** home-manager Sway module with conditional logic.

```
┌─────────────────────────────────────────────────────────┐
│     Single Unified Sway Module: sway.nix                │
│                                                         │
│  let isHeadless = hostname == "nixos-hetzner-sway"     │
│  in                                                     │
│    if isHeadless then                                   │
│      ▶ 3 headless outputs (HEADLESS-1/2/3)            │
│      ▶ VNC services (wayvnc)                           │
│      ▶ Software rendering (pixman, cairo)              │
│    else                                                │
│      ▶ 2 physical outputs (eDP-1, HDMI-A-1)           │
│      ▶ GPU rendering                                   │
│      ▶ Apple touchpad config                           │
└─────────────────────────────────────────────────────────┘
```

## Key Findings

### ✓ Unified (No Changes Needed)
- Keybindings system (Feature 047: sway-config-manager)
- Appearance configuration (JSON-based defaults)
- Swaybar structure (output-specific bars)
- Core Sway functionality

### ⚠ Partially Unified (Minor Fixes Needed)
- **Environment Variables**: `GSK_RENDERER=cairo` missing on M1 (but may not be needed)
- **Input Devices**: Unconditionally configured; ignored on headless anyway
- **Platform Detection**: Hostname-based (fragile, works but could be cleaner)

### ✗ Platform-Specific (Working As-Is)
- **VNC Services**: Headless-only (correctly gated with `lib.mkIf isHeadless`)
- **Output Config**: Different for each platform (conditionals in place)
- **Workspace Distribution**: Different modes for each (hardcoded but working)

## Top Issues to Fix

### Issue #1: Workspace Mode Handler (HIGH)
**File**: `home-modules/desktop/sway-config-manager.nix` line 44-147

**Problem**: `workspace-mode-handler.sh` hardcoded for HEADLESS-1/2/3
```bash
case $WORKSPACE in
    1|2) swaymsg "focus output HEADLESS-1; workspace number $WORKSPACE";;
    3|4|5) swaymsg "focus output HEADLESS-2; workspace number $WORKSPACE";;
    6|7|8|9) swaymsg "focus output HEADLESS-3; workspace number $WORKSPACE";;
esac
```

**Impact**: M1 with 2 outputs would incorrectly focus HEADLESS-1/2/3 (non-existent)

**Solution**: Query actual output names:
```bash
OUTPUTS=$(swaymsg -t get_outputs | jq -r '.[].name')
OUTPUT_ARRAY=($OUTPUTS)
# Calculate which output based on number and output count
```

### Issue #2: Platform Detection (MEDIUM)
**File**: `home-modules/desktop/sway.nix` line 101-107

**Problem**: Hostname-based detection
```nix
isHeadless = osConfig.networking.hostName == "nixos-hetzner-sway"
```

**Issues**:
- Breaks if hostname changes
- No way to test M1 config on different machine
- Single source of truth missing (duplicated in swaybar.nix, etc.)

**Solution**: Add explicit feature flag to configurations:
```nix
# In configurations/hetzner-sway.nix
sway.platform = "headless";

# In configurations/m1.nix
sway.platform = "physical";

# In home-modules/desktop/sway.nix
isHeadless = osConfig.sway.platform or "physical" == "headless";
```

### Issue #3: Environment Variables (LOW)
**File**: `modules/desktop/sway.nix` line 52-63

**Problem**: Scattered across 3 locations with no unified source
- `modules/desktop/sway.nix` (system-level common)
- `configurations/hetzner-sway.nix` (headless-specific)
- Greetd script in same file (duplicated!)

**Solution**: Centralize in `modules/desktop/sway-environment.nix`:
```nix
options.services.sway-environment = {
  platform = mkOption { type = enum [ "headless" "physical" ]; };
  softwareRendering = mkOption { type = bool; default = false; };
};

config.environment.sessionVariables = {
  # Common
  MOZ_ENABLE_WAYLAND = "1";
  QT_QPA_PLATFORM = "wayland";
  # ... rest
} // optionalAttrs (cfg.platform == "headless") {
  WLR_BACKENDS = "headless";
  WLR_RENDERER = "pixman";
} // optionalAttrs cfg.softwareRendering {
  GSK_RENDERER = "cairo";
};
```

## Files Organization

### Core Sway Configuration
```
home-modules/desktop/
├── sway.nix                          ← Main unified module
├── swaybar.nix                       ← Status bars (conditional)
├── sway-config-manager.nix           ← Dynamic config system
├── sway-default-keybindings.toml     ← Shared defaults
└── sway-default-appearance.json      ← Shared defaults
```

### System-Level Configuration
```
configurations/
├── hetzner-sway.nix                  ← Headless-specific
└── m1.nix                            ← M1-specific

modules/desktop/
├── sway.nix                          ← System-level setup
└── wayvnc.nix                        ← VNC server module (unused on M1)
```

### Dynamic Configuration (sway-config-manager)
```
home-modules/desktop/sway-config-manager/
├── daemon.py                         ← Main daemon
├── cli.py                            ← CLI interface
├── config/
│   ├── loader.py                     ← Load TOML/JSON configs
│   ├── validator.py                  ← Validate against schema
│   ├── merger.py                     ← Merge with Nix defaults
│   └── reload_manager.py             ← Hot-reload with `swaymsg reload`
├── rules/
│   ├── appearance_manager.py         ← Colors, fonts, gaps, borders
│   ├── window_rule_engine.py         ← Float, size, position rules
│   └── workspace_assignments.py      ← Workspace/output assignments
└── models.py                         ← Pydantic data models
```

## Configuration Hierarchy

1. **System-Level Nix** (stable, requires rebuild)
   - `modules/desktop/sway.nix` - Sway packages, systemd services
   - `configurations/{hetzner-sway,m1}.nix` - Platform-specific settings
   - Environment variables

2. **Home-Manager Nix** (user-specific, requires rebuild)
   - `home-modules/desktop/sway.nix` - Output config, keybindings, bars
   - `home-modules/desktop/sway-config-manager.nix` - Daemon setup

3. **Runtime Configuration** (hot-reloadable, NO rebuild needed)
   - `~/.config/sway/keybindings.toml` - User keybindings
   - `~/.config/sway/window-rules.json` - Floating/sizing rules
   - `~/.config/sway/workspace-assignments.json` - Workspace/output assignments
   - `~/.config/sway/appearance.json` - Colors, gaps, borders

4. **Generated Configuration** (auto-generated by daemon)
   - `~/.config/sway/keybindings-generated.conf` - Compiled from TOML
   - `~/.config/sway/appearance-generated.conf` - Compiled from JSON
   - `~/.config/sway/modes.conf` - Workspace modes (HARDCODED for Hetzner!)

## What Needs Fixing Before Full Unification

### Priority 1: workspace-mode-handler.sh
**Why**: Breaks M1 multi-output support
**Effort**: 30 minutes (query outputs dynamically)
**Impact**: Medium (workspace modes work, but on wrong outputs)

### Priority 2: Platform Detection Flag
**Why**: Improves code clarity and robustness
**Effort**: 1 hour (add option, update 2-3 files)
**Impact**: Low (works now, but fragile)

### Priority 3: Centralized Env Variables
**Why**: Single source of truth
**Effort**: 1.5 hours (extract to module, test both platforms)
**Impact**: Low (works now, but scattered)

## Testing Checklist

After implementing fixes, test on both platforms:

```bash
# On M1 (physical display)
[✓] Workspaces 1-3 distribute correctly across eDP-1 and HDMI-A-1
[✓] Workspace mode navigation works (Mod+<digit>)
[✓] Touchpad input works (natural scrolling, tap-to-click)
[✓] Walker launcher works
[✓] Status bars appear on both outputs

# On Hetzner-Sway (headless)
[✓] Three VNC outputs show workspaces correctly
[✓] Workspace mode navigation works across HEADLESS-1/2/3
[✓] VNC connections stable and responsive
[✓] Walker launcher works with cairo rendering
[✓] Status bars appear on all three outputs
[✓] Audio streaming over Tailscale (if enabled)
```

## Quick Wins (No Risk)

### 1. Add GSK_RENDERER=cairo to M1 (Optional)
Only needed if Walker has GPU rendering issues. Currently not needed.

### 2. Make Input Devices Explicitly Conditional
Doesn't hurt now (WLR_LIBINPUT_NO_DEVICES=1 ignores it), but better practice:
```nix
input = lib.mkIf (!isHeadless) { ... };
```

### 3. Unify Greetd Environment Variable Setting
Move from inline script to generated script:
```nix
# Use environment.sessionVariables to generate greetd script
```

## Long-Term Improvements

### Data-Driven Configuration
Define outputs as data, not conditionals:
```nix
sway.outputs = [
  { name = "eDP-1"; resolution = "2560x1600@60Hz"; scale = 2.0; }
  { name = "HDMI-A-1"; resolution = "1920x1080@60Hz"; scale = 1.0; }
];
```

Then generate Sway config from data (no if/then/else needed).

### Dynamic Modes Generation
Generate modes.conf based on actual output count:
```python
class ModesGenerator:
    def generate_for_outputs(self, outputs: List[OutputInfo]) -> str:
        """Create modes.conf dynamically"""
        if len(outputs) == 1:
            # Single output mode
        elif len(outputs) == 2:
            # Two output mode (1-2 on first, 3+ on second)
        else:
            # Multi-output mode (1-2, 3-5, 6+)
```

## Related Documentation

- Full analysis: `/etc/nixos/docs/SWAY_CONFIGURATION_UNIFICATION_ANALYSIS.md`
- Sway Feature 047: `/etc/nixos/specs/047-create-a-new/quickstart.md`
- Hetzner VNC setup: `/etc/nixos/specs/048-multi-monitor-headless/quickstart.md`
- M1 setup: `/etc/nixos/docs/M1_SETUP.md`

## Key Takeaway

**The architecture is already unified and working well.** Most differences are expected platform-specific behavior. Only `workspace-mode-handler.sh` needs attention to work correctly on M1, and platform detection could be cleaner with an explicit flag.

# Sway Compositor Configuration Analysis: Hetzner-Sway vs M1

## Executive Summary

Both Hetzner-Sway (headless/VNC) and M1 (physical display) configurations share the **same unified Sway module** (`home-modules/desktop/sway.nix`) with conditional logic to adapt to platform differences. The configuration uses a **detection pattern** based on hostname to determine runtime behavior.

### Key Insight
**The architecture is already unified** - a single `sway.nix` file handles both platforms with conditionals. However, there are opportunities to improve organization and reduce duplication.

---

## 1. Environment Variable Configuration

### Headless (Hetzner-Sway) Variables

**System-level** (`configurations/hetzner-sway.nix`):
```nix
environment.sessionVariables = {
  WLR_BACKENDS = "headless";               # No physical displays
  WLR_HEADLESS_OUTPUTS = "3";              # Three virtual outputs
  WLR_LIBINPUT_NO_DEVICES = "1";           # No input devices
  WLR_RENDERER = "pixman";                 # Software rendering (cloud VM)
  GSK_RENDERER = "cairo";                  # GTK4 software rendering (CRITICAL for Walker)
  XDG_SESSION_TYPE = "wayland";
  XDG_CURRENT_DESKTOP = "sway";
  QT_QPA_PLATFORM = "wayland";
  GDK_BACKEND = "wayland";
};
```

**Also in greetd command** (explicitly exported for login):
```bash
export WLR_BACKENDS=headless
export WLR_HEADLESS_OUTPUTS=3
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export GSK_RENDERER=cairo
```

### M1 (Physical Display) Variables

**System-level** (`modules/desktop/sway.nix`):
```nix
environment.sessionVariables = {
  MOZ_ENABLE_WAYLAND = "1";                # Firefox
  NIXOS_OZONE_WL = "1";                    # Chromium/Electron
  QT_QPA_PLATFORM = "wayland";
  SDL_VIDEODRIVER = "wayland";             # SDL applications
  _JAVA_AWT_WM_NONREPARENTING = "1";       # Java AWT
  XDG_SESSION_TYPE = "wayland";
  XDG_CURRENT_DESKTOP = "sway";
};
```

**Home-manager** (`home-modules/desktop/sway.nix`):
- No additional environment variables (inherits from system-level)

### Analysis

| Category | Headless | M1 | Unified? |
|----------|----------|-----|----------|
| **Display Rendering** | WLR_RENDERER=pixman | Default GPU | Platform-specific ✓ |
| **GTK4 Rendering** | GSK_RENDERER=cairo | Default GPU | Headless-specific ✓ |
| **Input Devices** | WLR_LIBINPUT_NO_DEVICES=1 | Uses libinput | Platform-specific ✓ |
| **Output Count** | WLR_HEADLESS_OUTPUTS=3 | Physical detection | Platform-specific ✓ |
| **Wayland Support** | QT_QPA_PLATFORM=wayland | QT_QPA_PLATFORM=wayland | IDENTICAL ✓ |
| **GTK Wayland** | GDK_BACKEND=wayland | GDK_BACKEND=wayland | IDENTICAL ✓ |

**Issue Found**: `GSK_RENDERER=cairo` is **only** set on Hetzner-Sway in system config. If M1 needs software rendering for Walker on weak GPU, this must be added.

---

## 2. Output Configuration Differences

### Headless (Hetzner-Sway) - `home-modules/desktop/sway.nix:142-177`

```nix
output = if isHeadless then {
  "HEADLESS-1" = {
    resolution = "1920x1200@60Hz";
    position = "0,0";
    scale = "1.0";
  };
  "HEADLESS-2" = {
    resolution = "1920x1200@60Hz";
    position = "1920,0";
    scale = "1.0";
  };
  "HEADLESS-3" = {
    resolution = "1920x1200@60Hz";
    position = "3840,0";
    scale = "1.0";
  };
} else { ... }
```

**Workspace Assignment** (Feature 048):
```nix
workspaceOutputAssign = if isHeadless then [
  { workspace = "1"; output = "HEADLESS-1"; }
  { workspace = "2"; output = "HEADLESS-1"; }
  { workspace = "3"; output = "HEADLESS-2"; }
  { workspace = "4"; output = "HEADLESS-2"; }
  { workspace = "5"; output = "HEADLESS-2"; }
  { workspace = "6"; output = "HEADLESS-3"; }
  { workspace = "7"; output = "HEADLESS-3"; }
  { workspace = "8"; output = "HEADLESS-3"; }
  { workspace = "9"; output = "HEADLESS-3"; }
] else [...]
```

### M1 (Physical Display) - `home-modules/desktop/sway.nix:163-219`

```nix
output = {
  "eDP-1" = {
    scale = "2.0";                    # Retina display scaling
    resolution = "2560x1600@60Hz";
    position = "0,0";
  };
  "HDMI-A-1" = {
    scale = "1.0";
    mode = "1920x1080@60Hz";
    position = "1280,0";
  };
};

workspaceOutputAssign = [
  { workspace = "1"; output = "eDP-1"; }
  { workspace = "2"; output = "eDP-1"; }
  { workspace = "3"; output = "HDMI-A-1"; }
];
```

### Analysis
- **Scale factor**: Headless=1.0 (virtual), M1=2.0 (Retina)
- **Resolution**: Headless=1920x1200 (VNC-friendly), M1=2560x1600 (native Retina)
- **Output names**: Headless=HEADLESS-1/2/3, M1=eDP-1/HDMI-A-1
- **Workspace distribution**: Headless=9 workspaces across 3 monitors, M1=3 workspaces across 2 monitors

---

## 3. Input Device Configuration

### M1 Only - `home-modules/desktop/sway.nix:180-197`

```nix
input = {
  "type:touchpad" = {
    natural_scroll = "enabled";
    tap = "enabled";
    tap_button_map = "lrm";
    dwt = "enabled";
    middle_emulation = "enabled";
  };
  
  "type:keyboard" = {
    xkb_layout = "us";
    repeat_delay = "300";
    repeat_rate = "50";
  };
};
```

### Headless (Not Applicable)
- No input device configuration in headless mode
- `WLR_LIBINPUT_NO_DEVICES=1` disables libinput entirely

### Analysis
- **M1 has Apple-specific input settings**: Natural scrolling, tap-to-click, three-finger middle-click
- **Headless has no input**: VNC client handles all input
- **Unconditional**: Input config is not conditionally included; Sway ignores it when `WLR_LIBINPUT_NO_DEVICES=1`

---

## 4. VNC/Headless Services

### Headless Only - `home-modules/desktop/sway.nix:461-535`

**wayvnc configuration** (Feature 048):
```nix
xdg.configFile."wayvnc/config" = lib.mkIf isHeadless {
  text = ''
    address=0.0.0.0
    enable_auth=false
  '';
};

systemd.user.services."wayvnc@HEADLESS-1" = lib.mkIf isHeadless {
  Service.ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o HEADLESS-1 -S /run/user/1000/wayvnc-headless-1.sock -R -Ldebug 0.0.0.0 5900";
};

systemd.user.services."wayvnc@HEADLESS-2" = lib.mkIf isHeadless { ... };
systemd.user.services."wayvnc@HEADLESS-3" = lib.mkIf isHeadless { ... };
```

**Audio over Tailscale** (Feature 048):
```nix
systemd.user.services."tailscale-rtp-default-sink" = lib.mkIf (isHeadless && tailscaleAudioEnabled) { ... };
```

### M1
- No VNC services (physical display)
- No audio streaming (local speakers)

### Analysis
- **100% headless-specific**: No shared code with M1
- **Three independent VNC instances**: One per virtual output
- **Audio streaming**: Only on Hetzner (Tailscale RTP sink)

---

## 5. Keybindings Configuration

### Unified Structure
**Both platforms**:
- `keybindings = lib.mkForce {}` (empty in home-manager)
- All keybindings managed by sway-config-manager (Feature 047)
- Sourced from dynamic files:
  ```
  include ~/.config/sway/keybindings-generated.conf
  include ~/.config/sway/appearance-generated.conf
  include ~/.config/sway/modes.conf
  ```

### Default Template - `sway-default-keybindings.toml`
```toml
[keybindings]
"Mod+1" = { command = "workspace number 1", description = "Focus workspace 1" }
"Mod+Return" = { command = "exec alacritty", description = "Open terminal" }
"Mod+d" = { command = "exec walker", description = "Application launcher" }
# ... more keybindings
```

### Platform-Specific Notes
- **Workspace modes** (`modes.conf`): Hardcoded for 3-output distribution (Hetzner-specific!)
  ```bash
  case $WORKSPACE in
      1|2) swaymsg "focus output HEADLESS-1; workspace number $WORKSPACE; mode default";;
      3|4|5) swaymsg "focus output HEADLESS-2; workspace number $WORKSPACE; mode default";;
      6|7|8|9) swaymsg "focus output HEADLESS-3; workspace number $WORKSPACE; mode default";;
  esac
  ```

**Issue Found**: `workspace-mode-handler.sh` is **hardcoded for Hetzner's 3 HEADLESS outputs**. M1 with 2 physical outputs needs conditional logic.

### Analysis
- **Identical keybindings**: Both platforms use same TOML-based system
- **Identical appearance**: Both use same appearance.json defaults
- **Platform-specific modes**: Workspace mode handler hardcoded for Hetzner

---

## 6. Status Bar (swaybar) Configuration

### Headless (Hetzner-Sway)
**6 bars total**: 2 bars per output × 3 outputs
- Top bar: System monitoring (all outputs)
- Bottom bar: Project context (all outputs)
- Output routing: `output HEADLESS-1/2/3`

### M1 (Physical Display)
**4 bars total**: 2 bars per output × 2 outputs
- Top bar: System monitoring (eDP-1, HDMI-A-1)
- Bottom bar: Project context (eDP-1 with system tray, HDMI-A-1 without)
- Output routing: `output eDP-1` (primary), `output HDMI-A-1` (secondary)

### Identical Elements
- Both use Catppuccin Mocha color scheme
- Both use FiraCode Nerd Font
- Both use event-driven status scripts
- Both support workspace buttons

### Analysis
- **Configuration is identical in structure**: Only bar count and output names differ
- **Could be unified**: Template with output name substitution

---

## 7. Display Manager Configuration

### Headless (Hetzner-Sway) - `configurations/hetzner-sway.nix:68-89`

```nix
services.greetd = {
  enable = true;
  settings = {
    default_session = {
      command = "${pkgs.writeShellScript "sway-with-env" ''
        export WLR_BACKENDS=headless
        export WLR_HEADLESS_OUTPUTS=3
        export WLR_LIBINPUT_NO_DEVICES=1
        export WLR_RENDERER=pixman
        export XDG_SESSION_TYPE=wayland
        export XDG_CURRENT_DESKTOP=sway
        export QT_QPA_PLATFORM=wayland
        export GDK_BACKEND=wayland
        export GSK_RENDERER=cairo
        exec ${pkgs.sway}/bin/sway
      ''}";
      user = "vpittamp";
    };
  };
};
```

### M1 - `configurations/m1.nix:63-71`

```nix
services.greetd = {
  enable = true;
  settings = {
    default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
      user = "greeter";
    };
  };
};
```

### Difference
- **Hetzner**: Shell wrapper to explicitly set WLR environment variables (greetd limitation)
- **M1**: tuigreet display manager with nice UI

### Analysis
- **Greetd limitation**: System-level `environment.sessionVariables` not loaded by greetd
- **Workaround used**: Explicit shell wrapper on Hetzner
- **Inconsistent**: M1 relies on system variables, Hetzner must export them

---

## 8. Conditional Detection Mechanism

### Current Implementation - `home-modules/desktop/sway.nix:101-107`

```nix
let
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";
  tailscaleAudioCfg = if osConfig != null then lib.attrByPath [ "services" "tailscaleAudio" ] { } osConfig else { };
  tailscaleAudioEnabled = tailscaleAudioCfg.enable or false;
in
```

### Issues with Current Approach
1. **Fragile**: Hostname-based detection depends on `networking.hostName` being exactly `"nixos-hetzner-sway"`
2. **Single source of truth missing**: Duplicated in multiple files (sway.nix, swaybar.nix)
3. **Future-proof risk**: If hostname changes or new platforms added, many conditionals break
4. **No explicit feature flag**: Configuration intent unclear from code

---

## Recommendations for Unification

### 1. Organize Environment Variables

**Recommendation**: Create a dedicated module `modules/desktop/sway-environment.nix` to centralize all platform-specific variables.

**Current state**: 
- Headless vars scattered across: `hetzner-sway.nix` (system), greetd script, `sway.nix` implicit
- M1 vars in: `modules/desktop/sway.nix`, `sway.nix` implicit

**Proposed structure**:
```nix
# modules/desktop/sway-environment.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.sway-environment;
in {
  options.services.sway-environment = {
    platform = mkOption {
      type = types.enum [ "headless" "physical" ];
      description = "Sway platform type";
    };
    
    headlessOutputCount = mkOption {
      type = types.int;
      default = 3;
    };
    
    useSoftwareRendering = mkOption {
      type = types.bool;
      default = false;
    };
  };
  
  config = {
    environment.sessionVariables = {
      # Common variables
      MOZ_ENABLE_WAYLAND = "1";
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORM = "wayland";
      SDL_VIDEODRIVER = "wayland";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "sway";
    } // (lib.optionalAttrs (cfg.platform == "headless") {
      WLR_BACKENDS = "headless";
      WLR_HEADLESS_OUTPUTS = toString cfg.headlessOutputCount;
      WLR_LIBINPUT_NO_DEVICES = "1";
      WLR_RENDERER = "pixman";
    }) // (lib.optionalAttrs cfg.useSoftwareRendering {
      GSK_RENDERER = "cairo";
    });
  };
}
```

### 2. Template File Sharing Strategy

**Recommendation**: Extract dynamic templates into a shared location with no platform dependencies.

**Current state**:
- `sway-default-keybindings.toml`: Platform-agnostic ✓
- `sway-default-appearance.json`: Platform-agnostic ✓
- `workspace-mode-handler.sh`: **Headless-specific** ✗
- `modes.conf`: **Hardcoded for HEADLESS-1/2/3** ✗

**Fix workspace-mode-handler.sh**:
```bash
# Make dynamic by querying Sway for output list
OUTPUT_COUNT=$(swaymsg -t get_outputs | jq 'length')

case $OUTPUT_COUNT in
    1) # Single output - all workspaces on output
        swaymsg "workspace number $WORKSPACE; mode default"
        ;;
    2) # Two outputs - split 1-2 vs 3+
        [[ $WORKSPACE -le 2 ]] && OUTPUT="0" || OUTPUT="1"
        swaymsg "focus output $OUTPUT; workspace number $WORKSPACE; mode default"
        ;;
    3) # Three outputs - 1-2, 3-5, 6+
        if [[ $WORKSPACE -le 2 ]]; then OUTPUT="0"
        elif [[ $WORKSPACE -le 5 ]]; then OUTPUT="1"
        else OUTPUT="2"
        fi
        swaymsg "focus output $OUTPUT; workspace number $WORKSPACE; mode default"
        ;;
esac
```

**or use sway-config-manager modes.conf generator**:
```python
# sway-config-manager/rules/modes_generator.py
def generate_modes_conf(outputs):
    """Generate modes.conf dynamically based on detected outputs"""
    conf = "# Auto-generated workspace modes\n"
    
    # Determine distribution rules based on output count
    if len(outputs) == 1:
        # All workspaces on single output
        ...
    elif len(outputs) == 2:
        # WS 1-2 on primary, 3-9 on secondary
        ...
    else:  # 3+
        # WS 1-2 on primary, 3-5 on secondary, 6+ on tertiary
        ...
    
    return conf
```

### 3. Platform Detection Unification

**Recommendation**: Use a feature flag system instead of hostname detection.

**Current**: Hostname-based
```nix
isHeadless = osConfig.networking.hostName == "nixos-hetzner-sway"
```

**Proposed**: Explicit feature flag
```nix
# In configurations/hetzner-sway.nix or m1.nix
sway.platform = "headless";  # or "physical"
```

Then in home-manager:
```nix
let
  isHeadless = osConfig.sway.platform or "physical" == "headless";
in
```

**Benefits**:
- Decouples configuration from hostname
- Works with multiple instances of same platform
- Enables testing on different machines
- Clear intent in code

### 4. Output Configuration Template

**Recommendation**: Create a data-driven output configuration system.

**Current**: Hardcoded conditionals for each platform

**Proposed**:
```nix
# configurations/hetzner-sway.nix
sway = {
  platform = "headless";
  outputs = [
    { name = "HEADLESS-1"; resolution = "1920x1200@60Hz"; position = "0,0"; scale = 1.0; }
    { name = "HEADLESS-2"; resolution = "1920x1200@60Hz"; position = "1920,0"; scale = 1.0; }
    { name = "HEADLESS-3"; resolution = "1920x1200@60Hz"; position = "3840,0"; scale = 1.0; }
  ];
  workspaceDistribution = "3-monitor";  # 1-2, 3-5, 6-9
};

# configurations/m1.nix
sway = {
  platform = "physical";
  outputs = [
    { name = "eDP-1"; resolution = "2560x1600@60Hz"; position = "0,0"; scale = 2.0; }
    { name = "HDMI-A-1"; resolution = "1920x1080@60Hz"; position = "1280,0"; scale = 1.0; }
  ];
  workspaceDistribution = "2-monitor";  # 1-2, 3+
};
```

Then generate Sway config from data:
```nix
# home-modules/desktop/sway.nix
output = lib.foldl (acc: out: acc // {
  "${out.name}" = {
    resolution = out.resolution;
    position = out.position;
    scale = toString out.scale;
  };
}) {} osConfig.sway.outputs;

workspaceOutputAssign = generateWorkspaceAssignments osConfig.sway;
```

### 5. Modes Configuration Generation

**Recommendation**: Generate `modes.conf` dynamically based on workspace distribution.

**Current**: Hardcoded for headless with HEADLESS-1/2/3

**Proposed**: In sway-config-manager daemon
```python
class ModesGenerator:
    def generate(self, workspace_distribution: str, outputs: List[str]) -> str:
        """Generate modes.conf based on distribution strategy"""
        if workspace_distribution == "3-monitor":
            # WS 1-2 → output[0], 3-5 → output[1], 6-9 → output[2]
            return self._generate_3monitor_modes(outputs)
        elif workspace_distribution == "2-monitor":
            # WS 1-2 → output[0], 3-9 → output[1]
            return self._generate_2monitor_modes(outputs)
        else:
            # Single output or custom
            return self._generate_custom_modes(outputs)
```

### 6. Extract M1-Specific Input Configuration

**Recommendation**: Move M1 touchpad configuration to separate module with clear platform gating.

**Current**: Unconditional input config in sway.nix (works because WLR_LIBINPUT_NO_DEVICES=1 on headless)

**Proposed**:
```nix
# home-modules/desktop/sway-input-m1.nix
{ config, lib, osConfig ? null, ... }:
lib.mkIf (osConfig != null && osConfig.sway.platform == "physical") {
  wayland.windowManager.sway.config.input = {
    "type:touchpad" = {
      natural_scroll = "enabled";
      tap = "enabled";
      tap_button_map = "lrm";
      dwt = "enabled";
      middle_emulation = "enabled";
    };
    
    "type:keyboard" = {
      xkb_layout = "us";
      repeat_delay = "300";
      repeat_rate = "50";
    };
  };
}
```

### 7. Greetd Environment Variables

**Recommendation**: Use shared environment variable generation in greetd script.

**Current**: Duplicated in greetd shell wrapper

**Proposed**:
```nix
# modules/desktop/greetd-sway.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.greetd;
  swayEnvVars = concatStringsSep "\n" (
    mapAttrsToList (k: v: "export ${k}=${v}")
      config.environment.sessionVariables
  );
in {
  services.greetd.settings.default_session.command = 
    pkgs.writeShellScript "sway-with-env" ''
      ${swayEnvVars}
      exec ${pkgs.sway}/bin/sway
    '';
}
```

---

## Summary Table

| Component | Hetzner-Sway | M1 | Unification Status |
|-----------|--------------|----|--------------------|
| **Sway Module** | home-modules/desktop/sway.nix | home-modules/desktop/sway.nix | ✓ Unified |
| **Environment Variables** | Partially unified (GSK_RENDERER missing on M1) | Partially unified | ⚠ Needs consolidation |
| **Output Config** | Conditional in sway.nix | Conditional in sway.nix | ✓ Unified structure |
| **Input Devices** | N/A (WLR_LIBINPUT_NO_DEVICES=1) | Hardcoded in sway.nix | ⚠ Should gate conditionally |
| **VNC Services** | home-modules/desktop/sway.nix | N/A | ✓ Headless-gated |
| **Keybindings** | Dynamic (sway-config-manager) | Dynamic (sway-config-manager) | ✓ Unified |
| **Appearance** | sway-default-appearance.json | sway-default-appearance.json | ✓ Unified |
| **Workspace Modes** | modes.conf (Hetzner-hardcoded) | modes.conf (Hetzner-hardcoded) | ✗ Headless-specific |
| **Status Bars** | 6 bars (3 outputs) | 4 bars (2 outputs) | ✓ Unified structure |
| **Display Manager** | greetd + shell wrapper | greetd + tuigreet | ⚠ Inconsistent approach |
| **Platform Detection** | Hostname-based | Hostname-based | ✗ Fragile |

---

## Implementation Priority

1. **HIGH**: Fix workspace-mode-handler.sh (currently Hetzner-specific)
2. **HIGH**: Add `GSK_RENDERER=cairo` to M1 if Walker needs software rendering
3. **MEDIUM**: Replace hostname detection with explicit feature flag
4. **MEDIUM**: Consolidate environment variables into dedicated module
5. **LOW**: Extract input configuration to gated module
6. **LOW**: Unify greetd configuration generation
7. **LONG-TERM**: Implement data-driven output configuration system

---

## Files Involved

### Current
- `/etc/nixos/home-modules/desktop/sway.nix` - Main Sway config (unified)
- `/etc/nixos/home-modules/desktop/swaybar.nix` - Status bars (conditionally structured)
- `/etc/nixos/home-modules/desktop/sway-config-manager.nix` - Dynamic config manager
- `/etc/nixos/configurations/hetzner-sway.nix` - Headless-specific system config
- `/etc/nixos/configurations/m1.nix` - M1-specific system config
- `/etc/nixos/modules/desktop/sway.nix` - System-level Sway config
- `/etc/nixos/modules/desktop/wayvnc.nix` - VNC server module

### Recommended New Files
- `/etc/nixos/modules/desktop/sway-environment.nix` - Centralized env vars
- `/etc/nixos/home-modules/desktop/sway-input.nix` - Platform-gated input config
- `/etc/nixos/home-modules/sway-config-manager/rules/modes_generator.py` - Dynamic modes

---

## Conclusion

The Sway configuration is **already well-unified** with a single home-manager module handling both platforms. The conditional logic based on `isHeadless` is effective. However, opportunities exist to:

1. Improve robustness by replacing hostname detection with explicit feature flags
2. Make workspace mode handler platform-agnostic (currently hardcoded for Hetzner)
3. Ensure consistency in environment variable setup across all platforms
4. Reduce duplication in greetd configuration
5. Extract platform-specific features (input devices, VNC) more explicitly

The recommended approach is **incremental unification** - start with high-impact fixes (modes.conf, env vars) before attempting larger architectural changes.

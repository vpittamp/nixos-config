# Research: Enhanced Swaybar Status

**Branch**: `052-enhanced-swaybar-status` | **Date**: 2025-10-31
**Phase**: 0 - Research & Technology Selection

## Overview

This document resolves the NEEDS CLARIFICATION items from the Technical Context and provides research-based decisions for implementing the enhanced swaybar status feature.

## Research Areas

### 1. Language/Runtime Selection: Python vs Deno

**Question**: Should the status generator be implemented in Python 3.11+ or Deno/TypeScript?

**Research Findings**:

**Python 3.11+ Option**:
- ✅ **Consistency**: Matches existing i3pm daemon runtime (already using Python 3.11+)
- ✅ **D-Bus Integration**: Mature `pydbus` library for querying system state
- ✅ **Testing**: Established pytest framework already in use
- ✅ **Async Support**: `asyncio` for non-blocking status updates
- ❌ **Startup Time**: ~50-100ms startup overhead for Python interpreter
- ❌ **Distribution**: Requires Python runtime and dependencies

**Deno/TypeScript Option**:
- ✅ **Fast Startup**: <10ms for compiled executable
- ✅ **Distribution**: Single standalone binary (no runtime needed)
- ✅ **Type Safety**: TypeScript with strict mode
- ✅ **Modern**: Aligns with Constitution Principle XIII (Deno CLI Standards)
- ❌ **D-Bus Integration**: Limited D-Bus libraries (would need to shell out to `dbus-send` or `gdbus`)
- ❌ **New Toolchain**: Introduces Deno tooling not currently used in project

**Decision**: **Python 3.11+**

**Rationale**:
1. **D-Bus Requirement**: Status blocks need to query system state via D-Bus (NetworkManager, BlueZ, PulseAudio/PipeWire, UPower). Python's `pydbus` provides native D-Bus integration, while Deno would require subprocess calls to `gdbus` or `dbus-send`, adding complexity and latency.
2. **Consistency**: Matches existing i3pm daemon architecture (Python 3.11+, asyncio, pytest). Developers already familiar with the codebase patterns.
3. **Performance**: While Deno has faster startup, status generator runs as a long-lived process (not repeatedly launched), so startup time is amortized. Update latency is dominated by D-Bus queries, not language overhead.
4. **Testing**: Existing pytest infrastructure supports unit and integration testing with mocks for D-Bus responses.

**Alternatives Considered**:
- **Deno**: Rejected due to D-Bus integration challenges and added toolchain complexity
- **Rust**: Excellent D-Bus support (zbus) and performance, but higher development time and complexity for a UI utility
- **Shell Script**: Simple but difficult to test, maintain, and handle error cases gracefully

**Impact**:
- Testing framework: `pytest` with `pytest-asyncio`
- Dependencies: `pydbus`, `asyncio`, standard library (json, subprocess for click handlers)
- Packaging: NixOS Python package derivation

---

### 2. Icon Rendering Strategy

**Question**: How should icons be rendered in the status bar - Font Awesome, Nerd Fonts, or SVG?

**Research Findings**:

**Nerd Fonts Option**:
- ✅ **Simplicity**: Unicode characters - no external files, renders directly in pango markup
- ✅ **Performance**: No file I/O or image loading
- ✅ **Compatibility**: Works with any font supporting Nerd Font glyphs
- ✅ **Existing Usage**: Already used in i3bar workspace indicators on hetzner-sway
- ❌ **Limited Icons**: Fixed set of glyphs (though very comprehensive)
- ❌ **Font Dependency**: Requires Nerd Font patched font

**Font Awesome (via pango markup) Option**:
- ✅ **Wide Adoption**: Industry standard icon set
- ✅ **Comprehensive**: Extensive icon collection including all needed categories
- ✅ **Text-Based**: Renders via pango markup using Unicode private use area
- ❌ **Font Dependency**: Requires Font Awesome font installation
- ❌ **Versioning**: Need to track Font Awesome version for icon codes

**SVG Icons Option**:
- ✅ **Flexibility**: Can use any SVG icon set or create custom icons
- ✅ **Quality**: Scalable vector graphics at any size
- ❌ **Complexity**: Requires image loading, conversion to pixmap, embedding in status bar
- ❌ **Performance**: File I/O overhead, potential memory usage for multiple icons
- ❌ **i3bar Protocol Limitation**: Does not natively support image embedding (would need workarounds)

**Decision**: **Nerd Fonts**

**Rationale**:
1. **Already Deployed**: hetzner-sway configuration uses Nerd Fonts for workspace icons (see existing swaybar config)
2. **Zero Overhead**: Unicode characters render directly without file I/O or image processing
3. **Comprehensive Coverage**: Nerd Fonts include all needed icons:
   - Volume: 󰕾 (nf-md-volume_high), 󰖀 (nf-md-volume_medium), 󰕿 (nf-md-volume_low), 󰝟 (nf-md-volume_mute)
   - Battery: 󰁹 (nf-md-battery_80), 󰂀 (nf-md-battery_charging), etc.
   - WiFi: 󰖩 (nf-md-wifi), 󰖪 (nf-md-wifi_strength_1-4)
   - Bluetooth: 󰂯 (nf-md-bluetooth), 󰂲 (nf-md-bluetooth_connected)
4. **Performance**: No file system access or image decoding - minimal CPU/memory overhead
5. **Consistency**: Matches existing icon rendering approach in project

**Alternatives Considered**:
- **Font Awesome**: Similar benefits to Nerd Fonts but not currently used in project; Nerd Fonts already includes Font Awesome icons
- **SVG Icons**: Too complex for i3bar protocol integration; would require custom rendering pipeline

**Impact**:
- Dependencies: Nerd Fonts package (already in system packages for hetzner-sway)
- Icon Format: Unicode hex codes in pango markup (e.g., `<span font='NerdFont'>󰕾</span> 75%`)
- Configuration: Icon mapping in `icons.nix` config module

---

### 3. D-Bus Interface Research

**System State Query Methods**:

**Volume (PulseAudio/PipeWire)**:
- D-Bus Service: `org.pulseaudio.Server` (PulseAudio) or `org.freedesktop.portal.Desktop` (PipeWire via XDG Desktop Portal)
- Alternative: Parse `pactl list sinks` output (fallback if D-Bus unavailable)
- Update Trigger: Poll every 1 second OR subscribe to volume change signals
- Click Handler: Launch `pavucontrol` or inline volume slider via rofi/wofi

**Battery (UPower)**:
- D-Bus Service: `org.freedesktop.UPower` (`/org/freedesktop/UPower/devices/battery_BAT0`)
- Properties: `Percentage`, `State` (charging/discharging), `TimeToEmpty`, `TimeToFull`
- Update Trigger: Subscribe to `PropertiesChanged` signal for real-time updates
- Click Handler: Show detailed power stats (estimated time, power draw, temperature)

**WiFi (NetworkManager)**:
- D-Bus Service: `org.freedesktop.NetworkManager`
- Properties: `ActiveConnections`, `Devices` (wireless device), `AccessPoints`, signal strength
- Update Trigger: Subscribe to `StateChanged` and `PropertiesChanged` signals
- Click Handler: Launch `nmtui` or network menu via rofi/wofi

**Bluetooth (BlueZ)**:
- D-Bus Service: `org.bluez` (`/org/bluez/hci0`)
- Properties: `Powered`, `Connected` devices, device names
- Update Trigger: Subscribe to `PropertiesChanged` signals for device changes
- Click Handler: Launch `bluetoothctl` or bluetooth menu via rofi/wofi

**Decision**: Use D-Bus as primary interface with subprocess fallbacks

**Rationale**: D-Bus provides structured, real-time data with signal-based updates. Fallback to CLI tools (`pactl`, `nmcli`, `bluetoothctl`) if D-Bus unavailable (edge case).

---

### 4. i3bar Protocol Integration

**Protocol Overview**:
- **Format**: JSON array of status blocks printed to stdout
- **Update Method**: Status generator prints full JSON array on each update
- **Click Events**: swaybar sends click events via stdin as JSON
- **Markup**: Supports pango markup for formatting (colors, fonts, icons)

**Status Block JSON Schema**:
```json
[
  {
    "full_text": "<span font='NerdFont'>󰕾</span> 75%",
    "short_text": "75%",
    "color": "#a6e3a1",
    "markup": "pango",
    "name": "volume",
    "instance": "default",
    "separator": true,
    "separator_block_width": 15
  }
]
```

**Click Event JSON Schema** (sent from swaybar to status generator via stdin):
```json
{
  "name": "volume",
  "instance": "default",
  "button": 1,  // 1=left, 2=middle, 3=right, 4=scroll up, 5=scroll down
  "x": 1234,
  "y": 5
}
```

**Architecture**:
- Status generator runs as long-lived process
- Main loop: Poll/subscribe to system state, print JSON array every update interval
- Separate thread: Listen for click events on stdin, dispatch handlers
- Update intervals: battery (30s), volume (1s or on-signal), network (5s), bluetooth (10s)

**Decision**: Event-driven architecture with signal subscriptions + periodic fallback polling

**Rationale**: D-Bus signals provide real-time updates for battery/network/bluetooth changes. Volume changes are frequent (user adjustments) so 1-second polling is acceptable. Fallback polling ensures status updates even if signals are missed.

---

### 5. Click Handler Implementation

**Requirement**: Users can click status elements to access controls or menus

**Options**:

**Option A: Launch External Applications**:
- Volume → `pavucontrol` (PulseAudio GUI mixer)
- Network → `nmtui` (NetworkManager TUI) or `nm-connection-editor` (GUI)
- Bluetooth → `blueman-manager` (GUI) or `bluetoothctl` (CLI)
- Battery → Power statistics viewer

**Option B: Inline Menus (rofi/wofi)**:
- Generate menu content dynamically
- Display menu at cursor position
- Execute actions based on selection

**Option C: Custom Popups**:
- Implement custom GTK/Qt popup windows
- Full control over UI but high complexity

**Decision**: **Hybrid Approach**
- **Simple Controls** (volume, battery): Launch lightweight external apps or rofi menus
- **Complex Menus** (network, bluetooth): Launch full GUI applications

**Rationale**:
1. **Minimize Complexity**: Don't reimplement network/bluetooth GUIs - use existing tools
2. **User Familiarity**: `pavucontrol`, `nmtui`, `blueman` are standard Linux tools
3. **Maintenance**: Leveraging existing tools reduces code to maintain
4. **Flexibility**: Can switch to rofi/wofi menus in future for more integrated UX

**Implementation**:
- Click handler reads click event from stdin
- Matches `name` field to determine which control to launch
- Spawns subprocess with appropriate command (e.g., `subprocess.Popen(['pavucontrol'])`)
- Detaches process so status generator doesn't block

---

### 6. Configuration Management

**Configuration Needs**:
- Icon mappings (Nerd Font glyphs for each status state)
- Color themes (colors for different battery levels, signal strengths)
- Update intervals (how often to poll each status source)
- Click handlers (which applications to launch)
- Hardware detection (enable/disable blocks based on available hardware)

**Decision**: Nix-based configuration with home-manager

**Structure**:
```nix
# home-modules/desktop/swaybar-enhanced.nix
{ config, lib, pkgs, ... }:

{
  programs.swaybar-enhanced = {
    enable = lib.mkEnableOption "Enhanced swaybar status";

    icons = {
      volume = {
        high = "󰕾";
        medium = "󰖀";
        low = "󰕿";
        mute = "󰝟";
      };
      # ... other icons
    };

    theme = {
      colors = {
        battery = {
          charging = "#a6e3a1";  # green
          high = "#a6e3a1";
          medium = "#f9e2af";    # yellow
          low = "#f38ba8";       # red
        };
        # ... other colors
      };
    };

    intervals = {
      battery = 30;
      volume = 1;
      network = 5;
      bluetooth = 10;
    };

    clickHandlers = {
      volume = "${pkgs.pavucontrol}/bin/pavucontrol";
      network = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
      bluetooth = "${pkgs.blueman}/bin/blueman-manager";
      battery = ""; # Optional - no handler by default
    };
  };
}
```

**Rationale**: Declarative NixOS configuration ensures reproducibility, type safety, and integration with existing home-manager setup.

---

## Summary of Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| **Language** | Python 3.11+ | D-Bus integration, consistency with existing codebase |
| **Icon Rendering** | Nerd Fonts (Unicode glyphs) | Already deployed, zero overhead, comprehensive coverage |
| **System State Queries** | D-Bus (pydbus) with CLI fallbacks | Real-time signal-based updates, structured data |
| **i3bar Integration** | Event-driven + periodic polling | Combines real-time updates (signals) with reliability (polling) |
| **Click Handlers** | Hybrid: rofi menus + external apps | Balance simplicity and user familiarity |
| **Configuration** | Nix-based via home-manager | Declarative, type-safe, reproducible |
| **Testing** | pytest with async support | Matches existing test infrastructure |

## Next Steps (Phase 1)

1. Generate `data-model.md` defining status block data structures
2. Define contracts for D-Bus interfaces and i3bar protocol
3. Create `quickstart.md` for user-facing documentation
4. Update `.specify/memory/agent-context.md` with Python/D-Bus technologies

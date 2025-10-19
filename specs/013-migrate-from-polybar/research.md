# Phase 0: Research & Technical Decisions

**Feature**: Migrate from Polybar to i3 Native Status Bar
**Date**: 2025-10-19
**Status**: Complete

## Overview

This document resolves all "NEEDS CLARIFICATION" items from the Technical Context and establishes technical decisions for the implementation phase.

## Research Questions & Decisions

### 1. Status Command: i3status vs i3blocks

**Question**: Which status command should power the i3bar?

**Options Evaluated**:

| Feature | i3status | i3blocks |
|---------|----------|----------|
| Complexity | Simple, built-in | Moderate, scriptable |
| Customization | Limited (config file only) | Extensive (custom scripts) |
| Project Indicator | Not possible | Easy (custom script) |
| Event-Driven Updates | No (polling only) | Yes (signal-based) |
| JSON Output | Yes | Yes |
| Resource Usage | Minimal | Low (runs scripts) |
| NixOS Package | `i3status` | `i3blocks` |

**Decision**: **i3blocks**

**Rationale**:
- Project indicator (P3 requirement) needs custom script capability
- Signal-based updates allow immediate response to project switches
- JSON output provides full control over colors and formatting
- Slightly higher resource usage is acceptable for flexibility
- Still lightweight compared to polybar

**Alternatives Considered**:
- i3status: Rejected due to lack of extensibility for project indicator
- polyblocks/bumblebee-status: Rejected as unnecessary complexity (Python-based)
- Custom Rust/Go status command: Rejected as over-engineering

---

### 2. i3bar Protocol Format

**Question**: Should we use JSON or plain text format for status output?

**Research**: i3bar supports two input formats:
1. **Plain text**: Simple, one-line-per-update, no color control
2. **JSON**: Structured blocks with full control over color, separators, markup

**Decision**: **JSON format**

**Rationale**:
- Enables per-block color customization for Catppuccin theme
- Supports separator configuration and block alignment
- Provides better visual distinction between status elements
- More maintainable (structured data vs string parsing)

**JSON Protocol Structure**:
```json
{
  "version": 1,
  "click_events": true
}
[
  [
    {
      "full_text": " NixOS",
      "color": "#b4befe",
      "separator": true,
      "separator_block_width": 15
    },
    {
      "full_text": "CPU: 25%",
      "color": "#cdd6f4"
    }
  ]
]
```

---

### 3. Project Indicator Update Mechanism

**Question**: How should the bar detect project changes and update the display?

**Options Evaluated**:

| Approach | Latency | CPU Usage | Complexity | Implementation |
|----------|---------|-----------|------------|----------------|
| Polling (5s interval) | 0-5 seconds | Low (1 check/5s) | Simple | i3blocks interval=5 |
| inotify watch | <100ms | Very low (event) | Moderate | Custom script with inotifywait |
| Signal-based | <100ms | Minimal (on-demand) | Simple | i3blocks signal=N, project system sends SIGRTMIN+N |

**Decision**: **Signal-based updates**

**Rationale**:
- Near-instant updates when project switches (meets 100ms goal)
- Zero CPU usage when idle (no polling)
- Simple integration: project switch command sends `pkill -RTMIN+10 i3blocks`
- i3blocks natively supports signal handling
- Cleaner than inotify (no file watching complexity)

**Implementation**:
```nix
# i3blocks config
[project]
command=~/.config/i3blocks/scripts/project.sh
interval=once
signal=10

# Project switch command
i3-project-switch nixos && pkill -RTMIN+10 i3blocks
```

---

### 4. Catppuccin Color Translation

**Question**: How do we translate Catppuccin Mocha colors from polybar to i3bar?

**Research**: Extracted current colors from polybar config:

| Element | Polybar Variable | Hex Value | Catppuccin Name |
|---------|------------------|-----------|-----------------|
| Background | background | #1e1e2e | Base |
| Foreground | foreground | #cdd6f4 | Text |
| Primary | primary | #b4befe | Lavender |
| Secondary | secondary | #89b4fa | Blue |
| Alert | alert | #f38ba8 | Red |
| Disabled | disabled | #6c7086 | Overlay0 |
| Focused BG | focused-bg | #45475a | Surface1 |
| Unfocused | unfocused | #313244 | Surface0 |

**Decision**: Use hex codes directly in i3bar configuration

**Color Mapping**:
```nix
colors = {
  background = "#1e1e2e";  # Base
  statusline = "#cdd6f4";  # Text
  separator  = "#6c7086";  # Overlay0
  
  # Workspace button colors (border, background, text)
  focused_workspace  = "#b4befe #45475a #cdd6f4";  # Lavender border
  active_workspace   = "#89b4fa #313244 #cdd6f4";  # Blue border (visible on other monitor)
  inactive_workspace = "#313244 #1e1e2e #bac2de";  # Surface0 border
  urgent_workspace   = "#f38ba8 #f38ba8 #1e1e2e";  # Red (alert state)
};
```

**No conversion needed**: i3bar accepts standard hex colors, same format as polybar.

---

### 5. Workspace Pinning Behavior

**Question**: Does i3bar support per-monitor workspace filtering like polybar's `pin-workspaces`?

**Research**: 
- i3bar does NOT have a `pin-workspaces` configuration option
- i3 ITSELF handles workspace-to-output assignments via config:
  ```
  workspace 1 output rdp0
  workspace 2 output rdp1
  ```
- i3bar automatically queries i3 via IPC and shows only workspaces assigned to each bar's output
- This is BETTER than polybar because it's natively integrated (no module configuration needed)

**Decision**: **Use i3's native workspace-to-output assignments**

**Rationale**:
- Already configured in current i3 config (workspaces 1-2 on rdp0, 3-9 distributed)
- i3bar respects these assignments automatically
- No additional configuration required
- More reliable than polybar's module-level filtering

**Validation**: Confirmed via i3 IPC documentation - GET_WORKSPACES returns output field, i3bar filters by matching output name.

---

## Best Practices Findings

### i3blocks Script Patterns

**Standard Script Structure**:
```bash
#!/usr/bin/env bash
# Description: [what this block displays]
# Dependencies: [any required commands]
# Signal: [SIGRTMIN+N if signal-based]

# Get data
VALUE=$(command to get value)

# Format output
if [[ condition ]]; then
  COLOR="#f38ba8"  # Alert color
else
  COLOR="#cdd6f4"  # Normal color
fi

# Output JSON block
echo "{\"full_text\":\"$VALUE\",\"color\":\"$COLOR\"}"
```

**Error Handling**:
- Always check command exit codes
- Provide fallback values if data unavailable
- Use timeouts for network operations
- Never let script hang (breaks entire status bar)

**Performance Optimization**:
- Cache expensive operations
- Use efficient commands (avoid heavy parsing)
- Minimize subprocess spawning
- Typical execution time: <50ms per block

---

### Home-Manager i3bar Configuration

**Pattern**: Embed `bar {}` block in i3 config generation:

```nix
xsession.windowManager.i3.config = {
  bars = [{
    position = "bottom";
    statusCommand = "${pkgs.i3blocks}/bin/i3blocks -c ${i3blocksConfig}";
    fonts = {
      names = [ "FiraCode Nerd Font" ];
      size = 10.0;
    };
    colors = {
      background = "#1e1e2e";
      # ... (see color mapping above)
    };
  }];
};
```

**Binary Path References**:
- Always use `${pkgs.package}/bin/command` for reproducibility
- Nix store paths are automatically managed
- No hardcoded /usr/bin or /bin paths

**Multi-Line String Generation**:
- Use Nix's multi-line string literals for complex configs
- Interpolate paths with ${} syntax
- Proper indentation for readability

---

### Multi-Monitor Bar Management

**How i3 handles multiple monitors**:
1. i3 detects all connected outputs via RandR
2. For each output, i3 spawns an i3bar instance
3. Each i3bar queries i3 via IPC: GET_WORKSPACES
4. i3bar filters workspaces by matching output field
5. Each bar displays only its assigned workspaces

**Dynamic monitor changes**:
- Monitor connect: i3 automatically spawns new bar
- Monitor disconnect: i3 kills orphaned bar
- No manual configuration needed

**Per-Monitor Settings** (if needed):
```nix
bars = [
  {
    position = "bottom";
    output = "rdp0";  # Only show on specific output
    # ... other settings
  }
  # Repeat for other monitors if different configs needed
];
```

**Decision**: Use single bar configuration (applies to all outputs) - no per-monitor customization needed.

---

## Technology Stack Summary

### Selected Technologies

| Component | Choice | Version | Package |
|-----------|--------|---------|---------|
| Status Bar | i3bar | 4.23+ (included with i3) | N/A (part of i3) |
| Status Command | i3blocks | 1.5+ | `pkgs.i3blocks` |
| Script Language | Bash | 5.x | `pkgs.bash` (system default) |
| Configuration | Home-Manager | 23.11+ | N/A (NixOS module) |
| Project State | JSON file | N/A | `~/.config/i3/active-project` |

### Dependencies

**System Dependencies** (already installed):
- i3wm 4.23+
- X11 server (for RDP)
- xrandr (for monitor detection)

**New Dependencies** (to be added):
- i3blocks 1.5+ (`pkgs.i3blocks`)

**Script Dependencies** (for status blocks):
- `sysstat` for CPU/memory metrics
- `iproute2` for network status
- `jq` for JSON parsing (project state)
- `coreutils` for date/time

---

## Implementation Patterns

### Configuration File Generation

i3blocks config will be generated via home-manager:

```nix
xdg.configFile."i3blocks/config".text = ''
  # Global properties
  separator_block_width=15
  markup=pango
  
  # CPU block
  [cpu]
  command=${./scripts/cpu.sh}
  interval=5
  color=#cdd6f4
  
  # Project block
  [project]
  command=${./scripts/project.sh}
  interval=once
  signal=10
'';
```

### Script Generation

Scripts will be generated via `home.file` with executable permissions:

```nix
home.file.".config/i3blocks/scripts/cpu.sh" = {
  text = ''
    #!/usr/bin/env bash
    # CPU usage script
    # ...script content...
  '';
  executable = true;
};
```

### Project Indicator Integration

Modify existing project switch commands to signal i3blocks:

```bash
# In i3-project-switch script
switch_project() {
  # ... existing project switch logic ...
  
  # Signal i3blocks to update project indicator
  pkill -RTMIN+10 i3blocks 2>/dev/null || true
}
```

---

## Validation Results

### Feature Parity Check

| Polybar Feature | i3bar Equivalent | Status |
|----------------|------------------|--------|
| Workspace indicators | Built-in workspace buttons | ✅ Better (native IPC) |
| CPU display | i3blocks CPU script | ✅ Equivalent |
| Memory display | i3blocks memory script | ✅ Equivalent |
| Network status | i3blocks network script | ✅ Equivalent |
| Date/time | i3blocks datetime script | ✅ Equivalent |
| Project indicator | i3blocks custom script | ✅ Equivalent + signal-based |
| Multi-monitor | Native i3 output handling | ✅ Better (automatic) |
| Catppuccin colors | Direct hex color mapping | ✅ Equivalent |
| Click actions | i3bar click events | ✅ Available (if needed) |
| Systray | i3bar tray support | ⚠️ Limited (not using) |

**Conclusion**: All required features have equivalent or better support in i3bar.

---

## Risk Mitigation

### Identified Risks from Spec

**Risk 1**: i3bar may not support all customization features
- **Mitigation**: Research confirmed feature parity for all essential features
- **Status**: ✅ Resolved - all requirements covered

**Risk 2**: Project indicator may require complex scripting
- **Mitigation**: Signal-based update pattern is simple and proven
- **Status**: ✅ Resolved - straightforward Bash script + signal

**Risk 3**: Color scheme may not translate perfectly
- **Mitigation**: Direct hex code mapping identified, no conversion needed
- **Status**: ✅ Resolved - same color format

**Risk 4**: Users may prefer polybar's appearance
- **Mitigation**: Focus on reliability and functionality, maintain visual consistency
- **Status**: ⚠️ Monitored - will validate with user after implementation

---

## Decision Summary

All research questions resolved. Ready to proceed to Phase 1 (Design).

**Key Decisions**:
1. ✅ Use i3blocks (not i3status) for extensibility
2. ✅ Use JSON protocol for full color control
3. ✅ Use signal-based updates for project indicator
4. ✅ Use direct hex color mapping (no conversion)
5. ✅ Use i3's native workspace-to-output assignments

**No Blockers**: All technical uncertainties resolved through research and documentation review.

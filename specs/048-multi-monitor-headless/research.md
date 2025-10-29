# Research: Multi-Monitor Headless Sway/Wayland Setup

**Feature**: 048-multi-monitor-headless
**Date**: 2025-10-29
**Scope**: WayVNC multi-instance architecture, Sway headless output management, systemd template services

## Overview

This research document consolidates findings on implementing a three-display headless Sway/Wayland configuration with WayVNC streaming over Tailscale. The goal is to enable multi-monitor workflows on a remote Hetzner Cloud VM by creating three virtual displays and streaming each independently.

## Decision 1: Static vs Dynamic Output Creation

### Decision: **Static triple-head with WLR_HEADLESS_OUTPUTS=3**

### Rationale:

**Static approach (chosen)**:
- Simpler configuration: Set environment variable once, outputs created automatically at Sway startup
- Declarative in NixOS: All configuration in Nix expressions (Principle VI compliance)
- Predictable: Outputs always available with consistent naming (HEADLESS-1, HEADLESS-2, HEADLESS-3)
- Integration-friendly: i3pm monitor detection can rely on fixed output count
- Performance: No runtime overhead for output creation/destruction

**Dynamic approach (rejected)**:
- Requires runtime management: Scripts to call `swaymsg create_output` when needed
- More complex: On-demand WayVNC spawning, state management for active outputs
- Less declarative: Runtime state not captured in NixOS configuration
- Integration complexity: i3pm would need to handle variable output counts
- Marginal benefit: Resource savings minimal (headless outputs are lightweight)

### Alternatives Considered:

1. **On-demand outputs with `swaymsg create_output`**: Rejected due to complexity and limited benefit in headless scenario
2. **Single output with viewport switching**: Rejected because VNC clients can't view multiple workspaces simultaneously
3. **Alternative streaming (Sunshine/NVENC)**: Rejected due to known stability issues with headless wlroots on VMs without GPUs (per user-provided research)

### Supporting Evidence:

- wlroots headless backend documentation: `WLR_HEADLESS_OUTPUTS` creates outputs at compositor initialization
- WayVNC FAQ confirms: "If the Wayland session consists of multiple outputs, only one will be captured" - requires multiple WayVNC instances
- Existing hetzner-sway configuration already uses `WLR_HEADLESS_OUTPUTS=1` successfully (line 74, 97)

---

## Decision 2: WayVNC Instance Management

### Decision: **Systemd template service (`wayvnc@.service`) with three instances**

### Rationale:

**Template service approach (chosen)**:
- NixOS best practice: Systemd templates for parameterized services
- Maintainable: Single service definition, three instantiations
- Declarative: Service configuration in home-manager module
- Logging: Per-instance journald logs (`journalctl --user -u wayvnc@HEADLESS-1`)
- Dependency management: All instances depend on `sway-session.target`
- Auto-restart: Systemd handles failure recovery per-instance

**Alternative approaches rejected**:
1. **Three separate service definitions**: Duplicates configuration, violates Principle I (Modular Composition)
2. **Single service with `wayvncctl` multiplexing**: Doesn't support concurrent output capture
3. **Manual launch scripts**: Violates Principle VI (Declarative Configuration)

### Implementation Pattern:

```nix
systemd.user.services."wayvnc@" = {
  Unit = {
    Description = "wayvnc on %i";
    After = [ "sway-session.target" ];
    PartOf = [ "sway-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o %i -p %I";
    Restart = "on-failure";
  };
  Install = {
    WantedBy = [ "sway-session.target" ];
  };
};
```

Instances enabled: `wayvnc@HEADLESS-1.service`, `wayvnc@HEADLESS-2.service`, `wayvnc@HEADLESS-3.service`

### Port Mapping:

The template service uses `%I` (unescaped instance name) as the port number, which requires mapping:
- `wayvnc@5900.service` → HEADLESS-1
- `wayvnc@5901.service` → HEADLESS-2
- `wayvnc@5902.service` → HEADLESS-3

**Note**: The `%I` specifier in systemd passes the instance name verbatim. To bind to specific ports while capturing specific outputs, the ExecStart command should specify both output (`-o HEADLESS-N`) and port (`-p 590N`) explicitly.

**Updated pattern** (output name as instance, port in service config):

```nix
systemd.user.services."wayvnc@HEADLESS-1" = {
  # ... (standard template fields)
  Service.ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o HEADLESS-1 -p 5900";
};
# Similar for HEADLESS-2 (port 5901), HEADLESS-3 (port 5902)
```

**Decision**: Use explicit service definitions (not template) due to fixed output-to-port mapping. Template services work best when instance name directly maps to a runtime parameter, but here we need two distinct values (output name + port). Three explicit service definitions are cleaner and avoid complex parameterization.

---

## Decision 3: Workspace Distribution Strategy

### Decision: **Fixed workspace-to-output mapping (1-3, 4-6, 7-9) with i3pm integration**

### Rationale:

**Fixed distribution (chosen)**:
- Predictable: Users know which display shows which workspaces
- i3pm compatible: Matches existing multi-monitor distribution pattern (Feature 033)
- Simple configuration: Declarative workspace assignments in Sway config
- No runtime coordination: Sway enforces assignments at startup

**Distribution pattern**:
- HEADLESS-1 (primary): Workspaces 1-3
- HEADLESS-2 (secondary): Workspaces 4-6
- HEADLESS-3 (tertiary): Workspaces 7-9

**Alignment with i3pm**: The existing workspace distribution system (Feature 033) already supports 3-monitor setups:
- 1 monitor: WS 1-9 on primary
- 2 monitors: WS 1-2 primary, WS 3-9 secondary
- **3 monitors**: WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary

**Adjustment needed**: The spec proposes 1-3, 4-6, 7-9 distribution, but i3pm uses 1-2, 3-5, 6-9.

**Final decision**: Adopt **1-2, 3-5, 6-9** distribution to align with existing i3pm behavior (Principle XI: i3 IPC Alignment). This ensures compatibility with workspace reassignment scripts and project switching logic.

**Alternative rejected**:
- Dynamic distribution based on active project: Too complex, violates simplicity principles
- Equal distribution (1-3, 4-6, 7-9): Doesn't match i3pm conventions, would require i3pm code changes

---

## Decision 4: Resolution and Positioning Configuration

### Decision: **1920x1080@60Hz for all outputs, horizontal positioning**

### Rationale:

**Resolution choice**:
- 1920x1080 balances clarity with VNC compression efficiency
- Standard resolution familiar to most users
- Avoids scaling issues or compression artifacts at higher resolutions
- Matches successful headless deployments in community examples

**Positioning strategy**:
- Horizontal layout: HEADLESS-1 at 0,0, HEADLESS-2 at 1920,0, HEADLESS-3 at 3840,0
- Creates logical left-to-right monitor arrangement
- Simplifies mental model for users (workspace 1-2 on left, 3-5 in center, 6-9 on right)
- Sway handles positioning automatically based on configuration

**Alternative resolutions considered**:
- 2560x1440: Rejected due to increased bandwidth and compression overhead
- 1280x720: Rejected due to reduced clarity for code/text readability
- Mixed resolutions: Rejected for simplicity (all displays identical reduces cognitive load)

**Configuration pattern**:

```nix
output = {
  "HEADLESS-1" = {
    resolution = "1920x1080@60Hz";
    position = "0,0";
    scale = "1.0";
  };
  "HEADLESS-2" = {
    resolution = "1920x1080@60Hz";
    position = "1920,0";
    scale = "1.0";
  };
  "HEADLESS-3" = {
    resolution = "1920x1080@60Hz";
    position = "3840,0";
    scale = "1.0";
  };
};
```

---

## Decision 5: Tailscale Firewall Configuration

### Decision: **Expose ports 5900-5902 only on tailscale0 interface**

### Rationale:

**Security requirement**: VNC streams must not be accessible from public internet (FR-007, SC-005)

**Implementation**:
```nix
networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
  5900  # HEADLESS-1
  5901  # HEADLESS-2
  5902  # HEADLESS-3
];
```

**Why not global firewall rule**: Public VNC exposure is a security risk (unencrypted protocol, potential DoS target)

**Validation**: Attempt external connection to VM IP:5900 should timeout/refuse, while Tailscale IP:5900 should connect

---

## Decision 6: Integration with sway-config-manager (Feature 047)

### Decision: **No changes required to sway-config-manager**

### Rationale:

Feature 047 provides hot-reloadable Sway configuration for keybindings, window rules, and workspace assignments. The multi-display setup uses **static output configuration** (managed by Nix), which doesn't conflict with Feature 047's runtime management of keybindings/window rules.

**Static (Nix-managed)**:
- Output definitions (resolution, position, scale)
- WayVNC service instances
- Workspace-to-output assignments (initial state)

**Dynamic (Feature 047 runtime-managed)**:
- Keybindings (already working)
- Window rules (already working)
- Project-specific overrides (already working)

**No changes needed**: Output configuration is orthogonal to Feature 047's scope. Users can still hot-reload keybindings and window rules without rebuilding NixOS.

**Future enhancement (optional)**: If users want to change workspace-to-output assignments dynamically (e.g., move workspace 3 from HEADLESS-1 to HEADLESS-2), this could be added to Feature 047's runtime config later. Not required for initial MVP.

---

## Decision 7: i3pm Monitor Detection Integration

### Decision: **No code changes required - Sway IPC compatibility ensures automatic detection**

### Rationale:

The i3pm monitor detection system (Feature 033) queries i3/Sway via IPC using `GET_OUTPUTS` and `GET_WORKSPACES` (Principle XI). Sway's i3 compatibility layer means these IPC commands work identically on both i3/X11 and Sway/Wayland.

**Verification**:
```bash
# Query outputs (works on Sway via i3 IPC compatibility)
swaymsg -t get_outputs

# Query workspaces (works on Sway via i3 IPC compatibility)
swaymsg -t get_workspaces
```

**Expected behavior**:
- `i3pm monitors status` should report 3 outputs (HEADLESS-1, HEADLESS-2, HEADLESS-3)
- `i3pm monitors reassign` should distribute workspaces using 3-monitor rule (1-2, 3-5, 6-9)
- No daemon code changes needed (already event-driven via Sway IPC subscriptions)

**Validation test**: After configuration is applied, run `i3pm monitors status` and verify output count = 3.

---

## Decision 8: WayVNC Configuration File

### Decision: **Use home-manager `xdg.configFile` to generate `/home/vpittamp/.config/wayvnc/config`**

### Rationale:

WayVNC supports configuration via `~/.config/wayvnc/config` file. Since we're using systemd services with explicit CLI arguments (`-o HEADLESS-N -p 590N`), the config file is **optional** but useful for shared settings.

**Minimal configuration** (if needed):
```ini
address=0.0.0.0
enable_auth=false
```

**Current implementation** (line 425-431 in sway.nix) already uses this pattern for single instance:
```nix
xdg.configFile."wayvnc/config" = lib.mkIf isHeadless {
  text = ''
    address=0.0.0.0
    port=5900
    enable_auth=false
  '';
};
```

**For multi-instance**: Remove `port=5900` from config file (conflicts with per-instance CLI `-p` argument), keep `address` and `enable_auth` as shared settings.

**Decision**: Update existing config to remove port (handled by systemd services), keep address and auth settings.

---

## Technology Stack Summary

### Core Technologies:
- **wlroots**: Wayland compositor library with headless backend support
- **Sway**: Tiling window manager using wlroots (i3-compatible IPC)
- **WayVNC**: VNC server for wlroots-based compositors
- **Tailscale**: Zero-config VPN for secure remote access
- **systemd**: Service management for WayVNC instances

### NixOS Integration:
- **home-manager**: User-level service and configuration management
- **environment.sessionVariables**: wlroots environment variables
- **greetd**: Auto-login display manager for headless operation
- **networking.firewall**: Interface-specific port filtering

### Version Requirements:
- **Sway**: 1.5+ (for runtime output creation support, though using static outputs)
- **WayVNC**: 0.8+ (for headless output auto-resize support)
- **wlroots**: Compatible with Sway version (handles `WLR_HEADLESS_OUTPUTS`)
- **NixOS**: 24.11 (current system.stateVersion)

---

## References

1. **WayVNC FAQ**: https://github.com/any1/wayvnc/blob/master/FAQ.md
   - Confirms single-output-per-instance requirement
   - Documents `-o` flag for output selection

2. **Sway GitHub**: Runtime output creation via `swaymsg create_output` (Sway 1.5+)
   - Evaluated but not used (static approach chosen)

3. **wlroots Headless Backend**: `WLR_HEADLESS_OUTPUTS` environment variable
   - Creates N virtual outputs at compositor startup

4. **Existing hetzner-sway.nix**: Lines 72-116 show successful single-output headless configuration
   - Proven pattern to extend for multi-output

5. **i3pm Feature 033**: Multi-monitor workspace distribution (1-2, 3-5, 6-9 for 3 monitors)
   - Establishes workspace assignment conventions

---

## Risk Assessment

### Low Risk:
- ✅ wlroots headless backend is mature and stable
- ✅ WayVNC has proven headless compatibility
- ✅ Systemd template services are standard NixOS practice
- ✅ Sway i3 IPC compatibility ensures i3pm integration works without changes

### Medium Risk:
- ⚠️ VNC bandwidth usage with 3 concurrent streams (Mitigation: Tailscale optimizes P2P connections)
- ⚠️ Port conflicts if services are manually restarted (Mitigation: Systemd ensures one instance per port)

### Addressed:
- ✅ GPU acceleration requirement: Using pixman software renderer (already validated in single-display setup)
- ✅ Multi-session isolation: Each VNC instance captures independent output, no cross-stream interference

---

## Open Questions

**None** - All technical decisions have been resolved with rationale documented above.

---

## Implementation Readiness

All research complete. Ready to proceed to Phase 1 (Data Model & Contracts).

**Next Steps**:
1. Create `data-model.md` defining output configuration schema and WayVNC instance mapping
2. Generate contracts for systemd service definitions and Sway output configuration
3. Create `quickstart.md` user guide for VNC client setup

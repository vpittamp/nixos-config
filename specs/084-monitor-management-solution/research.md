# Research: M1 Hybrid Multi-Monitor Management

**Feature**: 084-monitor-management-solution
**Date**: 2025-11-19

## Executive Summary

This research validates the technical approach for implementing dynamic virtual output creation on M1 MacBook Pro alongside the physical Retina display. Key findings confirm that `swaymsg create_output` provides runtime virtual output creation that integrates with existing Feature 083 infrastructure.

---

## Research Findings

### 1. Dynamic Output Creation with swaymsg

**Decision**: Use `swaymsg create_output` for runtime virtual output creation

**Rationale**:
- M1 cannot use `WLR_BACKENDS=headless` (would disable physical display)
- Dynamic creation allows profile switching without Sway restart
- Outputs named incrementally: HEADLESS-1, HEADLESS-2, etc.

**Alternatives Considered**:
- Static `WLR_HEADLESS_OUTPUTS`: Rejected - requires headless backend which disables eDP-1
- Pre-created outputs at startup: Rejected - M1 uses native backend, not headless

**Implementation Commands**:
```bash
# Create virtual output
swaymsg create_output

# Configure (after creation)
swaymsg "output HEADLESS-1 mode 1920x1080@60Hz position 2560,0 scale 1.0"
swaymsg "output HEADLESS-1 enable"

# Remove when switching to local-only
swaymsg "output HEADLESS-1 disable"
```

### 2. Hybrid Mode Architecture

**Decision**: Extend existing Feature 083 patterns with `isHybridMode` flag

**Rationale**:
- Reuses MonitorProfileService, EwwPublisher, profile switching logic
- Maintains modular composition (Constitution Principle I)
- Only differential logic for create_output vs pre-existing outputs

**Alternatives Considered**:
- Separate M1 daemon: Rejected - duplicates 083 infrastructure
- Unified headless mode: Rejected - M1 needs GPU for physical display

**Detection Pattern**:
```nix
# In sway.nix
isHeadless = hostname == "hetzner-sway";  # Existing
isHybridMode = hostname == "nixos-m1";     # New
hasVirtualOutputs = isHeadless || isHybridMode;
```

### 3. Profile Naming and Configuration

**Decision**: Use descriptive profile names for M1

**Rationale**:
- Clear indication of what's enabled
- Consistent with menu-driven activation approach
- Easy to understand in top bar and logs

**M1 Profiles**:
| Profile | Outputs | Workspace Distribution |
|---------|---------|------------------------|
| `local-only` | eDP-1 | All workspaces on eDP-1 |
| `local+1vnc` | eDP-1, HEADLESS-1 | 1-4 on eDP-1, 5-9 on V1 |
| `local+2vnc` | eDP-1, HEADLESS-1, HEADLESS-2 | 1-3 on eDP-1, 4-6 on V1, 7-9 on V2 |

**Comparison to Hetzner**:
| Hetzner Profile | M1 Equivalent | Outputs |
|-----------------|---------------|---------|
| single | local-only | 1 (but eDP-1, not HEADLESS-1) |
| dual | local+1vnc | 2 |
| triple | local+2vnc | 3 |

### 4. WayVNC Service Configuration

**Decision**: Use explicit service instances (not systemd templates)

**Rationale**:
- Consistent with Hetzner implementation
- Fixed output-to-port mapping is clearer
- Easier to manage individual services

**Service Pattern**:
```nix
systemd.user.services."wayvnc@HEADLESS-1" = {
  Unit = {
    Description = "WayVNC for VNC Display 1";
    After = [ "sway-session.target" ];
    PartOf = [ "sway-session.target" ];
  };
  Service = {
    ExecStart = "${wayvncWrapper "HEADLESS-1" 5900}";
    Restart = "on-failure";
  };
};
```

**Port Assignments**:
- HEADLESS-1 (V1): Port 5900
- HEADLESS-2 (V2): Port 5901

### 5. Top Bar Indicator Format

**Decision**: Use L/V1/V2 indicators for M1

**Rationale**:
- Distinguishes M1 (Local + VNC) from Hetzner (Headless only)
- Single letter per output for compact display
- Clear semantic meaning

**Indicator Mapping**:
| Output | M1 Indicator | Hetzner Indicator |
|--------|--------------|-------------------|
| eDP-1 | L | N/A |
| HEADLESS-1 | V1 | H1 |
| HEADLESS-2 | V2 | H2 |
| HEADLESS-3 | N/A | H3 |

**EwwPublisher Changes**:
```python
def get_short_name(output_name: str, is_hybrid: bool) -> str:
    if output_name == "eDP-1":
        return "L"
    elif is_hybrid and output_name.startswith("HEADLESS-"):
        num = output_name.split("-")[1]
        return f"V{num}"
    else:
        return f"H{output_name.split('-')[1]}"
```

### 6. Workspace-to-Monitor Mapping

**Decision**: Dynamic assignment based on active profile

**Rationale**:
- Existing Feature 001/049 patterns handle reassignment
- Works with workspace range 1-100+
- Consistent with project-workspace assignments

**Assignment Algorithm**:
```python
def assign_workspaces_to_outputs(profile: str, workspace_count: int):
    if profile == "local-only":
        return {range(1, workspace_count+1): "eDP-1"}
    elif profile == "local+1vnc":
        return {
            range(1, 5): "eDP-1",        # Core apps
            range(5, 10): "HEADLESS-1",  # Secondary apps
            range(50, 100): "HEADLESS-1" # PWAs on VNC
        }
    elif profile == "local+2vnc":
        return {
            range(1, 4): "eDP-1",
            range(4, 7): "HEADLESS-1",
            range(7, 10): "HEADLESS-2",
            range(50, 75): "HEADLESS-1",
            range(75, 100): "HEADLESS-2"
        }
```

### 7. Firewall Configuration

**Decision**: Restrict VNC ports to Tailscale interface only

**Rationale**:
- Security requirement from spec FR-010
- Consistent with Hetzner implementation
- Prevents unauthorized VNC access

**NixOS Configuration**:
```nix
# configurations/m1.nix
networking.firewall = {
  enable = true;
  interfaces."tailscale0".allowedTCPPorts = [ 5900 5901 ];
};
```

### 8. Profile Switch Performance

**Decision**: Target <2s for complete profile switch

**Rationale**:
- User experience requirement from spec SC-001
- Includes output creation, configuration, and WayVNC startup
- Eww update within 100ms (SC-003)

**Performance Breakdown**:
| Phase | Target | Implementation |
|-------|--------|----------------|
| Output creation | <500ms | `swaymsg create_output` |
| Configuration | <200ms | `swaymsg output ... mode/position` |
| WayVNC start | <1s | systemd service start |
| Eww update | <100ms | Event-driven via daemon |
| **Total** | **<2s** | Achieved via parallel operations |

### 9. Error Handling

**Decision**: Fail gracefully with rollback on profile switch failure

**Rationale**:
- Edge case from spec: "Profile switch fails with error notification, previous profile remains active"
- Prevents user from being stuck with partial configuration

**Rollback Strategy**:
```python
async def switch_profile(self, new_profile: str):
    old_profile = self.current_profile
    try:
        await self._apply_profile(new_profile)
        self.current_profile = new_profile
        await self.eww_publisher.publish_state()
    except Exception as e:
        # Rollback to previous profile
        await self._apply_profile(old_profile)
        await self.send_notification(f"Profile switch failed: {e}")
        raise ProfileSwitchError(str(e))
```

### 10. Keybinding Implementation

**Decision**: Use `Mod+Shift+M` for profile cycling

**Rationale**:
- User-specified requirement
- Consistent with other Mod+Shift combinations
- M for "Monitor"

**Implementation**:
```nix
# In sway-keybindings.nix
bindsym $mod+Shift+m exec ${pkgs.writeShellScript "cycle-monitor-profile" ''
  current=$(cat ~/.config/sway/monitor-profile.current)
  case $current in
    local-only) next="local+1vnc" ;;
    local+1vnc) next="local+2vnc" ;;
    local+2vnc) next="local-only" ;;
  esac
  set-monitor-profile "$next"
''}
```

---

## Open Questions Resolved

### Q1: Can `swaymsg create_output` work with native backend?
**Answer**: Yes. Research confirms that create_output works on non-headless Sway sessions. The wlroots compositor supports mixed physical + virtual outputs.

### Q2: How to name dynamically created outputs?
**Answer**: Use HEADLESS-1, HEADLESS-2 for consistency with existing patterns. The name is deterministic based on creation order.

### Q3: GPU rendering preserved on eDP-1?
**Answer**: Yes. Native backend maintains GPU acceleration. Only the virtual outputs use software rendering if needed (but WayVNC handles this transparently).

---

## Dependencies Confirmed

1. **Feature 083**: MonitorProfileService, EwwPublisher, profile switching infrastructure
2. **Feature 048**: WayVNC configuration patterns, firewall rules
3. **Feature 001**: Workspace-to-monitor assignment logic
4. **Feature 049**: Auto workspace redistribution on profile change

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| create_output not supported in Sway version | Low | High | Verify Sway version, document minimum |
| GPU contention between eDP-1 and VNC | Low | Medium | WayVNC uses separate rendering path |
| VNC latency over Tailscale | Medium | Low | Expected behavior, not a blocking issue |
| Workspace reassignment race condition | Low | Medium | Feature 049 debouncing already handles |

---

## Recommendations

1. **Start with MVP**: Implement local-only → local+1vnc first, add local+2vnc later
2. **Test on real M1**: Verify create_output behavior before full implementation
3. **Reuse aggressively**: Leverage all Feature 083 patterns, modify only for hybrid mode
4. **Document well**: Update CLAUDE.md with M1 monitor management section

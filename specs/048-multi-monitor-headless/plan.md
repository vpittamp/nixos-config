# Implementation Plan: Multi-Monitor Headless Sway/Wayland Setup

**Branch**: `048-multi-monitor-headless` | **Date**: 2025-10-29 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/048-multi-monitor-headless/spec.md`

## Summary

Enable a **static triple-head Sway/Wayland configuration** for the Hetzner Cloud VM with three virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3) accessible via three independent WayVNC instances over Tailscale. Each display will stream on a dedicated port (5900-5902), and workspaces 1-9 will be distributed across the displays (1-3, 4-6, 7-9). This approach extends the existing single-display headless Sway configuration to support multi-monitor workflows for remote development.

**Technical Approach**: Set `WLR_HEADLESS_OUTPUTS=3` to create three virtual displays at compositor startup, configure Sway output definitions with resolution/position/workspace assignments, implement a systemd template service (`wayvnc@.service`) to spawn three WayVNC instances (one per output), and integrate with i3pm monitor detection to recognize and distribute workspaces across three headless outputs.

## Technical Context

**Language/Version**: Nix (NixOS module system), Bash (systemd service scripts)
**Primary Dependencies**:
- wlroots headless backend (via WLR_BACKENDS=headless)
- WayVNC 0.8+ (VNC server with headless output support)
- Sway 1.5+ (Wayland compositor with runtime output management)
- Tailscale (VPN for secure VNC access)
- i3pm (workspace distribution and project management integration)

**Storage**: N/A (configuration only, no persistent data storage beyond systemd logs)

**Testing**:
- Manual validation: VNC client connectivity on ports 5900-5902 over Tailscale
- Automated validation: `nixos-rebuild dry-build` for configuration correctness
- Integration testing: i3pm monitor detection reports 3 outputs
- Functional testing: Workspace switching correctly activates outputs

**Target Platform**: Hetzner Cloud VM (x86_64, virtualized hardware, no GPU, headless)

**Project Type**: NixOS system configuration (declarative infrastructure)

**Performance Goals**:
- VNC stream latency <200ms over Tailscale for real-time updates
- All three WayVNC services start within 10 seconds of Sway initialization
- Workspace switching <100ms to activate correct output

**Constraints**:
- No GPU acceleration (software rendering via pixman required)
- Single user configuration (vpittamp)
- VNC ports must only be accessible via Tailscale (security)
- Must integrate with existing i3pm workspace distribution system

**Scale/Scope**:
- 3 virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3)
- 9 workspaces distributed across displays
- 3 concurrent VNC server instances
- Single Hetzner Cloud VM deployment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Compliance Review

**✅ Principle I: Modular Composition**
- Configuration changes will be made in existing modules (`configurations/hetzner-sway.nix`, `home-modules/desktop/sway.nix`)
- No code duplication - extends existing headless Sway configuration
- Systemd template service follows reusable pattern for multiple instances
- Adheres to configuration hierarchy: Base → Hardware → Services → Desktop → Target

**✅ Principle II: Reference Implementation Flexibility**
- Hetzner Sway is the current reference implementation (configurations/hetzner-sway.nix)
- Feature enhances reference configuration without breaking existing single-display functionality
- Changes validated on reference platform before considering other targets

**✅ Principle III: Test-Before-Apply**
- All changes will be tested with `nixos-rebuild dry-build --flake .#hetzner-sway` before applying
- VNC connectivity will be validated incrementally (first display, then second, then third)
- Rollback plan: NixOS generation rollback if configuration fails

**✅ Principle IV: Override Priority Discipline**
- Will use normal assignment for output configuration (no overrides needed)
- Existing `lib.mkIf isHeadless` conditionals will be preserved and extended
- No `lib.mkForce` required for this feature

**✅ Principle V: Platform Flexibility Through Conditional Features**
- Uses existing `isHeadless` conditional logic from `home-modules/desktop/sway.nix`
- Multi-display configuration only applies to headless mode (not M1 or other targets)
- Conditional workspace assignments based on `isHeadless` flag

**✅ Principle VI: Declarative Configuration Over Imperative**
- All configuration expressed in Nix (environment variables, output definitions, systemd services)
- No post-install scripts required
- WayVNC instances managed via systemd user services with declarative configuration

**✅ Principle VII: Documentation as Code**
- Will create `quickstart.md` for user guide on connecting VNC clients
- Will document configuration changes inline with comments
- Will update CLAUDE.md with VNC connection instructions and port mappings

**✅ Principle XI: i3 IPC Alignment & State Authority**
- i3pm monitor detection will query Sway via i3 IPC (`GET_OUTPUTS`, `GET_WORKSPACES`)
- No custom state tracking - Sway/i3pm IPC is authoritative for output configuration
- Event-driven architecture preserved (no polling)

**✅ Principle XII: Forward-Only Development & Legacy Elimination**
- Completely replaces single-display configuration with multi-display approach
- No backwards compatibility shims or feature flags
- Immediate, complete transition to 3-display setup on hetzner-sway

**⚠️ Principle VIII: Remote Desktop & Multi-Session Standards**
- **Potential Concern**: This principle specifies xrdp/X11 for multi-session RDP, but this feature uses WayVNC/Wayland
- **Justification**: VNC protocol serves same purpose as RDP (remote desktop access) but is designed for single-display-per-connection model. Three VNC instances provide equivalent functionality to multi-session RDP by allowing three concurrent connections (one per display). Wayland/Sway is already deployed on hetzner-sway as reference implementation, and this feature extends existing architecture rather than introducing new conflicts.
- **Compliance**: Multi-session isolation is achieved via three independent VNC streams; session persistence maintained via systemd service restart policies

**Status**: ✅ PASSED with justification for Principle VIII variance

### Post-Design Review (Phase 1)

**✅ Constitution Re-Check After Design Phase**

All principles remain compliant after design artifacts (research.md, data-model.md, contracts/) have been generated:

**✅ Principle I: Modular Composition**
- Design maintains modular approach with no code duplication
- Systemd service definitions use standard NixOS home-manager patterns
- Configuration changes isolated to two existing modules (hetzner-sway.nix, sway.nix)

**✅ Principle VI: Declarative Configuration Over Imperative**
- All contracts defined as declarative Nix expressions or JSON schemas
- No shell scripts or imperative configuration required
- Systemd services managed via home-manager, not manual systemctl commands

**✅ Principle VII: Documentation as Code**
- Generated comprehensive documentation: research.md, data-model.md, contracts/, quickstart.md
- User guide (quickstart.md) provides clear VNC connection instructions
- Inline comments in contracts explain service dependencies and validation

**✅ Principle XI: i3 IPC Alignment & State Authority**
- Workspace assignments validated via Sway IPC `GET_WORKSPACES` and `GET_OUTPUTS`
- No custom state tracking - Sway IPC remains authoritative
- i3pm integration queries Sway directly for output configuration

**Status**: ✅ PASSED - All constitutional principles satisfied after design phase

## Project Structure

### Documentation (this feature)

```
specs/048-multi-monitor-headless/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output: WayVNC multi-instance patterns, Sway output management
├── data-model.md        # Phase 1 output: Output configuration, WayVNC instance mapping
├── quickstart.md        # Phase 1 output: User guide for VNC client setup
├── contracts/           # Phase 1 output: Systemd service contracts, Sway output schema
│   ├── wayvnc-template-service.unit    # Systemd template unit definition
│   ├── sway-output-config.schema.json  # Sway output configuration schema
│   └── wayvnc-instance-map.json        # Output → Port → WayVNC instance mapping
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
/etc/nixos/
├── configurations/
│   └── hetzner-sway.nix           # Update: WLR_HEADLESS_OUTPUTS=3, firewall ports 5901-5902
│
├── home-modules/desktop/
│   └── sway.nix                    # Update: 3 output definitions, workspace assignments, wayvnc services
│
├── modules/services/
│   └── (no changes - i3pm daemon already supports Sway IPC)
│
└── scripts/
    └── (no changes - reassign-workspaces.sh already queries i3 IPC for outputs)
```

**Structure Decision**: This feature extends the existing NixOS modular configuration structure without introducing new directories. Changes are localized to:
1. **System-level configuration** (`configurations/hetzner-sway.nix`): Environment variables and firewall rules
2. **User-level desktop configuration** (`home-modules/desktop/sway.nix`): Output definitions, workspace assignments, systemd services

This aligns with Principle I (Modular Composition) by extending existing modules rather than duplicating code or creating new module files.

## Complexity Tracking

*No violations requiring justification*

This feature introduces no architectural complexity violations. It extends an existing single-display pattern to three displays using the same mechanisms (environment variables, Sway output configuration, systemd services). The systemd template service pattern is a standard NixOS approach for managing multiple instances of the same service.

# Implementation Plan: Migrate M1 MacBook Pro to Sway with i3pm Integration

**Branch**: `045-migrate-m1-macbook` | **Date**: 2025-10-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/045-migrate-m1-macbook/spec.md`

## Summary

Migrate M1 MacBook Pro configuration from KDE Plasma desktop environment to Sway tiling window manager with full i3pm daemon integration, maintaining architectural parity with Hetzner i3 configuration while adapting for Wayland and Apple Silicon hardware. This migration enables keyboard-driven productivity workflows, project-scoped window management, and native Wayland performance on M1 hardware.

**Technical Approach**: Port Hetzner's i3 configuration modules to Sway-compatible equivalents, update Python daemon to use Sway IPC instead of xprop, configure Walker for native Wayland operation, and implement wayvnc for remote access. All changes isolated to M1 configuration - Hetzner remains unchanged on i3/X11.

## Technical Context

**Language/Version**: Python 3.11+ (daemon), Nix expressions (configuration), Bash scripts (wrappers)
**Primary Dependencies**:
- Sway 1.8+ (window manager)
- i3ipc-python 2.2+ (Python i3/Sway IPC library - protocol compatible)
- Walker/Elephant (application launcher - native Wayland support)
- wayvnc (VNC server for Wayland)
- home-manager (user environment management)

**Storage**: Configuration files in `~/.config/sway/`, `~/.config/i3/` (daemon state), NixOS system configuration in `/etc/nixos/`

**Testing**:
- pytest (Python daemon unit/integration tests)
- Manual testing on M1 hardware via remote build deployment
- i3pm diagnostic tools (`i3pm diagnose health`, `i3pm windows --live`)

**Target Platform**: NixOS on Apple Silicon M1 MacBook Pro (aarch64-linux), Asahi Linux kernel, native Wayland, Retina display (2560x1600 at 2x scaling)

**Project Type**: System configuration (NixOS modules + Python daemon + shell scripts)

**Performance Goals**:
- Sway session startup <5 seconds to usable desktop
- i3pm daemon connection <2 seconds after Sway starts
- Window event processing <100ms latency
- Project switching <500ms for hide/show operations
- Walker launcher response <200ms for application search

**Constraints**:
- M1 hardware requires `--impure` flag for firmware access (Asahi Linux)
- Remote builds from Codespace/development machine (no local M1 build environment)
- Cannot break existing Hetzner i3 configuration
- Must maintain identical user workflows between Hetzner and M1
- Python daemon tests must pass without modification to test logic (only window property access methods change)

**Scale/Scope**:
- 6 user stories (3 P1, 2 P2, 1 P3)
- 25 functional requirements
- ~10 NixOS configuration files to create/modify
- 3 Python daemon files to update (connection.py, handlers.py, window_filter.py)
- 1 Walker configuration file to update (remove X11 compatibility flags)
- Support for 2-3 external monitors (multi-monitor workspace distribution)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

✅ **Principle I - Modular Composition**:
- Creating `modules/desktop/sway.nix` parallel to `i3wm.nix` (reusable module pattern)
- Creating `home-modules/desktop/sway.nix` parallel to `i3.nix` (composable home-manager module)
- Extracting common Wayland configuration into shared environment variables

✅ **Principle II - Reference Implementation Flexibility**:
- Hetzner remains the reference configuration (i3/X11)
- M1 becomes alternative desktop environment implementation (Sway/Wayland)
- Both platforms share i3pm daemon codebase (protocol compatibility)

✅ **Principle III - Test-Before-Apply**:
- Will execute `nixos-rebuild dry-build --flake .#m1 --impure` before each deployment
- Testing via remote build from development machine
- Can rollback via NixOS generations if issues arise

✅ **Principle IV - Override Priority Discipline**:
- Using `lib.mkForce false` to disable KDE Plasma on M1
- Using `lib.mkDefault` for Sway defaults that can be overridden
- Documented priority levels in module comments

✅ **Principle V - Platform Flexibility Through Conditional Features**:
- Sway module will detect Wayland vs X11 automatically
- Walker configuration adapts based on display server (remove GDK_BACKEND=x11 for Wayland)
- Python daemon remains display-server agnostic (IPC only)

✅ **Principle VI - Declarative Configuration Over Imperative**:
- All Sway configuration generated via home-manager `xdg.configFile`
- No manual configuration files or post-install scripts
- wayvnc configured via systemd user service

✅ **Principle VII - Documentation as Code**:
- This plan documents all architectural decisions
- Will create quickstart.md with Sway-specific commands
- Will update CLAUDE.md with M1 Sway build instructions

⚠️ **Principle VIII - Remote Desktop & Multi-Session Standards**:
- **DEVIATION**: Sway/Wayland uses VNC instead of RDP
- **Justification**: User explicitly approved VNC as acceptable alternative (per requirements)
- **Impact**: Single-session VNC vs multi-session RDP - documented limitation
- **Mitigation**: wayvnc provides secure VNC with authentication

✅ **Principle IX - Tiling Window Manager & Productivity Standards**:
- Sway is i3-compatible tiling window manager (same config syntax)
- Keyboard shortcuts identical to Hetzner i3 configuration
- Walker replaces rofi (already configured on Hetzner)
- Workspace naming via swaybar (equivalent to i3bar)

✅ **Principle X - Python Development & Testing Standards**:
- Python 3.11+ with async/await patterns (i3ipc.aio)
- pytest test suite remains unchanged (only implementation changes)
- Pydantic models unchanged (protocol-agnostic)
- Rich library for terminal UI (unchanged)

✅ **Principle XI - i3 IPC Alignment & State Authority**:
- Sway implements identical i3 IPC protocol (100% compatible)
- Same event subscriptions (window, workspace, output, tick, shutdown)
- Same IPC message types (GET_TREE, GET_WORKSPACES, GET_OUTPUTS, GET_MARKS)
- i3ipc-python library works with both i3 and Sway

✅ **Principle XII - Forward-Only Development & Legacy Elimination**:
- Complete replacement of KDE Plasma with Sway (no dual support)
- No backwards compatibility layers or feature flags
- Immediate cutover per user requirements

✅ **Principle XIII - Deno CLI Development Standards**:
- Not applicable (no new CLI tools in this feature)
- Existing Python CLI tools unchanged

### Platform Support Standards Compliance

✅ **Multi-Platform Compatibility**:
- M1 remains supported target alongside WSL, Hetzner, containers
- Hardware-specific settings isolated in `hardware/m1.nix` (unchanged)
- Sway-specific settings in `modules/desktop/sway.nix` (new)

✅ **Desktop Environment Transition**:
- Following documented transition process (KDE Plasma → Sway)
- Evaluated Wayland for M1 native hardware use case (HiDPI, touch gestures)
- X11 remains on Hetzner for mature RDP compatibility
- All critical integrations validated (1Password, terminal tools, browser)

### Security & Authentication Standards Compliance

✅ **1Password Integration**:
- M1 already has 1Password desktop app configured
- SSH keys via 1Password SSH agent (unchanged)
- Git signing via 1Password (unchanged)
- Firefox PWA compatibility preserved

✅ **SSH Hardening**:
- SSH configuration unchanged from current M1 setup
- Tailscale VPN integration preserved

### Violations Requiring Justification

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| VNC instead of RDP (Principle VIII) | Wayland/Sway lacks mature RDP support; user explicitly accepted VNC | waypipe (Wayland remote) is experimental, RDP on Wayland requires complex bridges (weston-rdp unstable) |

## Project Structure

### Documentation (this feature)

```
specs/045-migrate-m1-macbook/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Sway/Wayland best practices
├── data-model.md        # Phase 1 output - Configuration entities
├── quickstart.md        # Phase 1 output - M1 Sway build/deploy guide
├── contracts/           # Phase 1 output - IPC protocol schemas
│   ├── sway-ipc.md     # Sway IPC message types (identical to i3)
│   ├── daemon-adaptation.md  # Python daemon changes
│   └── wayvnc-config.md      # VNC service configuration
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```
# NixOS Configuration Modules (NEW)
modules/desktop/
├── sway.nix             # NEW: Sway window manager system module (mirrors i3wm.nix)
└── wayvnc.nix           # NEW: wayvnc VNC server module

home-modules/desktop/
├── sway.nix             # NEW: Sway user configuration (mirrors i3.nix)
├── swaybar.nix          # NEW: Swaybar configuration (mirrors i3bar.nix)
└── walker.nix           # MODIFIED: Remove X11 compatibility, enable Wayland

# Target Configuration (MODIFIED)
configurations/
└── m1.nix               # MODIFIED: Replace KDE imports with Sway

# Python Daemon (MODIFIED)
home-modules/desktop/i3-project-event-daemon/
├── connection.py        # MODIFIED: Replace xprop with Sway IPC queries
├── handlers.py          # MODIFIED: Use app_id instead of window_class
└── services/
    └── window_filter.py # MODIFIED: Update window property reading

# Tests (UNCHANGED - validate protocol compatibility)
tests/i3-project-daemon/
├── scenarios/           # Test scenarios remain unchanged
├── integration/         # Integration tests validate Sway IPC compatibility
└── fixtures/            # Mock data unchanged (protocol-agnostic)
```

**Structure Decision**: Following NixOS modular composition pattern established in constitution. Sway modules mirror i3 structure for maintainability (sway.nix parallel to i3wm.nix, home-modules/desktop/sway.nix parallel to i3.nix). Python daemon changes isolated to window property access methods - all business logic, state management, and testing remains unchanged due to i3 IPC protocol compatibility.

## Complexity Tracking

No constitution violations requiring justification beyond the documented VNC deviation (approved by user, documented in table above).

**Rationale**: This migration maintains existing architectural patterns (modular composition, parallel module structures) and leverages Sway's i3 IPC compatibility to minimize code changes. The only complexity is managing two desktop environments across platforms (Hetzner=i3/X11, M1=Sway/Wayland), which is already an accepted pattern per Principle II (Reference Implementation Flexibility).

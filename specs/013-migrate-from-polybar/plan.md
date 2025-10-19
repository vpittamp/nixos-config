# Implementation Plan: Migrate from Polybar to i3 Native Status Bar

**Branch**: `013-migrate-from-polybar` | **Date**: 2025-10-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-migrate-from-polybar/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace the current polybar status bar implementation with i3's native i3bar to achieve reliable workspace display and system information monitoring. The migration will leverage i3's built-in IPC protocol for workspace state synchronization, eliminating the complexity and reliability issues experienced with polybar's external module system. The solution will use i3blocks for the status command to display system metrics and project context, with declarative configuration managed via home-manager.

## Technical Context

**Language/Version**: Nix 2.18+, Bash 5.x (for i3blocks scripts)
**Primary Dependencies**: i3wm 4.23+, i3bar (included with i3), i3blocks 1.5+, home-manager 23.11+
**Storage**: State files (~/.config/i3/active-project for project context), no persistent database
**Testing**: Manual validation via nixos-rebuild dry-build, visual verification on 3-monitor RDP setup
**Target Platform**: NixOS 23.11+ on Hetzner Cloud (x86_64), accessed via xrdp/RDP with X11
**Project Type**: System configuration (NixOS modules + home-manager)
**Performance Goals**:
  - Workspace indicator updates within 100ms of workspace switch
  - System information updates every 5 seconds
  - Bar startup within 2 seconds of i3 launch

**Constraints**:
  - Must survive nixos-rebuild switch without manual restart
  - Must support 3 concurrent RDP sessions with independent bars
  - Configuration must be fully declarative (no imperative setup)
  - Must maintain Catppuccin Mocha color scheme consistency

**Scale/Scope**:
  - Single user, 3 monitors, 9 workspaces per session
  - ~50-100 lines of i3bar configuration (bar {} block)
  - 3-5 i3blocks scripts for status information
  - Replace ~280 lines of polybar configuration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

✅ **I. Modular Composition**
- Bar configuration will be added to existing `home-modules/desktop/i3.nix`
- i3blocks scripts will be created in `home-modules/desktop/i3blocks/` with clear separation
- Polybar module will be removed from imports to avoid conflicts
- No code duplication - single source of truth for bar configuration

✅ **II. Reference Implementation Flexibility**
- Hetzner is the reference platform (i3wm + xrdp + X11)
- Changes will be tested on Hetzner first before considering other platforms
- Documentation will be updated to reflect i3bar as the standard

✅ **III. Test-Before-Apply (NON-NEGOTIABLE)**
- All changes will use `nixos-rebuild dry-build --flake .#hetzner` before switch
- Rollback procedure: `nixos-rebuild switch --rollback` if issues occur
- Breaking changes will be documented in commit messages

✅ **IV. Override Priority Discipline**
- i3bar colors will use normal assignment (no overrides needed)
- Workspace assignments already use appropriate priority levels
- No new override requirements for this feature

✅ **V. Platform Flexibility Through Conditional Features**
- Not applicable - i3bar only makes sense where i3wm is enabled
- Will use `lib.mkIf config.xsession.windowManager.i3.enable` pattern
- No GUI vs headless adaptation needed (i3 implies GUI)

✅ **VI. Declarative Configuration Over Imperative**
- All configuration via home-manager Nix expressions
- Bar config embedded in i3 config file generation
- i3blocks scripts generated via home.file with proper permissions
- No manual configuration steps required

✅ **VII. Documentation as Code**
- Quickstart guide will document bar configuration and customization
- Comments in Nix modules explain bar structure and i3blocks protocol
- Migration notes for removing polybar

✅ **VIII. Remote Desktop & Multi-Session Standards**
- i3bar automatically creates per-session instances via i3's lifecycle management
- X11 display server already in place (required for xrdp)
- Session isolation maintained through i3's native multi-session support
- No additional multi-session configuration needed

✅ **IX. Tiling Window Manager & Productivity Standards**
- i3bar is the native status bar for i3wm (perfect alignment)
- Keyboard shortcuts remain unchanged (workspace switching)
- i3blocks will display project context from existing project management system
- Rofi, clipcat, alacritty integrations unaffected

### Platform Support Standards

✅ **Multi-Platform Compatibility**
- Primary target: Hetzner (reference platform)
- WSL and M1 platforms may adopt later if needed (not in scope for this feature)
- Container deployments don't use GUI, so not affected

✅ **Testing Requirements**
- Manual testing on Hetzner with 3 RDP monitors
- Verify workspace display, system info updates, project indicator
- Test nixos-rebuild switch survival
- Test monitor connect/disconnect handling

### Security & Authentication Standards

✅ **1Password Integration**
- No changes to 1Password configuration
- Existing integration continues to work

✅ **SSH Hardening**
- No changes to SSH configuration
- Not applicable to this feature

### Package Management Standards

✅ **Package Profiles**
- i3blocks is small (~500KB), will be added to development profile
- No impact on minimal/essential profiles (they don't include i3wm)

✅ **Package Organization**
- i3blocks package added to `home-modules/desktop/i3.nix` (module-specific)
- Follows best practice of module package scoping
- No system-wide package additions needed

### Home-Manager Standards

✅ **Module Structure**
- Will follow standard home-manager module pattern
- Proper `{ config, lib, pkgs, ... }:` declaration
- i3blocks scripts via `home.file` with executable permissions

✅ **Configuration File Generation**
- Bar config generated as part of i3 config via string interpolation
- Binary paths use `${pkgs.package}/bin/binary` format
- i3blocks scripts use proper Nix string templates

### Gate Evaluation

**Status**: ✅ PASS - No constitution violations

All principles are satisfied. This is a straightforward migration within existing architecture:
- Replaces one status bar (polybar) with another (i3bar)
- Uses existing home-manager patterns
- Maintains declarative configuration discipline
- Aligns with i3wm tiling window manager standards
- No new complexity introduced

## Project Structure

### Documentation (this feature)

```
specs/013-migrate-from-polybar/
├── spec.md              # Feature specification
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0: i3bar vs i3status vs i3blocks decision
├── data-model.md        # Phase 1: Bar state and configuration entities
├── quickstart.md        # Phase 1: User guide for customization
├── contracts/           # Phase 1: i3blocks protocol examples
│   └── i3blocks-protocol.md
├── checklists/
│   └── requirements.md  # Quality validation checklist
└── tasks.md             # Phase 2: Implementation task breakdown
```

### Source Code (repository root)

```
/etc/nixos/
├── home-modules/desktop/
│   ├── i3.nix                    # MODIFIED: Add bar {} block configuration
│   ├── i3blocks/                 # NEW: i3blocks configuration and scripts
│   │   ├── default.nix          # i3blocks home-manager module
│   │   ├── config               # i3blocks configuration file template
│   │   └── scripts/             # Status command scripts
│   │       ├── cpu.sh           # CPU usage display
│   │       ├── memory.sh        # Memory usage display
│   │       ├── network.sh       # Network status display
│   │       ├── datetime.sh      # Date/time display
│   │       └── project.sh       # Project context indicator
│   └── polybar.nix              # REMOVED: Delete entire module
│
├── home-vpittamp.nix            # MODIFIED: Remove polybar import, add i3blocks
│
└── specs/013-migrate-from-polybar/  # Feature documentation (above)
```

**Structure Decision**: This is a system configuration change, not application code. All changes are in NixOS/home-manager modules. The i3blocks scripts are configuration artifacts (declaratively generated), not standalone source code. Following NixOS conventions, scripts live alongside their module configuration in `home-modules/desktop/i3blocks/`.

## Complexity Tracking

*No violations - this section intentionally left empty*

All constitution principles are satisfied without requiring any complexity justifications. This is a like-for-like replacement within existing architecture patterns.

## Post-Design Constitution Re-Check

*Re-evaluated after Phase 1 design artifacts completed*

### Design Artifacts Created

- ✅ research.md - All technical decisions documented
- ✅ data-model.md - Configuration and state entities defined
- ✅ contracts/i3blocks-protocol.md - Script interface contract specified
- ✅ quickstart.md - User customization guide created

### Constitution Compliance Review

**I. Modular Composition** - ✅ PASS
- Design maintains modular structure
- i3blocks scripts separated by concern (cpu, memory, project, etc.)
- Configuration files generated declaratively
- No duplication between bar config and block scripts

**II. Reference Implementation Flexibility** - ✅ PASS
- Hetzner remains reference platform
- Design validated against Hetzner's 3-monitor RDP setup
- Documentation reflects current architecture

**III. Test-Before-Apply** - ✅ PASS
- Migration strategy includes dry-build validation
- Rollback procedure documented
- Testing checklist defined in quickstart

**IV. Override Priority Discipline** - ✅ PASS
- No new override requirements introduced
- Bar configuration uses standard assignments
- No conflicts with existing i3 workspace assignments

**V. Platform Flexibility** - ✅ PASS
- Design conditional on i3wm being enabled
- Graceful degradation if dependencies missing
- Script error handling prevents cascade failures

**VI. Declarative Configuration** - ✅ PASS
- All configuration via Nix expressions
- Scripts generated via home.file with executable flag
- State file (active-project) is user data, not configuration
- No imperative post-install steps required

**VII. Documentation as Code** - ✅ PASS
- Comprehensive quickstart guide created
- i3blocks protocol contract documented
- Data model explains all entities
- Research decisions captured for future reference

**VIII. Remote Desktop & Multi-Session** - ✅ PASS
- i3bar lifecycle managed by i3 (one instance per session)
- No session-sharing issues (each RDP session independent)
- Works with existing X11 + xrdp setup

**IX. Tiling WM & Productivity** - ✅ PASS
- Native i3 integration (i3bar is built for i3wm)
- Keyboard workflows unchanged
- Project indicator maintains productivity context
- Minimal resource usage (scripts <100ms)

### Final Gate Evaluation

**Status**: ✅ PASS - All principles satisfied post-design

**Summary**:
- Design artifacts complete and comprehensive
- No new constitutional violations introduced
- All requirements traceable to design elements
- Ready to proceed to Phase 2 (Task generation via /speckit.tasks)

**Complexity Justification**: None required - design maintains simplicity

---

## Planning Phase Complete

**Branch**: 013-migrate-from-polybar
**Status**: ✅ Planning Complete - Ready for Tasks

### Artifacts Generated

1. **plan.md** (this file) - Implementation plan with technical context
2. **research.md** - Phase 0 research and technical decisions
3. **data-model.md** - Configuration and state entity definitions
4. **contracts/i3blocks-protocol.md** - Script interface contract
5. **quickstart.md** - User customization guide

### Next Steps

**Run** `/speckit.tasks` to generate implementation task breakdown (tasks.md)

**Or manually proceed with**:
1. Remove polybar configuration from home-vpittamp.nix
2. Add i3bar configuration to home-modules/desktop/i3.nix
3. Create i3blocks module and scripts
4. Test on Hetzner with `nixos-rebuild dry-build`
5. Apply and validate all success criteria

### Key Design Decisions

1. ✅ Use i3blocks (not i3status) for extensibility
2. ✅ JSON protocol for full color control
3. ✅ Signal-based project indicator updates
4. ✅ Direct hex color mapping from Catppuccin palette
5. ✅ Native i3 workspace-to-output assignments

**Total Planning Tokens Used**: ~35k tokens (spec + plan + research + design)
**Estimated Implementation Effort**: 2-4 hours for experienced Nix user

---

*Planning completed: 2025-10-19*
*Next command: /speckit.tasks to generate implementation tasks*

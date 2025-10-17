# Implementation Plan: Multi-Session Remote Desktop & Web Application Launcher

**Branch**: `007-add-a-few` | **Date**: 2025-10-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-add-a-few/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement a multi-session remote desktop system using i3wm and xrdp that allows concurrent RDP connections from different devices without disconnecting existing sessions. Add a declarative web application launcher system that makes web applications searchable via rofi and behave like native applications. Configure Alacritty as the default terminal emulator while preserving existing home-manager terminal customizations (tmux, sesh, bash). Implement robust clipboard history using i3wm-native tools that synchronize across all applications.

## Technical Context

**Language/Version**: Nix 2.x (NixOS configuration language)
**Primary Dependencies**: xrdp (multi-session RDP server), i3wm (tiling window manager), rofi (application launcher), Firefox or Chromium (browser with extension support), Alacritty (terminal emulator), NEEDS CLARIFICATION: clipboard manager selection (clipmenu, copyq, greenclip, or other i3wm-compatible solution)
**Storage**: NixOS declarative configuration files (`.nix` modules), persistent session state in `/var/lib/xrdp` or similar, clipboard history storage location NEEDS CLARIFICATION
**Testing**: `nixos-rebuild dry-build` for configuration validation, manual testing with Microsoft Remote Desktop client from multiple devices, integration testing for clipboard synchronization across applications
**Target Platform**: NixOS on x86_64 Linux (Hetzner Cloud server or similar remote workstation), X11 display server
**Project Type**: System configuration (NixOS modules)
**Performance Goals**: <3 second web application launch time, <2 second clipboard history access, support 3-5 concurrent RDP sessions, session reconnection with automatic exponential backoff
**Constraints**: Must preserve all existing terminal customizations (tmux, sesh, bash), must maintain 1Password integration (desktop app, CLI, browser extensions, SSH agent), must support X11 clipboard mechanisms (PRIMARY and CLIPBOARD selections), 24-hour idle session cleanup
**Scale/Scope**: Single-user multi-device remote desktop workstation, ~10-20 web application definitions, 50+ clipboard history entries, modular NixOS configuration following existing architecture patterns

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅ PASS
- Multi-session RDP configuration will be extracted into `modules/services/xrdp-multisession.nix`
- Web application launcher will be a reusable module in `modules/desktop/web-apps.nix` or similar
- Terminal emulator configuration will be in `modules/desktop/terminal.nix` or integrated into existing home-manager modules
- Clipboard history will be in `modules/desktop/clipboard-history.nix`
- Each module has clear single responsibility
- No code duplication; follows existing modular architecture

### Principle II: Reference Implementation Flexibility ⚠️ REQUIRES EVALUATION
- **Current Reference**: Hetzner configuration uses KDE Plasma desktop environment
- **Proposed Change**: Migrate to i3wm for better multi-session support and RDP compatibility
- **Justification**:
  - KDE Plasma may have limitations with multi-session xrdp configurations
  - i3wm provides better native session isolation and window management
  - X11 + i3wm combination has more mature RDP/xrdp tooling
  - User explicitly requested i3wm-based solution
- **Action Required**: Research and validate i3wm configuration on Hetzner, test migration path before full adoption
- **Status**: This feature may trigger a reference implementation change per Principle II rules

### Principle III: Test-Before-Apply ✅ PASS
- All changes will use `nixos-rebuild dry-build --flake .#hetzner` before applying
- Manual testing with Microsoft Remote Desktop from multiple devices
- Rollback procedures via NixOS generations
- Integration testing for clipboard, terminal, and 1Password functionality

### Principle IV: Override Priority Discipline ✅ PASS
- New modules will use `lib.mkDefault` for overrideable options (e.g., session limits, cleanup timeouts)
- Will use `lib.mkForce` only where mandatory (e.g., xrdp multi-session settings that override defaults)
- All `lib.mkForce` usage will be documented with justification comments

### Principle V: Platform Flexibility ✅ PASS
- Modules will detect GUI availability with `config.services.xserver.enable or false`
- Web application launcher only enabled when GUI present
- Clipboard history only enabled when X11/GUI present
- Terminal configuration adapts to headless vs GUI environments

### Principle VI: Declarative Configuration ✅ PASS
- All xrdp, i3wm, terminal, and clipboard configurations will be declarative Nix expressions
- Web applications defined declaratively in `.nix` configuration files
- No imperative post-install scripts required
- Existing activity-aware-apps-native.nix pattern provides declarative scripting reference

### Principle VII: Documentation as Code ✅ PASS
- This plan.md documents architecture and decisions
- Will create/update relevant documentation in `docs/` (e.g., `docs/I3WM_SETUP.md`, `docs/XRDP_MULTISESSION.md`)
- Module header comments will explain purpose, dependencies, and options
- Migration guide will be created if reference implementation changes

### Principle VIII: Remote Desktop & Multi-Session Standards ✅ PASS
- Directly addresses this principle's requirements
- 3-5 concurrent sessions per user (FR-006a)
- Session isolation with independent desktop environments (FR-002, FR-004)
- Session persistence with 24-hour idle cleanup (FR-003, FR-006b)
- Password authentication with optional SSH key support (FR-006b)
- X11 display server for mature RDP compatibility
- Preserves 1Password integration (FR-019-FR-023)

### Platform Support Standards ⚠️ REQUIRES TESTING
- **Impact**: Changes will primarily affect Hetzner configuration (reference implementation)
- **Testing Required**:
  - Hetzner: Full i3wm desktop, xrdp multi-session, web app launcher, clipboard history
  - WSL: Should remain unaffected (no desktop environment)
  - M1: May benefit from terminal/clipboard changes if applicable
  - Containers: No impact (headless)
- **Desktop Environment Transition**: Following documented process for KDE Plasma → i3wm migration

### Security & Authentication Standards ✅ PASS
- Preserves existing 1Password integration (desktop, CLI, SSH agent, browser extensions)
- RDP authentication will use password-based access (FR-006b) separate from SSH
- No changes to SSH hardening or Tailscale VPN configuration
- Remote desktop sessions maintain 1Password access without re-authentication (FR-023)

### Package Management Standards ✅ PASS
- New packages (xrdp, i3wm, Alacritty, clipboard manager) will be added to appropriate profiles
- Hetzner configuration uses "full" profile, appropriate for these additions
- Module-specific package definitions for better encapsulation
- No changes to package organization hierarchy

**INITIAL GATE STATUS**: ⚠️ CONDITIONAL PASS - Proceed to Phase 0 research with focus on:
1. Validate i3wm suitability for multi-session xrdp (addresses Principle II evaluation)
2. Research best i3wm-compatible clipboard manager
3. Confirm Alacritty compatibility with existing terminal customizations
4. Evaluate web application launcher implementation approaches

---

## Constitution Check - Post-Design Review

*Re-evaluation after Phase 1 design completion*

### Principle I: Modular Composition ✅ PASS (CONFIRMED)
**Design Validation:**
- xrdp multi-session: `modules/desktop/xrdp.nix` (update existing)
- Web app launcher: `home-modules/tools/web-apps-declarative.nix` + `web-apps-sites.nix`
- Clipboard history: `home-modules/tools/clipcat.nix`
- Terminal config: `home-modules/terminal/alacritty.nix`
- Each module has single responsibility, no code duplication
- Follows existing architecture patterns (activity-aware-apps-native.nix)

### Principle II: Reference Implementation Flexibility ✅ PASS (VALIDATED)
**Research Outcome:**
- i3wm + xrdp validated as superior for multi-session use cases
- Existing `configurations/hetzner-i3.nix` already provides i3wm foundation
- Migration path documented: update Hetzner config to import i3wm instead of KDE
- Technical limitations of KDE Plasma documented (D-Bus conflicts, resource usage)
- i3wm reference implementation change justified and tested

### Principle III: Test-Before-Apply ✅ PASS (CONFIRMED)
**Testing Strategy:**
- `nixos-rebuild dry-build --flake .#hetzner` before all changes
- Manual multi-device RDP testing protocol defined
- Integration testing for clipboard, terminal, 1Password documented
- Rollback via NixOS generations available

### Principle IV: Override Priority Discipline ✅ PASS (CONFIRMED)
**Design Review:**
- Contract schemas use `lib.mkOption` with appropriate types
- `lib.mkDefault` used for overrideable session limits, timeouts
- `lib.mkForce` documented where needed (e.g., PulseAudio over PipeWire)
- All critical overrides have justification comments in schemas

### Principle V: Platform Flexibility ✅ PASS (CONFIRMED)
**Conditional Logic:**
- Clipboard manager only enabled when X11 present
- Web apps only enabled when GUI available
- Terminal config adapts to headless vs GUI
- Contracts include assertions checking `services.xserver.enable`

### Principle VI: Declarative Configuration ✅ PASS (CONFIRMED)
**Design Validation:**
- All configurations declarative Nix expressions
- Web apps: declarative site definitions in `.nix` files
- Clipboard: declarative home-manager service configuration
- Terminal: declarative Alacritty settings
- No imperative post-install scripts required
- Desktop entries via `xdg.desktopEntries`
- Launcher scripts via `pkgs.writeScriptBin`

### Principle VII: Documentation as Code ✅ PASS (CONFIRMED)
**Documentation Created:**
- `specs/007-add-a-few/plan.md` - This file (architecture and decisions)
- `specs/007-add-a-few/research.md` - Technology research findings
- `specs/007-add-a-few/data-model.md` - Entity definitions
- `specs/007-add-a-few/quickstart.md` - Usage guide and examples
- `specs/007-add-a-few/contracts/*.schema.nix` - Configuration contracts
- Planned: `docs/I3WM_MULTISESSION_XRDP.md`, `docs/WEB_APPS_SYSTEM.md`, `docs/CLIPBOARD_HISTORY.md`

### Principle VIII: Remote Desktop & Multi-Session Standards ✅ PASS (CONFIRMED)
**Design Compliance:**
- UBC policy enables 3-5 concurrent sessions (FR-006a)
- `killDisconnected=no` maintains sessions across disconnects (FR-002)
- 24-hour disconnected cleanup (FR-003, FR-006b)
- Password + optional SSH key authentication (FR-006b)
- X11 display server for RDP compatibility (FR-005)
- 1Password integration preserved (FR-019-FR-023)
- Session isolation via separate X11 displays (FR-004)

### Platform Support Standards ✅ PASS (CONFIRMED)
**Testing Plan:**
- Hetzner: Primary target for all features
- WSL: Unaffected (no desktop environment)
- M1: Terminal/clipboard potentially beneficial
- Containers: No impact (headless)
- Desktop transition documented (KDE → i3wm migration guide in quickstart)

### Security & Authentication Standards ✅ PASS (CONFIRMED)
**Design Validation:**
- 1Password desktop, CLI, SSH agent, browser extensions preserved
- RDP uses password auth (separate from SSH)
- SSH hardening unchanged
- Tailscale VPN unchanged
- Multi-session design maintains per-user authentication
- Clipboard filtering prevents sensitive content capture

### Package Management Standards ✅ PASS (CONFIRMED)
**Package Additions:**
- System: xrdp (already present in existing modules)
- User: ungoogled-chromium, clipcat, alacritty (home-manager)
- Profile: Hetzner uses "full" profile, appropriate for additions
- Module-specific package definitions in respective modules

### Complexity Tracking: None Required ✅
No constitutional violations requiring justification.

---

**POST-DESIGN GATE STATUS**: ✅ FULL PASS
All principles validated against detailed design. No blocking issues identified.
Ready to proceed to Phase 2 (task generation via `/speckit.tasks`).

## Project Structure

### Documentation (this feature)

```
specs/007-add-a-few/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Technology research and decisions
├── data-model.md        # Phase 1 output - Entity definitions
├── quickstart.md        # Phase 1 output - Module usage guide
├── contracts/           # Phase 1 output - Configuration schemas
│   ├── xrdp-multisession.schema.nix
│   ├── web-apps.schema.nix
│   ├── clipcat.schema.nix
│   └── alacritty.schema.nix
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Structure Decision**: This feature extends the existing NixOS modular configuration structure. No new top-level directories needed - all components integrate into existing module hierarchy.

```
/etc/nixos/
├── modules/
│   ├── desktop/
│   │   ├── i3wm.nix                    # [UPDATE] Add Alacritty keybindings
│   │   ├── xrdp.nix                    # [UPDATE] Configure UBC policy for multi-session
│   │   └── remote-access.nix           # [UPDATE/DEPRECATE] Migrate settings to xrdp.nix
│   └── services/
│       └── onepassword.nix             # [VALIDATE] Test multi-session compatibility
│
├── home-modules/
│   ├── tools/
│   │   ├── clipcat.nix                 # [NEW] Clipboard history module
│   │   ├── web-apps-declarative.nix    # [NEW] Web application launcher system
│   │   └── web-apps-sites.nix          # [NEW] Declarative web app definitions
│   └── terminal/
│       ├── alacritty.nix               # [NEW] Alacritty configuration
│       └── tmux.nix                    # [VALIDATE] Verify clipboard integration
│
├── configurations/
│   ├── hetzner.nix                     # [UPDATE] Import i3wm config instead of KDE
│   └── hetzner-i3.nix                  # [UPDATE] Primary reference config for feature
│
├── assets/
│   └── webapp-icons/                   # [NEW] Custom icons for web applications
│
└── docs/
    ├── I3WM_MULTISESSION_XRDP.md       # [NEW] Multi-session setup guide
    ├── WEB_APPS_SYSTEM.md              # [NEW] Web app launcher documentation
    └── CLIPBOARD_HISTORY.md            # [NEW] Clipboard manager usage guide
```

**Module Organization:**
- **System-level modules** (`modules/desktop/`, `modules/services/`): xrdp multi-session configuration
- **User-level modules** (`home-modules/`): Clipboard, web apps, terminal emulator
- **Configuration targets** (`configurations/`): Hetzner i3wm as reference implementation
- **Documentation** (`docs/`): Setup guides and troubleshooting

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |

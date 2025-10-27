# Implementation Plan: Complete Walker/Elephant Launcher Functionality

**Branch**: `043-get-full-functionality` | **Date**: 2025-10-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/043-get-full-functionality/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable full functionality of Walker/Elephant launcher service with proper X11 environment variable propagation, including clipboard history, file search, web search, calculator, symbols, and shell command execution. The primary challenge is ensuring the Elephant systemd user service receives and propagates all necessary environment variables (DISPLAY, XDG_DATA_DIRS, PATH, I3PM_*) to launched applications in an X11 environment, while maintaining compatibility with the i3pm project management system.

## Technical Context

**Language/Version**: Nix 2.18+ (declarative configuration), Bash (wrapper scripts), TOML (config files)
**Primary Dependencies**:
- Walker (≥1.5 for X11 file provider support) - GTK4 launcher UI
- Elephant (from flake input abenz1267/walker) - Backend service for providers
- i3pm daemon - Project context provider (existing)
- xclip - Clipboard operations
- Ghostty - Terminal emulator
- Neovim - Text editor for file opening
- Firefox - Web browser for search

**Storage**:
- Clipboard history: Ephemeral (in-memory, managed by Elephant service)
- Web search engines: TOML config file (`~/.config/elephant/websearch.toml`)
- Application registry: JSON file (`~/.config/i3/application-registry.json`) - existing from Feature 035
- No persistent database required

**Testing**:
- Manual functional testing (launch apps, test providers)
- Environment variable validation via `/proc/<pid>/environ` inspection
- Service health checks via `systemctl --user status elephant`
- Provider testing via Walker UI (type prefixes and verify results)

**Target Platform**: NixOS 24.05+ on X11 (Hetzner configuration with i3wm + xrdp)

**Project Type**: System configuration (NixOS modules) + user configuration (home-manager)

**Performance Goals**:
- Walker window appears <100ms after keybinding
- Clipboard history displays <200ms after ":" prefix
- File search returns results <500ms for 10k files
- Application launch inherits environment <50ms overhead

**Constraints**:
- MUST use X11 (not Wayland) - xrdp requirement
- MUST run Elephant as systemd user service (not system service) - environment access
- MUST preserve i3pm project context integration (I3PM_* environment variables)
- MUST NOT break existing Walker/Elephant configuration (file provider already enabled)

**Scale/Scope**:
- Single-user desktop environment
- ~21 curated applications from i3pm registry
- Clipboard history: 100-500 items
- File search scope: User home directory + active project directory
- 5 web search engines configured

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Modular Composition ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: Changes are isolated to existing `home-modules/desktop/walker.nix` configuration
- **Justification**: No new modules required - configuration updates to enable existing Walker/Elephant providers (clipboard, files, websearch, calc, symbols, runner). All changes are within the existing modular structure.

### Principle III: Test-Before-Apply ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: Standard `nixos-rebuild dry-build --flake .#hetzner` testing applies
- **Justification**: Configuration changes follow normal NixOS rebuild workflow with dry-build validation before switch

### Principle V: Platform Flexibility Through Conditional Features ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: Walker/Elephant configuration is already conditionally enabled only on GUI systems
- **Justification**: Existing `home-modules/desktop/walker.nix` module is only imported on systems with desktop environments. No changes needed to conditional logic.

### Principle VI: Declarative Configuration Over Imperative ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: All changes are declarative Nix configuration (systemd service, config files, environment variables)
- **Justification**: Walker config.toml, Elephant websearch.toml, and systemd service definitions are all declaratively generated via home-manager

### Principle VIII: Remote Desktop & Multi-Session Standards ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: Feature enhances X11-based launcher functionality for i3wm + xrdp environment
- **Justification**: Walker/Elephant already configured for X11 (as_window=true, GDK_BACKEND=x11). This feature enables additional providers while maintaining X11 compatibility and DISPLAY propagation.

### Principle IX: Tiling Window Manager & Productivity Standards ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: Walker is the keyboard-driven application launcher already configured for i3wm
- **Justification**: Feature enhances productivity by enabling quick access to clipboard history (:), file search (/), web search (@), calculator (=), symbols (.), and shell commands (>) - all keyboard-driven workflows

### Principle XII: Forward-Only Development & Legacy Elimination ✅ PASS
- **Status**: COMPLIANT
- **Assessment**: Feature enables existing providers, no legacy code or backwards compatibility concerns
- **Justification**: Walker/Elephant provider configuration is additive (enabling modules) with no legacy alternatives to maintain

### Summary
**GATE STATUS: ✅ PASS** - All applicable constitution principles are satisfied. No violations or complexity justifications required.

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
home-modules/desktop/
├── walker.nix              # Walker/Elephant configuration (MODIFY)
│   ├── programs.walker.config - Enable all providers
│   ├── systemd.user.services.elephant - Environment setup
│   └── xdg.configFile."walker/config.toml" - Provider configuration
│   └── xdg.configFile."elephant/websearch.toml" - Web search engines
└── i3.nix                  # i3 configuration (MODIFY if needed)
    └── bindsym for Walker launch (already configured)

home-modules/tools/
└── (no changes - Walker wrapper scripts already exist)
```

**Structure Decision**: This is a **configuration-only feature** with no new source code. All changes are to existing NixOS/home-manager configuration files in `home-modules/desktop/walker.nix`. The feature enables existing Walker/Elephant providers (clipboard, files, websearch, calc, symbols, runner) by:

1. Updating Walker config.toml to enable all provider modules
2. Configuring Elephant systemd service with proper environment variables (DISPLAY, PATH, XDG_DATA_DIRS)
3. Adding Elephant websearch.toml configuration for search engines

No new modules, scripts, or applications are created. All functionality exists in Walker/Elephant packages from the flake input.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**Status**: No violations - all constitution principles satisfied.

## Post-Design Constitution Re-Check

### After Phase 1 Design - Constitution Validation

All constitution principles remain satisfied after design phase:

**Principle I: Modular Composition** ✅ PASS
- Design confirms no new modules required
- All changes contained within existing `home-modules/desktop/walker.nix`
- No code duplication introduced

**Principle VI: Declarative Configuration Over Imperative** ✅ PASS
- All configurations remain declarative (TOML generation via home-manager)
- No imperative scripts or manual configuration steps
- Walker config.toml and Elephant websearch.toml generated from Nix expressions

**Principle XII: Forward-Only Development & Legacy Elimination** ✅ PASS
- No legacy code or backwards compatibility concerns
- Feature enables existing providers without introducing technical debt
- Configuration is additive (enabling modules that already exist)

**Overall Design Assessment**:
- Configuration-only feature with zero implementation complexity
- All functionality already exists in Walker/Elephant packages
- Design artifacts (data-model.md, contracts/, quickstart.md) document existing system
- No new code required - validation and documentation only

**GATE STATUS: ✅ PASS** - Design phase confirms constitution compliance

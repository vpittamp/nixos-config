# Implementation Plan: Enhanced Walker/Elephant Launcher Functionality

**Branch**: `050-enhance-the-walker` | **Date**: 2025-10-29 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/050-enhance-the-walker/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable additional Walker/Elephant launcher providers to enhance productivity: todo list management (`!` prefix), window switcher (fuzzy window navigation), bookmarks (quick URL access), custom commands (user-defined shortcuts), enhanced web search (multiple search engines), and clipboard history (`:` prefix). Configuration will be added to the existing NixOS home-manager Walker module (`home-modules/desktop/walker.nix`) with sensible defaults and comprehensive documentation.

## Technical Context

**Language/Version**: Nix expressions for home-manager configuration, TOML for Walker/Elephant configuration
**Primary Dependencies**: Walker launcher (≥1.5.0), Elephant backend (2.9.x), home-manager module
**Storage**: File-based via Walker/Elephant's built-in storage (todos, clipboard history, bookmarks in TOML config)
**Testing**: Manual testing of each provider with test cases from spec, validate with `home-manager switch`
**Target Platform**: NixOS with Sway/Wayland (hetzner-sway reference configuration)
**Project Type**: Single configuration file modification (home-modules/desktop/walker.nix)
**Performance Goals**: Walker startup time increase <200ms with all providers enabled (per SC-007)
**Constraints**: Must maintain existing Walker functionality, no source code modifications to Walker/Elephant, configuration-only changes
**Scale/Scope**: 6 new providers to enable (todo, windows, bookmarks, commands, enhanced web search, clipboard history)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I - Modular Composition ✅
**Status**: PASS
**Rationale**: This feature modifies a single existing home-manager module (`home-modules/desktop/walker.nix`) rather than creating new modules or duplicating configuration. Walker configuration is already properly modularized within the home-modules structure.

### Principle III - Test-Before-Apply ✅
**Status**: PASS (with process)
**Process**: All configuration changes will be tested with `home-manager switch --flake .#hetzner-sway` before committing. Manual testing of each provider will verify functionality per acceptance scenarios in spec.

### Principle VI - Declarative Configuration Over Imperative ✅
**Status**: PASS
**Rationale**: All provider configurations are declarative TOML/Nix expressions in the Walker home-manager module. No imperative scripts or post-install steps required. Walker/Elephant manage their own state files declaratively based on configuration.

### Principle VII - Documentation as Code ✅
**Status**: PASS (with deliverable)
**Deliverable**: quickstart.md will document all enabled providers with prefix reference table, usage examples, and common workflows. CLAUDE.md will be updated with provider summary in Walker section.

### Principle IX - Tiling Window Manager & Productivity Standards ✅
**Status**: PASS
**Rationale**: This feature enhances the existing keyboard-driven Walker launcher (already integrated with i3/Sway). All new providers use keyboard shortcuts and prefix-based activation, maintaining keyboard-first productivity focus.

### No Violations - No Complexity Justification Required

## Project Structure

### Documentation (this feature)

```
specs/050-enhance-the-walker/
├── spec.md              # Feature specification (already exists)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Walker provider documentation research
├── quickstart.md        # Phase 1 output - User-facing provider usage guide
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

Note: No data-model.md or contracts/ needed - this is a configuration-only feature with no new data models or APIs.

### Source Code (repository root)

```
home-modules/desktop/
└── walker.nix           # EXISTING FILE - will be modified to enable new providers

# Configuration structure within walker.nix:
xdg.configFile."walker/config.toml"     # Walker provider configuration
xdg.configFile."elephant/websearch.toml" # Web search engines (will be enhanced)
xdg.configFile."elephant/bookmarks.toml" # NEW - Bookmarks configuration
xdg.configFile."elephant/commands.toml"  # NEW - Custom commands configuration
xdg.configFile."elephant/todo.toml"      # NEW - Todo list configuration

# No new test files - testing via manual acceptance scenarios
```

**Structure Decision**: This is a configuration-only feature that modifies the existing Walker home-manager module. All changes are declarative configuration additions to `home-modules/desktop/walker.nix`. The module already follows NixOS/home-manager module conventions with xdg.configFile for Walker/Elephant configuration. No new source code, data models, or APIs are needed - only TOML configuration blocks to enable and configure the requested providers.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

No violations detected - Complexity Tracking table not needed.

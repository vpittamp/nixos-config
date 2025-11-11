# Implementation Plan: Unified Workspace Bar Icon System

**Branch**: `057-workspace-bar-icons` | **Date**: 2025-11-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/057-workspace-bar-icons/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement a unified icon lookup system that ensures workspace bar icons exactly match Walker launcher icons by using identical directory precedence, icon resolution logic, and XDG_DATA_DIRS configuration. The system will support regular applications, Firefox PWA icons, and terminal applications (Ghostty-launched like lazygit, yazi, btop) with high-quality rendering at 20×20 pixels. The workspace bar will display both workspace numbers and application icons in a visually unified design using the Catppuccin Mocha color palette.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing workspace_panel.py daemon)
**Primary Dependencies**:
- i3ipc (Sway IPC communication for window state)
- PyXDG (XDG Icon Theme Specification icon lookup via getIconPath())
- Eww (widget system for bar rendering)
**Storage**:
- JSON registries: `~/.config/i3/application-registry.json`, `~/.config/i3/pwa-registry.json`
- In-memory icon path cache (DesktopIconIndex class)
**Testing**: NEEDS CLARIFICATION (pytest for Python testing, sway-test framework for Eww bar integration testing?)
**Target Platform**: NixOS with Sway Wayland compositor (headless Hetzner Cloud + native M1 Mac)
**Project Type**: Single project (Python daemon + Nix configuration)
**Performance Goals**:
- Icon resolution: <50ms cached, <200ms initial lookup
- Workspace bar updates: <500ms from IPC event to icon display
- Real-time updates on window focus/creation (<100ms IPC event latency)
**Constraints**:
- Icon rendering: 20×20 pixels (configurable)
- Icon backgrounds: Transparent preferred (like Firefox, VS Code) over solid backgrounds (like ChatGPT, Claude with white)
- Memory: Icon cache <10MB for typical workload (~100 applications)
- CPU: <1% daemon overhead (event-driven, not polling)
**Scale/Scope**:
- ~100 applications in registry
- ~10 PWAs per user
- ~20 terminal applications
- 1-70 workspaces across 3 monitors (Hetzner) or 1 monitor (M1)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Modular Composition** | ✅ PASS | Changes localized to existing modules: `home-modules/tools/sway-workspace-panel/workspace_panel.py` (icon logic) and `home-modules/desktop/eww-workspace-bar.nix` (bar configuration). No code duplication. |
| **III. Test-Before-Apply** | ⚠️ PENDING | Must run `nixos-rebuild dry-build --flake .#hetzner-sway` and `#m1` before applying changes. |
| **VI. Declarative Configuration** | ✅ PASS | All icon configuration in Nix (XDG_DATA_DIRS, icon directories). No imperative scripts. |
| **VII. Documentation as Code** | ✅ PASS | quickstart.md created with icon lookup precedence, troubleshooting guide, and validation checklist. |
| **X. Python Development Standards** | ✅ PASS | Python 3.11+, async/await patterns already established in workspace_panel.py. Will add type hints for new icon logic. |
| **XI. i3 IPC Alignment** | ✅ PASS | Uses i3ipc for window state queries (authoritative source). Icon lookups based on app_id/window_class from Sway tree. |
| **XII. Forward-Only Development** | ✅ PASS | No backward compatibility needed - simply improving existing icon lookup logic without preserving old behavior. |
| **XIV. Test-Driven Development** | ✅ PASS | Hybrid testing strategy defined: pytest (Python unit tests) + sway-test (E2E integration). Tests will be written before implementation. |

**Post-Design Re-evaluation** (2025-11-10):
All constitution principles now passing. Critical paths resolved:
1. ✅ **Testing strategy**: Hybrid pytest + sway-test framework approach documented in research.md
2. ✅ **Icon lookup verification**: quickstart.md provides icon resolution traces and validation commands
3. ✅ **Terminal app detection**: Data model defines `expected_instance` field for terminal apps (lazygit, yazi, btop)

## Project Structure

### Documentation (this feature)

```text
specs/057-workspace-bar-icons/
├── spec.md              # Feature specification (already created)
├── checklists/
│   └── requirements.md  # Requirements checklist (already created)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (icon theme research, Walker analysis)
├── data-model.md        # Phase 1 output (IconIndex, IconResolutionCascade entities)
├── quickstart.md        # Phase 1 output (usage guide, troubleshooting)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Python daemon (existing, will be modified)
home-modules/tools/sway-workspace-panel/
├── workspace_panel.py           # Main daemon script
│   ├── DesktopIconIndex         # Icon lookup class (ENHANCE)
│   │   ├── _load_app_registry() # Already exists
│   │   ├── _load_pwa_registry() # Already exists
│   │   ├── _load_desktop_entries() # Already exists
│   │   └── _resolve_icon()      # Already exists (ENHANCE for terminal apps)
│   ├── build_workspace_payload() # Generate workspace data
│   └── pick_leaf()              # Select focused window
└── __init__.py                  # (if needed for testing)

# Eww bar configuration (existing, may need minor updates)
home-modules/desktop/
├── eww-workspace-bar.nix        # Eww bar definition
│   ├── workspace-button widget  # Icon display (already supports icon_path)
│   ├── workspacePanelCommand    # Daemon invocation
│   └── Environment XDG_DATA_DIRS # Icon theme directories (already configured)
└── walker.nix                   # Walker launcher config (reference only)

# Application registries (existing, no changes)
~/.config/i3/
├── application-registry.json    # Regular app icon mappings
└── pwa-registry.json            # PWA icon mappings

# Tests (to be created)
tests/057-workspace-bar-icons/
├── unit/
│   ├── test_icon_index.py       # Test DesktopIconIndex class
│   ├── test_icon_resolution.py  # Test _resolve_icon() logic
│   └── test_terminal_detection.py # Test Ghostty app detection
├── integration/
│   ├── test_walker_parity.json  # sway-test: Verify Walker/bar icon consistency
│   └── test_terminal_apps.json  # sway-test: Verify lazygit/yazi/btop icons
└── fixtures/
    └── mock_registries.json     # Test data
```

**Structure Decision**: Single project structure (Python daemon enhancements). This is primarily a refinement of existing `workspace_panel.py` icon lookup logic to ensure parity with Walker launcher. No new services or modules required - changes are localized to the existing DesktopIconIndex class and icon resolution cascade. Testing will use pytest for Python unit tests and sway-test framework for end-to-end icon display validation.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations detected.** This feature enhances existing icon lookup logic within established patterns (Python daemon, Nix configuration, i3ipc event handling). No new architectural complexity introduced.

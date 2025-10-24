# Implementation Plan: Unified Application Launcher with Project Context

**Branch**: `034-create-a-feature` | **Date**: 2025-10-24 | **Spec**: [/etc/nixos/specs/034-create-a-feature/spec.md](/etc/nixos/specs/034-create-a-feature/spec.md)
**Input**: Feature specification from `/specs/034-create-a-feature/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement a unified application launcher that consolidates fragmented launch mechanisms (rofi, fzf, bash scripts) into a single declarative registry system. The launcher will provide project-aware application launching with variable substitution, automatic desktop file generation via home-manager, and seamless integration with the i3pm daemon and window rules system. This eliminates the need for custom launch scripts, centralizes application configuration, and provides consistent behavior across GUI and CLI launch methods.

## Technical Context

**Language/Version**:
- Deno 1.40+ with TypeScript for CLI tools (per Constitution XIII)
- Nix expressions for home-manager integration and desktop file generation
- Bash for launcher wrapper script (variable substitution at runtime)

**Primary Dependencies**:
- Deno runtime with @std/cli/parse-args for CLI argument parsing
- i3pm daemon (Feature 015) for active project context queries
- rofi for unified launcher UI (GUI-focused with icon support)
- home-manager for declarative desktop file generation
- i3ipc for window management integration

**Storage**:
- JSON registry file at `~/.config/i3/application-registry.json` (declarative source of truth)
- Generated .desktop files in `~/.local/share/applications/` (managed by home-manager)
- Window rules in `~/.config/i3/window-rules.json` (augmented with registry entries)

**Testing**:
- Deno.test() for CLI command unit tests
- Manual integration testing for launcher UI behavior
- Validation testing for JSON schema and variable substitution
- End-to-end testing for project-aware launches

**Target Platform**:
- NixOS on Hetzner (i3wm + X11 + xrdp)
- NixOS on M1 Mac (i3wm + Wayland)
- WSL2 with limited GUI support

**Project Type**: Single project - CLI tools with system integration

**Performance Goals**:
- Launcher opens in <500ms from keybinding press
- Application launches complete in <3 seconds from selection
- CLI commands execute in <500ms
- Variable substitution overhead <100ms

**Constraints**:
- Must not break existing launch keybindings during migration
- Must support 70+ applications (current ~/.local/share/applications count)
- Must handle special characters and spaces in project paths
- Registry updates require home-manager rebuild (~30s rebuild time acceptable)

**Scale/Scope**:
- 10-15 core applications initially (VS Code, terminals, browsers, file managers)
- Expandable to 100+ applications without performance degradation
- 5-8 variable types for substitution (PROJECT_DIR, PROJECT_NAME, SESSION_NAME, WORKSPACE, etc.)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ I. Modular Composition
- Registry system will be implemented as a home-manager module in `home-modules/tools/app-launcher/`
- Desktop file generation will use home-manager's `xdg.desktopEntries` option
- Launcher wrapper script will be a separate module in `modules/services/app-launcher.nix`
- No code duplication - single source of truth in application-registry.json

### ✅ II. Reference Implementation Flexibility
- Feature will be validated on Hetzner (i3wm + X11) reference configuration first
- Testing on M1 (Wayland) and WSL2 to follow after Hetzner validation

### ✅ III. Test-Before-Apply
- All configuration changes will be tested with `nixos-rebuild dry-build --flake .#hetzner`
- CLI tool changes will be tested with `deno test` before rebuild

### ✅ IV. Override Priority Discipline
- Registry defaults will use `lib.mkDefault` for user overrides
- Desktop file paths will use normal priority
- No `lib.mkForce` expected unless conflicts arise

### ✅ V. Platform Flexibility Through Conditional Features
- Launcher will detect `config.services.xserver.enable` for GUI vs headless
- rofi will only be included on systems with X11/Wayland enabled
- CLI commands will work on all platforms regardless of GUI availability

### ✅ VI. Declarative Configuration Over Imperative
- Application registry is fully declarative JSON
- Desktop files generated via home-manager (no manual .desktop creation)
- Launcher wrapper script generated via `environment.etc` or home-manager

### ✅ VII. Documentation as Code
- Quickstart guide will be created in Phase 1
- Module header comments will document options and dependencies
- CLAUDE.md will be updated with launcher commands and workflow

### ✅ IX. Tiling Window Manager & Productivity Standards
- rofi integration maintains keyboard-first workflow
- Launcher keybinding (Win+D or custom) will be declaratively configured
- Integration with i3wsr for workspace awareness

### ✅ XIII. Deno CLI Development Standards
- CLI tool will use Deno 1.40+ with TypeScript
- `parseArgs()` from `@std/cli/parse-args` for argument parsing
- Compiled to standalone executable via `deno compile`
- Strict type checking enabled in deno.json

### ✅ XII. Forward-Only Development & Legacy Elimination
**Implementation Requirements** (per updated spec FR-031 to FR-034):
- **Complete removal in single commit**: All legacy launch scripts will be removed in the SAME commit that introduces the registry system
- **Files to remove**:
  - `launch-code.sh` (VS Code launcher)
  - `launch-ghostty.sh` (terminal launcher)
  - `launch-*.sh` (any other custom application launchers)
  - Check `~/.local/bin/` and `~/scripts/` for orphaned launchers
- **i3 keybindings**: Update all keybindings to reference new unified launcher, remove old script paths
- **No backwards compatibility**: No feature flags, no gradual migration, no dual-mode support
- **Documentation**: Commit message must list all removed legacy code for reference

**Success Criterion**: SC-009 verifies complete removal (zero launch-*.sh files, zero old keybinding patterns)

### ✅ XI. i3 IPC Alignment & State Authority
- Active project context will be queried from i3pm daemon (which uses i3 IPC)
- Window marking will use existing daemon event-driven system
- No parallel state tracking - daemon is authoritative

## Project Structure

### Documentation (this feature)

```
specs/034-create-a-feature/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── registry-schema.json     # JSON schema for application-registry.json
│   ├── cli-api.md               # i3pm apps subcommand specifications
│   └── launcher-protocol.md     # Launcher wrapper script interface
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
# Deno CLI Tool
home-modules/tools/app-launcher/
├── deno.json                # Deno configuration (tasks, imports, strict mode)
├── main.ts                  # Entry point with parseArgs() CLI handling
├── mod.ts                   # Public API exports
├── src/
│   ├── commands/
│   │   ├── list.ts         # i3pm apps list
│   │   ├── launch.ts       # i3pm apps launch <name>
│   │   ├── info.ts         # i3pm apps info <name>
│   │   ├── edit.ts         # i3pm apps edit
│   │   └── validate.ts     # i3pm apps validate
│   ├── models.ts            # Type definitions for registry entries
│   ├── registry.ts          # Registry loading and validation
│   ├── variables.ts         # Variable substitution logic
│   └── daemon-client.ts     # i3pm daemon IPC client
└── README.md

# NixOS/home-manager Integration
home-modules/tools/app-launcher.nix    # Home-manager module for CLI tool
modules/services/app-launcher.nix      # System module for launcher wrapper script

# Configuration
home-modules/desktop/app-registry.nix  # Declarative application registry definitions
home-modules/desktop/i3-launcher.nix   # i3 keybinding and rofi configuration

# Scripts
scripts/app-launcher-wrapper.sh        # Generated wrapper for desktop file Exec lines

# Tests
tests/app-launcher/
├── unit/
│   ├── registry_test.ts
│   ├── variables_test.ts
│   └── validation_test.ts
└── integration/
    └── launch_workflow_test.ts
```

**Structure Decision**: Single project structure chosen because this is a CLI tool with system integration, not a web or mobile application. The Deno CLI tool lives in `home-modules/tools/` following the pattern established for other user-facing tools. System integration modules live in `modules/services/` and `home-modules/desktop/` following existing NixOS patterns.

## Complexity Tracking

*No violations requiring justification - feature aligns with all constitution principles.*

## Phase 0: Research & Unknowns

### Research Tasks

1. **rofi vs fzf for unified launcher**
   - Research: rofi's desktop file integration capabilities
   - Research: rofi's icon display and theming support
   - Research: fzf's limitations with .desktop files
   - Decision criteria: Native XDG support, icon display, theme consistency

2. **home-manager desktop file generation patterns**
   - Research: `xdg.desktopEntries` option usage and capabilities
   - Research: How to parameterize Exec lines with wrapper scripts
   - Research: Desktop file precedence and conflict resolution
   - Best practices: Avoiding conflicts with system-provided .desktop files

3. **Variable substitution implementation**
   - Research: Bash parameter expansion patterns for robust escaping
   - Research: Security implications of variable substitution (command injection risks)
   - Best practices: Quoting and escaping special characters in paths
   - Research: How other application launchers handle parameterization

4. **i3pm daemon project context query API**
   - Research: Current `i3pm project current` output format
   - Research: JSON-RPC API endpoints for project queries
   - Verify: Project directory, name, and session name availability
   - Document: Expected response format and error states

5. **Window rules automatic generation**
   - Research: Current window-rules.json schema and priority system
   - Research: home-manager support for merging JSON configurations
   - Best practices: Preserving manual rules while generating from registry
   - Decision: Generation strategy (merge at build time vs daemon-side updates)

6. **Desktop file wrapper script architecture**
   - Research: How to invoke a wrapper script transparently from .desktop Exec lines
   - Research: Environment variable propagation to launched applications
   - Best practices: Error handling and user notification for launch failures
   - Decision: Script location and generation method

7. **Deno compilation and NixOS packaging**
   - Research: `deno compile` best practices for standalone executables
   - Research: NixOS derivation patterns for Deno applications
   - Research: Permission flags needed for i3pm daemon communication
   - Best practices: Binary size optimization and dependency bundling

### Output: research.md

Research findings will be consolidated into `/etc/nixos/specs/034-create-a-feature/research.md` with sections for each task above, including:
- Final decision with rationale
- Alternatives considered and why rejected
- Code examples or configuration snippets
- References to documentation or prior art

## Phase 1: Design & Contracts

### Data Model (data-model.md)

**Entities to document**:

1. **ApplicationRegistryEntry**
   - Fields: name, display_name, command, parameters, scope, expected_class, preferred_workspace, icon, nix_package, multi_instance, fallback_behavior
   - Validation rules: Unique names, valid scope enum, workspace 1-9
   - Relationships: Maps to DesktopFile (1:1), WindowRule (optional 1:1)

2. **VariableContext**
   - Fields: project_name, project_dir, session_name, workspace, user_home
   - Source: Queried from i3pm daemon or environment
   - State transitions: Active project → global mode, project switch

3. **DesktopFile** (generated artifact)
   - Fields: file_path, name, exec_command, icon, categories, startup_wm_class
   - Generation: From ApplicationRegistryEntry via home-manager
   - Lifecycle: Created on rebuild, removed when registry entry deleted

4. **LaunchCommand** (runtime state)
   - Fields: template, resolved_command, project_context_snapshot, timestamp
   - Lifecycle: Created at launch time, logged for debugging

### API Contracts (contracts/)

**1. registry-schema.json** - JSON Schema for application-registry.json
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["name", "display_name", "command"],
    "properties": {
      "name": {"type": "string", "pattern": "^[a-z0-9-]+$"},
      "display_name": {"type": "string"},
      "command": {"type": "string"},
      "parameters": {"type": "string"},
      "scope": {"enum": ["scoped", "global"]},
      "expected_class": {"type": "string"},
      "preferred_workspace": {"type": "integer", "minimum": 1, "maximum": 9},
      "icon": {"type": "string"},
      "nix_package": {"type": "string"},
      "multi_instance": {"type": "boolean"},
      "fallback_behavior": {"enum": ["skip", "use_home", "error"]}
    }
  }
}
```

**2. cli-api.md** - i3pm apps subcommand specifications
- `i3pm apps list [--format=table|json]`
- `i3pm apps launch <name> [--dry-run]`
- `i3pm apps info <name>`
- `i3pm apps edit`
- `i3pm apps validate [--fix]`

**3. launcher-protocol.md** - Launcher wrapper script interface
- Input: Application name, optional arguments
- Process: Query daemon, substitute variables, execute command
- Output: Exit codes, error messages, launch logs
- Error handling: Missing project, failed variable resolution, command not found

### Quickstart Guide (quickstart.md)

**Sections**:
1. Adding a new application to the registry
2. Launching applications from rofi
3. Launching applications from CLI
4. Debugging failed launches
5. Migrating existing launch scripts to registry

### Agent Context Update

After generating design artifacts, run:
```bash
.specify/scripts/bash/update-agent-context.sh claude
```

This will update `.specify/memory/claude-context.md` with:
- Deno as CLI tool technology
- rofi as unified launcher
- Application registry system overview
- Integration points with i3pm daemon

**Re-evaluate Constitution Check**: After design is complete, verify no new complexity or violations were introduced.

## Phase 2: Tasks Generation

**NOT INCLUDED IN THIS COMMAND** - Will be generated by `/speckit.tasks` command.

The tasks.md file will contain dependency-ordered implementation tasks generated from:
- Phase 0 research decisions
- Phase 1 data model and contracts
- Functional requirements from spec.md
- Constitution compliance requirements

## Stop and Report

Implementation plan complete. Next steps:

1. ✅ Generated implementation plan at `/etc/nixos/specs/034-create-a-feature/plan.md`
2. ⏳ Run Phase 0 research to generate `research.md`
3. ⏳ Run Phase 1 design to generate `data-model.md`, `contracts/`, `quickstart.md`
4. ⏳ Run agent context update script
5. ⏳ Execute `/speckit.tasks` command to generate `tasks.md`

**Branch**: `034-create-a-feature`
**Next Command**: Continue with Phase 0 research tasks as outlined above

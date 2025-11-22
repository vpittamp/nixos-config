# Implementation Plan: Remote Project Environment Support

**Branch**: `087-ssh-projects` | **Date**: 2025-11-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/home/vpittamp/nixos-087-ssh-projects/specs/087-ssh-projects/spec.md`

## Summary

This feature extends the i3pm project management system to support remote development environments via SSH. Users will be able to create projects that map local directories to remote hosts (Hetzner Cloud, other Tailscale-connected systems), with terminal-based applications automatically launching on the remote host via SSH wrapping. The implementation extends the existing Python 3.11+ Pydantic-based Project model, enhances the Bash app-launcher-wrapper.sh with SSH command construction, and adds TypeScript/Deno CLI commands for remote project lifecycle management.

## Technical Context

**Language/Version**: Python 3.11+ (daemon/models), Bash 5.0+ (launcher), TypeScript/Deno 1.40+ (CLI)
**Primary Dependencies**:
- Python: Pydantic 2.x (data validation), i3ipc.aio (Sway IPC), asyncio (event handling)
- Bash: jq (JSON parsing), systemd-run (process isolation)
- Deno: @std/cli/parse-args (CLI parsing), Zod 3.22+ (validation)
- System: openssh client (SSH connectivity), Tailscale (VPN networking)

**Storage**: JSON files in `~/.config/i3/projects/*.json` (Project definitions with optional remote field)
**Testing**:
- Python: pytest with pytest-asyncio for async tests
- Deno: Deno.test() for CLI command validation
- Sway: sway-test framework for window manager integration tests

**Target Platform**: NixOS (M1 MacBook Pro via Asahi Linux, Hetzner Cloud x86_64)
**Project Type**: Single project - extending existing i3pm system (no new microservices)

**Performance Goals**:
- Remote terminal launch: <3 seconds total (1-2s SSH connection + <1s command execution)
- SSH command wrapping: <10ms computation overhead
- Project switch with remote validation: <100ms (excluding network I/O)

**Constraints**:
- SSH connection establishment: 1-3s depending on Tailscale routing and network latency
- Terminal-only limitation: GUI apps cannot be launched remotely (requires X11 forwarding out of scope)
- SSH key authentication required: No password authentication support

**Scale/Scope**:
- Expected remote projects: 3-5 per user (Hetzner development environments)
- Terminal applications supported: 7 (terminal/ghostty, lazygit, yazi, btop, htop, k9s, sesh)
- CLI commands added: 4 (create-remote, set-remote, unset-remote, test-remote)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

✅ **I. Modular Composition**
- Extends existing modules (`models/project.py`, `app-launcher-wrapper.sh`) rather than creating duplicates
- No code duplication - single source implementation for remote SSH wrapping logic

✅ **III. Test-Before-Apply (NON-NEGOTIABLE)**
- Will test Python model changes with `pytest tests/`
- Will test Bash wrapper logic via sway-test framework integration tests
- Will validate against dry-build before committing

✅ **VI. Declarative Configuration Over Imperative**
- Remote configuration stored in JSON (declarative)
- No imperative post-install scripts
- SSH wrapping logic encapsulated in launcher wrapper (execution-time, not configuration-time)

✅ **VII. Documentation as Code**
- Quickstart guide (Phase 1 deliverable)
- Inline code comments for SSH command construction
- CLAUDE.md updated with remote project workflow

✅ **X. Python Development & Testing Standards**
- Python 3.11+ (matches existing i3pm daemon standard)
- Pydantic models for remote configuration validation
- pytest with pytest-asyncio for async tests
- Type hints for all new functions

✅ **XI. i3 IPC Alignment & State Authority**
- No changes to i3/Sway IPC interaction
- Daemon state remains authoritative for project context
- Remote projects validated against SSH connectivity, not i3 state

✅ **XII. Forward-Only Development & Legacy Elimination**
- Backward compatible extension (remote field is optional)
- No legacy code paths - remote logic integrated directly into existing flow
- No feature flags or dual support modes

✅ **XIII. Deno CLI Development Standards**
- New CLI commands use TypeScript/Deno runtime 1.40+
- Uses `parseArgs()` from `@std/cli/parse-args` for argument parsing
- Compiled to standalone executables via `deno compile`

✅ **XIV. Test-Driven Development & Autonomous Testing**
- Will write tests before implementing SSH wrapping logic
- Integration tests for SSH command construction and validation
- End-to-end tests for remote terminal launch workflow

✅ **XV. Sway Test Framework Standards**
- Will use sway-test for window manager integration testing
- Partial mode assertions for window launch and workspace assignment
- Declarative JSON test definitions for terminal app launches

### Gates Evaluation

**PASS** - No constitutional violations identified

- **Modular Composition**: Extends 2 existing files (project.py, app-launcher-wrapper.sh) and adds 4 CLI commands in existing i3pm CLI structure
- **Test Standards**: Follows pytest (Python), Deno.test (TypeScript), sway-test (integration) requirements
- **IPC Alignment**: No changes to Sway IPC interaction patterns
- **Forward-Only**: Backward compatible, no legacy preservation required

## Project Structure

### Documentation (this feature)

```text
specs/087-ssh-projects/
├── plan.md              # This file (/speckit.plan command output)
├── spec.md              # Feature specification (already created)
├── research.md          # Phase 0 output (SSH command construction patterns, validation)
├── data-model.md        # Phase 1 output (RemoteConfig, Project extensions)
├── quickstart.md        # Phase 1 output (User guide for remote projects)
├── contracts/           # Phase 1 output (CLI command schemas)
│   ├── create-remote.schema.json
│   ├── set-remote.schema.json
│   ├── unset-remote.schema.json
│   └── test-remote.schema.json
└── checklists/
    └── requirements.md  # Spec quality checklist (already created)
```

### Source Code (repository root)

```text
# Python daemon models (extend existing)
home-modules/desktop/i3-project-event-daemon/
├── models/
│   ├── project.py           # ADD: RemoteConfig model, extend Project with optional remote field
│   └── __init__.py          # UPDATE: Export RemoteConfig

# Bash launcher wrapper (extend existing)
scripts/
└── app-launcher-wrapper.sh  # ADD: Remote detection, SSH wrapping logic (lines 200-280)

# TypeScript/Deno CLI (extend existing)
home-modules/tools/i3pm-cli/
├── src/
│   ├── commands/
│   │   └── project/
│   │       ├── create-remote.ts    # NEW: Create remote project
│   │       ├── set-remote.ts       # NEW: Add remote config to existing project
│   │       ├── unset-remote.ts     # NEW: Remove remote config
│   │       └── test-remote.ts      # NEW: Test SSH connectivity
│   ├── models/
│   │   └── remote-config.ts        # NEW: TypeScript interface for RemoteConfig
│   └── services/
│       ├── ssh-client.ts           # NEW: SSH connectivity testing helper
│       └── project-service.ts      # UPDATE: Add remote project operations
├── main.ts                         # UPDATE: Register new subcommands
└── deno.json                       # UPDATE: Add test tasks

# Tests
tests/087-ssh-projects/
├── unit/
│   ├── test_remote_config_validation.py  # Test Pydantic RemoteConfig validation
│   └── test_ssh_command_construction.sh  # Test Bash SSH wrapping logic
├── integration/
│   ├── test_remote_project_creation.py   # Test CLI create-remote command
│   ├── test_remote_app_launch.py         # Test app-launcher-wrapper SSH execution
│   └── test_ssh_connectivity.py          # Test SSH connection validation
└── sway-tests/
    ├── test_remote_terminal_launch.json  # Sway test: Terminal launches on remote host
    └── test_remote_lazygit_launch.json   # Sway test: Lazygit launches on remote host
```

**Structure Decision**: Extends existing single-project i3pm architecture rather than creating new microservices. Remote support is implemented as:
1. **Data model extension** (Python Pydantic)
2. **Launcher wrapper enhancement** (Bash SSH wrapping)
3. **CLI command additions** (TypeScript/Deno subcommands)

This approach maintains consistency with existing i3pm patterns and avoids architectural fragmentation.

## Complexity Tracking

> **No complexity justification required** - This feature extends existing architecture without introducing new abstraction layers, deep inheritance hierarchies, or additional platform targets. All changes follow established patterns (Pydantic models, Bash launcher, Deno CLI commands).

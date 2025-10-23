# Implementation Plan: i3pm Production Readiness

**Branch**: `030-review-our-i3pm` | **Date**: 2025-10-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/030-review-our-i3pm/spec.md`

## Summary

Bring i3pm (i3 Project Manager) from 80% to 100% production-ready by implementing:
1. **Workspace Layout Persistence** - Save/restore window layouts across sessions
2. **Error Recovery** - Automatic state rebuilding after daemon/i3 restarts
3. **Production Validation** - Load testing, performance monitoring, security audit
4. **Complete Workspace Mapping** - 1:1 application-to-workspace mapping for all 70 configured applications (FR-014a)
5. **User Onboarding** - Interactive wizards, doctor command, documentation

**Current Status**: Core event-driven architecture complete (Features 010-029), workspace mapping 37% complete (26/70 apps)

## Technical Context

**Language/Version**: Python 3.13 (daemon), Deno 2.0/TypeScript 5.0 (CLI)
**Primary Dependencies**: i3ipc (i3 communication), Pydantic (data validation), systemd-python (daemon integration)
**Storage**: JSON files (`~/.config/i3/`), event history (`~/.local/share/i3pm/`)
**Testing**: pytest + pytest-asyncio (Python), Deno test (TypeScript)
**Target Platform**: Linux with i3 window manager, NixOS deployment
**Project Type**: System daemon + CLI tool (dual codebase)
**Performance Goals**: <100ms window switching, <500ms project switching, <5% CPU overhead
**Constraints**: <100MB memory (daemon), <2s monitor reassignment, systemd watchdog compliance
**Scale/Scope**:
- 70 applications with unique workspace assignments (1:1 mapping, FR-014a)
- 500+ window production testing
- 10+ projects per user
- Multi-monitor support (1-4 monitors)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

[Gates determined based on constitution file]

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
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |

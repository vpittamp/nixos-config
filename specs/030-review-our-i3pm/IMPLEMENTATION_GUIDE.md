# i3pm Production Readiness - Implementation Guide

**Feature**: 030-review-our-i3pm
**Date**: 2025-10-23
**Status**: Phase 1 Complete ✅ - Ready for Phase 2
**Strategy**: MVP-First (50 tasks → Full Production)

---

## 🎯 Executive Summary

Phase 1 (Setup) is **COMPLETE**. The development environment is ready for foundational implementation.

**What's Done**:
- ✅ Test dependencies added to NixOS configuration
- ✅ Test directory structure created
- ✅ Test environment tooling (conftest.py, run_tests.sh)
- ✅ Daemon verified running (PID 3057825)
- ✅ Configuration rebuild applied

**Next Steps**: Begin Phase 2 (Foundational - 17 tasks) to build core infrastructure

---

## 📊 Progress Dashboard

### Phase Completion

| Phase | Tasks | Status | Completion |
|-------|-------|--------|------------|
| Phase 1: Setup | 5 | ✅ DONE | 100% (5/5) |
| Phase 2: Foundational | 17 | ⏳ NEXT | 0% (0/17) |
| Phase 3: US1 Reliability | 7 | 📋 PLANNED | 0% (0/7) |
| Phase 4: US2 Layout Persistence | 21 | 📋 PLANNED | 0% (0/21) |
| **MVP Total** | **50** | **10% COMPLETE** | **5/50 tasks** |

### Overall Feature Progress

- **Total Tasks**: 118 tasks
- **Completed**: 5 tasks (4.2%)
- **In Progress**: Phase 1 → Phase 2 transition
- **Remaining**: 113 tasks

---

## 🚀 Quick Start: Continue Implementation

### Option A: Continue with Claude Code (Recommended)

```bash
# Let Claude continue with Phase 2
# Just respond: "continue with phase 2"
```

Claude will implement the 17 foundational tasks automatically.

### Option B: Manual Implementation

Follow the detailed phase breakdown below to implement tasks yourself.

---

## 📋 Phase 2: Foundational Tasks (NEXT - 17 tasks)

**Purpose**: Core infrastructure that BLOCKS all user stories
**Estimated Time**: 3-4 hours
**Critical**: Must complete before ANY user story work

### Subsection 1: Core Data Models (3 tasks)

#### T006 [P] - Pydantic Data Models
**File**: `home-modules/desktop/i3-project-event-daemon/layout/models.py`

Create new module directory:
```bash
mkdir -p home-modules/desktop/i3-project-event-daemon/layout
touch home-modules/desktop/i3-project-event-daemon/layout/__init__.py
```

Implement models from `specs/030-review-our-i3pm/data-model.md`:
- Project
- Window, WindowGeometry
- WindowPlaceholder
- LayoutSnapshot
- WorkspaceLayout, Container
- Monitor, MonitorConfiguration
- Event
- ClassificationRule

**Reference**: Lines 15-718 in data-model.md

#### T007 [P] - TypeScript Interfaces
**File**: `home-modules/tools/i3pm-deno/src/models.ts`

Mirror the Pydantic models in TypeScript.

#### T008 [P] - Data Model Tests
**File**: `tests/i3pm-production/unit/test_data_models.py`

Test Pydantic validation:
```python
def test_project_validation():
    """Test Project model validation"""
    from i3_project_daemon.layout.models import Project

    # Valid project
    project = Project(
        name="test-project",
        display_name="Test",
        directory="/tmp/test"
    )
    assert project.name == "test-project"

    # Invalid name (uppercase)
    with pytest.raises(ValidationError):
        Project(name="Invalid-Name", ...)
```

### Subsection 2: Security Infrastructure (4 tasks)

#### T009 [P] - IPC Authentication
**File**: `home-modules/desktop/i3-project-event-daemon/security/auth.py`

```bash
mkdir -p home-modules/desktop/i3-project-event-daemon/security
touch home-modules/desktop/i3-project-event-daemon/security/__init__.py
```

Implement UID-based authentication via SO_PEERCRED (research.md Decision 6):

```python
import socket
import struct
import os

def authenticate_client(sock: socket.socket) -> bool:
    """Authenticate IPC client via UID check"""
    creds = sock.getsockopt(
        socket.SOL_SOCKET,
        socket.SO_PEERCRED,
        struct.calcsize('3i')
    )
    pid, uid, gid = struct.unpack('3i', creds)

    if uid != os.getuid():
        raise PermissionError(f"UID mismatch: {uid} != {os.getuid()}")

    return True
```

#### T010 [P] - Sensitive Data Sanitization
**File**: `home-modules/desktop/i3-project-event-daemon/security/sanitize.py`

Implement regex-based sanitization (research.md Decision 7):

```python
import re

SANITIZE_PATTERNS = [
    (r'(api[_-]?key|token|secret)[=:\s]+[A-Za-z0-9_-]{20,}', 'API_KEY_REDACTED'),
    (r'Bearer\s+[A-Za-z0-9_-]{20,}', 'BEARER_TOKEN_REDACTED'),
    (r'(password|passwd|pwd)[=:\s]+\S+', 'PASSWORD_REDACTED'),
    # ... more patterns from research.md lines 388-413
]

def sanitize_text(text: str) -> str:
    """Remove sensitive patterns"""
    for pattern, replacement in SANITIZE_PATTERNS:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text
```

#### T011 [P] - Auth Tests
**File**: `tests/i3pm-production/unit/test_ipc_auth.py`

#### T012 [P] - Sanitization Tests
**File**: `tests/i3pm-production/unit/test_sanitization.py`

### Subsection 3: Monitoring Infrastructure (3 tasks)

#### T013 [P] - Health Metrics
**File**: `home-modules/desktop/i3-project-event-daemon/monitoring/health.py`

```bash
mkdir -p home-modules/desktop/i3-project-event-daemon/monitoring
touch home-modules/desktop/i3-project-event-daemon/monitoring/__init__.py
```

Track: uptime, memory, event counts, error rate, last successful operation

#### T014 [P] - Performance Metrics
**File**: `home-modules/desktop/i3-project-event-daemon/monitoring/metrics.py`

Track: switch latency, window marking latency, event processing time

#### T015 [P] - Diagnostic Snapshots
**File**: `home-modules/desktop/i3-project-event-daemon/monitoring/diagnostics.py`

Generate complete diagnostic reports (daemon state, window tree, events, config)

### Subsection 4: Daemon IPC Protocol (1 task)

#### T016 - Update Daemon IPC
**File**: `home-modules/desktop/i3-project-event-daemon/ipc_server.py`

Add new JSON-RPC methods from `specs/030-review-our-i3pm/contracts/daemon-ipc.json`:
- `daemon.status`
- `daemon.events` (with filtering)
- `daemon.diagnose`
- `layout.save`
- `layout.restore`

### Subsection 5: Event Buffer Persistence (3 tasks)

#### T017 - Event Persistence on Shutdown
**File**: `home-modules/desktop/i3-project-event-daemon/event_buffer.py` (extend existing)

Persist to: `~/.local/share/i3pm/event-history/`

#### T018 - Event Loading with Pruning
**File**: Same file as T017

7-day retention (research.md Decision 2)

#### T019 [P] - Event Persistence Tests
**File**: `tests/i3pm-production/unit/test_event_persistence.py`

### Subsection 6: Test Fixtures (3 tasks)

#### T020 [P] - Mock i3 IPC
**File**: `tests/i3pm-production/fixtures/mock_i3.py`

Mock i3ipc.Connection for isolated testing

#### T021 [P] - Sample Layouts
**File**: `tests/i3pm-production/fixtures/sample_layouts.py`

Fixture layouts from layout-format.json examples

#### T022 [P] - Load Profiles
**File**: `tests/i3pm-production/fixtures/load_profiles.py`

Profiles for 50, 100, 500 window tests

---

## 🎯 Phase 3: User Story 1 - Reliability (7 tasks)

**Blocked By**: Phase 2 completion
**Purpose**: Error recovery and automatic state rebuilding

### Key Files to Create

1. **Recovery Module** (3 tasks)
   - `home-modules/desktop/i3-project-event-daemon/recovery/state_validator.py`
   - `home-modules/desktop/i3-project-event-daemon/recovery/recovery.py`
   - Integration with daemon startup

2. **Tests** (3 tasks)
   - `tests/i3pm-production/integration/test_daemon_recovery.py`
   - `tests/i3pm-production/scenarios/test_error_recovery.py`
   - `tests/i3pm-production/scenarios/test_production_scale.py`

**Deliverable**: System recovers from crashes/restarts within 5 seconds

---

## 🎯 Phase 4: User Story 2 - Layout Persistence (21 tasks)

**Blocked By**: Phase 2 completion
**Purpose**: Save and restore workspace layouts

### Key Modules

1. **Layout Capture** (3 tasks)
   - Capture via i3 GET_TREE
   - Launch command discovery (desktop files → proc cmdline)
   - Serialization to i3 JSON format

2. **Layout Restore** (3 tasks)
   - Load from JSON
   - i3 append_layout execution
   - Window swallow monitoring

3. **Monitor Adaptation** (3 tasks)
   - Detect current monitor config
   - Workspace reassignment logic
   - Validation

4. **Deno CLI Commands** (5 tasks)
   - `i3pm layout save`
   - `i3pm layout restore`
   - `i3pm layout list`
   - `i3pm layout diff`
   - Progress indicators

5. **Tests** (5 tasks)
   - Unit tests for capture/restore/discovery
   - Integration test for full save/restore cycle
   - Scenario test for complex layouts (15 windows)

**Deliverable**: Complete layout save/restore with 95% accuracy, <5s restore time

---

## 🧪 Running Tests

### Quick Test
```bash
cd /etc/nixos
./tests/i3pm-production/run_tests.sh
```

### With Coverage
```bash
COVERAGE=1 ./tests/i3pm-production/run_tests.sh
```

### Specific Test File
```bash
./tests/i3pm-production/run_tests.sh tests/i3pm-production/unit/test_data_models.py
```

### Manual pytest
```bash
source tests/i3pm-production/.venv/bin/activate
pytest tests/i3pm-production -v
```

---

## 📁 File Structure Reference

### Actual Paths (Use These!)

```
home-modules/desktop/i3-project-event-daemon/   # Python daemon (NOT tools/i3-project-daemon)
├── daemon.py                                    # Main daemon
├── ipc_server.py                                # JSON-RPC server
├── event_buffer.py                              # Event buffer
├── models.py                                    # Existing models
├── layout/                                      # NEW: T006
│   ├── __init__.py
│   ├── models.py                                # Layout data models
│   ├── capture.py                               # NEW: T030
│   ├── restore.py                               # NEW: T034
│   └── discovery.py                             # NEW: T031
├── security/                                    # NEW: T009-010
│   ├── __init__.py
│   ├── auth.py
│   └── sanitize.py
├── monitoring/                                  # NEW: T013-015
│   ├── __init__.py
│   ├── health.py
│   ├── metrics.py
│   └── diagnostics.py
└── recovery/                                    # NEW: T023-024
    ├── __init__.py
    ├── state_validator.py
    └── recovery.py

home-modules/tools/i3pm-deno/                    # Deno CLI (NOT i3pm-cli)
├── src/
│   ├── models.ts                                # NEW: T007
│   ├── commands/
│   │   ├── layout.ts                            # NEW: T041-044
│   │   └── daemon.ts                            # Extend: T054-056
│   └── ui/
│       └── progress.ts                          # NEW: T045

tests/i3pm-production/                           # Test suite
├── conftest.py                                  # ✅ Created
├── run_tests.sh                                 # ✅ Created
├── unit/                                        # T008, T011, T012, T019, T046-048
├── integration/                                 # T027, T049, T072, T076-077
├── scenarios/                                   # T028-029, T050, T064-069
└── fixtures/                                    # T020-022
```

---

## 🔧 Development Tools

### Daemon Control
```bash
# Status
systemctl --user status i3-project-event-listener

# Restart (after code changes)
systemctl --user restart i3-project-event-listener

# Logs
journalctl --user -u i3-project-event-listener -f

# Check Python environment
systemctl --user show i3-project-event-listener -p ExecStart --value
```

### Daemon Queries (via i3pm CLI)
```bash
# Current implementation (works now)
i3pm daemon status
i3pm daemon events --limit=20
i3pm windows --tree
i3pm project list

# NEW commands (to be implemented)
i3pm layout save --name=daily-dev
i3pm layout restore --name=daily-dev
i3pm layout list
i3pm daemon diagnose --output=report.json
```

### NixOS Rebuild
```bash
# Test configuration
sudo nixos-rebuild dry-build --flake .#hetzner

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner

# Rebuild with changes
sudo nixos-rebuild switch --flake .#hetzner --rebuild
```

---

## 📚 Reference Documents

All documents in `specs/030-review-our-i3pm/`:

1. **spec.md** - 42 functional requirements, 6 user stories, 12 success criteria
2. **plan.md** - Tech stack, architecture, file structure, constitution check
3. **research.md** - 7 key technical decisions with rationale
4. **data-model.md** - Complete Pydantic models and TypeScript interfaces
5. **contracts/daemon-ipc.json** - JSON-RPC protocol specification
6. **contracts/layout-format.json** - i3 layout snapshot schema
7. **quickstart.md** - Step-by-step implementation walkthrough
8. **tasks.md** - 118 tasks with dependencies and parallel markers
9. **IMPLEMENTATION_STATUS.md** - Current progress and status
10. **IMPLEMENTATION_GUIDE.md** - This document

---

## ⚠️ Critical Reminders

### 1. Forward-Only Development (Constitution Principle XII)

**CRITICAL**: When implementation is complete, Phase 9 (Legacy Elimination) MUST happen in the SAME commit as new features.

Delete these files:
- `home-modules/tools/i3-project-manager/` (15,445 LOC) - entire directory
- Remove imports from `home-modules/tools/default.nix`
- Remove deprecated shell aliases

**NO backwards compatibility, NO migration period, NO dual code paths.**

### 2. Path Corrections

Plan.md shows **aspirational paths**. Use **actual paths**:
- ❌ `home-modules/tools/i3-project-daemon/`
- ✅ `home-modules/desktop/i3-project-event-daemon/`

- ❌ `home-modules/tools/i3pm-cli/`
- ✅ `home-modules/tools/i3pm-deno/`

### 3. Test Before Commit

```bash
# ALWAYS run before committing
./tests/i3pm-production/run_tests.sh

# Target: 80%+ coverage
COVERAGE=1 ./tests/i3pm-production/run_tests.sh
```

### 4. Daemon Restart After Changes

```bash
# Code changes require restart
systemctl --user restart i3-project-event-listener

# Verify it restarted successfully
systemctl --user status i3-project-event-listener
```

---

## 🎯 Success Criteria (MVP)

From spec.md, these apply to MVP scope (US1 + US2):

- ✅ **SC-010**: Daemon recovery <5s (US1)
- ✅ **SC-011**: Clear error messages (US1)
- ✅ **SC-003**: Layout restore 95% accuracy (US2)
- ✅ **SC-004**: No flicker during restore (US2)

---

## 🚀 Next Action

To continue with Phase 2:

```
continue with phase 2
```

Or implement manually using this guide.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-23 12:00 EDT
**Status**: Phase 1 Complete, Ready for Phase 2
**Contact**: See CLAUDE.md for additional guidance

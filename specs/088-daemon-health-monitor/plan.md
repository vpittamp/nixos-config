# Implementation Plan: Daemon Health Monitoring System

**Branch**: `088-daemon-health-monitor` | **Date**: 2025-11-22 | **Spec**: [spec.md](spec.md)

## Summary

Implement centralized daemon health monitoring in the Eww monitoring panel's Health tab to provide visual status indicators for all critical NixOS/home-manager services. Users will be able to quickly identify failed services after rebuilds/reboots and restart them with one-click actions. The system enhances the existing `monitoring_data.py --mode health` infrastructure with comprehensive service queries via systemctl, categorized health indicators (Core Daemons, UI Services, System Services, Optional Services), and service restart capabilities with sudo handling.

## Technical Context

**Language/Version**: Python 3.11+ (existing daemon standard per Constitution Principle X)

**Primary Dependencies**:
- `subprocess` module for systemctl queries (system service status, user service status)
- Existing `monitoring_data.py` health query infrastructure (Feature 085)
- Eww 0.4+ (GTK3 widgets for Health tab UI)
- systemd (service manager - NixOS standard)

**Storage**:
- Service health state: In-memory query results (5s refresh via defpoll)
- Service registry: Hardcoded Python dict in monitoring_data.py (Core/UI/System/Optional categories)
- Monitor profile state: `~/.config/sway/monitor-profile.current` (for conditional service detection)

**Testing**: pytest with subprocess mocking for systemctl command validation, Eww widget rendering tests via visual inspection

**Target Platform**: NixOS (Hetzner Sway headless, M1 Apple Silicon hybrid mode)

**Project Type**: Single Python module enhancement (existing monitoring_data.py) + Eww widget updates

**Performance Goals**:
- <3s to query all service health states (total systemctl query time)
- 5s defpoll refresh interval (existing infrastructure)
- <100ms UI render time for health indicators

**Constraints**:
- Must use existing defpoll mechanism (no new event-driven system)
- Must detect socket-activated services (i3-project-daemon.socket) correctly
- Must differentiate system vs user services for restart actions
- Must handle conditionally-enabled services (WayVNC disabled in local-only mode)

**Scale/Scope**:
- Monitor ~17 critical services across 4 categories
- Support 2 platforms (Hetzner headless, M1 hybrid) with mode-dependent service lists
- Provide restart actions for user services (no sudo) and system services (with sudo prompt)

## Constitution Check

### ✅ APPROVED - All Principles Pass

- ✅ Principle I (Modular Composition): Enhances existing module
- ✅ Principle III (Test-Before-Apply): Will use dry-build
- ✅ Principle VI (Declarative Configuration): Service registry declarative
- ✅ Principle X (Python Standards): Python 3.11+, pytest, subprocess
- ✅ Principle XI (IPC Alignment): Systemd as authoritative source
- ✅ Principle XII (Forward-Only): Removes legacy services
- ✅ Principle XIV (Test-Driven): Tests before implementation

No violations. Ready for implementation.

## Project Structure

### Documentation

```
specs/088-daemon-health-monitor/
├── plan.md                            # This file
├── research.md                        # ✅ Complete
├── data-model.md                      # ✅ Complete
├── quickstart.md                      # ✅ Complete
├── contracts/                         # Schema documentation
├── checklists/requirements.md         # ✅ Complete
└── tasks.md                           # Phase 2 (not created yet)
```

### Source Code

```
home-modules/tools/i3_project_manager/cli/
├── monitoring_data.py              # Enhanced query_health_data() function
└── README.md                       # Updated documentation

home-modules/desktop/
└── eww-monitoring-panel.nix        # Enhanced Health tab UI

tests/088-daemon-health-monitor/
├── unit/test_service_health_query.py
├── integration/test_health_query_integration.py
└── fixtures/mock_systemctl_output.json
```

## Phase 0: Research - ✅ COMPLETE

**Completed Research**:
1. ✅ systemctl command patterns (show, properties, parsing)
2. ✅ Socket-activated service detection (TriggeredBy property)
3. ✅ Conditional service detection (monitor profile integration)
4. ✅ Service categorization logic (4 categories: Core/UI/System/Optional)
5. ✅ Service restart patterns (Eww onclick with systemctl, sudo handling)

**Key Decisions**:
- Use `systemctl show -p <properties> --value` for health queries
- Parse KEY=VALUE output (no JSON available from systemctl)
- Check `TriggeredBy` for socket activation detection
- Read `~/.config/sway/monitor-profile.current` for conditional services
- Group services into 4 categories with color-coded health states
- Use terminal-based sudo for system service restarts

**Artifacts**: [research.md](research.md)

## Phase 1: Design & Contracts - ✅ COMPLETE

**Data Models**: [data-model.md](data-model.md)
- `ServiceHealth`: Individual service state (17 fields)
- `ServiceCategory`: Logical grouping (4 categories)
- `SystemHealth`: Overall health summary

**Contracts**:
- systemctl show output format (KEY=VALUE pairs)
- health query response JSON schema
- Eww defpoll consumption format

**User Guide**: [quickstart.md](quickstart.md)
- How to view Health tab
- How to interpret health indicators
- How to restart failed services
- Troubleshooting common issues

## Phase 2: Implementation Planning (Next Step)

**Ready for `/speckit.tasks` command** to generate:
- Task breakdown with dependencies
- Test-driven development order
- Implementation timeline

## Complexity Tracking

> **No violations detected - this section is empty**

---

## Summary

✅ **Planning Complete** - All Phase 0 and Phase 1 artifacts generated.

**Next Command**: `/speckit.tasks` to generate implementation task breakdown

**Artifacts Created**:
1. research.md (systemctl patterns, service categorization)
2. data-model.md (ServiceHealth, ServiceCategory, SystemHealth schemas)
3. quickstart.md (user guide for Health tab usage)
4. checklists/requirements.md (specification validation)

**Ready for Implementation**: Yes - all technical decisions documented, data models defined, no clarifications needed.
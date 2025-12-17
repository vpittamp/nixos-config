# Implementation Plan: eBPF-Based AI Agent Process Monitor

**Branch**: `119-explore-ebpf-monitor` | **Date**: 2025-12-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/119-explore-ebpf-monitor/spec.md`

## Summary

Replace the current tmux polling-based AI agent monitor with an eBPF-based system that uses kernel syscall tracing to detect when Claude Code and Codex CLI processes transition from active processing to waiting-for-input state. The eBPF monitor will trace read/poll/select syscalls on stdin file descriptors, generate events when AI processes block on input for longer than a threshold, and write badge state files compatible with the existing eww monitoring panel and notification system.

## Technical Context

**Language/Version**: Python 3.11+ (userspace daemon with BCC), bpftrace scripts for eBPF probes
**Primary Dependencies**: BCC (BPF Compiler Collection), libbpf, bpftrace, Pydantic (data models), i3ipc.aio (Sway IPC)
**Storage**: File-based badges at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json` (existing format)
**Testing**: pytest with pytest-asyncio for daemon tests, manual eBPF probe validation
**Target Platform**: NixOS Linux (kernel 6.12.61 with BTF support)
**Project Type**: Single project - Python daemon with embedded eBPF programs
**Performance Goals**: Detection latency <100ms from syscall to event, CPU usage <1%
**Constraints**: User-level service (no root), requires CAP_BPF+CAP_PERFMON via setcap
**Scale/Scope**: Monitor 1-10 concurrent AI sessions across multiple tmux/Ghostty windows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | New NixOS module in `modules/services/` or `home-modules/services/`, composable with existing system |
| II. Reference Implementation Flexibility | ✅ PASS | Validated on Hetzner-Sway reference platform |
| III. Test-Before-Apply | ✅ PASS | Will use `nixos-rebuild dry-build` before deployment |
| IV. Override Priority Discipline | ✅ PASS | Will use `mkDefault` for configurable defaults |
| V. Platform Flexibility | ✅ PASS | Conditional logic for eBPF availability |
| VI. Declarative Configuration | ✅ PASS | All configuration via NixOS module options |
| VII. Documentation as Code | ✅ PASS | Module will include option descriptions |
| X. Python Development Standards | ✅ PASS | Python 3.11+, Pydantic, async patterns |
| XI. i3 IPC Alignment | ✅ PASS | Uses Sway IPC for window ID resolution |
| XII. Forward-Only Development | ✅ PASS | Clean replacement of tmux-ai-monitor, no backward compatibility |
| XIV. Test-Driven Development | ⚠️ PARTIAL | eBPF probes difficult to unit test; will rely on integration tests |

**Gate Status**: PASS (proceed to Phase 0)

**Post-Design Re-evaluation** (after Phase 1):
| Principle | Status | Notes |
|-----------|--------|-------|
| XII. Forward-Only Development | ✅ PASS | Clean replacement confirmed in research - no backward compatibility |
| Security Model | ⚠️ REVISED | setcap approach rejected; root service required (see research.md) |

**Key Research Finding**: The original spec assumed setcap could grant CAP_BPF/CAP_PERFMON to enable user-level eBPF. Research revealed this is a security anti-pattern - "BCC tools should NOT be installed with CAP_BPF and CAP_PERFMON since unpriv users will be able to read kernel secrets." The architecture has been revised to use a system-level root service instead.

## Project Structure

### Documentation (this feature)

```text
specs/119-explore-ebpf-monitor/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (badge state contract)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# NixOS Module Structure
modules/services/ebpf-ai-monitor.nix        # System-level NixOS module (capabilities setup)
home-modules/services/ebpf-ai-monitor.nix   # User-level home-manager service

# Python Daemon
home-modules/tools/ebpf_ai_monitor/
├── __init__.py                 # Package initialization
├── __main__.py                 # CLI entry point
├── daemon.py                   # Main daemon loop with eBPF integration
├── models.py                   # Pydantic models (ProcessState, BadgeState)
├── bpf_probes.py               # BCC-based eBPF program definitions
├── process_tracker.py          # Process state tracking and window resolution
├── badge_writer.py             # Badge file management (reuse existing format)
├── notifier.py                 # Desktop notification integration
└── README.md                   # Module documentation

# eBPF Scripts (alternative bpftrace approach)
scripts/ebpf-ai-monitor/
├── stdin-monitor.bt            # bpftrace script for stdin monitoring
└── process-exit.bt             # bpftrace script for process exit detection

# Tests
tests/ebpf-ai-monitor/
├── test_models.py              # Data model tests
├── test_process_tracker.py     # Process tracking tests
├── test_badge_writer.py        # Badge file tests
└── fixtures/
    └── mock_bpf_events.py      # Mock eBPF events for testing
```

**Structure Decision**: Single project with Python daemon using BCC for eBPF. The daemon runs as a user-level systemd service with setcap-granted capabilities. NixOS modules at both system level (for setcap setup) and home-manager level (for user service).

## Complexity Tracking

> No constitution violations requiring justification.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | - | - |

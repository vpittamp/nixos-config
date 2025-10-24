# Feature 033: Declarative Workspace-to-Monitor Mapping

**Status**: Research Complete
**Date**: 2025-10-23

---

## Overview

This feature implements declarative workspace-to-monitor mapping in i3, allowing users to configure workspace assignments via a configuration file that persists across monitor changes, i3 restarts, and system reboots.

---

## Documentation Structure

### Core Specification Documents

1. **[spec.md](./spec.md)** (333 lines)
   - Complete feature specification
   - Requirements, scope, and acceptance criteria
   - User stories and use cases
   - Technical constraints and assumptions

2. **[plan.md](./plan.md)** (188 lines)
   - Implementation plan and architecture
   - Component breakdown and dependencies
   - Development phases and milestones
   - Testing strategy

### i3 IPC Research Documents

3. **[i3-workspace-output-research.md](./i3-workspace-output-research.md)** (1,050 lines)
   - **COMPREHENSIVE i3 IPC workspace assignment reference**
   - Command syntax for configuration and runtime
   - i3 IPC protocol details (GET_WORKSPACES, GET_OUTPUTS, RUN_COMMAND)
   - Runtime behavior analysis (tested against i3 v4.24)
   - Dynamic reassignment patterns
   - Edge case documentation with test results
   - Python i3ipc code examples
   - Performance benchmarks and best practices

4. **[quick-reference.md](./quick-reference.md)** (340 lines)
   - **Quick reference guide for i3 workspace assignment**
   - Command syntax cheat sheet
   - Python code snippets for common operations
   - Distribution patterns (1/2/3+ monitors)
   - Event-driven architecture examples
   - Validation patterns
   - Best practices checklist
   - Common pitfalls and solutions

### TUI Implementation Research

5. **[TUI_SUMMARY.md](./TUI_SUMMARY.md)** (274 lines)
   - Quick decision guide and recommendations
   - TL;DR comparison table (Python: Textual vs Asciimatics)
   - Implementation roadmap
   - 5-minute read

6. **[TUI_QUICKSTART.md](./TUI_QUICKSTART.md)** (643 lines)
   - Step-by-step Textual framework quickstart
   - Sample workspace configuration TUI
   - Live i3 state display examples
   - Reactive widget patterns
   - 15-minute read

7. **[TUI_LIBRARY_RESEARCH.md](./TUI_LIBRARY_RESEARCH.md)** (781 lines)
   - Terminal UI library comparison (Textual vs Asciimatics)
   - Feature matrix and architecture analysis
   - Recommendation: Textual for rich, modern TUI
   - Integration patterns with i3ipc
   - 30-minute read

### Supporting Documents

8. **[checklists/](./checklists/)** directory
   - Quality assurance checklists
   - Implementation validation criteria

---

## Quick Start

### For Developers

**Understanding i3 workspace assignment**:
1. Start with [quick-reference.md](./quick-reference.md) for syntax and patterns
2. Read [i3-workspace-output-research.md](./i3-workspace-output-research.md) for comprehensive details
3. Review existing implementation: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py`

**Building the TUI**:
1. Read [TUI_SUMMARY.md](./TUI_SUMMARY.md) for library decision
2. Follow [TUI_QUICKSTART.md](./TUI_QUICKSTART.md) for Textual patterns
3. See [TUI_LIBRARY_RESEARCH.md](./TUI_LIBRARY_RESEARCH.md) for detailed comparison

**Implementation**:
1. Review [plan.md](./plan.md) for architecture and phases
2. Check [spec.md](./spec.md) for requirements and acceptance criteria
3. Use checklists for quality validation

### For Users

**Key Capabilities**:
- Declarative workspace-to-monitor mapping via config file
- Automatic workspace redistribution on monitor changes
- TUI for visual configuration and testing
- Persistent assignments across i3 restarts

**Example Configuration**:
```json
{
  "version": "1.0",
  "mappings": [
    {
      "workspace": 1,
      "output": "HDMI-1",
      "fallbacks": ["DP-1", "eDP-1"]
    },
    {
      "workspace": 2,
      "output": "HDMI-1",
      "fallbacks": ["DP-1", "eDP-1"]
    }
  ]
}
```

---

## Key Research Findings

### i3 IPC Workspace Assignment

**Two Command Types**:
1. **Declarative**: `workspace <num> output <output>`
   - Sets preference, doesn't move immediately
   - Persists across workspace switches
   - Command succeeds even with non-existent outputs

2. **Immediate**: `move workspace to output <output>`
   - Moves workspace right now
   - All windows move with workspace
   - Fails if output doesn't exist

**Critical Discovery**: Must **switch to workspace first**, then **move it** for immediate effect:
```python
await i3.command(f"workspace {ws_num}")  # Switch to workspace
await i3.command(f"move workspace to output {output}")  # Move it
```

**Edge Cases Tested**:
- ✅ Non-existent outputs: Command succeeds, workspace stays on current output
- ✅ Workspace reassignment: Can move existing workspaces with windows
- ✅ Focused workspace: Focus follows workspace to new output
- ✅ Arbitrary workspace numbers: i3 supports numbers beyond 10
- ✅ Disconnected monitors: Workspaces become orphaned but remain accessible

### Event-Driven Architecture

**Best Practice**: Subscribe to i3 OUTPUT events instead of polling:
```python
i3.on(i3ipc.Event.OUTPUT, on_output_change)

async def on_output_change(i3, event):
    await redistribute_workspaces(i3)
```

**Debouncing**: Use 1-second delay to prevent rapid reassignments during monitor changes.

### TUI Framework Selection

**Winner**: Textual (Python)
- Modern, actively maintained (2024 releases)
- Rich widget library (DataTable, Tree, Tabs, etc.)
- Built-in theming and styling
- Async/await native support
- Excellent for i3ipc integration

**Rejected**: Asciimatics
- Older, callback-based architecture
- Manual widget construction required
- Less suitable for modern async patterns

---

## Implementation Phases

### Phase 1: Core Workspace Manager (Week 1)
- Load/save configuration from JSON
- Validate workspace-to-output assignments
- Implement distribution logic (1/2/3+ monitor patterns)
- Event-driven monitor change detection

### Phase 2: TUI Application (Week 2)
- Textual-based configuration editor
- Live i3 state display (GET_WORKSPACES, GET_OUTPUTS)
- Interactive workspace assignment
- Real-time validation feedback

### Phase 3: Integration & Testing (Week 3)
- Integrate with existing i3pm daemon
- Systemd service integration
- Automated testing suite
- Documentation and examples

---

## References

### Internal Documents
- **i3 IPC Patterns**: `/etc/nixos/docs/I3_IPC_PATTERNS.md`
- **Existing Implementation**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py`
- **Constitution Principle XI**: i3 IPC as authoritative source of truth
- **Python Development Standards**: `/etc/nixos/docs/PYTHON_DEVELOPMENT.md`

### External Resources
- **i3 User Guide**: https://i3wm.org/docs/userguide.html
- **i3 IPC Protocol**: https://i3wm.org/docs/ipc.html
- **i3ipc-python**: https://i3ipc-python.readthedocs.io/
- **Textual Framework**: https://textual.textualize.io/

### Key GitHub Issues
- **#555**: Multiple workspace output directives (fallback support)
- **#4691**: "Move workspace to output" error handling
- **#2657**: Workspace on inactive output behavior

---

## Performance Benchmarks

| Operation | Latency | Notes |
|-----------|---------|-------|
| GET_OUTPUTS | 2-3ms | Cache 500ms-1s or use events |
| GET_WORKSPACES | 2-3ms | Query on-demand |
| RUN_COMMAND (single) | 5-10ms | For workspace assignment |
| RUN_COMMAND (batch 10) | ~15ms | Better than individual calls |
| Event latency | <100ms | OUTPUT event to handler execution |

**Memory**: ~1MB per i3ipc.aio.Connection

---

## Validation Checklist

### Before Implementation
- [x] Research i3 IPC workspace assignment commands
- [x] Test edge cases (disconnected monitors, non-existent outputs)
- [x] Document runtime behavior
- [x] Compare TUI frameworks
- [x] Define data model and configuration format

### During Implementation
- [ ] Unit tests for workspace distribution logic
- [ ] Integration tests with i3 (using mock outputs)
- [ ] TUI navigation and validation
- [ ] Event subscription and debouncing
- [ ] Configuration persistence

### Before Release
- [ ] End-to-end testing on 1/2/3+ monitor setups
- [ ] Monitor connect/disconnect scenarios
- [ ] i3 restart persistence
- [ ] User documentation
- [ ] Example configurations

---

## Contributing

**Architecture Principles**:
1. **i3 IPC as source of truth**: Always validate against i3's state
2. **Event-driven**: Subscribe to OUTPUT events, don't poll
3. **Declarative configuration**: JSON-based workspace assignments
4. **Graceful degradation**: Handle disconnected monitors, invalid outputs
5. **User feedback**: TUI provides real-time validation

**Code Standards**:
- Python 3.11+ with async/await
- Type hints for all public APIs
- Pydantic models for configuration validation
- pytest for testing
- Rich/Textual for TUI

---

## Document Index

| Document | Lines | Purpose |
|----------|-------|---------|
| README.md (this file) | - | Navigation and overview |
| spec.md | 333 | Feature specification |
| plan.md | 188 | Implementation plan |
| i3-workspace-output-research.md | 1,050 | Comprehensive i3 IPC reference |
| quick-reference.md | 340 | Quick command reference |
| TUI_LIBRARY_RESEARCH.md | 781 | TUI framework comparison |
| TUI_QUICKSTART.md | 643 | Textual quickstart guide |
| TUI_SUMMARY.md | 274 | TUI decision summary |

**Total**: 3,609 lines of documentation

---

**Last Updated**: 2025-10-23
**Feature Status**: Research Complete, Ready for Implementation
**i3 Version Tested**: 4.24 (2024-11-06)

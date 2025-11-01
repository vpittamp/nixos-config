# Research: Event-Driven Workspace Mode Navigation

**Feature**: Event-Driven Workspace Mode Navigation
**Branch**: 042-event-driven-workspace-mode
**Date**: 2025-10-31

## Overview

This document captures research findings and architectural decisions for migrating workspace mode navigation from bash script-based implementation to event-driven Python daemon architecture.

## Research Questions & Decisions

### 1. State Management Architecture

**Question**: How should workspace mode state be managed in the daemon?

**Decision**: In-memory state with dedicated WorkspaceModeManager class

**Rationale**:
- Existing i3pm daemon already uses StateManager pattern (see `state.py`)
- Workspace mode sessions are ephemeral (active only during user input)
- No persistence required - daemon restart simply clears state (user must re-enter mode)
- Avoids file I/O on hot path (critical for <10ms digit accumulation latency)
- Async-safe with single event loop thread (no race conditions)

**Alternatives Considered**:
- **File-based state** (e.g., JSON in `~/.config/i3/workspace-mode-state.json`): Rejected due to I/O latency (10-20ms per write), unnecessary persistence overhead
- **Shared memory** (e.g., mmap): Rejected due to complexity, overkill for single-daemon architecture
- **Redis/external store**: Rejected due to dependency bloat, networking overhead

**Implementation Pattern**:
```python
class WorkspaceModeManager:
    """Manages workspace mode state in-memory."""

    def __init__(self, i3_connection):
        self._active = False
        self._mode_type = None  # "goto" or "move"
        self._accumulated_digits = ""
        self._entered_at = None
        self._output_cache = {}  # PRIMARY/SECONDARY/TERTIARY -> output name
        self._history = []  # Circular buffer, max 100 entries
        self._i3 = i3_connection

    async def enter_mode(self, mode_type: str) -> None:
        """Enter workspace mode (goto or move)."""
        self._active = True
        self._mode_type = mode_type
        self._accumulated_digits = ""
        self._entered_at = time.time()
        await self._refresh_output_cache()

    async def add_digit(self, digit: str) -> str:
        """Add digit to accumulated state. Returns current accumulated string."""
        if digit == "0" and not self._accumulated_digits:
            return self._accumulated_digits  # Ignore leading zero
        self._accumulated_digits += digit
        return self._accumulated_digits

    async def execute(self) -> int:
        """Execute workspace switch. Returns target workspace number."""
        if not self._accumulated_digits:
            return None  # Empty state, do nothing

        workspace = int(self._accumulated_digits)
        output = self._get_output_for_workspace(workspace)

        # Execute switch via i3 IPC
        if self._mode_type == "goto":
            await self._i3.command(f"workspace number {workspace}")
        elif self._mode_type == "move":
            await self._i3.command(f"move container to workspace number {workspace}; workspace number {workspace}")

        # Focus output
        await self._i3.command(f"focus output {output}")

        # Record history
        self._history.append({
            "workspace": workspace,
            "output": output,
            "timestamp": time.time(),
            "mode_type": self._mode_type
        })
        if len(self._history) > 100:
            self._history.pop(0)

        # Reset state
        self._active = False
        self._mode_type = None
        self._accumulated_digits = ""

        return workspace
```

### 2. Event Integration Architecture

**Question**: How should workspace mode events be broadcast to status bar and other subscribers?

**Decision**: Extend existing daemon event broadcasting mechanism (Feature 017 pattern)

**Rationale**:
- Daemon already has event broadcasting infrastructure for project switches (see `ipc_server.py`, line 57: `self.subscribed_clients`)
- Status bar scripts already subscribe to daemon events via IPC socket
- Proven <5ms latency for event delivery (measured in Feature 017)
- Consistent with existing architecture (no new patterns to learn)

**Alternatives Considered**:
- **D-Bus**: Rejected due to additional dependency, overkill for simple pub-sub
- **File watching** (e.g., inotify on state file): Rejected due to I/O overhead, polling lag
- **Direct status bar updates** (daemon writes to i3bar protocol): Rejected due to tight coupling, violates separation of concerns

**Implementation Pattern**:
```python
# In IPCServer class (ipc_server.py)
async def broadcast_event(self, event_type: str, payload: dict) -> None:
    """Broadcast event to subscribed clients."""
    message = {
        "jsonrpc": "2.0",
        "method": "event",
        "params": {
            "type": event_type,
            "payload": payload,
            "timestamp": time.time()
        }
    }

    for client in self.subscribed_clients:
        try:
            client.write(json.dumps(message).encode() + b"\n")
            await client.drain()
        except Exception as e:
            logger.warning(f"Failed to send event to client: {e}")
            self.subscribed_clients.discard(client)

# Broadcast workspace_mode events
await ipc_server.broadcast_event("workspace_mode", {
    "mode_active": True,
    "mode_type": "goto",
    "accumulated_digits": "23"
})
```

### 3. Sway Mode Integration

**Question**: How should Sway modes (goto_workspace, move_workspace) be integrated with daemon state?

**Decision**: Subscribe to Sway mode events via i3 IPC, use mode entry/exit as state triggers

**Rationale**:
- Sway emits mode events when user enters/exits modes (verified in i3/Sway IPC protocol docs)
- Daemon already subscribes to i3 events (window, workspace, output, tick) - adding mode subscription is trivial
- Mode events provide authoritative state (Sway knows mode state, daemon follows)
- Eliminates need for daemon to infer mode state from CLI commands

**Alternatives Considered**:
- **CLI-triggered state** (mode entry only via `i3pm workspace-mode enter`): Rejected due to inability to detect user exiting mode via Escape
- **Polling Sway mode state** (periodic query via IPC): Rejected due to latency, unnecessary CPU usage
- **Bash script integration** (keep bash scripts, add daemon calls): Rejected due to complexity, violates forward-only development principle

**Implementation Pattern**:
```python
# In daemon.py event handler
async def on_mode(self, i3, event):
    """Handle Sway mode events (Feature 042)."""
    mode_name = event.change

    if mode_name == "goto_workspace":
        await self.workspace_mode_manager.enter_mode("goto")
        await self.ipc_server.broadcast_event("workspace_mode", {
            "mode_active": True,
            "mode_type": "goto",
            "accumulated_digits": ""
        })
    elif mode_name == "move_workspace":
        await self.workspace_mode_manager.enter_mode("move")
        await self.ipc_server.broadcast_event("workspace_mode", {
            "mode_active": True,
            "mode_type": "move",
            "accumulated_digits": ""
        })
    elif mode_name == "default":
        # User exited workspace mode (Escape or successful execution)
        await self.workspace_mode_manager.cancel()
        await self.ipc_server.broadcast_event("workspace_mode", {
            "mode_active": False,
            "mode_type": None,
            "accumulated_digits": ""
        })
```

### 4. IPC Method Design

**Question**: What IPC methods should be exposed for CLI tool integration?

**Decision**: Five methods following existing i3pm IPC patterns

**Methods**:
1. `workspace_mode.digit` - Add digit to accumulated state
2. `workspace_mode.execute` - Execute workspace switch
3. `workspace_mode.cancel` - Exit mode without action
4. `workspace_mode.state` - Query current mode state
5. `workspace_mode.history` - Query navigation history

**Rationale**:
- Matches existing IPC method naming convention (`project.*`, `daemon.*`, `windows.*`)
- Granular methods enable precise CLI command mapping
- State query methods enable status bar integration and diagnostics
- History method supports future enhancements (recent workspace shortcuts)

**Alternatives Considered**:
- **Single unified method** (`workspace_mode.action {type, payload}`): Rejected due to less type-safe interface, harder to document
- **Overloaded execute method** (execute with/without digits): Rejected due to ambiguity, error-prone
- **No state/history methods** (only action methods): Rejected due to inability to query state for status bar

**Implementation Pattern**:
```python
# In IPCServer class (ipc_server.py)
async def handle_workspace_mode_digit(self, params: dict) -> dict:
    """Handle workspace_mode.digit IPC method."""
    digit = params.get("digit")
    if not digit or digit not in "0123456789":
        return {"error": "Invalid digit", "code": -32602}

    accumulated = await self.workspace_mode_manager.add_digit(digit)

    # Broadcast event for status bar update
    await self.broadcast_event("workspace_mode", {
        "mode_active": True,
        "mode_type": self.workspace_mode_manager.mode_type,
        "accumulated_digits": accumulated
    })

    return {"accumulated_digits": accumulated}
```

### 5. Output Cache Management

**Question**: How should output cache (PRIMARY/SECONDARY/TERTIARY → monitor names) be refreshed?

**Decision**: Refresh on output events + fallback refresh on every workspace switch

**Rationale**:
- Output events are rare (only when monitors plug/unplug) - low overhead
- Fallback refresh ensures cache is never stale even if output event is missed
- i3 IPC `get_outputs` is fast (<1ms) - acceptable overhead on every switch
- Matches existing pattern in monitor config manager (Feature 033)

**Alternatives Considered**:
- **Refresh only on output events**: Rejected due to risk of stale cache if event missed
- **Refresh on mode entry**: Rejected due to insufficient (user might plug monitor during digit accumulation)
- **Refresh on every digit accumulation**: Rejected due to unnecessary overhead, violates <10ms digit latency requirement

**Implementation Pattern**:
```python
async def _refresh_output_cache(self) -> None:
    """Refresh output cache from i3 IPC."""
    outputs = await self._i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    if len(active_outputs) == 1:
        # Single monitor - all outputs map to same display
        self._output_cache = {
            "PRIMARY": active_outputs[0].name,
            "SECONDARY": active_outputs[0].name,
            "TERTIARY": active_outputs[0].name
        }
    elif len(active_outputs) == 2:
        # Two monitors
        self._output_cache = {
            "PRIMARY": active_outputs[0].name,
            "SECONDARY": active_outputs[1].name,
            "TERTIARY": active_outputs[1].name
        }
    elif len(active_outputs) >= 3:
        # Three or more monitors
        self._output_cache = {
            "PRIMARY": active_outputs[0].name,
            "SECONDARY": active_outputs[1].name,
            "TERTIARY": active_outputs[2].name
        }
    else:
        logger.warning("No active outputs detected")

def _get_output_for_workspace(self, workspace: int) -> str:
    """Get output name for workspace number."""
    if workspace in (1, 2):
        return self._output_cache.get("PRIMARY", "eDP-1")
    elif workspace in (3, 4, 5):
        return self._output_cache.get("SECONDARY", "eDP-1")
    else:
        return self._output_cache.get("TERTIARY", "eDP-1")
```

### 6. Platform-Specific Keybindings

**Question**: How to handle different keybindings for M1 (CapsLock) vs Hetzner (Ctrl+0)?

**Decision**: Platform-conditional Nix configuration using `lib.mkIf`

**Rationale**:
- Existing pattern for platform-specific configuration (see `keyd.nix` for M1-specific keyd service)
- NixOS provides hostname detection via `config.networking.hostName`
- Declarative approach ensures keybindings match platform requirements
- No runtime detection needed (configuration baked in at build time)

**Alternatives Considered**:
- **Runtime detection** (daemon detects platform, adjusts behavior): Rejected due to unnecessary complexity, keybindings are input-level concern
- **Manual configuration** (user edits config file): Rejected due to violation of declarative configuration principle
- **Unified keybinding** (same key on all platforms): Rejected due to VNC limitations (Ctrl+0 required), physical keyboard availability (CapsLock preferred)

**Implementation Pattern**:
```nix
# In home-modules/desktop/sway.nix
let
  isM1 = config.networking.hostName == "m1-mbp";
  isHetzner = config.networking.hostName == "hetzner";
in {
  # M1-specific: CapsLock activation via keyd remapping
  xdg.configFile."sway/config.d/workspace-mode-m1.conf" = lib.mkIf isM1 {
    text = ''
      # CapsLock remapped to F13 by keyd (see keyd.nix)
      bindcode 191 mode goto_workspace
      bindcode Shift+191 mode move_workspace
    '';
  };

  # Hetzner-specific: Ctrl+0 activation (VNC compatible)
  xdg.configFile."sway/config.d/workspace-mode-hetzner.conf" = lib.mkIf isHetzner {
    text = ''
      bindsym Control+0 mode goto_workspace
      bindsym Control+Shift+0 mode move_workspace
    '';
  };
}
```

### 7. Status Bar Integration

**Question**: How should status bar display workspace mode state?

**Decision**: Dedicated i3bar block script subscribing to daemon events + fallback to Sway binding_mode_indicator

**Rationale**:
- Existing i3bar configuration already has custom blocks (project context, system monitor)
- Daemon event subscription provides <5ms latency updates (proven in Feature 017)
- Sway's binding_mode_indicator provides native fallback (always shows mode name)
- Both approaches can coexist (status bar shows accumulated digits, mode indicator shows mode name)

**Alternatives Considered**:
- **Sway mode indicator only**: Rejected due to inability to show accumulated digits (only shows mode name)
- **notify-send notifications**: Rejected due to visual clutter, no persistence across redraws
- **dmenu/rofi overlay**: Rejected due to focus stealing, modal interruption

**Implementation Pattern**:
```python
#!/usr/bin/env python3
"""i3bar status block for workspace mode.

Subscribes to daemon workspace_mode events and outputs i3bar protocol JSON.
"""
import asyncio
import json
import sys
from pathlib import Path

async def main():
    """Subscribe to daemon and output workspace mode state."""
    socket_path = Path.home() / ".local" / "state" / "i3-project-daemon.sock"

    reader, writer = await asyncio.open_unix_connection(str(socket_path))

    # Subscribe to events
    request = {
        "jsonrpc": "2.0",
        "method": "subscribe",
        "params": {},
        "id": 1
    }
    writer.write(json.dumps(request).encode() + b"\n")
    await writer.drain()

    # Read events
    while True:
        line = await reader.readline()
        if not line:
            break

        event = json.loads(line.decode())
        if event.get("method") == "event" and event["params"]["type"] == "workspace_mode":
            payload = event["params"]["payload"]

            if payload["mode_active"]:
                # Show accumulated digits
                text = f"WS: {payload['accumulated_digits'] or '_'}"
                mode = "goto" if payload["mode_type"] == "goto" else "move"
                print(json.dumps({
                    "full_text": text,
                    "short_text": text,
                    "color": "#a6e3a1",  # Catppuccin green
                    "urgent": False
                }))
            else:
                # Mode inactive - show nothing or project context
                print(json.dumps({
                    "full_text": "",
                    "short_text": ""
                }))

            sys.stdout.flush()
```

### 8. Testing Strategy

**Question**: How should workspace mode navigation be tested?

**Decision**: Multi-layer testing: unit tests (pytest), integration tests (daemon IPC), scenario tests (end-to-end workflows)

**Rationale**:
- Follows existing testing patterns from Features 017-018 (i3pm monitor/test frameworks)
- Unit tests validate state management logic (digit accumulation, output cache, history tracking)
- Integration tests validate IPC contract (method calls, event broadcasting)
- Scenario tests validate real user workflows (enter mode → type digits → execute → verify focus)
- pytest-asyncio supports async test patterns (required for i3ipc.aio)

**Test Coverage Goals**:
- Unit tests: >80% coverage of WorkspaceModeManager class
- Integration tests: All IPC methods (digit, execute, cancel, state, history)
- Scenario tests: All acceptance scenarios from spec.md user stories
- Edge cases: Empty digits, leading zeros, rapid mode entry, daemon restart

**Implementation Pattern**:
```python
# tests/i3pm/workspace_mode/test_workspace_mode_manager.py
import pytest
from home_modules.tools.i3pm.daemon.workspace_mode import WorkspaceModeManager

@pytest.mark.asyncio
async def test_digit_accumulation():
    """Test digit accumulation logic."""
    manager = WorkspaceModeManager(mock_i3_connection)
    await manager.enter_mode("goto")

    assert await manager.add_digit("2") == "2"
    assert await manager.add_digit("3") == "23"
    assert await manager.add_digit("5") == "235"

@pytest.mark.asyncio
async def test_leading_zero_ignored():
    """Test leading zero is ignored."""
    manager = WorkspaceModeManager(mock_i3_connection)
    await manager.enter_mode("goto")

    assert await manager.add_digit("0") == ""  # Ignored
    assert await manager.add_digit("5") == "5"  # Now accepted

@pytest.mark.asyncio
async def test_output_cache_single_monitor():
    """Test output cache with single monitor."""
    manager = WorkspaceModeManager(mock_i3_connection_single_monitor)
    await manager._refresh_output_cache()

    assert manager._output_cache["PRIMARY"] == "eDP-1"
    assert manager._output_cache["SECONDARY"] == "eDP-1"
    assert manager._output_cache["TERTIARY"] == "eDP-1"
```

## Best Practices from Existing Codebase

### From Feature 015 (Event-Driven Daemon)
- Use async/await for i3 IPC communication (i3ipc.aio)
- Subscribe to i3 events via IPC subscriptions (not polling)
- Single-threaded event loop with asyncio (no race conditions)
- Systemd socket activation for IPC server
- Auto-reconnection with exponential backoff for i3 IPC connection

### From Feature 017 (Monitoring Tools)
- Use Rich library for terminal UI (tables, live displays)
- Event broadcasting via IPC socket to subscribed clients
- JSON-RPC protocol for CLI ↔ daemon communication
- <5ms event delivery latency target

### From Feature 018 (Testing Framework)
- pytest with pytest-asyncio for async tests
- Pydantic models for data validation
- Mock i3 IPC connection for unit tests
- Scenario-based integration tests for end-to-end workflows

### From Feature 033 (Monitor Config Manager)
- Query i3 IPC for authoritative output state (GET_OUTPUTS)
- Cache output configuration, refresh on output events
- Support 1, 2, 3 monitor configurations dynamically

## Technology Stack Summary

**Core Dependencies**:
- Python 3.11+ (existing daemon runtime)
- i3ipc-python (i3ipc.aio) - i3/Sway IPC communication
- asyncio - async event loop
- Pydantic - data models and validation
- Rich - terminal UI for status bar scripts

**Testing Dependencies**:
- pytest - test framework
- pytest-asyncio - async test support

**Platform Dependencies**:
- NixOS - declarative configuration
- Sway/i3 - window manager with IPC protocol
- systemd - daemon service management

**Development Tools**:
- keyd (M1 only) - keyboard remapping for CapsLock
- i3bar - status bar protocol (existing)

## Performance Targets & Validation

**Latency Targets**:
- Digit accumulation: <10ms (IPC round-trip + state update + event broadcast)
- Workspace switch execution: <20ms (IPC command + i3 processing + focus change)
- Event broadcast: <5ms (socket write to subscribed clients)
- Total navigation: <100ms (mode entry → digits → execute → focus)

**Validation Methods**:
1. **Microbenchmarks**: Time individual operations (digit accumulation, IPC calls)
2. **Integration benchmarks**: Time full workflows (enter → type → execute)
3. **Real-world testing**: User perception testing on M1 and Hetzner
4. **Stress testing**: 50 rapid switches per minute (ensure no lag, state corruption)

**Instrumentation**:
- Add timing logs to WorkspaceModeManager methods (DEBUG level)
- Measure IPC round-trip time via JSON-RPC id correlation
- Track event broadcast latency via timestamp diff

## Migration Plan

### Phase 1: Daemon Extension
1. Add WorkspaceModeManager class (`workspace_mode.py`)
2. Register IPC methods in IPCServer (`ipc_server.py`)
3. Add mode event handler to daemon (`daemon.py`)
4. Add event broadcasting for workspace_mode events

### Phase 2: CLI Tool
1. Create CLI commands (`cli/workspace_mode.py`)
2. Package CLI tool in Nix (`home-modules/tools/i3pm-deno.nix` or Python variant)
3. Test IPC communication (manual testing with daemon running)

### Phase 3: Sway Integration
1. Define Sway modes in Nix configuration (`modes.conf.nix`)
2. Add platform-specific keybindings (M1 CapsLock, Hetzner Ctrl+0)
3. Subscribe to mode events in daemon

### Phase 4: Status Bar Integration
1. Create status bar block script (`workspace_mode_block.py`)
2. Configure i3bar to include new block
3. Test event subscription and display updates

### Phase 5: Testing & Validation
1. Write unit tests (state management, output cache, history)
2. Write integration tests (IPC methods, event broadcasting)
3. Write scenario tests (user workflows)
4. Performance benchmarking and optimization

### Phase 6: Legacy Cleanup
1. Remove bash script implementations (if any exist)
2. Update documentation (CLAUDE.md, quickstart.md)
3. Verify backward compatibility (existing keybindings still work)

## Known Risks & Mitigations

**Risk 1: Sway mode events not emitted reliably**
- *Mitigation*: Test early with minimal Sway config, verify event subscription works
- *Fallback*: Poll Sway mode state via IPC if events prove unreliable

**Risk 2: Event broadcast lag to status bar**
- *Mitigation*: Measure latency in integration tests, optimize if >10ms
- *Fallback*: Use Sway binding_mode_indicator only (no digit display)

**Risk 3: Daemon restart during mode session**
- *Mitigation*: Document that mode state is lost on restart (user must exit and re-enter)
- *Acceptance*: Daemon restarts are rare (only during development/updates), acceptable UX degradation

**Risk 4: Output cache stale after monitor change**
- *Mitigation*: Refresh cache on every workspace switch (fallback strategy)
- *Validation*: Test monitor plug/unplug scenarios on Hetzner

**Risk 5: Platform-specific keybinding conflicts**
- *Mitigation*: Use keyd for M1 CapsLock remapping (established pattern from Feature 051)
- *Validation*: Test on both M1 and Hetzner platforms

## Conclusion

The event-driven workspace mode architecture leverages existing i3pm daemon infrastructure (Feature 015), proven event broadcasting patterns (Feature 017), and i3 IPC best practices (Feature 018). The design prioritizes performance (<20ms latency), simplicity (in-memory state, no persistence), and consistency with existing patterns.

All technical unknowns have been resolved through research and architectural decisions. The implementation can proceed to Phase 1 (data modeling and contracts).

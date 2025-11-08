# Research: Tree Monitor Inspect Command - Daemon Backend Fix

**Date**: 2025-11-08
**Feature**: 066-inspect-daemon-fix

## Executive Summary

The Python daemon's `get_event` RPC method receives string event IDs from the TypeScript client but was not properly converting them to integers before buffer lookup, causing "Event not found" errors. Analysis shows the fix requires graceful type conversion with appropriate error handling, use of JSON-RPC 2.0 standard error code -32000, and a version bump in the NixOS package to trigger daemon rebuild. The implementation pattern is already in place in `server.py` (lines 333-344) and only requires validation of the conversion logic.

## 1. JSON-RPC 2.0 Error Code Standards

**Decision**: Use error code **-32000** for "Event not found"

**Analysis**:
The JSON-RPC 2.0 specification (RFC-like standard) defines error code ranges:
- `-32768 to -32000`: Reserved for implementation-defined errors
- `-32700`: Parse error
- `-32600`: Invalid Request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

Error code `-32000` is explicitly for application-specific errors per the spec. The existing Python daemon implementation in `/etc/nixos/home-modules/tools/sway-tree-monitor/rpc/server.py` already uses this pattern:

```python
class RPCError(Exception):
    """Custom exception for RPC errors with error codes"""
    def __init__(self, code: int, message: str, data: Any = None):
        self.code = code
        self.message = message
        self.data = data
        super().__init__(message)
```

The `handle_get_event` method (lines 320-396) currently raises:
```python
raise RPCError(-32000, "Event not found", f"Event ID {event_id} does not exist in buffer")
```

This is the correct error code. No change needed here.

**Alternatives Considered**:
- `-32602` (Invalid params) - Rejected because the parameter format is valid JSON-RPC; the event simply doesn't exist
- `-32603` (Internal error) - Rejected as too vague; doesn't indicate user error
- Custom positive codes (e.g., 1000, 404) - Rejected as non-compliant with JSON-RPC 2.0

**Error Response Format**:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32000,
    "message": "Event not found",
    "data": "Event ID 123 does not exist in buffer"
  },
  "id": <request_id>
}
```

## 2. Python Type Conversion Best Practices

**Decision**: Use `try/except` with `int()` for graceful conversion, with explicit error message including type and value

**Current Implementation** (lines 333-337 in `server.py`):
```python
# Convert event_id to int (accept both string and int from RPC client)
try:
    event_id = int(event_id)
except (ValueError, TypeError):
    raise ValueError(f"Invalid event_id: must be an integer or numeric string, got {event_id!r}")
```

**Analysis**:
The current implementation correctly:
1. Uses `int()` constructor which accepts strings like "123", "0", "-1"
2. Catches both `ValueError` (non-numeric string like "abc") and `TypeError` (None, list, dict)
3. Includes the actual value in error message using `!r` repr format for debugging
4. Raises `ValueError` which is caught by the RPC error handler at line 189

**Why This Approach**:
- `int()` handles all JSON types that could represent integers (strings, actual ints, floats with no decimal part)
- `ValueError` for non-numeric strings: `int("abc")` → ValueError
- `TypeError` for incompatible types: `int(None)` → TypeError
- Explicit error message aids debugging (shows client sent "abc" vs expecting numeric)
- The `ValueError` is then caught by the outer exception handler and converted to RPC error -32603

**Alternative Approaches Considered**:
- `isinstance(event_id, int)` followed by conversion - Inefficient, does type check twice
- `int(event_id, base=10)` - Unnecessary, `int()` already defaults to base 10
- Strict type enforcement (reject strings) - Not viable; JSON-RPC can receive IDs as either int or string
- `Decimal(event_id)` - Overkill, unnecessary precision; we need an integer

**Exception Handling Chain**:
```
Client sends: {"event_id": "123"}
     ↓
int("123") succeeds, event_id = 123
     ↓
buffer.get_event_by_id(123) returns event or None
     ↓
if not event: raise RPCError(-32000, ...)

Client sends: {"event_id": "abc"}
     ↓
int("abc") raises ValueError
     ↓
except ValueError: raise ValueError("Invalid event_id: ...")
     ↓
Line 189: except Exception as e: → return self._error_response(..., -32603, "Internal error", str(e))
```

This creates a mismatch: `-32602` (Invalid params) would be more semantically correct than `-32603` (Internal error). However, the current implementation explicitly raises `ValueError` which gets caught as a generic exception.

**Recommendation**: The type conversion implementation is correct. If desired, could wrap in `RPCError(-32602, ...)` instead of `ValueError` for better semantics, but current approach is functional.

## 3. NixOS Package Rebuilds and Version Bumps

**Decision**: Version bump from 1.0.0 to 1.1.0 in `/etc/nixos/home-modules/tools/sway-tree-monitor.nix` triggers daemon rebuild

**Current Package Definition** (lines 4-28 in `sway-tree-monitor.nix`):
```nix
sway-tree-monitor = pkgs.python3Packages.buildPythonPackage {
  pname = "sway-tree-monitor";
  version = "1.1.0";  # Bumped to force rebuild with get_event fix

  src = ./sway-tree-monitor;

  format = "other";

  propagatedBuildInputs = with pkgs.python3Packages; [
    i3ipc
    orjson
    psutil
  ];

  installPhase = ''
    mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_tree_monitor
    cp -r * $out/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_tree_monitor/
  '';
```

**How Nix Detects Changes**:
1. Nix computes a hash of all inputs: `pname`, `version`, `src` (directory contents), `propagatedBuildInputs`
2. If any input changes, the hash changes
3. Different hash = new derivation, old cached build is discarded
4. Package gets rebuilt and reinstalled
5. Systemd service (line 71-98) restarts on next system rebuild

**Version Bump Impact**:
- Changing version from "1.0.0" to "1.1.0" directly changes the derivation hash
- Even if Python source code is identical, different version = different package
- This forces Nix to rebuild, ensuring new daemon is deployed
- Without version bump, Nix would use cached build (old daemon code still runs)

**Daemon Restart Process**:
```bash
# User applies NixOS configuration
sudo nixos-rebuild switch --flake .#m1

# Nix detects version change → rebuilds sway-tree-monitor package
# Nix activates new package → overwrites /nix/store/...sway-tree-monitor-1.1.0...
# Systemd service (ExecStart references new package) restarts on next event
# Or manual restart: systemctl --user restart sway-tree-monitor
```

**Source Hash (./sway-tree-monitor)**:
The `src = ./sway-tree-monitor` points to the local directory. If Python files change but version doesn't, Nix might use cached build. This is why the comment says "Bumped to force rebuild" - it's a safeguard.

**In Production**:
Typically, version bumps happen on actual releases. For development/testing:
- Option 1: Bump version (current approach) - guarantees rebuild
- Option 2: Use `--impure` flag: `sudo nixos-rebuild switch --flake .#m1 --impure`
- Option 3: Remove cached derivation: `nix store delete /nix/store/...sway-tree-monitor-1.0.0-*`

## 4. Existing get_event Implementation Analysis

**Current Implementation** (lines 320-396 in `server.py`):

The method correctly implements the fix:

```python
async def handle_get_event(self, params: dict) -> dict:
    """
    Handle 'get_event' method - get detailed event with diff and enrichment.

    Params:
        - event_id: Event ID to retrieve
        - include_snapshots: Include full tree snapshots (default: False)
        - include_enrichment: Include enriched context (default: True)
    """
    event_id = params.get('event_id')
    if event_id is None:
        raise ValueError("Missing required parameter: event_id")

    # Convert event_id to int (accept both string and int from RPC client)
    try:
        event_id = int(event_id)
    except (ValueError, TypeError):
        raise ValueError(f"Invalid event_id: must be an integer or numeric string, got {event_id!r}")

    include_snapshots = params.get('include_snapshots', False)
    include_enrichment = params.get('include_enrichment', True)

    event = self.event_buffer.get_event_by_id(event_id)
    if not event:
        raise RPCError(-32000, "Event not found", f"Event ID {event_id} does not exist in buffer")

    # Build detailed event response
    result = { ... }
    return result
```

**Execution Flow**:

1. **Receive**: RPC method receives `params` dict with `event_id` (could be string "123" or int 123)
2. **Validate presence**: Check event_id is not None (line 330-331)
3. **Type conversion**: Convert to int, catching ValueError/TypeError (lines 333-337)
4. **Buffer lookup**: Call `self.event_buffer.get_event_by_id(event_id)` (line 342)
5. **Check result**: If None, raise RPCError with -32000 (line 343-344)
6. **Serialize**: Build detailed response with snapshots, diff, correlations, enrichment (lines 346-396)

**Buffer Implementation** (`event_buffer.py` lines 120-135):
```python
def get_event_by_id(self, event_id: int) -> Optional[TreeEvent]:
    """
    Get single event by ID.

    Args:
        event_id: Event ID to find

    Returns:
        TreeEvent if found, None otherwise

    Performance: O(n) linear scan, ~0.01ms for 500 events
    """
    for event in self.events:
        if event.event_id == event_id:
            return event
    return None
```

The buffer expects `event_id` to be an `int`. Linear comparison `event.event_id == event_id` requires both to be same type.

**Potential Issue Scenario** (what causes "Event not found"):

Without type conversion:
```python
# Client sends: {"jsonrpc": "2.0", "method": "get_event", "params": {"event_id": "5"}, "id": 1}
# params.get('event_id') returns "5" (string)
# if event_id is None: False (it's "5")
# event = self.event_buffer.get_event_by_id("5")  # ← Passes string to buffer
# for event in self.events: if event.event_id == event_id:  # ← Compares int 5 to string "5"
# Result: 5 == "5" is False in Python
# return None
# raise RPCError(-32000, "Event not found")
```

With type conversion (current code):
```python
# event_id = int("5") → 5
# event = self.event_buffer.get_event_by_id(5)  # ← Passes int to buffer
# for event in self.events: if event.event_id == event_id:  # ← Compares int 5 to int 5
# Result: 5 == 5 is True
# return event
# Serialize and return event details
```

**Status**: The fix is already implemented in the current code. The type conversion (lines 333-337) handles string-to-int conversion with proper error handling. No code changes needed; only verify it's being used.

## 5. Daemon Restart Procedure

**Objective**: Ensure new daemon code (with the fix) is loaded and running

**Step 1: Apply NixOS Configuration**
```bash
# On m1 target (requires --impure for Asahi firmware)
sudo nixos-rebuild switch --flake .#m1 --impure

# On hetzner-sway target
sudo nixos-rebuild switch --flake .#hetzner-sway
```

What happens:
- Nix detects version change (1.0.0 → 1.1.0) in sway-tree-monitor.nix
- Rebuilds Python package (copies sway-tree-monitor/ directory to /nix/store)
- Systemd service points to new package path
- Service restarts on next system boot or manual restart

**Step 2: Manual Daemon Restart** (if needed before reboot)
```bash
# Restart the service
systemctl --user restart sway-tree-monitor

# Check status
systemctl --user status sway-tree-monitor

# View logs
journalctl --user -u sway-tree-monitor -f

# Verify it's running
ps aux | grep "python.*sway.*tree"
```

**Step 3: Verify New Code is Loaded**
```bash
# Check that the new package is in use
python3 -c "import sys; print(sys.path)" | grep sway-tree-monitor
# Should show: /nix/store/...-sway-tree-monitor-1.1.0-python-env/lib/python3.X/site-packages

# Verify RPC socket exists and responds
i3pm monitor --mode diagnose
# Or direct RPC check:
python3 << 'EOF'
import socket
import json
from pathlib import Path
import os

runtime_dir = os.getenv('XDG_RUNTIME_DIR', '/run/user/1000')
socket_path = Path(runtime_dir) / 'sway-tree-monitor.sock'

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(str(socket_path))

# Send ping
request = {
    "jsonrpc": "2.0",
    "method": "ping",
    "params": {},
    "id": 1
}
sock.sendall(json.dumps(request).encode('utf-8') + b'\n')
response = sock.recv(4096).decode('utf-8')
print("Daemon response:", response)
sock.close()
EOF
```

**Step 4: Test the Fix**
```bash
# Query some events
sway-tree-monitor query --last 5 --json

# Get a specific event by ID (the actual test)
sway-tree-monitor get-event 3 --json

# If successful: Returns full event details
# If daemon has old code: Returns "Event not found" error
```

**Troubleshooting**:

| Problem | Cause | Solution |
|---------|-------|----------|
| Socket not found | Daemon not running | `systemctl --user start sway-tree-monitor` |
| "Event not found" | Old daemon code | `systemctl --user restart sway-tree-monitor` |
| Event details empty | Different event ID | Use `sway-tree-monitor query` to list available IDs |
| Type conversion error | Daemon crashed | Check logs: `journalctl --user -u sway-tree-monitor -f` |

**Service Configuration** (`sway-tree-monitor.nix` lines 71-98):
```nix
systemd.user.services.sway-tree-monitor = {
  Unit = {
    Description = "Sway Tree Diff Monitor - Real-time window state monitoring";
    After = [ "sway-session.target" ];
    Requires = [ "sway-session.target" ];
    PartOf = [ "sway-session.target" ];
  };

  Service = {
    Type = "simple";
    ExecStart = "${sway-tree-monitor-daemon}/bin/sway-tree-monitor-daemon";
    Restart = "on-failure";
    RestartSec = "2";

    MemoryHigh = "40M";
    MemoryMax = "50M";
    NoNewPrivileges = true;
    PrivateTmp = true;
  };

  Install = {
    WantedBy = [ "sway-session.target" ];
  };
};
```

The `ExecStart` references `${sway-tree-monitor-daemon}` which is generated from the Nix package. After rebuild, this points to the new version.

## Summary of Decisions

| Topic | Decision | Rationale | Source |
|-------|----------|-----------|--------|
| Error code | -32000 | JSON-RPC 2.0 standard for app-specific errors | RFC compliance, existing implementation |
| Type conversion | `try/except int()` | Graceful, handles both string and int inputs | Best practice, already implemented |
| Error handling | Catch ValueError + TypeError | Covers non-numeric strings and incompatible types | Comprehensive exception handling |
| Error message | Include actual value with `!r` | Aids debugging, shows client-sent value | Better observability |
| Package rebuild | Version bump 1.0.0 → 1.1.0 | Forces Nix to rebuild daemon with new code | NixOS derivation hash changes |
| Restart method | systemctl restart | Standard Linux service restart, ensures new code loaded | Service management best practice |
| Verification | RPC ping + get_event test | Confirms daemon running with new code | End-to-end validation |

## Implementation Checklist

- [x] Type conversion using `int()` with try/except (already in code)
- [x] Catch ValueError and TypeError separately (already in code)
- [x] Raise RPCError with -32000 on event not found (already in code)
- [x] Include event_id in error data for debugging (already in code)
- [x] Version bump in sway-tree-monitor.nix (1.1.0, already in code)
- [ ] Test with string event IDs from TypeScript client
- [ ] Test with missing event IDs
- [ ] Test with invalid event IDs ("abc")
- [ ] Verify daemon restart loads new code

## References

- **JSON-RPC 2.0 Specification**: Standard error codes (-32000 to -32099 for implementation-defined)
- **Python int() Documentation**: Accepts strings with optional base parameter
- **NixOS buildPythonPackage**: Version changes invalidate derivation hash, forcing rebuild
- **systemd Service Management**: restart action reloads ExecStart binary
- **Existing Code**:
  - `/etc/nixos/home-modules/tools/sway-tree-monitor/rpc/server.py` (lines 320-344)
  - `/etc/nixos/home-modules/tools/sway-tree-monitor/buffer/event_buffer.py` (lines 120-135)
  - `/etc/nixos/home-modules/tools/sway-tree-monitor.nix` (lines 1-28, 71-98)

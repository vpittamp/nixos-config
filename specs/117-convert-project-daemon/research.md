# Research: Convert i3pm Project Daemon to User-Level Service

**Feature**: 117-convert-project-daemon
**Date**: 2025-12-14

## Resolved Clarifications

### Q1: How do existing user services handle socket activation?

**Decision**: Use home-manager `systemd.user.sockets` and `systemd.user.services` pattern without socket activation wrapper.

**Research Findings**:
- Existing user services (eww-monitoring-panel, eww-top-bar) use simple `Type=simple` services without socket activation
- Socket activation via home-manager is possible via `systemd.user.sockets.<name>` but adds complexity
- The daemon already handles socket creation internally - it creates the socket file at startup
- **Simplification**: Let the daemon create its own socket file rather than using systemd socket activation

**Reference Implementation** (`eww-monitoring-panel.nix:12570-12599`):
```nix
systemd.user.services.eww-monitoring-panel = {
  Unit = {
    Description = "Eww Monitoring Panel";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "...";
    Restart = "on-failure";
  };
  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

**Alternatives Considered**:
1. Full socket activation via `systemd.user.sockets` - Rejected: Added complexity, daemon already manages socket
2. Keep current system service - Rejected: Requires complex wrapper, doesn't bind to session lifecycle

---

### Q2: How should daemon clients handle socket path resolution?

**Decision**: Invert the priority - check user socket first, then fall back to system socket for backward compatibility.

**Current Implementation** (`daemon_client.py:20-33`):
```python
def get_default_socket_path() -> Path:
    # System socket (primary - daemon runs as system service with socket activation)
    system_socket = Path("/run/i3-project-daemon/ipc.sock")
    if system_socket.exists():
        return system_socket

    # Fallback to user runtime directory (for development/testing)
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"
```

**New Implementation**:
```python
def get_default_socket_path() -> Path:
    # User socket (primary - daemon runs as user service)
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    user_socket = Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"
    if user_socket.exists():
        return user_socket

    # Fallback to system socket (for backward compatibility during transition)
    system_socket = Path("/run/i3-project-daemon/ipc.sock")
    if system_socket.exists():
        return system_socket

    # Return user socket path (will fail with clear error if daemon not running)
    return user_socket
```

**Alternatives Considered**:
1. Hardcode user socket path only - Rejected: No backward compatibility
2. Environment variable override - Rejected: Adds complexity, fallback is simpler

---

### Q3: How should the service be configured for home-manager?

**Decision**: Use `systemd.user.services` with direct Python invocation (no wrapper script).

**Key Configuration Elements**:
- `After = [ "graphical-session.target" ]` - Start after graphical session
- `PartOf = [ "graphical-session.target" ]` - Stop when session stops (unlike system service where PartOf didn't work)
- `Type = "notify"` - Keep sd_notify for watchdog
- Direct `pythonEnv/bin/python3 -m i3_project_daemon` invocation (no wrapper)
- Environment inherits SWAYSOCK, WAYLAND_DISPLAY, XDG_RUNTIME_DIR automatically

**Key Differences from System Service**:
| Aspect | System Service | User Service |
|--------|---------------|--------------|
| Socket discovery | 55-line wrapper script | Inherited from session |
| PartOf= | Doesn't work (NixOS bug?) | Works correctly |
| Socket path | `/run/i3-project-daemon/` | `$XDG_RUNTIME_DIR/i3-project-daemon/` |
| tmpfiles.rules | Required for /run dir | Not needed (dir exists under user) |

---

### Q4: What about the existing socket activation in the system service?

**Decision**: Remove socket activation entirely - let daemon create its own socket.

**Rationale**:
- The Python daemon already has code to create the socket file
- Socket activation adds complexity (separate socket unit file)
- User services don't need the "start on first connection" behavior - they start with the graphical session
- Other user services (eww-*, elephant, swaync) don't use socket activation

**Implementation Change**:
- Remove `systemd.sockets.i3-project-daemon` unit
- Remove `requires = [ "i3-project-daemon.socket" ]` from service
- Daemon creates socket directory and file in ExecStartPre or at startup

---

### Q5: How to handle directory creation for user socket?

**Decision**: Use `ExecStartPre` to create socket directory.

**Implementation**:
```nix
ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/i3-project-daemon";
```

Where `%t` expands to `$XDG_RUNTIME_DIR` in user services.

**Alternatives Considered**:
1. `systemd.user.tmpfiles` - Works but more complex
2. Daemon creates directory - Rejected: Daemon may not have create permission

---

## Best Practices

### Home-Manager User Service Pattern

Based on analysis of existing user services in the codebase:

1. **Unit section**:
   - `After = [ "graphical-session.target" ]` - Wait for GUI
   - `PartOf = [ "graphical-session.target" ]` - Lifecycle binding
   - No `Requires` unless explicitly needed

2. **Service section**:
   - `Type = "simple"` for most services (or `"notify"` if using sd_notify)
   - `ExecStartPre` for directory creation
   - `Restart = "on-failure"` with reasonable `RestartSec`
   - Environment variables inherited from session

3. **Install section**:
   - `WantedBy = [ "graphical-session.target" ]` - Auto-start with session

### Socket Path Pattern

The standard pattern for user-level IPC sockets:
```
$XDG_RUNTIME_DIR/<service-name>/<socket-file>
```

For this feature:
```
$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock
```

This matches the pattern used by other Sway/Wayland components.

---

## Integration Patterns

### Python Daemon Socket Path Updates

Files requiring socket path updates follow this pattern:

**Before** (system socket):
```python
socket_path = Path("/run/i3-project-daemon/ipc.sock")
```

**After** (user socket with fallback):
```python
def get_socket_path():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    user_socket = Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"
    if user_socket.exists():
        return user_socket

    # Backward compatibility fallback
    system_socket = Path("/run/i3-project-daemon/ipc.sock")
    if system_socket.exists():
        return system_socket

    return user_socket  # Return user path for error messages
```

### Bash Script Socket Path Updates

**Before**:
```bash
SOCK="/run/i3-project-daemon/ipc.sock"
```

**After**:
```bash
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
# Fallback to system socket if user socket doesn't exist
if [[ ! -S "$SOCK" && -S "/run/i3-project-daemon/ipc.sock" ]]; then
    SOCK="/run/i3-project-daemon/ipc.sock"
fi
```

### TypeScript/Deno Socket Path Updates

**Before**:
```typescript
const SOCKET_PATH = "/run/i3-project-daemon/ipc.sock";
```

**After**:
```typescript
function getSocketPath(): string {
    const runtimeDir = Deno.env.get("XDG_RUNTIME_DIR") ?? `/run/user/${Deno.uid()}`;
    const userSocket = `${runtimeDir}/i3-project-daemon/ipc.sock`;

    try {
        Deno.statSync(userSocket);
        return userSocket;
    } catch {
        // Fallback to system socket
        const systemSocket = "/run/i3-project-daemon/ipc.sock";
        try {
            Deno.statSync(systemSocket);
            return systemSocket;
        } catch {
            return userSocket;  // Return user path for error messages
        }
    }
}
```

---

## Migration Strategy

1. **Create new user service module** in `home-modules/services/i3-project-daemon.nix`
2. **Update all daemon clients** (18+ files) with new socket path resolution
3. **Update configuration targets** to enable user service instead of system service
4. **Remove system service module** (modules/services/i3-project-daemon.nix)
5. **Test on reference platform** (Hetzner) before other targets

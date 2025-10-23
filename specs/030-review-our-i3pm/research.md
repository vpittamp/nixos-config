# Research: i3pm Production Readiness

**Feature**: 030-review-our-i3pm
**Date**: 2025-10-23
**Purpose**: Resolve technical unknowns and clarify implementation decisions

## Overview

This document consolidates research findings for production readiness decisions. Each section addresses a NEEDS CLARIFICATION item from the Technical Context or Open Questions in the specification.

---

## Decision 1: Layout Storage Format

**Question**: Should layouts be stored in i3's native JSON format or a custom human-readable format?

**Decision**: **Use i3's native JSON format as primary storage, with optional human-readable export**

**Rationale**:
1. **i3 Compatibility**: i3's `append_layout` command requires JSON in i3's specific format. Using this natively eliminates conversion complexity.
2. **Existing Tools**: i3-save-tree outputs i3 JSON format. Our tooling can leverage existing i3 ecosystem.
3. **Validation**: i3's JSON schema is well-defined and validates correctly via i3's parser.
4. **Performance**: No conversion overhead during restoration - pass JSON directly to i3.

**Alternatives Considered**:
- **Custom YAML format**: More human-readable but requires bidirectional conversion. Risk of conversion bugs. Rejected due to added complexity.
- **Custom JSON format**: Cleaner schema but still requires conversion to i3 format. Rejected for same reasons as YAML.
- **TOML format**: Similar issues to YAML. No significant benefit over i3 JSON.

**Implementation**:
```python
# Primary storage: i3 JSON format
layout_file = f"~/.config/i3/layouts/{project_name}-{layout_name}.json"

# Optional: Export to human-readable format for documentation
layout_file_readable = f"~/.config/i3/layouts/{project_name}-{layout_name}.yaml"
```

**Commands**:
```bash
# Save layout (i3 JSON)
i3pm layout save --name=daily-dev

# Export to human-readable format
i3pm layout export --name=daily-dev --format=yaml
```

---

## Decision 2: Event Buffer Persistence

**Question**: Should the event history buffer be persisted to disk on shutdown for debugging historical issues?

**Decision**: **Yes, persist with configurable retention and automatic pruning**

**Rationale**:
1. **Post-Mortem Analysis**: Daemon crashes or system reboots lose valuable debugging context. Persisted events enable analysis after the fact.
2. **Debugging Remote Issues**: Users can save event buffer and share for troubleshooting without running live monitoring.
3. **Disk Space Control**: Configurable retention (default 7 days) and automatic pruning prevent unbounded growth.
4. **Performance**: Async writes on shutdown don't impact runtime performance. Buffer is in-memory during normal operation.

**Alternatives Considered**:
- **No persistence**: Simpler but loses critical debugging data. Rejected due to poor debuggability of historical issues.
- **Persistent circular buffer (mmap)**: Better performance but complexity of memory-mapped files. Rejected as unnecessary optimization.
- **SQLite database**: Overkill for simple event storage. Adds dependency. Rejected for simplicity.

**Implementation**:
```python
# Configuration
EVENT_BUFFER_SIZE = 500  # In-memory circular buffer
EVENT_PERSISTENCE_PATH = "~/.local/share/i3pm/event-history"
EVENT_RETENTION_DAYS = 7

# On daemon shutdown
async def persist_events():
    events_json = json.dumps({
        "timestamp": datetime.now().isoformat(),
        "events": list(event_buffer),  # Last 500 events
    })
    async with aiofiles.open(persistence_path, 'w') as f:
        await f.write(events_json)
```

**Automatic Pruning**:
```python
# On daemon startup
async def load_and_prune_events():
    cutoff = datetime.now() - timedelta(days=EVENT_RETENTION_DAYS)
    # Load persisted events from last N days
    # Merge with current buffer
```

**Commands**:
```bash
# View historical events (from persisted buffer)
i3pm daemon events --historical --since="2 days ago"

# Clear old events manually
i3pm daemon events --prune --older-than="7 days"
```

---

## Decision 3: Monitor Detection Mechanism

**Question**: Should we rely solely on i3 output events or also integrate xrandr/wayland output monitoring?

**Decision**: **Primary: i3 output events. Fallback: xrandr for edge cases.**

**Rationale**:
1. **i3 IPC Authority** (Constitution Principle XI): i3 is the authoritative source for output configuration. Query i3 first.
2. **Event-Driven**: i3 output events provide real-time notifications. No polling required.
3. **Consistency**: All window management state comes from i3. Monitor state should too.
4. **Fallback for Edge Cases**: xrandr handles scenarios where i3's output state is incomplete (e.g., during initialization or xrandr hotplug before i3 processes event).

**Alternatives Considered**:
- **xrandr only**: Requires polling. Doesn't integrate with i3's event system. Rejected due to latency and inconsistency with event-driven architecture.
- **Wayland output protocol**: Not applicable - i3 runs on X11, not Wayland. i3's Wayland successor (Sway) uses different protocol.
- **udev monitoring**: Lower-level than needed. Adds complexity. Rejected as unnecessary.

**Implementation**:
```python
# Primary: Subscribe to i3 output events
await i3.subscribe([Event.OUTPUT])

async def on_output_event(event):
    # Query authoritative state from i3
    outputs = await i3.get_outputs()
    validate_workspace_assignments(outputs)

# Fallback: xrandr for edge cases
async def validate_outputs_xrandr():
    xrandr_outputs = parse_xrandr_output()
    i3_outputs = await i3.get_outputs()
    # Reconcile if discrepancies
```

**Edge Cases**:
- **Monitor hotplug during i3 restart**: xrandr fallback detects new monitors before i3 reconnects
- **Missing output in i3 tree**: Query xrandr to confirm physical display exists
- **Output resolution mismatch**: xrandr provides physical capabilities, i3 provides current config

---

## Decision 4: Classification Precedence

**Question**: When system-wide and user rules conflict, should there be a way for users to override system rules?

**Decision**: **System rules win by default, add explicit user override flag**

**Rationale**:
1. **Enterprise Security**: System administrators need enforceable policies. Users shouldn't circumvent security classifications.
2. **Sensible Defaults**: System rules represent organizational or expert-defined classifications. Users benefit from these defaults.
3. **Opt-In Override**: Users who understand implications can explicitly override with `--user-override` flag.
4. **Audit Trail**: Explicit overrides are logged for security auditing.

**Alternatives Considered**:
- **User rules always win**: Circumvents administrator intent. Rejected for security reasons.
- **No override mechanism**: Too restrictive for power users. Rejected as heavy-handed.
- **Merge strategy (union/intersection)**: Complex logic, confusing semantics. Rejected for complexity.

**Implementation**:
```python
# Classification rule precedence
def get_window_classification(window_class):
    # 1. Check system rules (highest priority)
    if system_rule := check_system_rules(window_class):
        return system_rule

    # 2. Check user rules (only if no system rule)
    if user_rule := check_user_rules(window_class):
        return user_rule

    # 3. Default classification
    return ClassificationType.GLOBAL  # Safe default

# User override (explicit flag required)
def create_project_with_override(project_config, user_override=False):
    if user_override:
        log_audit_event("USER_OVERRIDE", project_config)
        # Allow user rules to take precedence
    else:
        # Normal precedence (system > user)
```

**Configuration**:
```json
// /etc/i3pm/rules.json (system-wide)
{
  "scoped_classes": ["firefox", "chrome"],
  "enforcement": "strict"  // Prevents user override
}

// ~/.config/i3/app-classes.json (user-specific)
{
  "scoped_classes": ["vscode", "alacritty"],
  "overrides": {
    "firefox": "global"  // Ignored if system rule is "strict"
  }
}
```

**Commands**:
```bash
# Normal behavior (system rules win)
i3pm project create --name=test

# Explicit user override (if system allows)
i3pm project create --name=test --user-override

# View effective rules (shows precedence)
i3pm rules list --effective
```

---

## Decision 5: Launch Command Discovery Method

**Question**: How should we discover launch commands for applications in saved layouts?

**Decision**: **Multi-source discovery with priority fallback: Desktop files → Process cmdline → User-provided commands**

**Rationale**:
1. **Desktop Files** (Priority 1): Most applications have .desktop files with `Exec=` lines. Standard, reliable, includes arguments.
2. **Process Cmdline** (Priority 2): For windows without desktop files, inspect `/proc/{pid}/cmdline` at capture time.
3. **User-Provided** (Priority 3): Allow users to manually specify commands for edge cases.
4. **Validation**: Test discovered commands during save to warn about non-executable paths.

**Alternatives Considered**:
- **Desktop files only**: Misses applications without .desktop files (custom scripts, AppImages). Rejected as incomplete.
- **Process cmdline only**: Less reliable (environment variables, wrapper scripts). Rejected as primary method.
- **Manual only**: Too much user burden. Rejected except as fallback.
- **ML-based inference**: Overkill for this problem. Rejected as unnecessary complexity.

**Implementation**:
```python
# 1. Try desktop file lookup
def find_desktop_file(window_class, window_instance):
    desktop_dirs = [
        "/usr/share/applications",
        "~/.local/share/applications"
    ]

    # Search for .desktop files matching WM_CLASS
    for desktop_file in search_desktop_files(desktop_dirs, window_class):
        exec_line = parse_desktop_file(desktop_file)["Exec"]
        return expand_desktop_exec(exec_line)

    return None

# 2. Fallback to process cmdline
async def get_process_cmdline(window):
    pid = window.pid
    if pid:
        cmdline_path = f"/proc/{pid}/cmdline"
        cmdline = await read_file(cmdline_path)
        return parse_cmdline(cmdline)  # Handle \0 separators
    return None

# 3. Prompt user if both fail
def prompt_launch_command(window_title, window_class):
    return input(f"Launch command for {window_title} ({window_class}): ")

# Discovery workflow
async def discover_launch_command(window):
    # Try desktop file
    if cmd := find_desktop_file(window.window_class, window.window_instance):
        if validate_command(cmd):
            return cmd

    # Try process cmdline
    if cmd := await get_process_cmdline(window):
        if validate_command(cmd):
            return cmd

    # Prompt user
    return prompt_launch_command(window.name, window.window_class)
```

**Validation**:
```python
def validate_command(cmd):
    # Check if command executable exists
    executable = shlex.split(cmd)[0]
    if not shutil.which(executable):
        warning(f"Command not found: {executable}")
        return False
    return True
```

**Layout Format** (includes discovered commands):
```json
{
  "workspace": 1,
  "windows": [
    {
      "class": "firefox",
      "launch_command": "firefox --new-window",
      "swallow": {
        "class": "^firefox$",
        "instance": "^Navigator$"
      },
      "geometry": {...}
    }
  ]
}
```

---

## Decision 6: IPC Authentication Method

**Question**: How should we authenticate IPC clients connecting to the daemon?

**Decision**: **UID-based authentication via UNIX socket peer credentials**

**Rationale**:
1. **Standard UNIX Approach**: UNIX sockets provide `SO_PEERCRED` for retrieving connecting process UID/GID.
2. **No Additional Infrastructure**: No need for tokens, certificates, or external auth systems.
3. **Per-User Isolation**: Each user's daemon only accepts connections from processes with matching UID.
4. **Performance**: Zero overhead - credential check is O(1) syscall.

**Alternatives Considered**:
- **Token-based auth**: Requires token distribution, storage, rotation. Overkill for local IPC. Rejected as unnecessary complexity.
- **Certificate-based (mTLS)**: Heavy for UNIX socket IPC. Better for network sockets. Rejected as overengineered.
- **No authentication**: Security risk. Malicious process could control another user's daemon. Rejected for security.

**Implementation**:
```python
import socket
import struct

# Server side (daemon)
async def authenticate_client(conn: socket.socket):
    # Get peer credentials (Linux SO_PEERCRED)
    creds = conn.getsockopt(
        socket.SOL_SOCKET,
        socket.SO_PEERCRED,
        struct.calcsize('3i')
    )
    pid, uid, gid = struct.unpack('3i', creds)

    # Verify UID matches daemon's UID
    if uid != os.getuid():
        raise PermissionError(f"IPC connection from UID {uid} rejected (expected {os.getuid()})")

    return True

# Client side (CLI)
# No changes needed - authentication is transparent
```

**Socket Permissions**:
```python
# Create socket with restrictive permissions
SOCKET_PATH = f"/run/user/{os.getuid()}/i3pm/daemon.sock"

# Socket file permissions: 0600 (owner read/write only)
os.chmod(SOCKET_PATH, 0o600)
```

**Error Messages**:
```bash
$ i3pm daemon status
Error: Permission denied (UID mismatch)
  Your UID: 1001
  Daemon UID: 1000

Hint: You are trying to connect to another user's daemon.
      Start your own daemon with: systemctl --user start i3-project-event-listener
```

---

## Decision 7: Sensitive Data Sanitization Patterns

**Question**: What patterns should be sanitized from command lines and window titles in logs/events?

**Decision**: **Comprehensive regex-based sanitization for common secret patterns**

**Rationale**:
1. **Defense in Depth**: Even if applications leak secrets in window titles, we sanitize before logging.
2. **Common Patterns**: Target known patterns (passwords, tokens, API keys) used in CLI tools and applications.
3. **Configurable**: Allow users to add custom patterns for organization-specific secrets.
4. **Balance**: Sanitize enough to prevent leaks without over-sanitizing useful debugging info.

**Patterns to Sanitize**:
```python
SANITIZE_PATTERNS = [
    # API keys and tokens
    (r'(api[_-]?key|token|secret)[=:\s]+[A-Za-z0-9_-]{20,}', 'API_KEY_REDACTED'),
    (r'Bearer\s+[A-Za-z0-9_-]{20,}', 'BEARER_TOKEN_REDACTED'),

    # Passwords
    (r'(password|passwd|pwd)[=:\s]+\S+', 'PASSWORD_REDACTED'),
    (r'--password[=\s]+\S+', '--password=PASSWORD_REDACTED'),

    # AWS credentials
    (r'AWS_SECRET_ACCESS_KEY[=:\s]+\S+', 'AWS_SECRET_REDACTED'),
    (r'AKIA[0-9A-Z]{16}', 'AWS_ACCESS_KEY_REDACTED'),

    # GitHub tokens (ghp_, gho_, ghs_)
    (r'gh[pso]_[A-Za-z0-9_]{36,}', 'GITHUB_TOKEN_REDACTED'),

    # SSH private key indicators
    (r'-----BEGIN.*PRIVATE KEY-----', 'PRIVATE_KEY_REDACTED'),

    # Database connection strings
    (r'(mysql|postgresql|mongodb)://[^@]+:[^@]+@', 'DB_CONNECTION_REDACTED'),

    # JWT tokens
    (r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', 'JWT_TOKEN_REDACTED'),
]

def sanitize_text(text: str) -> str:
    for pattern, replacement in SANITIZE_PATTERNS:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text
```

**Application**:
```python
# Sanitize before logging
def log_event(event):
    event.command_line = sanitize_text(event.command_line)
    event.window_title = sanitize_text(event.window_title)
    logger.info(event)

# Sanitize before diagnostic export
def export_diagnostics():
    diagnostics = collect_diagnostics()
    diagnostics["events"] = [
        {**event, "command": sanitize_text(event["command"])}
        for event in diagnostics["events"]
    ]
    return diagnostics
```

**Configuration** (user-extensible):
```json
// ~/.config/i3pm/sanitize-patterns.json
{
  "custom_patterns": [
    {
      "pattern": "MYORG_SECRET_[A-Z0-9]+",
      "replacement": "MYORG_SECRET_REDACTED"
    }
  ]
}
```

---

## Summary of Decisions

| Decision | Choice | Impact |
|----------|--------|--------|
| Layout storage format | i3 native JSON (with optional YAML export) | Eliminates conversion complexity, leverages i3 ecosystem |
| Event buffer persistence | Yes, with 7-day retention and auto-pruning | Enables post-mortem debugging without unbounded growth |
| Monitor detection | i3 output events (primary), xrandr (fallback) | Aligns with constitution (i3 IPC authority), handles edge cases |
| Classification precedence | System rules win, explicit user override flag | Enables enterprise security while preserving power user flexibility |
| Launch command discovery | Desktop files → Process cmdline → User-provided | Reliable multi-source approach with fallbacks |
| IPC authentication | UID-based via UNIX socket peer credentials | Standard, performant, per-user isolation |
| Sanitization patterns | Comprehensive regex for common secrets | Prevents credential leaks in logs without over-sanitizing |

All NEEDS CLARIFICATION items from Technical Context are now resolved. Proceed to Phase 1 (Design & Contracts).

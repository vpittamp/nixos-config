# eBPF AI Agent Monitor

A kernel-level monitoring daemon for AI agent processes (Claude Code, Codex CLI) on NixOS.

## Overview

This daemon uses eBPF syscall tracing to detect when AI processes transition from active processing to waiting-for-input state, then sends desktop notifications and updates badge files for the eww monitoring panel.

## Features

- **Kernel-level detection**: Uses eBPF tracepoints for efficient syscall monitoring
- **Low overhead**: Kernel-space filtering keeps CPU usage < 1%
- **Fast detection**: < 100ms latency from syscall to notification
- **EWW integration**: Badge files compatible with existing monitoring panel
- **Desktop notifications**: SwayNC integration for completion alerts

## Requirements

- NixOS with kernel 5.2+ (preferably 6.x for full BTF support)
- Sway window manager
- tmux terminal multiplexer
- Ghostty terminal emulator
- BCC (BPF Compiler Collection)

## Installation

Add to your NixOS configuration:

```nix
{
  services.ebpf-ai-monitor = {
    enable = true;
    user = "your-username";
  };
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#your-target
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable the eBPF monitor service |
| `user` | string | required | Username to monitor AI processes for |
| `processes` | list[str] | ["claude", "codex"] | Process names to monitor |
| `waitThreshold` | int | 1000 | Milliseconds before "waiting" state |
| `logLevel` | enum | "INFO" | Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL) |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    System Level (root)                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  ebpf-ai-monitor.service                              │  │
│  │  - Loads eBPF programs (tracepoints)                  │  │
│  │  - Monitors sys_enter_read, sys_exit_read             │  │
│  │  - Writes badge files (chown to user)                 │  │
│  │  - Triggers notifications via D-Bus                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
          │
          │ Badge files written to:
          │ /run/user/<uid>/i3pm-badges/<window_id>.json
          │ (owned by user)
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    User Session                              │
│  ┌────────────────┐    ┌─────────────────────────────────┐  │
│  │  eww panel     │◄───│  inotify on badge directory     │  │
│  │  (existing)    │    │                                 │  │
│  └────────────────┘    └─────────────────────────────────┘  │
│                                                              │
│  ┌────────────────┐    ┌─────────────────────────────────┐  │
│  │  SwayNC        │◄───│  notify-send (via D-Bus)        │  │
│  │  (existing)    │    │                                 │  │
│  └────────────────┘    └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Process State Machine

```
             ┌─────────────────┐
             │    UNKNOWN      │
             │ (initial state) │
             └────────┬────────┘
                      │ process_detected
                      ▼
┌────────────────────────────────────────┐
│                WORKING                  │
│  (process running, not waiting input)  │
└─────────────┬──────────────────────────┘
              │
 sys_enter_read(fd=0)
 + timeout elapsed
              │
              ▼
┌────────────────────────────────────────┐
│                WAITING                  │
│  (blocked on stdin read > threshold)   │◀─────┐
└─────────────┬──────────────────────────┘      │
              │                                  │
 process_exit │    sys_exit_read                 │
              │    (user resumes)                │
              ▼                                  │
┌────────────────────────────────────────┐      │
│                EXITED                   │      │
│  (process terminated)                   │      │
└────────────────────────────────────────┘      │
                                                 │
User types → sys_exit_read ─────────────────────┘
```

## Troubleshooting

### Service won't start

```bash
# Check status
sudo systemctl status ebpf-ai-monitor

# View logs
sudo journalctl -u ebpf-ai-monitor -f

# Verify BCC is available
python3 -c "from bcc import BPF; print('BCC OK')"
```

### No events detected

```bash
# Run bpftrace manually to test
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_read /args->fd == 0/ { printf("%s\n", comm); }'

# Then run claude in another terminal
```

### Badge files not appearing

```bash
# Check directory
ls -la /run/user/$(id -u)/i3pm-badges/

# Check service has write access
sudo journalctl -u ebpf-ai-monitor | grep -i badge
```

### Notifications not working

```bash
# Test notify-send
notify-send "Test" "This is a test"

# Check SwayNC
systemctl --user status swaync
```

## Development

```bash
# Run manually for testing
sudo python3 -m ebpf_ai_monitor --user vpittamp --log-level DEBUG

# Run tests
pytest tests/ebpf-ai-monitor/
```

## Related Documentation

- [Feature Specification](../../../specs/119-explore-ebpf-monitor/spec.md)
- [Implementation Plan](../../../specs/119-explore-ebpf-monitor/plan.md)
- [Quickstart Guide](../../../specs/119-explore-ebpf-monitor/quickstart.md)
- [Badge State Contract](../../../specs/119-explore-ebpf-monitor/contracts/badge-state.json)

## License

MIT

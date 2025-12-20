# NixOS Configuration - LLM Navigation Guide

## Quick Start

```bash
# Test config (ALWAYS before applying)
sudo nixos-rebuild dry-build --flake .#hetzner-sway  # Hetzner
sudo nixos-rebuild dry-build --flake .#m1 --impure  # M1 Mac
sudo nixos-rebuild switch --flake .#<target>        # Apply
```

**Targets**: `wsl` (Windows), `hetzner-sway` (remote), `m1` (Apple Silicon), containers

## Directory Structure

```
flake.nix           # Entry point (flake-parts)
lib/helpers.nix     # Reusable functions
nixos/default.nix   # System definitions
home/default.nix    # Darwin home config
configurations/     # Target configs
hardware/           # Hardware settings
modules/            # System modules
home-modules/       # User environment
```

## Key Keybindings

| Key | Action |
|-----|--------|
| `Meta+D` / `Alt+Space` | Elephant launcher |
| `Mod+M` | Monitoring panel |
| `Mod+Shift+M` | Toggle dock mode (overlay ↔ docked) |
| `Win+P` | Project switcher |
| `Win+Shift+P` | Clear project (global) |
| `Win+Return` | Scratchpad terminal |
| `Win+C/G/Y` | VS Code / Lazygit / Yazi |
| `CapsLock` (M1) / `Ctrl+0` | Workspace mode |
| `Mod+Tab` | Workspace overview |

## Monitoring Panel (Features 085, 086, 099, 109, 125)

`Mod+M` toggle visibility | `Mod+Shift+M` toggle dock mode | `Alt+1-7` tabs

**Modes**: 🔳 Overlay (floating) | 📌 Docked (reserved space)
- **Overlay**: Panel floats over windows, clicks pass through when hidden
- **Docked**: Panel reserves screen space, windows resize to fit

**Status**: ● teal=active | ● red=dirty | ↑↓ sync | 💤 stale | ✓ merged | ⚠ conflicts

```bash
systemctl --user restart eww-monitoring-panel  # Restart
journalctl --user -u eww-monitoring-panel -f   # Logs
```

## Project Management (i3pm)

```bash
i3pm project {switch|create|list|current}  # pswitch/pclear/plist aliases
i3pm worktree {list|create|remove} <repo>
i3pm daemon {status|events}
i3pm diagnose {health|window <id>|validate|events|socket-health}
i3pm monitors {status|reassign|config}
i3pm layout {save|restore|list|delete} <name>
i3pm scratchpad {toggle|status|cleanup}
```

**Scoped apps** (hidden on switch): Ghostty, VS Code, Yazi, Lazygit
**Global apps** (always visible): Firefox, PWAs, K9s

### Remote Projects (Feature 087)

```bash
i3pm project create-remote <name> \
  --local-dir ~/projects/foo --remote-host hetzner.tailnet \
  --remote-user vpittamp --remote-dir /home/vpittamp/dev/foo
```

Terminal apps auto-wrap with SSH. GUI apps not supported in remote projects.

### Worktree Environment (Feature 098)

Environment variables in launched apps: `I3PM_IS_WORKTREE`, `I3PM_PARENT_PROJECT`, `I3PM_BRANCH_NUMBER`, `I3PM_BRANCH_TYPE`, `I3PM_GIT_*`

## Sway Configuration (Feature 047)

**Dynamic** (hot-reload): `~/.config/sway/{window-rules,appearance,workspace-assignments}.json`
**Static** (rebuild): `home-modules/desktop/sway-keybindings.nix`

```bash
swaymsg reload              # Reload (or Mod+Shift+C)
swayconfig validate         # Validate
swayconfig rollback <hash>  # Rollback
```

## Bars & Device Controls (Features 057, 060, 116)

```bash
systemctl --user restart eww-top-bar           # Top bar
systemctl --user restart sway-workspace-panel  # Bottom bar
systemctl --user restart swaync                # Notifications
```

**Device controls**: Volume 󰕾 | Brightness 󰃟 | Bluetooth 󰂯 | Battery 󰁹 (click to expand)
**Devices tab**: `Mod+M` → `Alt+7`

## Workspace Navigation (Feature 042)

Enter mode (`CapsLock`/`Ctrl+0`) → type digits → `Enter` | `Escape` cancel | `+Shift` move window
Type `:` in workspace mode for project fuzzy search

## PWA Management

```bash
pwa-install-all   # Install all
pwa-list          # List configured
```

**Workspaces**: Regular apps 1-50, PWAs 50+
Edit `home-modules/tools/firefox-pwas-declarative.nix` → rebuild → `pwa-install-all`

## Session & Layout (Features 074, 076)

```bash
i3pm layout save my-layout     # Save
i3pm layout restore my-layout  # Restore (idempotent via marks)
```

**Mark format**: `i3pm_app:name`, `i3pm_project:name`, `i3pm_ws:N`, `i3pm_scope:scoped`

## Multi-Monitor (Features 083, 084)

```bash
set-monitor-profile single/dual/triple     # Hetzner
set-monitor-profile local-only/local+1vnc/local+2vnc  # M1
```

**VNC**: `vnc://<tailscale-ip>:{5900|5901|5902}`

## Claude Code (Feature 090)

Notifications on task completion. `Enter` returns to terminal, `Escape` dismisses.

```bash
systemctl --user status swaync
ls ~/.config/claude-code/hooks/
```

## Observability Stack (Feature 129)

Unified telemetry collection via Grafana Alloy, exporting to Kubernetes LGTM stack.

**Architecture**:
```
AI CLIs → Alloy :4318 → [batch] → otel-ai-monitor :4320 (local EWW)
                               → K8s OTEL Collector (remote)
System  → node exporter → Alloy → Mimir (K8s)
Journald → Alloy → Loki (K8s)
```

**Services**:
| Service | Port | Purpose |
|---------|------|---------|
| grafana-alloy | 4318 (OTLP), 12345 (UI) | Unified telemetry collector |
| otel-ai-monitor | 4320 | Local AI session tracking for EWW |
| grafana-beyla | - | eBPF auto-instrumentation (optional) |
| pyroscope-agent | - | Continuous profiling (optional) |

**Commands**:
```bash
systemctl status grafana-alloy              # Service status
journalctl -u grafana-alloy -f              # Logs
curl -s localhost:4318/v1/traces            # Test OTLP endpoint
curl -s localhost:12345/metrics             # Alloy metrics
```

**Alloy UI**: http://localhost:12345 (live debugging enabled)

**Configuration** (`configurations/{thinkpad,hetzner}.nix`):
```nix
services.grafana-alloy = {
  enable = true;
  k8sEndpoint = "https://otel-collector-1.tail286401.ts.net";  # Via Tailscale Operator Ingress
  lokiEndpoint = "https://loki.tail286401.ts.net";
  mimirEndpoint = "https://mimir.tail286401.ts.net";
  enableNodeExporter = true;  # System metrics
  enableJournald = true;      # Log collection
  journaldUnits = [ "grafana-alloy.service" "otel-ai-monitor.service" ];
};
```

**Graceful Degradation**: Local AI monitoring (EWW widgets) works when K8s offline. Remote telemetry queued (100MB buffer) and retried.

## Testing

```bash
sway-test run tests/test.json
i3-project-test {run|suite|verify-state}
```

## Quick Debug

```bash
nixos-rebuild dry-build --flake .#<target> --show-trace
nix flake show
i3pm diagnose health
journalctl --user -u i3-project-event-listener -f
```

## Additional Docs

- `docs/ARCHITECTURE.md` - System design
- `docs/PYTHON_DEVELOPMENT.md` - Python standards
- `docs/PWA_SYSTEM.md` - PWA details
- `docs/M1_SETUP.md` - Apple Silicon
- `docs/ONEPASSWORD.md` - 1Password integration
- `/etc/nixos/specs/<feature>/quickstart.md` - Feature specs

## Tech Stack

- **Daemon**: Python 3.11+, i3ipc.aio, Pydantic, asyncio
- **CLI**: TypeScript/Deno 1.40+, Zod
- **UI**: Eww 0.4+ (GTK3), SwayNC
- **Config**: Nix flakes, JSON files in `~/.config/{i3,sway}/`

## Active Technologies
- Bash (hooks), Python 3.11+ (daemon/backend), Nix (configuration) + i3ipc.aio, Pydantic, eww (GTK3 widgets), swaync, inotify-tools (117-improve-notification-progress-indicators)
- File-based badges at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json` (117-improve-notification-progress-indicators)
- Nix (configuration), Bash (scripts), Yuck (eww widgets), CSS (styling) + eww 0.4+, swaymsg (Sway IPC), jq, bash (119-fix-window-close-actions)
- N/A (eww state is in-memory, config in ~/.config/eww-monitoring-panel) (119-fix-window-close-actions)
- Bash (cleanup script), Python 3.11 (daemon health endpoint), Nix (service configuration) + systemd, i3ipc.aio, bash coreutils (121-improve-socket-discovery)
- N/A (runtime state only) (121-improve-socket-discovery)
- Python 3.11+ (OTLP receiver), Nix (configuration), Yuck/SCSS (EWW widgets) + opentelemetry-proto (parsing), aiohttp/uvicorn (HTTP server), EWW deflisten (123-otel-tracing)
- N/A (in-memory session state only, no persistence) (123-otel-tracing)
- Nix (flakes), Yuck (eww widget DSL), SCSS, Bash (scripts), Python 3.11+ (backend) + eww 0.4+, Sway IPC (layer-shell protocol), GTK3, i3ipc.aio (125-convert-sidebar-split-pane)
- File-based state persistence (`$XDG_STATE_HOME/eww-monitoring-panel/dock-mode`) (125-convert-sidebar-split-pane)
- Nix (flakes), Alloy configuration language, Python 3.11+ (existing otel-ai-monitor) + Grafana Alloy 1.x, Grafana Beyla 1.x, Pyroscope agent, opentelemetry-collector-contrib (129-create-observability-nixos)
- Remote only (Kubernetes LGTM stack); local memory buffer (100MB) for offline queuing (129-create-observability-nixos)
- JavaScript (Node.js, Claude Code runtime) + Node.js `http` module (built-in), `node:buffer` (130-create-logical-multi)
- N/A (stateless interceptor, memory-only during session) (130-create-logical-multi)

## Recent Changes
- 117-improve-notification-progress-indicators: Added Bash (hooks), Python 3.11+ (daemon/backend), Nix (configuration) + i3ipc.aio, Pydantic, eww (GTK3 widgets), swaync, inotify-tools

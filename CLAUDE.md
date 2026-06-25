# NixOS Configuration - LLM Navigation Guide

## Quick Start

```bash
# Test config (ALWAYS before applying)
sudo nixos-rebuild dry-build --flake .#thinkpad     # ThinkPad
sudo nixos-rebuild dry-build --flake .#ryzen        # Ryzen desktop
sudo nixos-rebuild switch --flake .#<target>        # Apply
```

**Targets**: `thinkpad`, `ryzen`, `kubevirt-sway`, `hetzner` (legacy), containers

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
| `Win+C/G/Y` | VS Code / Lazygit / Yazi (global, open in $HOME) |
| `CapsLock` (M1) / `Ctrl+0` | Workspace mode |
| `Mod+Tab` | Workspace overview |

## Walker/Elephant Launcher

`Meta+D` or `Alt+Space` opens Walker. Use prefixes for quick access:

| Prefix | Provider | Description |
|--------|----------|-------------|
| `*` | 1Password | Search vaults (Return=password, Shift+Return=username, Ctrl+Return=OTP) |
| `=` | Calculator | Math expressions |
| `:` | Clipboard | Clipboard history |
| `/` | Files | File browser |
| `@` | Websearch | Web search |
| `>` | Runner | Shell commands |
| `?` | Help | List all providers |
| `;s ` | Sesh | Tmux session switcher |
| `;h ` | History | Browser history |

**1Password Integration**: Requires 1Password GUI running and `op` CLI authenticated.

## Monitoring Panel (Features 085, 086, 099, 109, 125)

`Mod+M` toggle visibility | `Mod+Shift+M` toggle dock mode | `Alt+1-7` tabs

**Modes**: 🔳 Overlay (floating) | 📌 Docked (reserved space)
- **Overlay**: Panel floats over windows, clicks pass through when hidden
- **Docked**: Panel reserves screen space, windows resize to fit

**Status**: ● teal=active | ● red=dirty | ↑↓ sync | 💤 stale | ✓ merged | ⚠ conflicts

```bash
systemctl --user restart quickshell-runtime-shell  # Restart
journalctl --user -u quickshell-runtime-shell -f   # Logs
```

## i3pm Runtime Daemon

The project-scoping system (project switch, scoped-app hide/show, per-project
scratchpad/layouts, worktree discovery) was **retired** — herdr now owns the
terminal/AI-session workflow. The i3pm daemon remains as the runtime backbone:
it builds the dashboard snapshot that powers the QuickShell bottom bar + herdr
panel, routes focus, aggregates local + remote herdr, and manages monitors/
display. All apps are global (no hide-on-switch); the bottom-bar context chip
shows the focused herdr space's `repo[:branch]` + git status.

```bash
i3pm daemon {status|events}
i3pm diagnose {health|window <id>|validate|events|socket-health}
i3pm monitors {status|reassign|config}
i3pm dashboard {snapshot|watch}
i3pm herdr-proxy {snapshot|events|focus}
i3pm context {current|clear}            # pclear/pcurrent aliases
i3pm health
```

## Sway Configuration (Feature 047)

**Dynamic** (hot-reload): `~/.config/sway/{window-rules,appearance}.json`
**Nix-generated** (rebuild): `workspace-assignments.json`, `monitor-profiles/*.json`, `monitor-profile.default`, `active-outputs`
**Static** (rebuild): `home-modules/desktop/sway-keybindings.nix`

```bash
swaymsg reload              # Reload (or Mod+Shift+C)
swayconfig validate         # Validate
swayconfig rollback <hash>  # Rollback
```

## Bars & Device Controls

Bars, panels, and on-screen widgets are driven by Quickshell (`home-modules/desktop/quickshell-runtime-shell/`).

```bash
systemctl --user restart quickshell-runtime-shell  # Bar + panel
systemctl --user restart swaync                    # Notifications
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

## AI CLI Sessions

**Notifications**: `Enter` returns to terminal, `Escape` dismisses.

**Session Tracking**: QuickShell reads Herdr-native agent state through the i3pm daemon. The panel shows Herdr workspaces/tabs/panes and raw `agent_status` values (`working`, `blocked`, `done`, `idle`, `unknown`).

**Providers shown in the panel**: Herdr-managed Claude Code and Codex CLI sessions. Non-Herdr sessions are intentionally invisible in this panel.

```bash
herdr status --json                                # Server/protocol health
herdr agent list                                   # Agent sessions
herdr pane list                                    # Herdr panes
herdr integration status                           # Claude/Codex hooks
systemctl --user restart quickshell-runtime-shell  # Panel
i3pm health                                        # Runtime health, including Herdr
```

## Observability Stack (Feature 129)

Unified telemetry collection via Grafana Alloy, exporting to the hub K8s cluster's OTEL collector over Tailscale. The hub is the canonical observability sink (otel-collector + otel-clickhouse + grafana + tempo); spokes forward in-cluster traces to it via `clickhouse-hub-egress`.

**Architecture**:
```
Clients → Alloy :4318 → [batch] → otel-collector-hub-1.tail286401.ts.net:4318
                              → K8s otel-collector (hub observability ns)
                                → otel-clickhouse-tailnet (hub)         (durable storage)
                                → otlphttp/mlflow                       (per-CLI MLflow experiments)

System  → node exporter → Alloy → Mimir (K8s)
Journald → Alloy → Loki (K8s)
```

**Services**:
| Service | Port | Purpose |
|---------|------|---------|
| grafana-alloy | 4318 (OTLP), 12345 (UI) | Unified telemetry collector |
| grafana-beyla | - | eBPF auto-instrumentation (optional) |
| pyroscope-agent | - | Continuous profiling (optional) |

**Commands**:
```bash
systemctl status grafana-alloy              # Service status
journalctl -u grafana-alloy -f              # Logs
curl -s localhost:4318/v1/traces            # Test OTLP endpoint
curl -s localhost:12345/metrics             # Alloy metrics
curl -sk http://clickhouse-hub.tail286401.ts.net:8123/ping   # ClickHouse reachable
```

**Alloy UI**: http://localhost:12345 (live debugging enabled)

**Configuration** (`configurations/{thinkpad,ryzen}.nix`):
```nix
services.grafana-alloy = {
  enable = true;
  # k8sEndpoint default = http://otel-collector-hub-1.tail286401.ts.net:4318 (Tailscale LoadBalancer on hub; "-1" suffix is from a stale Service entry that needs Tailscale admin cleanup)
  # NOTE: lokiEndpoint/mimirEndpoint still default to legacy *.cnoe.localtest.me:8443 URLs
  # and silently fail (Loki/Mimir aren't deployed; observability is hub-side). Logs/metrics
  # flow through the K8s otel-collector on hub instead.
  enableNodeExporter = true;
  enableJournald = true;
  journaldUnits = [ "grafana-alloy.service" "i3pm-daemon.service" ];
};
```

**Known Issues / Troubleshooting**:
- OTLP gRPC `4317` may be taken by `docker-proxy`; prefer OTLP HTTP on `4318` (Alloy default).
- `*.cnoe.localtest.me:8443` URLs no longer work — they were idpbuilder/kind legacy that resolved to `::1`. Post-A6 hub-managed mode moved observability to hub-side Tailscale Ingresses (`otel-collector-hub.tail286401.ts.net`, `clickhouse-hub.tail286401.ts.net`, `grafana-hub.tail286401.ts.net`, etc.). The dev/ryzen spoke Ingresses for observability were retired (see stacks `389291160`, `ab457a041`).

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
- `docs/AI_TRACING_GRAFANA.md` - Correlating Claude Code telemetry in Grafana
- `/etc/nixos/specs/<feature>/quickstart.md` - Feature specs

## Tech Stack

- **Daemon**: Python 3.11+, i3ipc.aio, Pydantic, asyncio
- **CLI**: TypeScript/Deno 1.40+, Zod
- **UI**: Quickshell (Qt/QML), SwayNC
- **Config**: Nix flakes, JSON files in `~/.config/{i3,sway}/`

For per-feature history, see `git log` or `ls specs/`. EWW is no longer in use; see Quickshell (`home-modules/desktop/quickshell-runtime-shell/`) for panel/widget code.

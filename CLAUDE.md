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
| `Mod+Shift+M` | Panel focus mode |
| `Win+P` | Project switcher |
| `Win+Shift+P` | Clear project (global) |
| `Win+Return` | Scratchpad terminal |
| `Win+C/G/Y` | VS Code / Lazygit / Yazi |
| `CapsLock` (M1) / `Ctrl+0` | Workspace mode |
| `Mod+Tab` | Workspace overview |

## Monitoring Panel (Features 085, 086, 099, 109)

`Mod+M` toggle | `Mod+Shift+M` focus mode | `Alt+1-7` tabs

**Focus mode keys**: `j/k` nav | `g/G` first/last | `Enter` select | `Space` expand | `c` create | `d` delete | `y` copy path | `t` terminal | `E` Code | `F` yazi | `L` lazygit

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
i3pm diagnose {health|window <id>|validate|events}
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
- Bash (hooks/monitor), Python 3.11+ (daemon/backend), Nix (configuration) + tmux, i3ipc.aio, Pydantic, eww (GTK3 widgets), swaync, inotify-tools (117-improve-notification-progress-indicators)
- File-based badges at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json` (117-improve-notification-progress-indicators)
- Nix (configuration), Bash (scripts), Yuck (eww widgets), CSS (styling) + eww 0.4+, swaymsg (Sway IPC), jq, bash (119-fix-window-close-actions)
- N/A (eww state is in-memory, config in ~/.config/eww-monitoring-panel) (119-fix-window-close-actions)
- Python 3.11+ (monitoring_data.py, git_utils.py), Yuck/GTK (eww widgets), SCSS (styling) + eww 0.4+, i3ipc.aio, Pydantic, existing i3_project_manager infrastructure (120-improve-git-changes)
- N/A (data computed on demand from git commands) (120-improve-git-changes)

## Recent Changes
- 117-improve-notification-progress-indicators: Added Bash (hooks), Python 3.11+ (daemon/backend), Nix (configuration) + i3ipc.aio, Pydantic, eww (GTK3 widgets), swaync, inotify-tools

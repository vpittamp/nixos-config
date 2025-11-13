# NixOS Configuration - LLM Navigation Guide

## 🚀 Quick Start

### Essential Commands

```bash
# Test configuration changes (ALWAYS RUN BEFORE APPLYING)
sudo nixos-rebuild dry-build --flake .#wsl    # For WSL
sudo nixos-rebuild dry-build --flake .#hetzner-sway # For Hetzner Cloud
sudo nixos-rebuild dry-build --flake .#m1 --impure  # For M1 Mac

# Apply configuration changes
sudo nixos-rebuild switch --flake .#<target>
```

### M1 MacBook Pro (Apple Silicon)

Single Retina display (eDP-1), RustDesk, local audio. Requires `--impure` flag for Asahi firmware.

**Quick**: `sudo nixos-rebuild switch --flake .#m1 --impure`

## 📁 Directory Structure

- `flake.nix` - Entry point
- `configurations/` - Target configs (wsl, hetzner-sway, m1, container)
- `hardware/` - Hardware-specific settings
- `modules/` - Reusable system modules
- `home-modules/` - User environment (editors, shell, terminal, tools)
- `docs/` - Detailed documentation

## 🎯 Configuration Targets

**WSL**: Local development on Windows
**Hetzner**: Remote workstation with Sway, VNC, Tailscale
**M1**: Native NixOS on Apple Silicon
**Containers**: Minimal/dev/full profiles

## 📦 Package Management

Profiles: `minimal` (~100MB), `essential` (~275MB), `development` (~600MB), `full` (~1GB)

**Add packages**: Edit `modules/services/` (system), `user/packages.nix` (user), or `configurations/` (target-specific)

## 🚀 Walker/Elephant Launcher (Features 043, 050)

Universal keyboard-driven launcher for apps, files, web search, calculator, todos, windows, bookmarks.

**Launch**: `Meta+D` or `Alt+Space`

**Prefixes**: `/` file search | `@` web search | `!` todos | `=` calculator | `.` unicode | `:` clipboard | `>` shell | `;s` tmux | `;p` i3pm

**Service**: `systemctl --user {status|restart} elephant`

## 🔄 Sway Dynamic Configuration Management (Feature 047)

Hot-reloadable Sway configuration (<100ms latency).

**Dynamic** (runtime editable, Git-tracked):
- `~/.config/sway/window-rules.json`
- `~/.config/sway/appearance.json`
- `~/.config/sway/workspace-assignments.json`

**Static** (requires rebuild):
- **Keybindings**: `/etc/nixos/home-modules/desktop/sway-keybindings.nix`

**Commands**:
```bash
swaymsg reload           # Reload rules/appearance (or Mod+Shift+C)
swayconfig validate      # Validate without applying
swayconfig versions      # View version history
swayconfig rollback <hash>  # Rollback to previous version
```

**Docs**: `/etc/nixos/specs/047-create-a-new/quickstart.md`

## 🗺️ Sway Workspace Overview (sov)

Visual schematic layout of all workspaces with app names.

**Keys**: `Mod+Tab` (show) | `Mod+Shift+Tab` (hide)

## 🎨 Unified Bar System (Feature 057)

Centralized theming with Catppuccin Mocha across top bar (Swaybar), bottom bar (Eww), and notification center (SwayNC).

**Theme**: `~/.config/sway/appearance.json` (hot-reloadable)

**Commands**:
```bash
swaymsg reload                         # Reload appearance
systemctl --user restart sway-workspace-panel  # Bottom bar
systemctl --user restart swaync       # Notification center
```

**Docs**: `/etc/nixos/specs/057-unified-bar-system/quickstart.md`

## ⌨️ Event-Driven Workspace Mode Navigation (Feature 042)

Navigate to workspace 1-70 by typing digits (<20ms latency).

**Keys**: CapsLock (M1) / Ctrl+0 (Hetzner) | +Shift (move window) | Escape (cancel)

**Usage**: Enter mode → Type digits → Enter (e.g., CapsLock → 23 → Enter)

**Visual Feedback** (Feature 058): Workspace button lights up **YELLOW** when typed, **BLUE** when focused.

**CLI**: `i3pm workspace-mode {state|history|digit|execute|cancel}`

**Docs**: `/etc/nixos/specs/042-event-driven-workspace-mode/quickstart.md`

## 🌐 PWA Management

```bash
pwa-install-all      # Install all declared PWAs
pwa-update-panels    # Update taskbar icons
pwa-get-ids          # Get PWA IDs for pinning
pwa-list             # List configured PWAs
```

**Add PWA**: Edit `home-modules/tools/firefox-pwas-declarative.nix` → Rebuild → `pwa-install-all`

## 🎯 Project Management Workflow (i3pm)

Project-scoped workspace management. Switch contexts, auto show/hide apps.

### Quick Keys

| Key | Action |
|-----|--------|
| `Win+P` | Project switcher |
| `Win+Shift+P` | Clear (global mode) |
| `Win+Return` | **Scratchpad Terminal** (1200×600, project-scoped) |
| `Win+C` | VS Code |
| `Win+G` | Lazygit |
| `Win+Y` | Yazi |

**Scoped apps** (hidden on switch): Ghostty, VS Code, Yazi, Lazygit
**Global apps** (always visible): Firefox, PWAs, K9s

### Scratchpad Terminal (Feature 062)

Project-scoped floating terminal with state persistence.

```bash
i3pm scratchpad toggle [project]  # Launch/show/hide terminal
i3pm scratchpad status [--all]    # Get status
i3pm scratchpad cleanup           # Remove invalid terminals
```

**Docs**: `/etc/nixos/specs/062-project-scratchpad-terminal/quickstart.md`

### Essential Commands

```bash
# Project (aliases: pswitch, pclear, plist, pcurrent)
i3pm project {switch|create|list|current} [args]

# Daemon
i3pm daemon {status|events}
systemctl --user {status|restart} i3-project-event-listener

# Diagnostics (Feature 039)
i3pm diagnose {health|window <id>|validate|events}

# Monitors (Feature 001)
i3pm monitors {status|reassign|config}
```

### Declarative Workspace-to-Monitor Assignment (Feature 001)

Assign workspaces to monitor roles (primary/secondary/tertiary) declaratively.

**Monitor Roles**:
- Primary: WS 1-2
- Secondary: WS 3-5
- Tertiary: WS 6+

**Config Example** (`app-registry-data.nix`):
```nix
{
  name = "code";
  preferred_workspace = 2;
  preferred_monitor_role = "primary";  # Always on primary monitor
  floating = true;
  floating_size = "medium";  # scratchpad/small/medium/large
}
```

**CLI**:
```bash
i3pm monitors status    # Show current assignments
i3pm monitors reassign  # Force reassignment
i3pm monitors config    # Show configuration
```

**Docs**: `/etc/nixos/specs/001-declarative-workspace-monitor/quickstart.md`

### Window Filtering & State Preservation (Features 037, 038)

Scoped windows hide to scratchpad on project switch, restore with exact state.

**Troubleshooting**:
```bash
i3pm daemon status          # Daemon running?
pcurrent                    # Active project?
i3pm diagnose health        # System health?
i3pm diagnose window <id>   # Check window state
```

**Docs**: `/etc/nixos/specs/037-given-our-top/quickstart.md`, `038-create-a-new/quickstart.md`, `039-create-a-new/quickstart.md`

### Diagnostic Tooling (Feature 039)

```bash
i3pm diagnose health           # Daemon health (exit: 0=ok, 1=warn, 2=critical)
i3pm diagnose window <id>      # Window identity, env vars, registry match
i3pm diagnose events [--follow] # Event trace (500 buffer, colored timing)
i3pm diagnose validate         # State consistency check
```

## 🚀 IPC Launch Context (Feature 041)

Pre-notification system for multi-instance app tracking. Accuracy: 100% sequential, 95% rapid launches.

**Debug**: `i3pm diagnose window <id>` | `i3pm daemon events --type=launch`

## 📦 Registry-Centric Architecture (Feature 035)

Apps inherit `I3PM_*` env vars from registry (`app-registry.nix`). Daemon reads `/proc/<pid>/environ` for window ownership.

**Debug**: `window-env <pid>` or `cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM_`

## 🪟 Window State Visualization (Feature 025)

```bash
i3pm windows [--tree|--table|--live|--json]  # Default: tree
```

**Modes**: Tree (hierarchy), Table (sortable), Live TUI (Tab=switch, H=hidden, Q=quit), JSON (scripting)

## 🔍 Window Environment Query Tool

```bash
window-env <pid|class|title> [--pid|--filter PATTERN|--all|--json]
```

## 📊 Sway Tree Diff Monitor (Feature 064)

Real-time window state change monitoring with <10ms diff computation.

```bash
sway-tree-monitor live                          # Live event stream
sway-tree-monitor history --last 50             # Past events
sway-tree-monitor diff <EVENT_ID>               # Detailed diff
sway-tree-monitor stats [--since 1h]            # Performance stats
systemctl --user {status|restart} sway-tree-monitor
```

**Docs**: `/etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md`

## 🐍 Python Testing & Development

**Monitor**: `i3-project-monitor [--mode=events|history|tree|diagnose]`
**Test**: `i3-project-test {run|suite|verify-state} [--verbose|--ci]`

**Standards**: Python 3.11+, async/await, pytest-asyncio, Rich UI, i3ipc.aio, Pydantic

**Docs**: `docs/PYTHON_DEVELOPMENT.md`, `docs/I3_IPC_PATTERNS.md`

## 🧪 Sway Test Framework (Features 069, 070)

Declarative JSON-based testing with synchronization primitives (zero race conditions).

**Quick Start**:
```bash
sway-test run tests/test_example.json   # Run a test
deno task test:basic                     # Run category
sway-test list-apps --filter firefox    # List apps
sway-test cleanup --all                  # Cleanup orphaned processes
```

**Performance**: 5-6x faster tests, <1% flakiness rate, 100% migration to sync-based tests.

**Detailed Docs**: See `home-modules/tools/sway-test/CLAUDE.md`

## 📚 Additional Documentation

- `README.md` - Project overview
- `docs/ARCHITECTURE.md` - Detailed architecture
- `docs/PYTHON_DEVELOPMENT.md` - Python standards
- `docs/PWA_SYSTEM.md` - PWA management
- `docs/M1_SETUP.md` - Apple Silicon setup
- `docs/ONEPASSWORD.md` - 1Password integration
- `docs/HETZNER_NIXOS_INSTALL.md` - Hetzner installation

## 🔍 Quick Debugging

```bash
nixos-rebuild dry-build --flake .#<target> --show-trace  # Test config
nix flake show                                           # List configurations
nix flake metadata                                       # Check flake inputs
```

## 🖥️ Multi-Monitor VNC Access (Hetzner Cloud)

Three virtual displays via WayVNC over Tailscale.

**Connect**: `vnc://<tailscale-ip>:{5900|5901|5902}` (Displays 1-3)
**Find IP**: `tailscale status | grep hetzner`

**Docs**: `/etc/nixos/specs/048-multi-monitor-headless/quickstart.md`

## 🤖 Claude Code Integration

Bash history hook auto-registers all Claude Code commands to `~/.bash_history`.

**Access**: Ctrl+R (fzf search), Up/Down arrows

## 🔐 1Password

```bash
op signin                    # Sign in
op {vault|item} list         # List vaults/items
gh auth status               # Auto-uses 1Password token
```

**Docs**: `docs/ONEPASSWORD.md`, `docs/ONEPASSWORD_SSH.md`

---

## ⚠️ Recent Updates (2025-11)

**Key Features**:
- **Feature 073**: Eww interactive menu stabilization (M/F key actions, Delete key close, keyboard hints). See `/etc/nixos/specs/073-eww-menu-stabilization/`
- **Feature 072**: Unified workspace/window/project switcher with all-windows preview
- **Feature 062**: Project-scoped scratchpad terminal
- **Feature 053**: 100% PWA workspace assignment via event-driven daemon
- **Feature 049**: Auto workspace-to-monitor redistribution
- **Feature 047**: Hybrid config (keybindings static, window rules dynamic)
- **Feature 001**: Declarative workspace-to-monitor assignment

**Tech Stack**: Python 3.11+ (i3pm daemon), i3ipc.aio (async Sway IPC), Pydantic (data validation), TypeScript/Deno (CLI), Nix, firefoxpwa (PWAs)

**Storage**: In-memory daemon state, JSON config files (`~/.config/i3/`, `~/.config/sway/`, `~/.local/share/firefoxpwa/`)

## Active Technologies
- Python 3.11+ + i3ipc.aio (async Sway IPC), asyncio, psutil, pytest, Pydantic
- TypeScript/Deno 1.40+ + Zod 3.22+, @std/cli, Sway IPC mark/unmark
- Eww 0.4+ (ElKowar's Wacky Widgets), GTK3, SwayNC 0.10+
- In-memory daemon state, JSON configuration files

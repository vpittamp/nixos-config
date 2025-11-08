# NixOS Configuration - LLM Navigation Guide

## 🚀 Quick Start

### Essential Commands

```bash
# Test configuration changes (ALWAYS RUN BEFORE APPLYING)
sudo nixos-rebuild dry-build --flake .#wsl    # For WSL
sudo nixos-rebuild dry-build --flake .#hetzner-sway # For Hetzner Cloud (Sway/Wayland)
sudo nixos-rebuild dry-build --flake .#m1 --impure  # For M1 Mac (--impure for firmware)

# Apply configuration changes
sudo nixos-rebuild switch --flake .#wsl    # For WSL
sudo nixos-rebuild switch --flake .#hetzner-sway # For Hetzner Cloud (Sway/Wayland)
sudo nixos-rebuild switch --flake .#m1 --impure  # For M1 Mac (--impure for firmware)

# Remote build/deploy from Codespace or another machine (requires SSH access)
nixos-rebuild switch --flake .#hetzner-sway --target-host vpittamp@hetzner --use-remote-sudo

# Build container images
nix build .#container-minimal      # Minimal container (~100MB)
nix build .#container-dev          # Development container (~600MB)
```

### M1 MacBook Pro (Apple Silicon)

**Platform**: M1 MacBook Pro with Sway/Wayland, single Retina display (eDP-1), i3pm daemon

**Quick Commands**:
```bash
# Rebuild (requires --impure for Asahi firmware)
sudo nixos-rebuild switch --flake .#m1 --impure

# Daemon management
systemctl --user status i3-project-event-listener
i3pm daemon status

# Display info
swaymsg -t get_outputs | jq '.[] | {name, scale, current_mode}'
```

**Key Differences from hetzner-sway**: Single eDP-1 display vs 3 virtual displays, RustDesk vs WayVNC, local audio vs Tailscale streaming, BCM4378 WiFi firmware

**Troubleshooting**: See `docs/M1_SETUP.md` for detailed hardware-specific issues

## 📁 Directory Structure

**Key Locations**:
- `flake.nix` - Entry point, defines all configurations
- `configurations/` - Target-specific configs (base, hetzner-sway, m1, wsl, container)
- `hardware/` - Hardware-specific settings (hetzner, m1)
- `modules/` - Reusable system modules (desktop, services)
- `home-modules/` - User environment with home-manager (editors, shell, terminal, tools)
- `docs/` - Detailed documentation for specific features

**Package Management**: `system/packages.nix` (system-level), `user/packages.nix` (user-level), `shared/package-lists.nix` (profiles)

## 🏗️ Architecture Overview

### Configuration Hierarchy

```
1. Base Configuration (configurations/base.nix)
   ↓ Provides core settings
2. Hardware Module (hardware/*.nix)
   ↓ Adds hardware-specific settings
3. Service Modules (modules/services/*.nix)
   ↓ Adds optional services
4. Desktop Modules (modules/desktop/*.nix)
   ↓ Adds GUI if needed
5. Target Configuration (configurations/*.nix)
   ↓ Combines and customizes
6. Flake Output (flake.nix)
```

### Key Design Principles

1. **Hetzner Sway as Reference**: The hetzner-sway configuration (`configurations/hetzner-sway.nix`) serves as the reference implementation with Sway/Wayland compositor
2. **Modular Composition**: Each target combines only the modules it needs
3. **Override Hierarchy**: Use `lib.mkDefault` for overrideable defaults, `lib.mkForce` for mandatory settings
4. **Single Source of Truth**: Avoid duplication by extracting common patterns into modules

## 🎯 Configuration Targets

### WSL (Windows Subsystem for Linux)

- **Purpose**: Local development on Windows
- **Features**: Docker Desktop integration, VS Code support, 1Password CLI
- **Build**: `sudo nixos-rebuild switch --flake .#wsl`

### Hetzner (Cloud Server)

- **Purpose**: Remote development workstation
- **Features**: Sway Wayland compositor, VNC access, dynamic configuration management (Feature 047), Tailscale VPN, 1Password GUI
- **Build**: `sudo nixos-rebuild switch --flake .#hetzner-sway`
- **Note**: Uses template-based configuration to avoid home-manager conflicts

### M1 (Apple Silicon Mac)

- **Purpose**: Native NixOS on Apple hardware
- **Features**: Optimized for ARM64, Apple-specific drivers, Retina display support
- **Build**: `sudo nixos-rebuild switch --flake .#m1 --impure`
- **Note**: Requires `--impure` flag for Asahi firmware access

### Containers

- **Purpose**: Minimal NixOS for Kubernetes/Docker
- **Profiles**: minimal, development, full
- **Build**: `nix build .#container-minimal`

## 📦 Package Management

### Package Profiles

Controlled by environment variables or module imports:

- `minimal` (~100MB): Core utilities only
- `essential` (~275MB): Basic development tools
- `development` (~600MB): Full development environment
- `full` (~1GB): Everything including K8s tools

### Adding Packages

1. **System-wide** - Edit appropriate module in `modules/services/`
2. **User-specific** - Edit `user/packages.nix`
3. **Target-specific** - Add to specific configuration in `configurations/`

## 🚀 Walker/Elephant Launcher (Features 043, 050)

Universal keyboard-driven launcher: apps, files, web search, calculator, todos, windows, bookmarks, custom commands

**Launch**: `Meta+D` or `Alt+Space`

**Quick Reference**:
- No prefix: Apps, windows, bookmarks, custom commands
- `/` - File search | `@` - Web search | `!` - Todos | `=` - Calculator
- `.` - Unicode symbols | `:` - Clipboard | `>` - Shell commands
- `;s` - Tmux sessions | `;p` - i3pm projects

**Common Examples**: `Meta+D` then type:
- `code` - Launch VS Code | `firefox` - Focus window | `!groceries` - Add todo
- `@nix hyprland` - Search packages | `/file.nix` - Find file | `=2+2` - Calculate

**Custom Commands** (no rebuild):
```bash
walker-cmd add "name" "command"  # Add command
walker-cmd list                   # Show all
walker-cmd edit                   # Edit file directly
```

**Service**: `systemctl --user {status|restart} elephant`

**Docs**: See `/etc/nixos/specs/043-get-full-functionality/quickstart.md` and `050-enhance-the-walker/quickstart.md`

## 🔄 Sway Dynamic Configuration Management (Feature 047)

Hot-reloadable Sway configuration for window rules and appearance. Uses template-based approach to avoid home-manager conflicts.

**What's Dynamic** (runtime editable, Git-tracked):
- `~/.config/sway/window-rules.json` - Window rules (floating, sizing, positioning)
- `~/.config/sway/appearance.json` - Gaps, borders, colors
- `~/.config/sway/workspace-assignments.json` - Workspace assignments

**What's Static** (managed in Nix, requires rebuild):
- **Keybindings** - `/etc/nixos/home-modules/desktop/sway-keybindings.nix`
  - Edit file, then: `sudo nixos-rebuild switch --flake .#<target>`
  - Organized by section (workspace nav, window mgmt, system, etc.)

**Essential Commands**:
```bash
# Reload window rules/appearance (auto-validates, commits to Git)
swaymsg reload  # or Mod+Shift+C

# Validate window rules without applying
swayconfig validate

# View version history
swayconfig versions

# Rollback to previous version
swayconfig rollback <commit-hash>

# Check daemon status
systemctl --user status sway-config-daemon
```

**Key Features**:
- <100ms hot-reload latency for window rules
- Automatic syntax/semantic validation
- Git version control (auto-commit on success)
- File watcher with 500ms debounce
- Runtime window rule injection (walker, scratchpad)

**Architecture**: Hybrid approach - keybindings in Nix for simplicity, window rules dynamic for runtime additions

**Detailed Documentation**: See `/etc/nixos/specs/047-create-a-new/quickstart.md`

## 🗺️ Sway Workspace Overview (sov)

Visual schematic layout of all workspaces with app names (not thumbnails). Multi-display support, 3-column layout.

**Keys**: `Mod+Tab` (show) | `Mod+Shift+Tab` (hide) | Auto-hide on workspace switch

**Service**: `systemctl --user {status|restart} sov` | Logs: `journalctl --user -u sov -f`

**Config**: `home-modules/desktop/sway.nix` | Manual: `echo 1 > /tmp/sovpipe` (show)

## ⌨️ Event-Driven Workspace Mode Navigation (Feature 042)

Navigate to workspace 1-70 by typing digits. <20ms latency via event-driven Python daemon.

**Keys**: CapsLock (M1) / Ctrl+0 (Hetzner) / Mod+; (goto) | +Shift (move window) | Escape (cancel)

**Usage**: Enter mode → Type digits → Enter (e.g., CapsLock → 2 3 → Enter = WS 23)

**Visual**: Swaybar shows `→ WS` (goto) / `⇒ WS` (move) + digits

**CLI**: `i3pm workspace-mode {state|history}` | Manual: `i3pm workspace-mode {digit|execute|cancel}`

**Multi-monitor**: Auto-focuses correct output (WS 1-2 primary, 3-5 secondary, 6+ tertiary)

**Docs**: `/etc/nixos/specs/042-event-driven-workspace-mode/quickstart.md`

## 🌐 PWA Management

### Installing PWAs

```bash
# Install all declared PWAs
pwa-install-all

# Update taskbar with PWA icons
pwa-update-panels

# Get PWA IDs for permanent pinning
pwa-get-ids

# List configured and installed PWAs
pwa-list
```

### Adding New PWAs

1. Edit `home-modules/tools/firefox-pwas-declarative.nix`
2. Add PWA definition with name, URL, and icon
3. Rebuild: `sudo nixos-rebuild switch --flake .#<target>`
4. Install: `pwa-install-all`
5. Update panels: `pwa-update-panels` or update `panels.nix` with IDs

## 🔧 Common Tasks

### Testing Changes

```bash
# ALWAYS test before applying
sudo nixos-rebuild dry-build --flake .#<target>

# Check for errors, then apply
sudo nixos-rebuild switch --flake .#<target>
```

### Building Containers

```bash
# Build specific container profile
nix build .#container-minimal
nix build .#container-dev

# Load into Docker
docker load < result

# Run container
docker run -it nixos-container:latest
```

### Updating Flake Inputs

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

## ⚠️ Important Notes

### Recent Updates (2025-11)

**Key Features**:
- **Feature 062**: Project-scoped scratchpad terminal (toggle, state persistence, <500ms). See `specs/062-project-scratchpad-terminal/`
- **Feature 053**: 100% PWA workspace assignment via event-driven daemon (removed native Sway assign rules). See `specs/053-workspace-assignment-enhancement/`
- **Feature 049**: Auto workspace-to-monitor redistribution on connect/disconnect (1/2/3 monitor presets). See `specs/049-intelligent-automatic-workspace/`
- **Feature 047**: Hybrid config management - keybindings static (Nix), window rules dynamic (runtime). See `specs/047-create-a-new/`
- **Feature 029**: Multi-source event monitoring (systemd, /proc, i3 IPC) with correlation. See `specs/029-linux-system-log/`
- **Feature 025**: Window state visualization (tree/table/live TUI/JSON). See `specs/025-visual-window-state/`
- **Feature 015**: Event-driven i3pm daemon (<100ms latency, <1% CPU, <15MB mem). See `specs/015-create-a-new/`

**2025-09**: M1 migrated to Wayland, declarative PWA system, 1Password integration
**2024-09**: Consolidated from 46 to ~25 .nix files, removed 3,486 duplicate lines

### Module Conventions

- Use `lib.mkDefault` for overrideable options
- Use `lib.mkForce` only when override is mandatory
- Always test with `dry-build` before applying
- Keep hardware-specific settings in `hardware/` modules

### Troubleshooting

1. **File system errors**: Ensure `hardware-configuration.nix` exists
2. **Package conflicts**: Check for deprecated packages (e.g., mysql → mariadb)
3. **Option deprecations**: Update to new option names (e.g., hardware.opengl → hardware.graphics)
4. **Build failures**: Run with `--show-trace` for detailed errors

## 🎯 Project Management Workflow (i3pm)

Project-scoped workspace management for i3/Sway. Switch contexts, auto show/hide apps, multi-monitor support.

### Quick Keys

| Key | Action |
|-----|--------|
| `Win+P` | Project switcher | `Win+Shift+P` | Clear (global mode) |
| `Win+Return` | **Scratchpad Terminal** | Toggle project terminal (1200×600, centered) |
| `Win+Shift+Return` | Regular terminal | Opens Alacritty (non-scratchpad) |
| `Win+C` | VS Code | `Win+G` | Lazygit | `Win+Y` | Yazi |

**Scoped apps** (hidden on switch): Ghostty, VS Code, Yazi, Lazygit
**Global apps** (always visible): Firefox, PWAs, K9s

### Scratchpad Terminal (Feature 062)

Project-scoped floating terminal that toggles show/hide without affecting other windows. Each project maintains independent terminal with separate command history and working directory.

**Quick Access**: `Win+Return` (launches if doesn't exist, shows if hidden, hides if visible)

**Key Features**:
- **Project Isolation**: Each project has its own terminal with independent command history
- **State Persistence**: Running processes persist when terminal is hidden
- **Auto Working Directory**: Terminal opens in project root directory
- **Ghostty Terminal**: Modern GPU-accelerated terminal with shell integration
- **Unified Font Size**: 11pt (centralized terminal configuration)
- **Compact Size**: 1200×600 pixels, centered on display
- **Global Terminal**: Use `i3pm scratchpad toggle global` for project-less terminal
- **Fast Toggle**: <500ms for existing terminals, <2s for initial launch

**CLI Commands**:
```bash
# Toggle terminal (most common)
i3pm scratchpad toggle [project]     # Launch/show/hide terminal

# Explicit operations
i3pm scratchpad launch [project]     # Launch new terminal
i3pm scratchpad status [--all]       # Get status of terminal(s)
i3pm scratchpad close [project]      # Close terminal
i3pm scratchpad cleanup              # Remove invalid terminals

# Status includes: PID, window ID, state, working directory, timestamps
```

**Examples**:
```bash
# Use with current project
i3pm scratchpad toggle              # Toggle current project's terminal

# Use with specific project
i3pm scratchpad toggle nixos        # Toggle nixos project terminal

# Global terminal (no project)
i3pm scratchpad toggle global       # Toggle global terminal in $HOME

# Check status
i3pm scratchpad status --all        # View all terminals
i3pm scratchpad status nixos --json # Get terminal info as JSON
```

**How It Works**:
- Terminal is marked with `scratchpad:{project_name}` in Sway
- Uses Sway's native scratchpad mechanism (hidden ≠ closed)
- Daemon tracks terminal state via `ScratchpadManager`
- Environment variables: `I3PM_SCRATCHPAD=true`, `I3PM_PROJECT_NAME=...`, `I3PM_WORKING_DIR=...`

**Troubleshooting**:
```bash
# Terminal not appearing?
i3pm scratchpad status              # Check if terminal exists
i3pm daemon status                  # Verify daemon is running
i3pm scratchpad cleanup             # Remove invalid terminals

# Multiple terminals per project?
i3pm scratchpad status --all        # List all terminals
i3pm scratchpad close <project>     # Close specific terminal

# Terminal state issues?
i3pm scratchpad launch <project>    # Force new launch
```

**Docs**: See `/etc/nixos/specs/062-project-scratchpad-terminal/quickstart.md`

### Essential Commands

```bash
# Project (aliases: pswitch, pclear, plist, pcurrent)
i3pm project {switch|create|list|current} [args]

# Daemon
i3pm daemon {status|events}                # Monitor
systemctl --user {status|restart} i3-project-event-listener

# Diagnostics (Feature 039)
i3pm diagnose {health|window <id>|validate|events}

# Monitors (auto-adapts: 1mon=all primary, 2mon=1-2 primary/3-70 sec, 3mon=1-2 pri/3-5 sec/6-70 ter)
i3pm monitors {status|reassign|config}
```

### Window Filtering & State Preservation (Features 037, 038)

**Auto hide/show**: Scoped windows hide to scratchpad on project switch, restore with exact state (workspace, tiling/floating, geometry). Persisted in `~/.config/i3/window-workspace-map.json` (v1.1).

**Performance**: 2-5ms for 10 windows, <10px geometry tolerance

**Troubleshooting**:
```bash
# Check filtering/state
i3pm daemon events --type=tick | grep filtering
cat ~/.config/i3/window-workspace-map.json | jq .version  # Should be "1.1"
i3pm diagnose window <id>  # Check window state

# Common issues
i3pm daemon status         # Daemon running?
pcurrent                   # Active project?
i3pm diagnose health       # System health?
```

**Docs**: See `/etc/nixos/specs/037-given-our-top/quickstart.md` (filtering), `038-create-a-new/quickstart.md` (state preservation), `039-create-a-new/quickstart.md` (diagnostics)

### Diagnostic Tooling (Feature 039)

Troubleshoot window management without reading daemon source.

**Commands**:
```bash
i3pm diagnose health              # Daemon health (exit: 0=ok, 1=warn, 2=critical)
i3pm diagnose window <id>         # Window identity, env vars, registry match
i3pm diagnose events [--follow]   # Event trace (500 buffer, colored timing)
i3pm diagnose validate            # State consistency check
```

**Add `--json` for machine-readable output**

**Docs**: `/etc/nixos/specs/039-create-a-new/quickstart.md`

## 🚀 IPC Launch Context (Feature 041)

Pre-notification system for multi-instance app tracking. Launcher notifies daemon before app starts, correlates window on appearance (0.5-2s later). Accuracy: 100% sequential, 95% rapid launches.

**Debug**: `i3pm diagnose window <id>` (confidence, signals) | `i3pm daemon events --type=launch`

**Docs**: `/etc/nixos/specs/041-ipc-launch-context/quickstart.md`

## 📦 Registry-Centric Architecture (Feature 035)

Apps inherit `I3PM_*` env vars from registry (`app-registry.nix`). Daemon reads `/proc/<pid>/environ` for window ownership. No manual config.

**Commands**: `i3pm {apps|project|layout} {list|show|save|restore}` (see i3pm section above)

**Debug**: `window-env <pid>` or `cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM_`

**Docs**: `/etc/nixos/specs/035-now-that-we/quickstart.md`

## 🪟 Window State Visualization (Feature 025)

```bash
i3pm windows [--tree|--table|--live|--json]  # Default: tree
```

**Modes**: Tree (hierarchy), Table (sortable), Live TUI (Tab=switch, H=hidden, Q=quit), JSON (scripting)

**Indicators**: ● Focus | 🔸 Scoped | 🔒 Hidden | ⬜ Floating | Project tags

**Docs**: `/etc/nixos/specs/025-visual-window-state/quickstart.md`

## 🔍 Window Environment Query Tool

Query window PIDs and env vars by PID, class, or title.

```bash
window-env <pid|class|title> [--pid|--filter PATTERN|--all|--json]
```

**Examples**: `window-env 4099278` | `window-env YouTube` | `window-env --filter I3PM_ Code` | `window-env --pid Firefox`

**Features**: Fuzzy match, colored I3PM_* output, PID validation, helpful errors

## 🐍 Python Testing & Development

**Monitor**: `i3-project-monitor [--mode=events|history|tree|diagnose]`

**Test**: `i3-project-test {run|suite|verify-state} [--verbose|--ci]`

**Standards**: Python 3.11+, async/await, pytest-asyncio, Rich UI, i3ipc.aio, Pydantic models

**Docs**: `docs/PYTHON_DEVELOPMENT.md`, `docs/I3_IPC_PATTERNS.md`

## 📚 Additional Documentation

- `README.md` - Project overview and quick start
- `docs/ARCHITECTURE.md` - Detailed architecture documentation
- `docs/PYTHON_DEVELOPMENT.md` - Python development standards and patterns
- `docs/I3_IPC_PATTERNS.md` - i3 IPC integration patterns and best practices
- `docs/PWA_SYSTEM.md` - PWA (Progressive Web App) management system
- `docs/M1_SETUP.md` - Apple Silicon setup and troubleshooting
- `docs/DARWIN_SETUP.md` - macOS Darwin home-manager setup guide
- `docs/ONEPASSWORD.md` - 1Password integration guide
- `docs/ONEPASSWORD_SSH.md` - 1Password SSH and Git authentication guide
- `docs/HETZNER_NIXOS_INSTALL.md` - Hetzner installation guide
- `docs/AVANTE_SETUP.md` - Neovim AI assistant setup
- `docs/MIGRATION.md` - Migration from old structure

## 🔍 Quick Debugging

```bash
# Check current configuration
nixos-rebuild dry-build --flake .#<target> --show-trace

# List available configurations
nix flake show

# Check flake inputs
nix flake metadata

# Evaluate specific option
nix eval .#nixosConfigurations.<target>.config.<option>
```

## 🖥️ Multi-Monitor VNC Access (Hetzner Cloud)

Three virtual displays via WayVNC over Tailscale.

**Connect**: `vnc://<tailscale-ip>:{5900|5901|5902}` (Display 1-3, WS 1-2/3-5/6-9)

**Find IP**: `tailscale status | grep hetzner`

**Commands**: `systemctl --user {status|restart} wayvnc@HEADLESS-{1,2,3}` | Logs: `journalctl --user -u wayvnc@HEADLESS-1 -f`

**Troubleshoot**: Check `i3pm monitors status` | Verify `swaymsg -t get_outputs`

**Docs**: `/etc/nixos/specs/048-multi-monitor-headless/quickstart.md`

## 🤖 Claude Code Integration

**Bash History Hook**: Auto-registers all Claude Code bash commands to `~/.bash_history`. Already configured in `claude-code.nix`.

**Access**: Ctrl+R (fzf search), Up/Down arrows, all terminal sessions

**Rebuild after changes**: `sudo nixos-rebuild switch --flake .#<target>` or `home-manager switch`

**Manual**: `claude-register-command "command"` | `history | tail -20`

## 🔐 1Password

```bash
op signin                    # Sign in
op {vault|item} list         # List vaults/items
SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l  # Test SSH agent
gh auth status               # Auto-uses 1Password token
```

**Docs**: `docs/ONEPASSWORD.md`, `docs/ONEPASSWORD_SSH.md`

## 🍎 macOS Darwin Home-Manager

```bash
home-manager switch --flake .#darwin   # Apply config
nix flake update                       # Update packages
```

**Docs**: `docs/DARWIN_SETUP.md`

---

_Last updated: 2025-11-06 - Hybrid config: static keybindings (Nix), dynamic window rules (runtime)_

**Tech Stack**: Python 3.11+ (i3pm daemon), i3ipc.aio (async Sway IPC), Pydantic (data validation), TypeScript/Deno (CLI), Nix (config mgmt), firefoxpwa (PWAs)

**Storage**: In-memory daemon state, JSON config files (`~/.config/i3/`, `~/.config/sway/`, `~/.local/share/firefoxpwa/`)

**Recent**: Feature 062 (scratchpad terminal), Hybrid config (keybindings→Nix, window rules→dynamic), Feature 058 (Python backend consolidation), 053 (100% workspace assignment)

## Active Technologies
- Python 3.11+ (matching existing i3pm daemon) + i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation), pytest (testing), Pydantic (data models) (063-scratchpad-filtering)
- In-memory daemon state (project → terminal PID/window ID mapping), Sway window marks for persistence (063-scratchpad-filtering)
- Python 3.11+ (matching existing sway-tree-monitor daemon) + i3ipc (Sway IPC), orjson (JSON serialization), psutil (process info) (066-inspect-daemon-fix)
- In-memory circular buffer (500 events), no persistent storage (066-inspect-daemon-fix)

## Recent Changes
- 063-scratchpad-filtering: Added Python 3.11+ (matching existing i3pm daemon) + i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation), pytest (testing), Pydantic (data models)

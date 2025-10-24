# NixOS Configuration - LLM Navigation Guide

## 🚀 Quick Start

### Essential Commands

```bash
# Test configuration changes (ALWAYS RUN BEFORE APPLYING)
sudo nixos-rebuild dry-build --flake .#wsl    # For WSL
sudo nixos-rebuild dry-build --flake .#hetzner # For Hetzner
sudo nixos-rebuild dry-build --flake .#m1 --impure  # For M1 Mac (--impure for firmware)

# Apply configuration changes
sudo nixos-rebuild switch --flake .#wsl    # For WSL
sudo nixos-rebuild switch --flake .#hetzner # For Hetzner
sudo nixos-rebuild switch --flake .#m1 --impure  # For M1 Mac (--impure for firmware)

# Remote build/deploy from Codespace or another machine (requires SSH access)
nixos-rebuild switch --flake .#hetzner --target-host vpittamp@hetzner --use-remote-sudo

# Build container images
nix build .#container-minimal      # Minimal container (~100MB)
nix build .#container-dev          # Development container (~600MB)
```

## 📁 Directory Structure

```
/etc/nixos/
├── flake.nix                    # Entry point - defines all configurations
├── configuration.nix            # Current system configuration (symlink/import)
├── hardware-configuration.nix   # Auto-generated hardware config
│
├── configurations/              # Target-specific configurations
│   ├── base.nix                # Shared base configuration (from Hetzner)
│   ├── hetzner.nix             # Hetzner Cloud server config
│   ├── m1.nix                  # Apple Silicon Mac config
│   ├── wsl.nix                 # Windows Subsystem for Linux config
│   └── container.nix           # Container base configuration
│
├── hardware/                    # Hardware-specific configurations
│   ├── hetzner.nix             # Hetzner virtual hardware
│   └── m1.nix                  # Apple Silicon hardware
│
├── modules/                     # Reusable system modules
│   ├── desktop/
│   │   ├── kde-plasma.nix      # KDE Plasma 6 desktop
│   │   └── remote-access.nix   # RDP/VNC configuration
│   └── services/
│       ├── development.nix     # Dev tools (Docker, K8s, languages)
│       ├── networking.nix      # Network services (SSH, Tailscale)
│       ├── onepassword.nix     # 1Password integration (GUI/CLI)
│       └── container.nix       # Container-specific services
│
├── home-modules/                # User environment (home-manager)
│   ├── ai-assistants/          # Claude, Codex, Gemini CLI tools
│   ├── editors/                # Neovim with lazy.nvim
│   ├── shell/                  # Bash, Starship prompt
│   ├── terminal/               # Tmux, terminal tools
│   └── tools/                  # Git, SSH, developer utilities
│
├── shared/                      # Shared configurations
│   └── package-lists.nix       # Package profiles
│
├── system/                      # System-level packages
│   └── packages.nix            # System packages
│
├── user/                        # User-level packages
│   └── packages.nix            # User packages
│
├── scripts/                     # Utility scripts
└── docs/                        # Additional documentation
```

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

1. **Hetzner as Base**: The Hetzner configuration serves as the reference implementation
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
- **Features**: Full KDE desktop, RDP access, Tailscale VPN, 1Password GUI
- **Build**: `sudo nixos-rebuild switch --flake .#hetzner`

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

### Recent Updates (2025-10)

- **Linux System Log Integration** - Multi-source event monitoring and correlation (Feature 029)
  - Unified event stream from systemd journals, /proc filesystem, and i3 events
  - Real-time process monitoring with 500ms polling (<5% CPU overhead)
  - Multi-factor correlation detection (timing, hierarchy, name similarity, workspace)
  - Commands: `i3pm daemon events --source=systemd|proc|all`, `--correlate` flag
  - Event sources: `systemd` (service logs), `proc` (process spawns), `i3` (window events)
  - Example: Query systemd logs with `--since="1 hour ago"`, monitor process spawns
  - Correlation display: Shows window → process relationships with confidence scores
  - Benefits: Debug application startup, correlate GUI with backend, unified monitoring
  - Documentation: `/etc/nixos/specs/029-linux-system-log/quickstart.md`

- **Visual Window State Management** - Real-time window visualization (Feature 025 MVP)
  - Tree and table views for hierarchical window state (outputs → workspaces → windows)
  - Real-time updates with <100ms latency via daemon event subscriptions
  - Multiple display modes: `--tree`, `--table`, `--live` (interactive TUI), `--json`
  - Comprehensive Pydantic data models for layout save/restore (foundation for full feature)
  - New command: `i3pm windows` with visualization modes
  - Benefits: Visual understanding of window state, live monitoring, rich property display
  - Documentation: `/etc/nixos/specs/025-visual-window-state/quickstart.md`

- **Event-Driven i3 Project Management** - Real-time project synchronization (Feature 015)
  - Replaced polling-based system with event-driven daemon using i3 IPC subscriptions
  - Automatic window marking with project context (<100ms latency)
  - Long-running systemd daemon with socket activation and watchdog monitoring
  - JSON-RPC IPC server for CLI tool communication
  - Commands: `i3pm daemon status`, `i3pm daemon events`, `i3pm project create`
  - Benefits: No race conditions, instant updates, <1% CPU usage, <15MB memory
  - Documentation: `/etc/nixos/specs/015-create-a-new/quickstart.md`

- **Migrated from Polybar to i3bar + i3blocks** - Native i3 status bar (Feature 013)
  - Replaced polybar with i3's native i3bar for workspace indicators
  - Implemented i3blocks for status command with system information blocks
  - Added project context indicator that updates via daemon query (not signals)
  - System info blocks: CPU usage, memory usage, network status, date/time
  - Configuration in `home-modules/desktop/i3blocks/` with shell scripts
  - Benefits: Better i3 integration, simpler configuration, more reliable workspace sync

### Recent Updates (2025-09)

- **Migrated M1 MacBook Pro from X11 to Wayland** - Following Asahi Linux recommendations
  - Enabled Wayland in KDE Plasma 6 for better HiDPI and gesture support
  - Removed X11-specific workarounds and touchegg (Wayland has native gestures)
  - Updated environment variables for Wayland compatibility
  - Note: Experimental GPU driver options available if needed (see m1.nix comments)
- **Implemented Declarative PWA System** - Firefox PWAs with KDE integration
  - Declarative PWA configuration in `firefox-pwas-declarative.nix`
  - Automatic taskbar pinning with `panels.nix`
  - Custom icon support in `/etc/nixos/assets/pwa-icons/`
  - Helper commands: `pwa-install-all`, `pwa-update-panels`, `pwa-get-ids`
- Added comprehensive 1Password integration
- Fixed M1 display scaling and memory issues
- Implemented conditional module features (GUI vs headless)
- Added declarative Git signing configuration
- Fixed Hetzner configuration to properly import hardware-configuration.nix
- Re-enabled all home-manager modules after architecture isolation debugging
- Added GitHub CLI to development module

### Recent Consolidation (2024-09)

- Reduced from 46 to ~25 .nix files
- Removed 3,486 lines of duplicate code
- Hetzner configuration now serves as base
- Modular architecture for better maintainability

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

## 🎯 Project Management Workflow

### Overview

The i3 window manager includes a project-scoped application workspace management system that allows you to:
- Switch between project contexts (NixOS, Stacks, Personal)
- Automatically show/hide project-specific applications
- Maintain global applications accessible across all projects
- Adapt workspace distribution across multiple monitors

### Quick Reference Keybindings

| Key | Action |
|-----|--------|
| `Win+P` | Open project switcher |
| `Win+Shift+P` | Clear active project (global mode) |
| `Win+C` | Launch VS Code in project context |
| `Win+Return` | Launch Ghostty terminal with sesh session |
| `Win+G` | Launch lazygit in project repository |
| `Win+Y` | Launch yazi file manager in project directory |
| `Win+Shift+M` | Manually trigger monitor detection/reassignment |

### Project-Scoped vs Global Applications

**Project-Scoped** (hidden when switching projects):
- Ghostty terminal (with sesh sessions)
- VS Code (opens project directory)
- Yazi file manager
- Lazygit

**Global** (always visible):
- Firefox browser
- YouTube PWA
- K9s
- Google AI PWA

### Shell Commands

The following shell aliases are available for project management:

| Command | Alias | Description |
|---------|-------|-------------|
| `i3pm project switch <name>` | `pswitch` | Switch to a project |
| `i3pm project clear` | `pclear` | Clear active project (global mode) |
| `i3pm project list` | `plist` | List all available projects |
| `i3pm project current` | `pcurrent` | Show current active project |
| `i3pm project create` | - | Create a new project |
| `i3pm daemon status` | - | Show daemon status and diagnostics |
| `i3pm daemon events` | - | Show recent daemon events for debugging |
| `i3pm monitors config show` | - | Display workspace-monitor configuration |
| `i3pm monitors config edit` | - | Edit configuration in $EDITOR |
| `i3pm monitors config validate` | - | Validate configuration syntax |
| `i3pm monitors config reload` | - | Hot-reload config without restart |
| `i3pm monitors reassign` | - | Apply workspace distribution now |
| `i3pm monitors status` | - | Show monitor table with roles |
| `i3pm monitors workspaces` | - | Show workspace assignments |

### Workspace-to-Monitor Configuration

Feature 033 provides declarative workspace distribution across monitors:

```bash
# View current configuration
i3pm monitors config show

# Edit configuration
i3pm monitors config edit

# Validate configuration
i3pm monitors config validate

# Reload configuration (no restart needed)
i3pm monitors config reload

# Apply workspace redistribution
i3pm monitors reassign
i3pm monitors reassign --dry-run  # Preview changes

# View system state
i3pm monitors status              # Monitor table
i3pm monitors workspaces          # Workspace assignments
```

**Configuration File**: `~/.config/i3/workspace-monitor-mapping.json`

**Default Distribution**:
- 1 monitor: All workspaces on primary
- 2 monitors: WS 1-2 primary, WS 3-70 secondary
- 3 monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-70 tertiary

**Automatic Adaptation**: Workspaces automatically redistribute when monitors are connected/disconnected (configurable via `enable_auto_reassign` and `debounce_ms` settings).

### Daemon Management

The event-based daemon runs as a systemd user service:

```bash
# Check daemon status
systemctl --user status i3-project-event-listener
i3pm daemon status

# View daemon logs
journalctl --user -u i3-project-event-listener -f

# Restart daemon
systemctl --user restart i3-project-event-listener

# View recent events
i3pm daemon events --limit=20

# Follow event stream in real-time
i3pm daemon events --follow
```

### Common Workflows

**Create a new project:**
```bash
i3-project-create --name nixos --dir /etc/nixos --icon "" --display-name "NixOS"
```

**Start working on a project:**
```bash
# Press Win+P to open rofi project switcher
# Or from command line:
i3-project-switch nixos
# Or use the short alias:
pswitch nixos
```

**Check current project:**
```bash
i3-project-current
# Or use short alias:
pcurrent
```

**List all projects:**
```bash
i3-project-list
# Or use short alias:
plist
```

**Return to global mode:**
```bash
# Press Win+Shift+P
# Or from command line:
i3-project-switch --clear
# Or use short alias:
pclear
```

### Multi-Monitor Support

Workspaces automatically distribute based on monitor count:
- **1 monitor**: All workspaces on primary
- **2 monitors**: WS 1-2 on primary, WS 3-9 on secondary
- **3+ monitors**: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

After connecting/disconnecting monitors, press `Win+Shift+M` to reassign workspaces.

### Troubleshooting

**Daemon not running:**
1. Check daemon status: `i3pm daemon status`
2. View logs: `journalctl --user -u i3-project-event-listener -n 50`
3. Restart daemon: `systemctl --user restart i3-project-event-listener`

**Windows not auto-marking:**
1. Check recent events: `i3pm daemon events --limit=20 --type=window`
2. Verify window class in scoped_classes: `cat ~/.config/i3/app-classes.json`
3. Reload daemon config: Send tick event or restart daemon

**Applications not opening in project context:**
1. Check active project: `i3pm project current` or `pcurrent`
2. Verify project directory exists
3. Check daemon is running: `i3pm daemon status`
4. Try clearing and reactivating: `Win+Shift+P` then `Win+P`

**Windows from old project still visible:**
1. Check i3bar shows correct project
2. Verify project switch completed: `i3pm project current`
3. Check daemon processed switch: `i3pm daemon events | grep tick`
4. Try switching again: `i3pm project switch <project-name>`

**Edit project configuration:**
```bash
# Manually edit
vi ~/.config/i3/projects/nixos.json

# Reload daemon after edits
systemctl --user restart i3-project-event-listener
```

For more details, see the quickstart guides:
```bash
cat /etc/nixos/specs/015-create-a-new/quickstart.md  # Event-based system (current)
cat /etc/nixos/docs/I3_PROJECT_EVENTS.md              # Troubleshooting guide (coming soon)
```

## 🪟 Window State Visualization (Feature 025)

View and monitor window state with multiple display modes:

```bash
# Tree view - hierarchical display (outputs → workspaces → windows)
i3pm windows --tree    # or just `i3pm windows` (default)

# Table view - sortable table with all window properties
i3pm windows --table

# Live TUI - interactive monitor with real-time updates
i3pm windows --live    # Press Tab to switch between tree/table, H to toggle hidden windows, Q to quit

# JSON output - for scripting/automation
i3pm windows --json | jq '.outputs[0].workspaces[0].windows'
```

**Tree View Features:**
- Visual hierarchy: 📺 Monitors → Workspaces → Windows
- Status indicators: ● Focus, 🔸 Scoped, 🔒 Hidden, ⬜ Floating
- Project tags: `[nixos]`, `[stacks]`
- Real-time updates (<100ms latency)

**Table View Features:**
- Sortable columns: ID, Class, Title, Workspace, Output, Project, Status
- Compact display for many windows
- Easy scanning and comparison

**Live TUI Features:**
- Real-time monitoring with event subscriptions
- Two tabs: Tree View and Table View
- Keyboard navigation: Tab (switch tabs), H (toggle hidden windows), Q (quit)
- Automatic refresh on window events
- Hidden window filter: scoped windows from inactive projects are hidden by default (press H to show)

**Common Use Cases:**
```bash
# Monitor window state during debugging
i3pm windows --live

# Quick check of current windows
i3pm windows

# Export window state for analysis
i3pm windows --json > window-state.json

# Pipe to other tools
i3pm windows --json | jq '.total_windows'
```

## 🐍 Python Project Testing & Monitoring

### i3 Project System Monitor

Real-time monitoring tool for debugging the i3 project management system:

```bash
# Live dashboard (default) - shows current state
i3-project-monitor

# Event stream - watch events as they occur
i3-project-monitor --mode=events

# Historical events - review recent events
i3-project-monitor --mode=history

# i3 tree inspector - inspect window hierarchy
i3-project-monitor --mode=tree

# Diagnostic capture - save complete state snapshot
i3-project-monitor --mode=diagnose --output=report.json
```

### Automated Testing Framework

Run automated tests for the i3 project management system:

```bash
# Run single test scenario
i3-project-test run project_lifecycle

# Run full test suite
i3-project-test suite

# Run tests with verbose output
i3-project-test suite --verbose

# Run tests in CI mode (JSON output)
i3-project-test suite --ci --output=test-results.json

# Validate current state
i3-project-test verify-state
```

### Multi-Pane Debugging Workflow

Use tmux for simultaneous monitoring and testing:

```bash
# Split terminal for monitor + commands
tmux split-window -h 'i3-project-monitor'

# Or use test framework's built-in tmux integration
i3-project-test interactive project_lifecycle
```

### Python Development Standards

All Python-based system tools follow these standards:
- **Language**: Python 3.11+ with async/await patterns
- **Testing**: pytest with async support (pytest-asyncio)
- **Terminal UI**: Rich library for tables and live displays
- **i3 Integration**: i3ipc.aio for async i3 IPC communication
- **Type Safety**: Type hints for all public APIs
- **Data Validation**: Pydantic models or dataclasses with validation

See `docs/PYTHON_DEVELOPMENT.md` for detailed patterns and examples.

### i3 IPC Integration

All i3-related state queries must use i3's native IPC API:
- Use `GET_WORKSPACES` for workspace-to-output assignments
- Use `GET_OUTPUTS` for monitor/output configuration
- Use `GET_TREE` for window hierarchy and marks
- Use `GET_MARKS` for all window marks
- Subscribe to events for real-time updates (not polling)

See `docs/I3_IPC_PATTERNS.md` for integration patterns and best practices.

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

## 🤖 Claude Code Integration

### Bash History Hook

Claude Code can be configured to automatically register executed commands in your bash history using a hook.

**Setup Instructions:**

The bash history hook is **already configured and active** in your `claude-code.nix`.

1. The hook automatically registers all bash commands executed by Claude Code in your `~/.bash_history`
2. Commands are immediately available in:
   - Ctrl+R (fzf history search - shows most recent first)
   - Up/Down arrows (bash history navigation)
   - All terminal sessions

**Note:** New Claude Code sessions automatically load the hook configuration. If you modify the hook, rebuild with:

```bash
sudo nixos-rebuild switch --flake .#<target>
# Or for home-manager only:
home-manager switch --flake .#<user>@<target>
```

Then restart Claude Code to load the updated configuration.

**How it works:**
- Uses a `PostToolUse` hook that triggers after each Bash tool execution
- The `claude-register-command` function appends commands to `~/.bash_history`
- Commands are also added to the current shell's in-memory history
- Uses the configured `HISTFILE` location (defaults to `~/.bash_history`)
- Respects your existing bash history settings (size limits, deduplication, etc.)

**Hook configuration** (already set in `claude-code.nix`):
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": {"tools": ["Bash"]},
      "hooks": [{"type": "command", "command": "claude-register-command \"{{command}}\""}]
    }]
  }
}
```

**Manual usage:**
```bash
# Register a command manually
claude-register-command "ls -la /etc/nixos"

# View recent history
history | tail -20
```

**Benefits:**
- Seamlessly integrates Claude Code commands with your bash workflow
- Commands can be recalled with Ctrl+R (fzf history search)
- Full command history available in all terminals
- Works with existing bash history configuration

## 🔐 1Password Commands

```bash
# Sign in to 1Password
op signin

# List vaults
op vault list

# List items
op item list

# Create SSH key
op item create --category="SSH Key" --title="My Key" --vault="Personal" --ssh-generate-key=ed25519

# Test SSH agent
SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l

# Use GitHub CLI with 1Password
gh auth status  # Uses 1Password token automatically
```

## 🍎 macOS Darwin Home-Manager

For using this configuration on macOS without NixOS:

```bash
# Apply Darwin home-manager configuration
home-manager switch --flake .#darwin

# Update packages
nix flake update
home-manager switch --flake .#darwin

# Test configuration
home-manager build --flake .#darwin
```

See `docs/DARWIN_SETUP.md` for detailed setup instructions for your M1 MacBook Pro.

---

_Last updated: 2025-10-20 with Python testing workflows and i3 IPC patterns_
- add the need to stage files when rebuilding nixos sytem

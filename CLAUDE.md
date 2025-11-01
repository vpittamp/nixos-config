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

### M1 MacBook Pro (Apple Silicon) Specific

**Platform**: M1 MacBook Pro with Sway/Wayland (aligned with hetzner-sway as of Feature 051)

**Key Features**:
- Single built-in Retina display (eDP-1) with 2x HiDPI scaling
- i3pm project management daemon (Feature 037)
- Sway dynamic configuration management (Feature 047)
- Walker/Elephant launcher with Wayland support
- Workspace mode handler with dynamic output detection

**M1-Specific Commands**:
```bash
# Rebuild system (requires --impure for Asahi firmware)
sudo nixos-rebuild switch --flake .#m1 --impure

# Check i3pm daemon status
systemctl --user status i3-project-event-listener

# Test i3pm daemon
i3pm daemon status
i3pm project list

# Check Sway outputs (M1 has single eDP-1 display)
swaymsg -t get_outputs | jq '.[] | {name, scale, current_mode}'

# Test workspace mode switching
workspace-mode single  # All workspaces on eDP-1
```

**Platform Differences from hetzner-sway**:
- **Display**: Single physical eDP-1 (Retina 3024x1890@2x) vs 3 virtual HEADLESS-* displays
- **Outputs**: Dynamic detection adapts to single monitor (PRIMARY=eDP-1, SECONDARY/TERTIARY=eDP-1)
- **Input**: Touchpad with natural scrolling and tap-to-click vs headless (no input devices)
- **Remote Access**: RustDesk (peer-to-peer) vs WayVNC (headless VNC server)
- **Audio**: Local PipeWire with speakers/headphones vs Tailscale audio streaming
- **WiFi**: BCM4378 firmware with power management workarounds

**i3pm Daemon Setup**:
The i3pm daemon is configured as a system service in `/etc/nixos/configurations/m1.nix`:
```nix
services.i3ProjectDaemon = {
  enable = true;
  user = "vpittamp";
  logLevel = "INFO";
};
```

After applying configuration, verify daemon is running:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener

# View daemon logs
journalctl --user -u i3-project-event-listener -f

# Test project commands
i3pm project list
i3pm daemon status
```

**Troubleshooting M1-Specific Issues**:

*Daemon not starting*:
```bash
# Check service status
systemctl --user status i3-project-event-listener

# Check daemon logs for errors
journalctl --user -u i3-project-event-listener -n 50

# Restart daemon
systemctl --user restart i3-project-event-listener

# Rebuild if module wasn't enabled
sudo nixos-rebuild switch --flake .#m1 --impure
```

*Workspace mode handler errors*:
```bash
# Check detected outputs
swaymsg -t get_outputs | jq -r '.[].name'
# Should show: eDP-1

# Test workspace mode
workspace-mode single
# Should succeed with all workspaces on eDP-1

# Check handler script
cat ~/.config/sway/workspace-mode
```

*WiFi stability issues (BCM4378)*:
```bash
# Check if WiFi recovery service ran
systemctl status wifi-recovery

# Manually reload WiFi module
sudo modprobe -r brcmfmac && sleep 2 && sudo modprobe brcmfmac

# Check kernel params
cat /proc/cmdline | grep brcmfmac
# Should show: brcmfmac.feature_disable=0x82000
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

Keyboard-driven application launcher with file search, web search, calculator, symbol picker, todo list, window switching, bookmarks, and custom commands.

**Launch**: `Meta+D` or `Alt+Space`

**Provider Prefixes**:
- (none) - Launch applications from registry
- (none) - Window switcher (fuzzy window search)
- (none) - Bookmarks (quick URL access)
- (none) - Custom commands (user-defined shortcuts)
- `/` - Search files in $HOME or project dir
- `@` - Web search (Google, GitHub, Nix, Arch Wiki, Stack Overflow, Rust Docs, etc.)
- `!` - Todo list management (create, view, complete tasks)
- `=` - Calculator (e.g., `=2+2`)
- `.` - Unicode symbols (e.g., `.lambda` → λ)
- `:` - Clipboard history (Wayland only)
- `>` - Run shell commands
- `;s` - Switch tmux sessions
- `;p` - Switch i3pm projects

**Common Tasks**:
```bash
# Launch app with project context
Meta+D → type "code" → Return

# Task management (Feature 050)
Meta+D → type "!buy groceries" → Return  # Create task
Meta+D → type "!" → Return                # View all tasks

# Window switching (Feature 050)
Meta+D → type "firefox" → Return  # Focus Firefox window
Meta+D → type "term" → Return      # Focus terminal

# Quick bookmarks (Feature 050)
Meta+D → type "github" → Return    # Open GitHub
Meta+D → type "nix manual" → Return # Open NixOS docs

# Custom commands (Feature 050)
Meta+D → type "reload sway" → Return     # Execute swaymsg reload
Meta+D → type "rebuild nixos" → Return   # Rebuild NixOS config

# Tmux session switching (sesh plugin)
Meta+D → type ";s nixos" → Return       # Attach to 'nixos' tmux session
Meta+D → type ";s " → Return             # Show all sessions

# Project switching (i3pm plugin)
Meta+D → type ";p nixos" → Return       # Switch to NixOS project
Meta+D → type ";p " → Return             # Show all projects

# Enhanced web search (Feature 050)
Meta+D → type "@nix hyprland" → Return   # Search Nix packages
Meta+D → type "@arch bluetooth" → Return # Search Arch Wiki
Meta+D → type "@so rust async" → Return  # Search Stack Overflow

# File search
Meta+D → type "/file.nix" → Return

# Calculator
Meta+D → type "=2+2" → Return  # Copies "4" to clipboard
```

**Service Management**:
```bash
systemctl --user status elephant  # Check backend service
journalctl --user -u elephant -f  # View logs
systemctl --user restart elephant  # Restart after config changes
```

**Customization** (Feature 050):

**Dynamic Command Management** (no rebuild required):
```bash
walker-cmd add "backup nixos" "sudo rsync -av /etc/nixos /backup/"
walker-cmd save "git status"    # Interactive prompt for name (via rofi)
walker-cmd remove "backup nixos"
walker-cmd list                 # Show all custom commands
walker-cmd edit                 # Edit commands file directly
walker-cmd reload               # Reload Elephant service
```

**Save commands from history** (manual workflow):
```bash
# Run a command via runner provider
Meta+D → >git status → Return

# Save it from terminal
walker-cmd save "git status"
# Rofi prompts for name → Enter name → Return
# Command now saved to custom commands!
```

**Runner provider actions**:
- `Return` - Execute command
- `Shift+Return` - Execute in terminal

**Static Configuration** (requires rebuild):
- **Bookmarks**: Edit `home-modules/desktop/walker.nix` → `xdg.configFile."elephant/bookmarks.toml"`
- **Search Engines**: Edit `home-modules/desktop/walker.nix` → `xdg.configFile."elephant/websearch.toml"`
- Rebuild: `home-manager switch --flake .#hetzner-sway`

**Note**: Custom commands are now managed dynamically via `walker-cmd` CLI tool and persist across rebuilds.

**Detailed Documentation**:
- Feature 043 (Base): `/etc/nixos/specs/043-get-full-functionality/quickstart.md`
- Feature 050 (Enhanced): `/etc/nixos/specs/050-enhance-the-walker/quickstart.md`

## 🔄 Sway Dynamic Configuration Management (Feature 047)

Hot-reloadable Sway configuration with validation, version control, and conflict detection. Uses template-based approach to avoid home-manager conflicts.

**Configuration Files** (writable, Git-tracked):
- `~/.config/sway/keybindings.toml` - Keybinding definitions
- `~/.config/sway/window-rules.json` - Window rules
- `~/.config/sway/workspace-assignments.json` - Workspace assignments

**Essential Commands**:
```bash
# Reload configuration (auto-validates, commits to Git)
swaymsg reload  # or Mod+Shift+C

# Validate without applying
swayconfig validate

# View version history
swayconfig versions

# Rollback to previous version
swayconfig rollback <commit-hash>

# Check daemon status
systemctl --user status sway-config-daemon
```

**Key Features**:
- <100ms hot-reload latency
- Automatic syntax/semantic validation
- Git version control (auto-commit on success)
- File watcher with 500ms debounce
- Template initialization from `~/.local/share/sway-config-manager/templates/`

**Detailed Documentation**: See `/etc/nixos/specs/047-create-a-new/quickstart.md`

## ⌨️ Event-Driven Workspace Mode Navigation (Feature 042)

Fast keyboard-driven workspace navigation with <20ms latency. Navigate to any workspace (1-70) by typing digits in a dedicated mode, replacing slow bash scripts (70ms) with event-driven Python daemon.

**Quick Access Keybindings**:

| Action | M1 MacBook Pro | Hetzner Cloud | Fallback |
|--------|----------------|---------------|----------|
| **Navigate to workspace** | `CapsLock` | `Ctrl+0` | `Mod+;` |
| **Move window to workspace** | `Shift+CapsLock` | `Ctrl+Shift+0` | `Mod+Shift+;` |
| **Cancel mode** | `Escape` | `Escape` | `Escape` |

**Common Workflows**:
```bash
# Navigate to workspace 23
1. Press CapsLock (M1) or Ctrl+0 (Hetzner)
2. Type: 2 3
3. Press Enter
→ Focus switches to workspace 23 with correct monitor

# Move window to workspace 5
1. Focus the window
2. Press Shift+CapsLock (M1) or Ctrl+Shift+0 (Hetzner)
3. Type: 5
4. Press Enter
→ Window moves to workspace 5, you follow it

# Cancel without action
1. Enter workspace mode (CapsLock)
2. Type some digits (optional)
3. Press Escape
→ Mode exits, no workspace change
```

**Visual Feedback**:
- **Native mode indicator** (swaybar binding_mode): `→ WS` (goto), `⇒ WS` (move)
- **Status bar block** (i3bar): `WS: 23` (shows accumulated digits)
- **Real-time updates**: <10ms event latency from daemon

**CLI Commands**:
```bash
# Query current mode state
i3pm workspace-mode state
# Output: Active: true, Mode: goto, Digits: 23, Entered: 2025-10-31 12:34:56

# View navigation history (last 100 switches)
i3pm workspace-mode history
i3pm workspace-mode history --limit=10 --json

# Manual control (for scripting)
i3pm workspace-mode digit 2    # Add digit to accumulator
i3pm workspace-mode digit 3
i3pm workspace-mode execute    # Execute switch
i3pm workspace-mode cancel     # Exit mode without action
```

**Multi-Monitor Output Focusing**:
Workspaces automatically focus the correct monitor based on workspace number:

| Workspace | M1 (1 monitor) | Hetzner (3 monitors) |
|-----------|----------------|----------------------|
| 1-2 | eDP-1 (built-in) | HEADLESS-1 (PRIMARY) |
| 3-5 | eDP-1 (built-in) | HEADLESS-2 (SECONDARY) |
| 6+ | eDP-1 (built-in) | HEADLESS-3 (TERTIARY) |

**Adaptive behavior**: Automatically adjusts for 1-3 monitor setups, no configuration required.

**Performance Metrics**:
- Digit accumulation: <10ms latency
- Workspace switch: <20ms execution
- Total navigation: <100ms (mode entry → digit input → execution → focus change)
- Status bar update: <5ms event broadcast

**Troubleshooting**:
```bash
# Check daemon integration
i3pm daemon status  # Verify workspace_mode_manager is active

# View workspace mode events
i3pm daemon events --type=mode --follow

# Check navigation history
i3pm workspace-mode history --limit=20

# Verify mode state
i3pm workspace-mode state --json
```

**Detailed Documentation**: See `/etc/nixos/specs/042-event-driven-workspace-mode/quickstart.md`

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

- **Intelligent Automatic Workspace-to-Monitor Assignment** - Automatic workspace redistribution (Feature 049)
  - Fully automatic workspace reassignment when monitors connect/disconnect
  - Zero configuration - works out of the box with hardcoded distribution rules
  - 500ms debounce prevents flapping during rapid monitor changes
  - Window preservation - windows never lost during monitor changes
  - Distribution rules: 1 monitor (all WS), 2 monitors (WS 1-2 primary, 3-70 secondary), 3 monitors (WS 1-2 primary, 3-5 secondary, 6-70 tertiary)
  - State persistence to `~/.config/sway/monitor-state.json`
  - CLI command: `i3pm monitors status` - view monitor configuration
  - Reassignment history tracked in daemon (last 100 operations)
  - Event-driven with <1 second total latency (output event → completion)
  - Replaces legacy MonitorConfigManager with simpler DynamicWorkspaceManager
  - Documentation: `/etc/nixos/specs/049-intelligent-automatic-workspace/quickstart.md`

- **Sway Dynamic Configuration Management** - Hot-reloadable Sway configuration (Feature 047)
  - Migrated from i3/X11 to Sway/Wayland as primary window manager on Hetzner Cloud
  - Dynamic keybinding management with TOML-based configuration
  - Automatic validation before applying configuration changes
  - Git-based version control with automatic commits on successful reloads
  - File watcher for automatic reloads (500ms debounce)
  - Template-based approach avoids home-manager read-only symlink conflicts
  - Configuration files: `~/.config/sway/keybindings.toml`, `window-rules.json`, `workspace-assignments.json`
  - CLI commands: `swayconfig reload`, `swayconfig validate`, `swayconfig rollback`, `swayconfig versions`
  - <100ms reload latency, conflict detection, rollback support
  - Documentation: `/etc/nixos/specs/047-create-a-new/quickstart.md`

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

- **Event-Driven i3bar Status Bar** - Real-time status updates via daemon subscriptions
  - Replaced Polybar with native i3bar using event-driven protocol
  - Status bar subscribes to i3pm daemon events for instant updates (<100ms latency)
  - Status blocks: project context, CPU, memory, network, date/time
  - Catppuccin Mocha theme with workspace buttons
  - Configuration in `home-modules/desktop/i3bar.nix` with event-driven script
  - Benefits: Instant project updates, native i3 integration, lower resource usage (no polling)

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

The i3pm (i3 project management) system provides project-scoped application workspace management for i3 and Sway window managers (both share the same IPC protocol). Features include:
- Switch between project contexts (NixOS, Stacks, Personal)
- Automatically show/hide project-specific applications
- Maintain global applications accessible across all projects
- Adapt workspace distribution across multiple monitors
- Works on both i3/X11 and Sway/Wayland configurations

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

### Essential Commands

```bash
# Project management (aliases: pswitch, pclear, plist, pcurrent)
i3pm project switch <name>        # Switch to project
i3pm project create <name> --directory <dir> --icon "🚀"
i3pm project list                 # List all projects
i3pm project current              # Show active project

# Daemon monitoring
i3pm daemon status                # Status and diagnostics
i3pm daemon events --follow       # Real-time event stream

# Diagnostics (Feature 039)
i3pm diagnose health              # Health check
i3pm diagnose window <id>         # Window properties
i3pm diagnose validate            # State consistency

# Multi-monitor workspace distribution (Feature 033)
i3pm monitors config show         # View configuration
i3pm monitors reassign            # Apply workspace distribution
i3pm monitors status              # Show monitor table
```

**Workspace Distribution** (auto-adapts on monitor connect/disconnect):
- 1 monitor: All workspaces on primary
- 2 monitors: WS 1-2 primary, WS 3-70 secondary
- 3+ monitors: WS 1-2 primary, WS 3-5 secondary, WS 6-70 tertiary

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

### Automatic Window Filtering (Feature 037) with State Preservation (Feature 038)

**Automatic hiding/showing on project switch**: When you switch projects, scoped windows from the previous project automatically hide (move to scratchpad), while windows for the new project restore to their exact workspace locations. Global apps remain visible across all projects.

**How it works**:
1. User switches project via `Win+P` or `pswitch nixos`
2. Daemon receives tick event and triggers filtering
3. All scoped windows from old project hide to scratchpad **with full state capture**
4. All scoped windows for new project restore from scratchpad **with exact state restoration**
5. Windows return to exact workspace positions (tracked persistently)

**Window State Preservation (Feature 038 - v1.4.0)**:
- ✅ **Tiling state preserved** (FIXED in v1.4.0): Tiled windows remain tiled, floating windows remain floating
  - **v1.4.0 Fix**: State is now captured BEFORE scratchpad move on first hide, then preserved on subsequent hides
  - **Root Cause**: i3's `move scratchpad` always makes windows floating, so capturing state after move was incorrect
  - **Solution**: Check for existing saved state and preserve original floating value (lines 437-448 in `window_filter.py`)
- ✅ **Exact workspace restoration**: Windows return to their original workspace numbers (not current workspace)
- ✅ **Floating geometry preserved**: Position (x, y) and size (width, height) maintained for floating windows
- ✅ **Scratchpad origin tracking**: Windows manually placed in scratchpad stay there (not auto-restored)
- ✅ **Manual moves tracked**: Move VS Code from WS2 → WS5, position persists across project switches
- ✅ **Backward compatible**: Works with existing v1.0 window-workspace-map.json files

**Window persistence**:
- State persisted in `~/.config/i3/window-workspace-map.json` (schema v1.1)
- Works across daemon restarts (persistent storage)
- Workspace assignment on launch (apps open on configured workspace regardless of focus)
- Geometry tolerance: <10px drift acceptable for floating windows

**Performance**:
- Typical project switch: 2-5ms for 10 windows
- Sequential processing prevents race conditions
- Request queue handles rapid switches gracefully

**Backend API** (for advanced usage):
```python
# Query hidden windows via daemon client
async with DaemonClient() as daemon:
    result = await daemon.get_hidden_windows(project_name="nixos")
    # Returns: {"projects": {...}, "total_hidden": N}

    # Inspect specific window state
    state = await daemon.get_window_state(window_id=123456)
    # Returns: visibility, I3PM_* env vars, tracking info, i3 state
```

**Troubleshooting window filtering and state preservation**:
```bash
# Check if windows are being filtered
i3pm daemon events --type=tick | grep filtering

# Verify window tracking with full state
cat ~/.config/i3/window-workspace-map.json | jq .

# Inspect specific window state (Feature 038)
i3pm windows --json | jq '.outputs[].workspaces[].windows[] | select(.id == WINDOW_ID)'

# Check window state schema version
cat ~/.config/i3/window-workspace-map.json | jq '.version'  # Should be "1.1"

# View daemon logs for state capture/restoration (Feature 038)
journalctl --user -u i3-project-event-listener -n 100 | grep -E "Capturing state|Restoring window|geometry"

# Check performance metrics (target <50ms per window)
journalctl --user -u i3-project-event-listener -n 50 | grep "Window filtering complete"

# Verify floating state preservation
# Open floating calculator, switch projects, verify it's still floating with same position
xwininfo -int  # Click window to get window ID, then check state

# Manual hide/restore (via daemon API)
# Note: Automatic filtering happens on project switch
```

### Multi-Monitor Support

Workspaces automatically distribute based on monitor count:
- **1 monitor**: All workspaces on primary
- **2 monitors**: WS 1-2 on primary, WS 3-9 on secondary
- **3+ monitors**: WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary

After connecting/disconnecting monitors, **workspaces automatically reassign** (Feature 037 T030-T035). You can also manually trigger reassignment with `Win+Shift+M` or `i3pm monitors reassign`.

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

**Tiled windows becoming floating after project switch (Feature 038):**
1. Check daemon version: `systemctl --user status i3-project-event-listener | grep version`
   - Should be v1.4.0 or higher (v1.4.0 includes the scratchpad floating state fix)
2. Verify state capture logging: `journalctl --user -u i3-project-event-listener | grep "Capturing state"`
   - Look for "preserved_state=True" on subsequent hides
3. Check window state file: `cat ~/.config/i3/window-workspace-map.json | jq '.version'`
   - Should be "1.1" for full state preservation
4. If version is old, rebuild and restart daemon: `sudo nixos-rebuild switch --flake .#hetzner-sway`

**Floating windows losing position/size (Feature 038):**
1. Verify geometry is being captured: `journalctl --user -u i3-project-event-listener | grep "Captured geometry"`
2. Check state file has geometry: `cat ~/.config/i3/window-workspace-map.json | jq '.windows[].geometry'`
3. Verify restoration sequence: `journalctl --user -u i3-project-event-listener | grep "Restoring geometry"`
4. If geometry is null for floating windows, there may be a capture timing issue - report bug

**Windows not returning to original workspace:**
1. Check state file workspace numbers: `cat ~/.config/i3/window-workspace-map.json | jq '.windows[].workspace_number'`
2. Verify restoration uses exact workspace: `journalctl --user -u i3-project-event-listener | grep "move workspace number"`
3. Check for workspace fallback: `journalctl --user -u i3-project-event-listener | grep "No saved state"`

**Edit project configuration:**
```bash
# Manually edit
vi ~/.config/i3/projects/nixos.json

# Reload daemon after edits
systemctl --user restart i3-project-event-listener
```

For more details, see the quickstart guides:
```bash
cat /etc/nixos/specs/015-create-a-new/quickstart.md  # Event-based system (Feature 015)
cat /etc/nixos/specs/035-now-that-we/quickstart.md   # Registry-centric system (Feature 035)
cat /etc/nixos/specs/037-given-our-top/quickstart.md # Window filtering (Feature 037)
cat /etc/nixos/specs/038-create-a-new/quickstart.md  # Window state preservation (Feature 038)
cat /etc/nixos/specs/039-create-a-new/quickstart.md  # Diagnostic tooling (Feature 039)
```

### Diagnostic Tooling (Feature 039)

The `i3pm diagnose` command provides comprehensive diagnostic capabilities for troubleshooting window management issues without reading daemon source code.

**Quick Diagnostic Commands**:
```bash
# Check daemon health and event subscriptions
i3pm diagnose health
i3pm diagnose health --json  # Machine-readable output

# Inspect specific window properties
i3pm diagnose window <window_id>
i3pm diagnose window 94532735639728 --json

# View recent event history
i3pm diagnose events
i3pm diagnose events --limit=50 --type=window
i3pm diagnose events --follow  # Live event stream (Ctrl+C to stop)

# Validate daemon state consistency
i3pm diagnose validate
i3pm diagnose validate --json
```

**Health Check** (`i3pm diagnose health`):
- Daemon version and uptime
- i3 IPC connection status
- JSON-RPC server status
- Event subscription details (window, workspace, output, tick)
- Window tracking statistics
- Overall health assessment with exit codes:
  - `0` = Healthy
  - `1` = Warning (state drift, subscription issues)
  - `2` = Critical (daemon not running, i3 IPC disconnected)

**Window Identity** (`i3pm diagnose window <id>`):
- Window class, instance, and title
- Workspace and output location
- I3PM environment variables (`I3PM_PROJECT_NAME`, `I3PM_APP_NAME`, etc.)
- Registry matching details (matched app, match type)
- Project association
- PWA detection (Firefox FFPWA-*, Chrome PWAs)
- Class mismatch detection with fix suggestions

**Event Trace** (`i3pm diagnose events`):
- Recent events from circular buffer (500 events)
- Event timestamps, types, and changes
- Window information for each event
- Processing duration with color coding:
  - Green: <50ms (good)
  - Yellow: 50-100ms (acceptable)
  - Red: >100ms (slow)
- Error detection and reporting
- Live streaming mode with `--follow` flag
- Filter by type: `--type=window|workspace|output|tick`

**State Validation** (`i3pm diagnose validate`):
- Compare daemon tracked state vs actual i3 window tree
- Detect workspace mismatches
- Identify mark inconsistencies
- Report state drift with severity levels
- Consistency percentage and detailed mismatch table
- Exit codes:
  - `0` = State is consistent
  - `1` = State inconsistencies detected

**Example Troubleshooting Workflow**:
```bash
# 1. Check if daemon is healthy
i3pm diagnose health
# Output: Daemon version, uptime, event subscriptions, health status

# 2. Find window ID (if investigating specific window)
i3-msg -t get_tree | jq '.. | select(.window?) | {id: .id, class: .window_properties.class, title: .name}'

# 3. Inspect window identity
i3pm diagnose window 94532735639728
# Output: Window properties, I3PM env, registry matching, project association

# 4. Check recent events for anomalies
i3pm diagnose events --limit=20 --type=window
# Output: Recent window events with timing and error info

# 5. Validate state consistency
i3pm diagnose validate
# Output: State comparison, mismatch detection, consistency metrics

# 6. Monitor live events during testing
i3pm diagnose events --follow
# Press Ctrl+C to stop
```

**Common Diagnostic Scenarios**:

*Window opens on wrong workspace:*
```bash
# Check if workspace rule exists
i3pm diagnose window <window_id>
# Look at "Registry Matching" section for matched app and workspace assignment
```

*Window class mismatch:*
```bash
# Diagnostic shows class mismatch with suggestions
i3pm diagnose window <window_id>
# Output includes:
#   - Expected class from configuration
#   - Actual class from window
#   - Normalized class
#   - Fix suggestions (update config, use alias, etc.)
```

*Events not processing:*
```bash
# Check event subscriptions are active
i3pm diagnose health
# Look for "Event Subscriptions" section

# Check recent events
i3pm diagnose events --limit=50
# Verify events are being recorded
```

*State drift after daemon restart:*
```bash
# Validate state consistency
i3pm diagnose validate
# Output shows windows with workspace mismatches
```

**Output Formats**:
- Default: Rich-formatted tables with color coding
- `--json` flag: Machine-readable JSON for scripting/automation
- Exit codes match severity for shell scripting integration

**Error Handling**:
- Clear error messages with actionable suggestions
- Connection errors: "Start daemon with: systemctl --user start i3-project-event-listener"
- Timeout errors: "Check daemon status: systemctl --user status i3-project-event-listener"
- Window not found: "Tip: Get window ID with: i3-msg -t get_tree | jq '..'"

## 🚀 IPC Launch Context (Feature 041)

Solves multi-instance application tracking by correlating windows to launches via pre-notification system.

**Key Concept**: Launcher wrapper notifies daemon BEFORE app starts. When window appears (0.5-2s later), daemon correlates it using class match + timing + workspace signals.

**Accuracy**: 100% for sequential launches (>2s apart), 95% for rapid launches (<0.5s apart)

**Essential Commands**:
```bash
# View correlation metrics
i3pm daemon status  # Shows launch registry stats

# Debug window correlation
i3pm diagnose window <window_id>  # Shows matched_via_launch, confidence, signals_used

# View launch events
i3pm daemon events --type=launch --limit=10
```

**Troubleshooting**:
- Window assigned to wrong project → Check `i3pm diagnose window <id>` for confidence score
- Launch notification not received → Verify `app-launcher-wrapper.sh` is being used
- Pending launch expired → Check daemon logs for timing issues

**Detailed Documentation**: See `/etc/nixos/specs/041-ipc-launch-context/quickstart.md`

## 📦 Registry-Centric Architecture (Feature 035)

Environment variable-based project management replacing tag-based system. Applications launched via registry inherit `I3PM_*` environment variables for deterministic window-to-project association.

**Key Concepts**:
- **Application Registry** (`app-registry.nix`): Single source of truth for apps, metadata, workspace assignments
- **Environment Variables**: `I3PM_PROJECT_NAME`, `I3PM_PROJECT_DIR`, `I3PM_APP_NAME`, `I3PM_SCOPE`
- **Window Filtering**: Daemon reads `/proc/<pid>/environ` to determine window ownership
- **No Configuration**: Automatic based on active project

**Essential Commands**:
```bash
# Application management
i3pm apps list                    # List registered apps
i3pm apps show vscode             # Show app details

# Project management
i3pm project create <name> --directory <dir> --icon "🚀"
i3pm project list                 # List projects
i3pm project switch nixos         # Switch projects (or use 'pswitch' alias)
i3pm project current              # Show active project

# Layout management
i3pm layout save nixos            # Save current layout
i3pm layout restore nixos         # Restore saved layout
i3pm layout list                  # List saved layouts

# Daemon monitoring
i3pm daemon status                # Check daemon
i3pm daemon events --follow       # Real-time event stream
```

**Debugging**:
```bash
# Check window environment
xprop _NET_WM_PID | awk '{print $3}'  # Get PID
cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM_

# Monitor launches
tail -f ~/.local/state/app-launcher.log
```

**Detailed Documentation**: See `/etc/nixos/specs/035-now-that-we/quickstart.md`

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

## 🖥️ Multi-Monitor VNC Access (Hetzner Cloud)

### Quick Connect

The Hetzner Cloud VM provides **three virtual displays** accessible via VNC over Tailscale for a multi-monitor development workflow.

**Connection URLs** (replace `100.64.1.234` with your Tailscale IP):
```
Display 1 (Workspaces 1-2): vnc://100.64.1.234:5900
Display 2 (Workspaces 3-5): vnc://100.64.1.234:5901
Display 3 (Workspaces 6-9): vnc://100.64.1.234:5902
```

**Find your Tailscale IP**:
```bash
tailscale status | grep hetzner
```

### Common VNC Commands

```bash
# Check VNC services status
systemctl --user status wayvnc@HEADLESS-{1,2,3}

# Restart all VNC services
systemctl --user restart wayvnc@HEADLESS-{1,2,3}

# View VNC service logs
journalctl --user -u wayvnc@HEADLESS-1 -f

# Verify displays exist
swaymsg -t get_outputs | jq '.[] | {name, active, current_mode}'

# Check workspace assignments
swaymsg -t get_workspaces | jq '.[] | {num, output, visible}'
```

### Troubleshooting VNC Connections

**Connection Refused:**
```bash
# Verify services are running
systemctl --user list-units 'wayvnc@*'

# Restart failed service
systemctl --user restart wayvnc@HEADLESS-1

# Check firewall rules
sudo iptables -L -n | grep -E '590[0-2]'
```

**Blank Screen:**
```bash
# Verify outputs are active
swaymsg -t get_outputs | jq '.[] | {name, active}'

# Switch to workspace to activate display
swaymsg workspace number 1  # For Display 1
swaymsg workspace number 3  # For Display 2
swaymsg workspace number 6  # For Display 3
```

**Workspace on Wrong Display:**
```bash
# Check monitor status
i3pm monitors status

# Verify workspace assignments
swaymsg -t get_workspaces | jq '.[] | {num, output}'

# Check Sway config workspace assignments
grep "workspace.*output" ~/.config/sway/config
```

**Performance Issues:**
```bash
# Monitor VNC service resource usage
systemctl --user status wayvnc@HEADLESS-1 | grep -E "(CPU|Memory)"

# Monitor network traffic
sudo iftop -i tailscale0

# Check Tailscale connection type (direct vs relay)
tailscale status
```

### Complete Documentation

For detailed setup, VNC client recommendations, resolution changes, and advanced usage, see:
```bash
cat /etc/nixos/specs/048-multi-monitor-headless/quickstart.md
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

_Last updated: 2025-10-29 with Sway/Wayland migration and Feature 047 (Dynamic Configuration Management)_
- Migrated primary configuration from i3/X11 to Sway/Wayland (hetzner-sway)
- Added hot-reloadable Sway configuration with validation and version control
- Template-based configuration approach avoids home-manager conflicts
- i3pm system works with both i3 and Sway via shared IPC protocol

## Active Technologies
- Python 3.11+ (existing i3pm daemon runtime) + i3ipc-python (i3ipc.aio for async), asyncio, Rich (terminal UI), pytest/pytest-asyncio (testing) (042-event-driven-workspace-mode)
- In-memory state only (no persistence) - workspace mode state and history stored in daemon memory, cleared on restart (042-event-driven-workspace-mode)
- Configuration files only (swaybar config, status generator config) - no persistent data storage (052-enhanced-swaybar-status)

## Recent Changes
- 052-enhanced-swaybar-status: Enhanced swaybar with event-driven status blocks (volume, battery, network, bluetooth) using D-Bus integration, while preserving all original system monitoring features
- 042-event-driven-workspace-mode: Added Python 3.11+ (existing i3pm daemon runtime) + i3ipc-python (i3ipc.aio for async), asyncio, Rich (terminal UI), pytest/pytest-asyncio (testing)

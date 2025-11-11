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

# Monitors (Feature 001: Declarative workspace-to-monitor assignment)
i3pm monitors {status|reassign|config}
```

### Declarative Workspace-to-Monitor Assignment (Feature 001)

Assign workspaces to specific monitor roles (primary/secondary/tertiary) declaratively in Nix configuration. Supports automatic fallback when monitors disconnect, PWA-specific preferences, floating window sizing, and output preferences.

**Quick Keys**: None (configured in app-registry-data.nix and pwa-sites.nix)

**Monitor Roles**:
- **Primary**: Main display (WS 1-2 by default)
- **Secondary**: Second display (WS 3-5 by default)
- **Tertiary**: Third display (WS 6+ by default)

**Key Features**:
- **Declarative Configuration**: Specify `preferred_monitor_role` in app definitions
- **Automatic Fallback**: Workspaces reassign when monitors disconnect (tertiary→secondary→primary)
- **PWA Support**: PWAs can override monitor role preferences in pwa-sites.nix
- **Floating Windows**: Declare floating behavior with size presets (scratchpad/small/medium/large)
- **Output Preferences**: Optionally prefer specific physical outputs (e.g., HDMI-A-1 always primary)
- **Hot-Reload**: Changes apply on next daemon event (<1s reassignment time)

#### CLI Commands

```bash
# Show current monitor assignments
i3pm monitors status

# Force workspace reassignment (after monitor connect/disconnect)
i3pm monitors reassign

# Show monitor role configuration and workspace assignments
i3pm monitors config
```

#### Configuration Examples

**App with Monitor Role** (`app-registry-data.nix`):
```nix
(mkApp {
  name = "code";
  display_name = "VS Code";
  command = "code";
  preferred_workspace = 2;
  preferred_monitor_role = "primary";  # Always on primary monitor
  # ... other fields
})
```

**PWA with Monitor Role** (`pwa-sites.nix`):
```nix
{
  name = "YouTube";
  url = "https://youtube.com";
  preferred_workspace = 50;
  preferred_monitor_role = "tertiary";  # PWA preference overrides app-registry
  # ... other fields
}
```

**Floating Window** (`app-registry-data.nix`):
```nix
(mkApp {
  name = "btop";
  display_name = "btop";
  command = "ghostty";
  parameters = "-e btop";
  preferred_workspace = 7;
  floating = true;
  floating_size = "medium";  # 1200×800, centered
  scope = "global";  # Visible across all projects
  # ... other fields
})
```

**Size Presets**:
- `scratchpad`: 1200×600 (Feature 062 terminal size)
- `small`: 800×500 (lightweight tools)
- `medium`: 1200×800 (default)
- `large`: 1600×1000 (full-featured apps)
- `null`: Natural size (application decides)

#### Monitor Role Inference

If `preferred_monitor_role` not specified, inferred from workspace number:
- **WS 1-2** → primary
- **WS 3-5** → secondary
- **WS 6+** → tertiary

#### Fallback Logic

When monitors disconnect, workspaces automatically reassign:
- **Tertiary unavailable** → use secondary
- **Secondary unavailable** → use primary
- **Primary unavailable** → error (no fallback)

#### Multi-Monitor Configurations

**1 Monitor** (M1 Mac): All workspaces on eDP-1 (primary role)

**2 Monitors** (Hetzner typical):
- Primary (HEADLESS-1): WS 1-2
- Secondary (HEADLESS-2): WS 3-70

**3 Monitors** (Hetzner full):
- Primary (HEADLESS-1): WS 1-2
- Secondary (HEADLESS-2): WS 3-5
- Tertiary (HEADLESS-3): WS 6-70

#### Output Preferences (Optional)

Prefer specific physical outputs for monitor roles (ignores connection order):

```nix
# In daemon config (future enhancement - US5)
output_preferences = {
  primary = ["HDMI-A-1", "DP-1"];      # Prefer HDMI-A-1, fallback to DP-1
  secondary = ["HDMI-A-2"];
  tertiary = ["DP-2"];
};
```

#### Troubleshooting

```bash
# Check current assignments
i3pm monitors status

# Show configuration
i3pm monitors config

# Force reassignment
i3pm monitors reassign

# Check daemon logs
journalctl --user -u i3-project-event-listener -f | grep -i monitor

# Verify workspace-assignments.json
cat ~/.config/sway/workspace-assignments.json | jq '.version'  # Should be "1.0"
```

**Common Issues**:
- **Workspace on wrong monitor**: Check `preferred_monitor_role` in app definition
- **PWA not respecting role**: PWA preference in pwa-sites.nix overrides app-registry
- **Floating window wrong size**: Verify `floating_size` preset (scratchpad/small/medium/large)
- **Monitor reassignment slow**: Should be <1s; check daemon status

**Docs**: See `/etc/nixos/specs/001-declarative-workspace-monitor/quickstart.md`

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

## 📊 Sway Tree Diff Monitor (Feature 064)

Real-time window state change monitoring with <10ms diff computation, user action correlation, and enriched context.

### Quick Commands

```bash
# Live monitoring (real-time event stream)
sway-tree-monitor live

# Historical query (past events with correlation)
sway-tree-monitor history --last 50
sway-tree-monitor history --since 5m --filter window::new

# Detailed diff inspection (field-level changes + I3PM context)
sway-tree-monitor diff <EVENT_ID>

# Performance statistics (CPU, memory, event distribution)
sway-tree-monitor stats [--since 1h]

# Daemon management
systemctl --user {status|start|stop|restart} sway-tree-monitor
journalctl --user -u sway-tree-monitor -f
```

### Key Features

- **Real-Time Monitoring**: Live stream of window/workspace changes with <100ms latency
- **User Action Correlation**: Matches keypresses to tree changes (500ms window, 90% accuracy)
- **Enriched Context**: Reads I3PM_* env vars and project marks from windows
- **Performance Optimized**: <2% CPU, <25MB memory, <10ms diff computation
- **Multiple Views**: Live, history, detailed diff, performance stats
- **Filtering**: By event type, significance, time range, project, user-initiated

### Use Cases

```bash
# Debug window management issues
sway-tree-monitor live  # Watch real-time changes

# Find what caused a window to close
sway-tree-monitor history --filter window::close --last 10

# Inspect specific event with full context
sway-tree-monitor diff 42  # Shows field changes + I3PM_PROJECT_NAME, etc.

# Monitor performance over time
sway-tree-monitor stats --since 1h  # Memory, CPU, diff times
```

### Architecture

- **Hash-Based Diffing**: Merkle tree hashing skips unchanged subtrees (2-8ms for 100 windows)
- **Circular Buffer**: 500-event buffer with automatic eviction (FIFO)
- **Correlation Engine**: Multi-factor confidence scoring (temporal, semantic, exclusivity, cascade)
- **JSON-RPC API**: Unix socket for CLI ↔ daemon communication

### Troubleshooting

```bash
# Daemon not running?
systemctl --user status sway-tree-monitor
systemctl --user start sway-tree-monitor

# High memory usage?
sway-tree-monitor stats  # Check buffer size, cache size

# Missing correlations?
journalctl --user -u sway-tree-monitor | grep "Captured binding"

# No enrichment data?
sway-tree-monitor diff <ID> | grep -A 5 "I3PM"  # Check environment vars
```

**Docs**: `/etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md`

## 🐍 Python Testing & Development

**Monitor**: `i3-project-monitor [--mode=events|history|tree|diagnose]`

**Test**: `i3-project-test {run|suite|verify-state} [--verbose|--ci]`

**Standards**: Python 3.11+, async/await, pytest-asyncio, Rich UI, i3ipc.aio, Pydantic models

**Docs**: `docs/PYTHON_DEVELOPMENT.md`, `docs/I3_IPC_PATTERNS.md`

## 🧪 Sway Test Framework (Feature 069)

Declarative JSON-based testing framework for Sway window manager with synchronization primitives to eliminate race conditions.

### Quick Commands

```bash
# Run a test
sway-test run tests/test_example.json

# Run all tests in a category
deno task test:basic          # Fast core functionality tests
deno task test:integration    # Multi-component tests
deno task test:regression     # Bug fix verification

# Generate coverage report
deno task coverage:html       # Open coverage/html/index.html
```

### Synchronization Actions (Zero Race Conditions)

**Problem**: Tests fail ~10% of the time because state is checked before Sway IPC commands finish X11 processing.

**Solution**: Use sync actions that guarantee X11 state consistency before continuing.

#### Action Types

| Action | Purpose | Example |
|--------|---------|---------|
| `sync` | Explicit sync point | After IPC command, before state check |
| `launch_app_sync` | Launch app + auto-sync | Launch Firefox, automatically wait for window |
| `send_ipc_sync` | IPC command + auto-sync | Workspace switch, automatically wait for completion |

#### Migration Pattern

```json
// OLD (slow, flaky - 10s runtime, ~10% failure rate)
{"type": "launch_app", "params": {"app_name": "firefox"}},
{"type": "wait_event", "params": {"timeout": 10000}}

// NEW (fast, reliable - 2s runtime, 100% success rate)
{"type": "launch_app_sync", "params": {"app_name": "firefox"}}
```

### Example Test

```json
{
  "name": "Firefox workspace assignment",
  "actions": [
    {
      "type": "send_ipc_sync",
      "params": {"ipc_command": "[app_id=\"firefox\"] kill"}
    },
    {
      "type": "launch_app_sync",
      "params": {"app_name": "firefox"}
    }
  ],
  "expectedState": {
    "focusedWorkspace": 3,
    "workspaces": [{
      "num": 3,
      "windows": [{"app_id": "firefox", "focused": true}]
    }]
  }
}
```

### Performance Improvements

| Metric | OLD (timeout-based) | NEW (sync-based) | Improvement |
|--------|---------------------|------------------|-------------|
| Individual test | 10-15s | 2-3s | **5-6x faster** |
| Test suite (50 tests) | ~50s | ~25s | **50% faster** |
| Flakiness rate | 5-10% | <1% | **10x more reliable** |
| Sync latency (p95) | N/A | <10ms | Sub-millisecond accuracy |

### Test Organization

```
home-modules/tools/sway-test/tests/sway-tests/
├── basic/          # Core functionality (< 2s per test)
│   ├── test_sync_basic.json
│   └── test_window_launch.json
├── integration/    # Multi-component (2-10s per test)
│   ├── test_firefox_workspace_sync.json
│   └── test_launch_app_sync.json
└── regression/     # Bug fix verification
    └── (future tests)
```

### Architecture

- **Language**: TypeScript/Deno 1.40+ (matches existing framework)
- **Sync Protocol**: Sway IPC mark/unmark commands (inspired by i3 I3_SYNC)
- **State Comparison**: Multi-mode (partial, exact, assertions, empty) - Feature 068
- **Storage**: In-memory execution with JSON test files

### Key Features

1. **Zero Race Conditions**: Sync primitives guarantee state consistency
2. **5-10x Faster Tests**: No arbitrary timeouts (10s → 0.2-2s per action)
3. **Declarative Tests**: JSON-based test definitions with type validation
4. **Coverage Reporting**: Deno native coverage (>85% framework code)
5. **Organized Structure**: Tests categorized by type (basic/integration/regression)

### Development Workflow

```bash
# Write test (JSON)
cat > tests/test_example.json <<'EOF'
{
  "name": "Example test",
  "actions": [
    {"type": "launch_app_sync", "params": {"app_name": "alacritty"}}
  ],
  "expectedState": {
    "windowCount": 1
  }
}
EOF

# Run test
sway-test run tests/test_example.json

# Verify coverage
deno task coverage:html
```

### Migration Status (Feature 069)

**Phase 8 Complete**: 100% migration to sync-based tests
- **Migrated**: 7 timeout-based tests → sync-based
- **Deleted**: 8 legacy timeout-based test files
- **Result**: ZERO timeout-based tests remain (Constitution Principle XII)
- **Validation**: All 19 tests use sync patterns or event-driven helpers

### Docs

- **Quickstart**: `/etc/nixos/specs/069-sync-test-framework/quickstart.md` - Migration guide with examples
- **Data Model**: `/etc/nixos/specs/069-sync-test-framework/data-model.md` - TypeScript interfaces
- **Research**: `/etc/nixos/specs/069-sync-test-framework/research.md` - Sync protocol analysis
- **Framework Location**: `home-modules/tools/sway-test/`

---

## 🚀 Sway Test Framework Usability Improvements (Feature 070)

**Version**: 1.1.0 | **Status**: ✅ Complete | **Built on**: Feature 069 (Sync Framework)

Five developer experience improvements for the sway-test framework.

### Quick Commands

```bash
# List available apps and PWAs
sway-test list-apps --filter firefox    # Find apps by name
sway-test list-pwas --workspace 50      # Find PWAs by workspace

# Launch PWA in test by name (no ULID needed)
{
  "type": "launch_pwa_sync",
  "params": {"pwa_name": "youtube"}
}

# Launch app by registry name (auto-resolves command, workspace, class)
{
  "type": "launch_app_sync",
  "params": {"app_name": "firefox"}
}

# Manual cleanup of orphaned processes/windows
sway-test cleanup --all                  # Clean everything
sway-test cleanup --dry-run --verbose    # Preview cleanup
sway-test cleanup --json > report.json   # Get JSON report

# Enable performance benchmarking
SWAY_TEST_BENCHMARK=1 sway-test list-apps
```

### Feature 1: Clear Error Diagnostics

**Problem**: Cryptic errors required reading framework source code.

**Solution**: Structured errors with 8 error types, clear remediation steps, and diagnostic context.

**Example Error**:
```
Error: APP_NOT_FOUND - App Registry Reader
Application "firefx" not found in registry

Remediation steps:
  • Did you mean one of these? firefox, firefox-pwa
  • Run: sway-test list-apps --filter firefx
  • Add the app to app-registry-data.nix if it's missing

Diagnostic context:
  - app_name: firefx
  - available_apps: [firefox, firefox-pwa, code, ... (22 total)]
  - similar_apps: [firefox, firefox-pwa]
```

**Error Types**: `APP_NOT_FOUND`, `PWA_NOT_FOUND`, `INVALID_ULID`, `LAUNCH_FAILED`, `TIMEOUT`, `MALFORMED_TEST`, `REGISTRY_ERROR`, `CLEANUP_FAILED`

**Error Catalog**: `/etc/nixos/specs/070-sway-test-improvements/error-catalog.md`

### Feature 2: Graceful Cleanup Commands

**Problem**: Failed tests leave orphaned processes/windows requiring manual cleanup or system restart.

**Solution**: Automatic cleanup on test completion/failure + manual CLI command for recovery.

**Cleanup Strategies**:
- **Processes**: SIGTERM with 500ms timeout → SIGKILL if needed
- **Windows**: Sway IPC kill command via window markers
- **Concurrent**: Processes and windows cleaned in parallel

**Examples**:
```bash
# Preview cleanup
sway-test cleanup --dry-run --verbose

# Actual output:
Dry run: Would cleanup 3 process(es) and 2 window(s)

# Run cleanup
sway-test cleanup

# Output:
Processes:
  ✓ Terminated PID 12345 (firefox) - SIGTERM in 450ms
  ✓ Terminated PID 12346 (firefoxpwa) - SIGTERM in 380ms

Windows:
  ✓ Closed test_firefox_123 (workspace 3) in 120ms

Summary: 2 processes, 1 window cleaned in 1.25s
Success rate: 100%
```

### Feature 3: PWA Application Support

**Problem**: PWA testing required manual ULID lookup and brittle boilerplate.

**Solution**: First-class `launch_pwa_sync` action with friendly name resolution.

**Before (manual ULID)**:
```json
{
  "type": "launch_pwa_sync",
  "params": {"pwa_ulid": "01K666N2V6BQMDSBMX3AY74TY7"}
}
```

**After (friendly name)**:
```json
{
  "type": "launch_pwa_sync",
  "params": {"pwa_name": "youtube"}
}
```

**Features**:
- Auto-resolve PWA ULID from name
- Support both `pwa_name` and `pwa_ulid` parameters
- Validate ULID format (26-char base32)
- Clear errors if PWA not found or firefoxpwa missing
- `allow_failure` parameter for optional PWA launches

### Feature 4: App Registry Integration

**Problem**: Tests hardcoded app commands, making them brittle when configs changed.

**Solution**: Name-based app launches with automatic metadata resolution from `application-registry.json`.

**Test Code**:
```json
{
  "type": "launch_app_sync",
  "params": {"app_name": "firefox"}
}
```

**Framework Auto-Resolves**:
- Command: `firefox`
- Expected class: `firefox`
- Workspace: `3`
- Monitor role: `secondary`
- Scope: `global`
- Floating config (if applicable)

**Benefits**:
- Tests remain valid when app configs change
- Fuzzy matching suggests similar app names on errors
- Centralized app metadata in `app-registry-data.nix`

### Feature 5: CLI Discovery Commands

**Problem**: Developers searched through Nix files to find app names and PWA ULIDs.

**Solution**: CLI commands to explore available apps/PWAs without filesystem navigation.

**Examples**:
```bash
# List all apps with table formatting
sway-test list-apps

# Output:
NAME      COMMAND    WORKSPACE  MONITOR     SCOPE
firefox   firefox    3          secondary   global
code      code       2          primary     scoped
alacritty alacritty  1          primary     global

22 applications found

# Filter by name
sway-test list-apps --filter fire

# Filter by workspace
sway-test list-apps --workspace 3

# JSON output for scripting
sway-test list-apps --json | jq '.applications[] | select(.workspace == 3)'

# CSV export for spreadsheets
sway-test list-apps --format csv > apps.csv

# List PWAs
sway-test list-pwas

# Output:
NAME     URL                      ULID                       WORKSPACE  MONITOR
youtube  https://www.youtube.com  01K666N2V6BQMDSBMX3AY74TY7  50         tertiary
claude   https://claude.ai        01JCYF8Z2VQRST123456789ABC  52         tertiary

9 PWAs found
```

### Performance Benchmarks

Enable with `SWAY_TEST_BENCHMARK=1`:

| Operation | Target | Measured | Status |
|-----------|--------|----------|--------|
| Registry loading (app+PWA) | <50ms | ~7ms | ✅ 7x faster |
| PWA launch | <5s | ~2-3s | ✅ On target |
| Cleanup (10 resources) | <2s | ~1.25s | ✅ 37% faster |
| Error formatting | <10ms | ~2ms | ✅ 5x faster |

**Benchmark Output Example**:
```bash
SWAY_TEST_BENCHMARK=1 sway-test list-apps

[BENCHMARK] App registry load breakdown:
  - File read: 1.23ms
  - JSON parse: 0.45ms
  - Validation: 2.10ms
  - Map conversion: 0.18ms
  - TOTAL: 3.96ms (target: <50ms)
  - Apps loaded: 22
```

### Key Design Decisions

1. **StructuredError Pattern**: 8 error types with type/component/cause/remediation/context fields
2. **Zod Validation**: Schema validation for all registries (PWA, App, Test definitions)
3. **Cached Registries**: Load once per test session (7ms initial, <0.1ms cached)
4. **Graceful Termination**: SIGTERM first, SIGKILL after 500ms timeout
5. **JSON-First Output**: All commands support `--json` for scripting
6. **Unicode-Aware Tables**: Uses `@std/cli/unicode-width` for proper column alignment

### Tech Stack

- **Language**: TypeScript/Deno 1.40+ (matches Feature 069)
- **Validation**: Zod 3.22.4 (schema validation with `.nullable()` support)
- **Table Formatting**: `@std/cli`, `@std/fmt/colors` (Unicode-aware)
- **Registries**: JSON files at `~/.config/i3/{application,pwa}-registry.json`
- **Error Handling**: Custom `StructuredError` class with enum error types
- **Performance**: `performance.now()` for <1ms accurate benchmarking

### Docs

- **Quickstart**: `/etc/nixos/specs/070-sway-test-improvements/quickstart.md` - Full usage guide
- **Error Catalog**: `/etc/nixos/specs/070-sway-test-improvements/error-catalog.md` - All error types
- **Spec**: `/etc/nixos/specs/070-sway-test-improvements/spec.md` - User stories & requirements
- **Data Model**: `/etc/nixos/specs/070-sway-test-improvements/data-model.md` - TypeScript interfaces
- **Framework Location**: `home-modules/tools/sway-test/`

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

**Recent**: Feature 069 (sync test framework - 100% migration complete), Feature 062 (scratchpad terminal), Hybrid config (keybindings→Nix, window rules→dynamic), Feature 058 (Python backend consolidation), 053 (100% workspace assignment)

## Active Technologies
- Python 3.11+ (matching existing i3pm daemon) + i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation), pytest (testing), Pydantic (data models) (063-scratchpad-filtering)
- In-memory daemon state (project → terminal PID/window ID mapping), Sway window marks for persistence (063-scratchpad-filtering)
- Python 3.11+ (matching existing sway-tree-monitor daemon) + i3ipc (Sway IPC), orjson (JSON serialization), psutil (process info) (066-inspect-daemon-fix)
- In-memory circular buffer (500 events), no persistent storage (066-inspect-daemon-fix)
- TypeScript/Deno 1.40+ (sway-test framework) + Deno standard library (@std/cli, @std/fs, @std/path, @std/json), Zod 3.22+ (validation), Sway IPC mark/unmark (sync protocol) (068-fix-state-comparator, 069-sync-test-framework)
- N/A (test framework operates in-memory with JSON test files, zero legacy timeout code) (068-fix-state-comparator, 069-sync-test-framework)
- Python 3.11+ (matching existing i3pm daemon), Nix configuration language + i3ipc.aio (async Sway IPC), Pydantic (data validation), Nix expression evaluation (001-declarative-workspace-monitor)
- JSON state files (`~/.config/sway/monitor-state.json` extended from Feature 049), Nix configuration files (`app-registry-data.nix`, `pwa-sites.nix`) (001-declarative-workspace-monitor)
- TypeScript with Deno 1.40+ runtime (matches Constitution Principle XIII) (070-sway-test-improvements)
- TypeScript with Deno 1.40+ runtime + Zod 3.22.4 (validation), @std/cli (argument parsing, Unicode width), Sway IPC (window management) (070-sway-test-improvements)
- JSON registries (~/.config/i3/application-registry.json, ~/.config/i3/pwa-registry.json), In-memory cleanup state (070-sway-test-improvements)
- Python 3.11+ (matching existing workspace_panel.py daemon) (057-workspace-bar-icons)
- Python 3.11+ (matching existing i3pm daemon and sway-workspace-panel) + i3ipc.aio (async Sway IPC), Pydantic (data models), orjson (JSON serialization) (058-workspace-mode-feedback)
- In-memory state in `WorkspaceModeManager`, no persistent storage required (058-workspace-mode-feedback)

## Recent Changes
- **001-declarative-workspace-monitor** (2025-11): Declarative workspace-to-monitor assignment with 5 user stories: monitor role configuration (primary/secondary/tertiary), automatic fallback on disconnect, PWA-specific preferences, floating window sizing (scratchpad/small/medium/large), and optional output preferences. CLI commands: `i3pm monitors {status|reassign|config}`. See `/etc/nixos/specs/001-declarative-workspace-monitor/`
- 069-sync-test-framework: Enhanced sway-test with synchronization primitives (sync, launch_app_sync, send_ipc_sync), migrated 100% of tests from timeout-based to sync-based (zero legacy code remains), achieved 5-6x test speedup and <1% flakiness rate
- 063-scratchpad-filtering: Added Python 3.11+ (matching existing i3pm daemon) + i3ipc.aio (async Sway IPC), asyncio (event loop), psutil (process validation), pytest (testing), Pydantic (data models)

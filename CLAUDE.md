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

## 🚀 Walker/Elephant Launcher (Feature 043)

### Overview

Walker is a keyboard-driven application launcher with Elephant backend service providing advanced functionality. All features are fully configured and operational.

**Key Features**:
- Application launching with project context inheritance
- Clipboard history management
- File search and navigation
- Web search integration
- Calculator and symbol picker
- Shell command execution

**Configuration**: `/etc/nixos/home-modules/desktop/walker.nix` (fully configured, no changes needed)

### Quick Reference

#### Launch Walker
```bash
Meta+D     # Primary keybinding
Alt+Space  # Alternative keybinding
```

#### Provider Prefixes

| Prefix | Provider | Example | Description |
|--------|----------|---------|-------------|
| (none) | Applications | `code` | Launch applications from i3pm registry |
| `:` | Clipboard | `: ` (space after) | Show clipboard history |
| `/` | Files | `/walker.nix` | Search for files in $HOME or project dir |
| `@` | Web Search | `@nixos tutorial` | Search web with configured engines |
| `=` | Calculator | `=2+2` | Evaluate math expressions |
| `.` | Symbols | `.lambda` | Find Unicode symbols/emoji |
| `>` | Runner | `>echo hello` | Run shell commands |
| `;s ` | Sesh | `;s nixos` | Switch tmux sessions |
| `;p ` | Projects | `;p ` (space after) | Switch i3pm projects |

#### Keybindings (within Walker)

| Key | Action |
|-----|--------|
| `Return` | Execute default action |
| `Ctrl+Return` | Execute alternate action (e.g., open file with default app) |
| `Shift+Return` | Execute tertiary action (e.g., run command in terminal) |
| `Esc` | Close Walker |
| `↑/↓` | Navigate results |

### Common Workflows

#### Launch Application with Project Context
```bash
# 1. Press Meta+D to open Walker
# 2. Type application name (e.g., "code")
# 3. Press Return
# → Application launches with I3PM_* environment variables from active project
```

**Environment Variables Inherited**:
- `DISPLAY` - X11 display for window rendering
- `I3PM_PROJECT_NAME` - Active project name (e.g., "nixos")
- `I3PM_PROJECT_DIR` - Project directory path (e.g., "/etc/nixos")
- `I3PM_APP_NAME` - Application name from registry
- `I3PM_SCOPE` - "scoped" or "global"
- `XDG_DATA_DIRS` - Isolated to i3pm-applications directory

#### Clipboard History
```bash
# Access clipboard history
Meta+D → type ":" → select entry → Return

# Copy multiple items, then retrieve previous copies
echo "First" | xclip -selection clipboard
echo "Second" | xclip -selection clipboard
# Press Meta+D, type ":", navigate to "First", press Return
# Paste with Ctrl+V to get "First" back
```

**Features**:
- Reverse chronological order (most recent first)
- Text and image support
- Fuzzy search within history
- Preview shows first 100 characters

#### File Search
```bash
# Search for files
Meta+D → type "/walker.nix" → select file → Return
# → Opens in Ghostty + Neovim

# Open with default application
Meta+D → type "/document.pdf" → Ctrl+Return
# → Opens with xdg-open (default PDF viewer)

# Open file at specific line number
# (if walker-open-in-nvim script supports it)
Meta+D → type "/file.txt" → Return
# → Opens at line 1 by default
```

**Search Scope**:
- User home directory (`$HOME`)
- Active project directory (`$I3PM_PROJECT_DIR` if project active)
- Excludes: `.git`, `.cache`, `.nix-profile`, `node_modules`, `target`, `result`

#### Web Search
```bash
# Search with default engine (Google)
Meta+D → type "@nixos tutorial" → Return

# Search with specific engine
Meta+D → type "@" → select "GitHub" → type "nixos" → Return
```

**Configured Search Engines**:
- Google (default)
- DuckDuckGo
- GitHub
- YouTube
- Wikipedia

**URL Encoding**: Special characters automatically encoded (e.g., "C++" → "C%2B%2B")

#### Calculator
```bash
# Basic math
Meta+D → type "=2+2" → Return (copies "4" to clipboard)

# Supported operators
=10+5     → 15 (addition)
=10-5     → 5 (subtraction)
=10*5     → 50 (multiplication)
=100/4    → 25 (division)
=17%5     → 2 (modulo)
=2^8      → 256 (exponentiation)
=(2+3)*4  → 20 (parentheses)
```

**Result**: Automatically copied to clipboard for pasting

#### Symbol Picker
```bash
# Search for symbol
Meta+D → type ".lambda" → select λ → Return
# → Symbol inserts at cursor position in focused application

# Browse mode
Meta+D → type "." → browse symbols

# Common searches
.heart    → ❤, 💙, 💚, 💛
.arrow    → →, ←, ↑, ↓
.check    → ✓, ✔
```

#### Shell Commands
```bash
# Background execution (no terminal)
Meta+D → type ">notify-send 'Test'" → Return
# → Desktop notification appears, no terminal

# Terminal execution
Meta+D → type ">echo 'Hello'" → Shift+Return
# → Ghostty terminal opens with command output

# Interactive commands
Meta+D → type ">htop" → Shift+Return
# → htop runs in Ghostty terminal
```

**Execution Modes**:
- `Return`: Background (silent, no terminal)
- `Shift+Return`: Terminal (Ghostty opens with output)

### Service Management

#### Elephant Backend Service
```bash
# Check service status
systemctl --user status elephant

# View service logs
journalctl --user -u elephant -f

# Restart service
systemctl --user restart elephant

# Check service environment
systemctl --user show-environment | grep -E "DISPLAY|PATH|XDG_"
```

**Service Health**:
- Should be `active (running)` at all times
- Memory usage: ~30-100MB (varies with loaded providers)
- Auto-restarts on failure (RestartSec=1)

#### Troubleshooting

**Walker doesn't open when pressing Meta+D**:
```bash
# Check i3 keybinding
grep "bindsym.*walker" ~/.config/i3/config

# Try launching manually
env GDK_BACKEND=x11 walker
```

**Elephant service not running**:
```bash
# Check service status
systemctl --user status elephant

# Check DISPLAY environment
systemctl --user show-environment | grep DISPLAY

# Restart service
systemctl --user restart elephant

# If DISPLAY issue, reload i3 (imports DISPLAY)
i3-msg reload
```

**Clipboard history shows no results**:
```bash
# Test clipboard manually
echo "test" | xclip -selection clipboard
xclip -selection clipboard -o

# Restart Elephant
systemctl --user restart elephant

# Check xclip installed
which xclip
```

**File search returns no results**:
```bash
# Check file provider enabled
grep "files = true" ~/.config/walker/config.toml

# Verify file is in search scope
echo $HOME  # Should include your home directory
i3pm project current  # Check active project directory
```

### Configuration Files

**Walker Config**:
- Location: `~/.config/walker/config.toml`
- Generated by: `/etc/nixos/home-modules/desktop/walker.nix`
- DO NOT edit directly - changes will be overwritten by home-manager
- To customize: Edit walker.nix and rebuild

**Elephant Websearch Config**:
- Location: `~/.config/elephant/websearch.toml`
- Generated by: walker.nix (xdg.configFile)
- Add search engines by editing walker.nix:
  ```nix
  [[engines]]
  name = "StackOverflow"
  url = "https://stackoverflow.com/search?q=%s"
  ```

**Elephant Service**:
- Service file: `~/.config/systemd/user/elephant.service`
- Environment: DISPLAY, PATH, XDG_DATA_DIRS, XDG_RUNTIME_DIR
- Auto-generated by home-manager

### Performance Notes

| Operation | Target | Typical |
|-----------|--------|---------|
| Walker launch | <100ms | 50-80ms |
| Clipboard history | <200ms | 100-150ms |
| File search (10k files) | <500ms | 200-400ms |
| Application launch overhead | <50ms | 20-30ms |
| Elephant memory | <30MB baseline | 30-100MB active |

### Validation Status

**✅ Configuration Validated** (Feature 043 - 2025-10-27):
- All providers enabled and configured
- Elephant service running with correct environment
- DISPLAY propagation working via i3 integration
- 16 applications available in i3pm registry
- 5 search engines configured
- All provider prefixes configured (8 total)

**⏳ Interactive Testing Pending**:
- Performance measurements (timing tests)
- Clipboard history workflow
- File search behavior
- Web search URL encoding
- Calculator operator testing
- Symbol picker fuzzy search
- Shell command execution modes

**Documentation**:
- Validation report: `/etc/nixos/specs/043-get-full-functionality/VALIDATION_REPORT.md`
- Quickstart guide: `/etc/nixos/specs/043-get-full-functionality/quickstart.md`
- Data model: `/etc/nixos/specs/043-get-full-functionality/data-model.md`
- User workflows: `/etc/nixos/specs/043-get-full-functionality/contracts/user-workflows.md`

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
| `i3pm diagnose health` | - | Comprehensive daemon health check (Feature 039) |
| `i3pm diagnose window <id>` | - | Inspect window properties and identity (Feature 039) |
| `i3pm diagnose events` | - | View event history and live stream (Feature 039) |
| `i3pm diagnose validate` | - | Validate daemon state consistency (Feature 039) |
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
4. If version is old, rebuild and restart daemon: `sudo nixos-rebuild switch --flake .#hetzner`

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

## 🚀 IPC Launch Context for Multi-Instance App Tracking (Feature 041)

### Overview

Feature 041 introduces **IPC Launch Context**, a pre-notification system that solves the multi-instance application tracking problem. When you launch VS Code for "nixos" and then launch another VS Code for "stacks", each window is correctly assigned to its respective project with 100% accuracy.

**Key Innovation**: The launcher wrapper sends a notification to the daemon BEFORE the application starts, creating a "pending launch" entry. When the window appears (0.5-2s later), the daemon correlates it to the correct launch using multiple signals (application class, timing, workspace) and assigns the correct project.

**Benefits**:
- ✅ **100% accurate** project assignment for sequential launches (>2s apart)
- ✅ **95% accurate** for rapid launches (<0.5s apart) using signal-based disambiguation
- ✅ **No fallback mechanisms** - system fails explicitly rather than guessing
- ✅ **Zero configuration** - works automatically with app-launcher-wrapper.sh
- ✅ **Performance** - <10ms correlation, <100ms total latency, <5MB memory overhead

### How It Works

1. **Application Launch**:
   - User launches app via Walker, keybinding, or CLI
   - `app-launcher-wrapper.sh` intercepts the launch
   - Wrapper sends `notify_launch` to daemon via Unix socket (synchronous)
   - Daemon creates `PendingLaunch` entry with expected window class, project, workspace
   - Application executes (wrapper waits for window to appear)

2. **Window Creation**:
   - Application window appears (0.5-2s after launch)
   - Daemon receives i3 `window::new` event
   - Gets window PID using xprop, reads window class
   - Queries launch registry: `find_match(window_info)`
   - Calculates correlation confidence using signals

3. **Correlation Algorithm**:
   - **Required**: Application class match (baseline 0.5 confidence)
   - **Timing**: Time delta since launch (<1s: +0.3, <2s: +0.2, <5s: +0.1)
   - **Workspace**: Workspace match adds +0.2 boost
   - **Threshold**: Minimum 0.6 (MEDIUM) confidence required
   - **First-match-wins**: If multiple pending launches, select highest confidence

4. **Project Assignment**:
   - If confidence >= 0.6: Assign project to window, mark launch as matched
   - If confidence < 0.6: Reject match, log error (explicit failure)
   - Pending launches expire after 5 seconds (±0.5s accuracy)

### CLI Commands

**Query launch registry stats**:
```bash
# View launch correlation metrics
i3pm daemon status

# Output includes:
# Launch Registry (Feature 041):
# Pending:         3 (2 unmatched)
# Notifications:   127
# Matched:         120 (94.5%)
# Expired:         5 (3.9%)
# Failed:          2
```

**Debug pending launches**:
```bash
# List current pending launches
# Note: This command needs to be added or use daemon events
i3pm daemon events --type=launch --limit=10

# View window correlation info
i3pm diagnose window <window_id>
# Shows: matched_via_launch, launch_id, confidence, signals_used
```

### Troubleshooting

**Window assigned to wrong project**:
```bash
# Check correlation details
i3pm diagnose window <window_id>

# Look for:
# - matched_via_launch: true/false
# - confidence: <score>
# - signals_used: {class_match, time_delta, workspace_match}

# If confidence is low (<0.6), check:
# 1. Expected window class matches actual class
# 2. Window appeared within 5 seconds of launch
# 3. Workspace configuration is correct
```

**Launch notification not received**:
```bash
# Check daemon is running
i3pm daemon status

# Check app-launcher-wrapper is being used
which app-launcher-wrapper.sh

# Check daemon events for launch notifications
i3pm daemon events --limit=20 | grep notify_launch

# If no notifications, check launcher is sending them:
tail -f ~/.local/state/app-launcher.log
```

**Rapid launches mismatching** (e.g., VS Code for "nixos" and "stacks" 0.2s apart):
```bash
# Expected: 95% accuracy with MEDIUM confidence (0.6+)
# Check timing and workspace signals are being used

# View correlation for both windows
i3pm diagnose window <window1_id>
i3pm diagnose window <window2_id>

# Verify:
# - Different workspace_numbers provide disambiguation
# - Time deltas are distinct (e.g., 0.7s vs 0.9s)
# - Both have HIGH confidence (0.8+) if possible
```

**Pending launch expired** (window appeared after 5 seconds):
```bash
# Check for expired launches
i3pm daemon status
# Look at "Expired: <count>" in launch registry stats

# Common causes:
# - Application slow to start (system under load)
# - Window class mismatch (wrong expected_class in registry)
# - Application crashed before creating window

# Check daemon logs
journalctl --user -u i3-project-event-listener -n 50 | grep expired
```

**Window appeared without matching launch**:
```bash
# Check window was launched via app-launcher-wrapper
# If launched directly from terminal, no notification sent

# Verify daemon received notification
i3pm daemon events --limit=50 | grep <app_name>

# If notification sent but no match:
# - Check window class matches expected_class
# - Verify window appeared within 5 seconds
# - Check for correlation errors in daemon logs
journalctl --user -u i3-project-event-listener -n 100 | grep correlation
```

### Configuration

**No configuration required** - the system uses:
- Application registry (`~/.config/i3/application-registry.json`)
- Expected window class from registry (`expected_class` field)
- Active project context from daemon

**Customization** (if needed):
```bash
# Adjust timeout (default: 5 seconds)
# Edit launch_registry.py:
# self.timeout = 5.0  # Increase if apps are slow to start

# Adjust confidence threshold (default: 0.6 MEDIUM)
# Edit window_correlator.py:
# CONFIDENCE_THRESHOLD = 0.6  # Raise for stricter matching
```

### Success Criteria Validation

From Feature 041 specification:

- **SC-001**: Sequential launches (>2s) → 100% accuracy with HIGH confidence (0.8+) ✓
- **SC-002**: Rapid launches (<0.5s) → 95% accuracy with MEDIUM+ confidence (0.6+) ✓
- **SC-003**: Correlation latency → <100ms for 95% of launches ✓
- **SC-005**: Timeout accuracy → 5±0.5s with 100% accuracy ✓
- **SC-009**: Pure IPC (no fallback) → 100% ✓
- **SC-010**: Edge case coverage → 100% ✓

### Technical Details

**IPC Endpoints** (JSON-RPC over Unix socket):
- `notify_launch`: Launcher wrapper → Daemon (before app execution)
- `get_launch_stats`: CLI → Daemon (query correlation metrics)
- `get_pending_launches`: CLI → Daemon (debug pending launches)
- `get_window_state`: Extended with correlation info (if matched via launch)

**Data Models** (Pydantic):
- `PendingLaunch`: app_name, project_name, expected_class, timestamp, workspace_number
- `LaunchWindowInfo`: window_id, window_class, window_pid, workspace_number, timestamp
- `CorrelationResult`: confidence, signals_used, matched_launch

**Performance Characteristics**:
- notify_launch: 2-3ms (Unix socket + in-memory insertion)
- find_match: 5-10ms (iterate pending launches, calculate confidence)
- Total latency: <100ms (notification + window event + correlation + project assignment)
- Memory: <200 bytes per pending launch, <5MB total overhead

For complete technical documentation, see:
- Specification: `/etc/nixos/specs/041-ipc-launch-context/spec.md`
- API contracts: `/etc/nixos/specs/041-ipc-launch-context/contracts/ipc-endpoints.md`
- Quickstart guide: `/etc/nixos/specs/041-ipc-launch-context/quickstart.md`

## 📦 Registry-Centric Architecture (Feature 035)

### Overview

Feature 035 introduces a **registry-centric** approach that replaces the old tag-based system with **environment variable-based filtering**. This provides a simpler, more powerful architecture for project-scoped window management.

### Key Concepts

**Application Registry** (`app-registry.nix`):
- Single source of truth for all applications
- Defines application metadata: name, command, scope, workspace
- Auto-generates desktop files for launchers
- Auto-generates i3 window rules for global apps

**Environment Variable Injection**:
- All applications launched via `app-launcher` receive `I3PM_*` environment variables
- Variables persist in `/proc/<pid>/environ` and are read by the daemon
- Enables deterministic window-to-project association
- No configuration needed - automatic based on active project

**I3PM Environment Variables**:
```bash
I3PM_APP_ID             # Unique instance ID: ${app}-${project}-${pid}-${timestamp}
I3PM_APP_NAME           # Registry application name (e.g., "vscode", "terminal")
I3PM_PROJECT_NAME       # Active project name (e.g., "nixos", "stacks", or empty)
I3PM_PROJECT_DIR        # Project directory path
I3PM_PROJECT_DISPLAY_NAME  # Human-readable project name
I3PM_PROJECT_ICON       # Project icon emoji
I3PM_SCOPE              # Application scope: "scoped" or "global"
I3PM_ACTIVE             # "true" if project active, "false" otherwise
I3PM_LAUNCH_TIME        # Unix timestamp of launch
I3PM_LAUNCHER_PID       # Wrapper script PID
```

**Window Filtering**:
- Daemon reads `/proc/<pid>/environ` for each window
- Extracts `I3PM_PROJECT_NAME` to determine window ownership
- Automatically shows/hides windows when switching projects
- No manual configuration or tagging required

### CLI Commands

**Application Management**:
```bash
# List all registered applications
i3pm apps list
i3pm apps list --scope=scoped   # Filter by scope
i3pm apps list --workspace=3    # Filter by workspace

# Show application details
i3pm apps show vscode
i3pm apps show terminal --json  # JSON output for scripting
```

**Project Management**:
```bash
# Create new project
i3pm project create mynewproject \
  --directory ~/projects/mynewproject \
  --display-name "My New Project" \
  --icon "🚀"

# List projects
i3pm project list
i3pm project list --json

# Show project details
i3pm project show nixos
i3pm project current    # Show active project

# Switch projects
i3pm project switch nixos
pswitch nixos  # Shell alias

# Update project
i3pm project update nixos --icon "💻"

# Delete project (with confirmation)
i3pm project delete oldproject
```

**Layout Management** (NEW in Feature 035):
```bash
# Save current window layout for a project
i3pm layout save nixos
i3pm layout save nixos custom-layout  # Named layout
i3pm layout save nixos --overwrite    # Overwrite existing

# Restore saved layout
i3pm layout restore nixos              # Uses project's saved layout
i3pm layout restore nixos custom-layout  # Restore specific layout
i3pm layout restore nixos --dry-run    # Preview without launching

# Delete layout
i3pm layout delete nixos
i3pm layout delete nixos custom-layout

# List all saved layouts
i3pm layout list
i3pm layout list --json
```

**Daemon Monitoring**:
```bash
# Check daemon status
i3pm daemon status
i3pm daemon status --json

# View daemon events
i3pm daemon events --limit=50
i3pm daemon events --type=window  # Filter by event type
i3pm daemon events --follow       # Real-time stream

# Quick ping
i3pm daemon ping
```

### Application Registry Structure

Located at: `home-modules/desktop/app-registry.nix`

```nix
{
  name = "vscode";                  # Unique identifier (used in CLI commands)
  display_name = "VS Code";         # Human-readable name
  command = "code";                 # Command to execute
  scope = "scoped";                 # "scoped" or "global"
  preferred_workspace = 2;          # Workspace assignment
  expected_class = "Code";          # Window class for matching

  # Optional fields:
  fallback_behavior = "skip";       # "skip", "use_home", or "error"
  multi_instance = true;            # Allow multiple instances
  expected_title_contains = "Code"; # Title matching fallback

  # Variable substitution in parameters:
  # $PROJECT_DIR → replaced with project directory
  # Example: parameters = "$PROJECT_DIR";
}
```

### How It Works

1. **Application Launch**:
   - User launches app via Walker, keybinding, or CLI
   - `app-launcher-wrapper.sh` intercepts the launch
   - Wrapper queries daemon for active project
   - Injects `I3PM_*` environment variables
   - Launches application (variables persist in /proc)

2. **Window Creation**:
   - Daemon receives i3 window::new event
   - Gets window PID using xprop
   - Reads `/proc/<pid>/environ` for `I3PM_*` variables
   - Extracts `I3PM_PROJECT_NAME` and `I3PM_APP_ID`
   - Applies project mark and workspace assignment

3. **Project Switch**:
   - User switches project via CLI or keybinding
   - Daemon receives tick event
   - Scans all windows, reading `/proc/<pid>/environ` for each
   - Compares `I3PM_PROJECT_NAME` to new active project
   - Moves non-matching scoped windows to scratchpad (hidden)
   - Keeps matching and global windows visible

4. **Layout Save/Restore**:
   - **Save**: Captures i3 tree, reads `/proc` for each window, records `I3PM_APP_ID` and geometry
   - **Restore**: Closes existing project windows, launches apps with `I3PM_APP_ID_OVERRIDE`, positions windows

### Benefits Over Tag-Based System

**Simplicity**:
- ✅ No manual tag configuration needed
- ✅ No XDG isolation required
- ✅ No application-to-tag mappings
- ✅ Environment variables provide context automatically

**Reliability**:
- ✅ Deterministic window matching via unique instance IDs
- ✅ Process environment persists for window lifetime
- ✅ No race conditions or timing issues
- ✅ Handles multiple instances of same app correctly

**Visibility**:
- ✅ Check environment: `cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM_`
- ✅ Monitor launches: `tail -f ~/.local/share/app-launcher/launcher.log`
- ✅ Daemon events: `i3pm daemon events --follow`

### Configuration Files

```
~/.config/i3/
├── application-registry.json   # Runtime registry (generated from app-registry.nix)
├── projects/                   # Project definitions
│   ├── nixos.json
│   ├── stacks.json
│   └── personal.json
├── layouts/                    # Saved layouts (Feature 035)
│   ├── nixos.json              # Default layout for nixos project
│   └── nixos-custom.json       # Named layout
├── active-project.json         # Current active project
└── window-rules-generated.conf # Auto-generated i3 rules (Feature 035)
```

### Debugging

**Check application environment**:
```bash
# Find PID of window
xprop _NET_WM_PID | awk '{print $3}'

# View environment variables
cat /proc/<pid>/environ | tr '\0' '\n' | grep I3PM_
```

**Monitor application launches**:
```bash
tail -f ~/.local/state/app-launcher.log
```

**Test window filtering**:
```bash
# Launch app in project
pswitch nixos
~/.local/bin/app-launcher-wrapper.sh vscode

# Verify environment
# (Find PID, check /proc/<pid>/environ for I3PM_PROJECT_NAME=nixos)

# Switch to different project
pswitch stacks

# Verify window hidden
i3pm windows | grep Code  # Should not appear
```

**Validate registry**:
```bash
# Check registry loaded correctly
i3pm apps list
i3pm apps show vscode --json | jq .

# Verify daemon can read registry
i3pm daemon status | grep -i registry
```

For complete documentation, see:
```bash
cat /etc/nixos/specs/035-now-that-we/quickstart.md
cat /etc/nixos/specs/035-now-that-we/data-model.md
cat /etc/nixos/specs/035-now-that-we/contracts/cli-commands.md
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

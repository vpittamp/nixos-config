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

### Flake Organization (2025-11 Refactor)

- `flake.nix` - Main entry point (110 lines, uses flake-parts)
- `lib/` - Common helper functions
  - `helpers.nix` - Reusable functions for system/home configs
- `nixos/` - NixOS system configurations
  - `default.nix` - System definitions (hetzner-sway, m1)
- `home/` - Standalone Home Manager configs (macOS only)
  - `default.nix` - Darwin home configuration
- `packages/` - Container and VM image builds
- `checks/` - Flake test checks
- `devshells/` - Development shell environments

### System Configuration

- `configurations/` - Target configs (hetzner-sway, m1, container)
- `hardware/` - Hardware-specific settings
- `modules/` - Reusable system modules
- `home-modules/` - User environment (editors, shell, terminal, tools)
- `docs/` - Detailed documentation

**See `FLAKE_REFACTOR_GUIDE.md` for migration details**

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

Centralized theming with Catppuccin Mocha across top bar (Eww), bottom bar (Eww), and notification center (SwayNC).

**Theme**: `~/.config/sway/appearance.json` (hot-reloadable)

**Commands**:
```bash
swaymsg reload                             # Reload appearance
systemctl --user restart eww-top-bar       # Top bar (Feature 060)
systemctl --user restart sway-workspace-panel  # Bottom bar
systemctl --user restart swaync            # Notification center
```

**Docs**: `/etc/nixos/specs/057-unified-bar-system/quickstart.md`

### Eww Top Bar (Feature 060)

Eww-based top bar with system metrics (CPU, memory, disk, network, temperature, date/time).

**Enable**:
```nix
# File: /etc/nixos/home-vpittamp.nix
programs.eww-top-bar.enable = true;
```

**Commands**:
```bash
systemctl --user {status|restart|stop} eww-top-bar
journalctl --user -u eww-top-bar -f        # Follow logs
```

**Metrics**:
- CPU: Load average (2s update)
- Memory: Used/Total GB and percentage (2s update)
- Disk: Used/Total GB and percentage (2s update)
- Network: RX/TX Mbps (2s update)
- Temperature: Average thermal zone temp (2s update)
- Date/Time: Full date and time (1s update)

**Multi-Monitor**: Auto-detects outputs (eDP-1/HDMI-A-1 on M1, HEADLESS-1/2/3 on Hetzner)

**Hardware Auto-Detection**: Battery, bluetooth, thermal sensors (shows only if available)

**Docs**: `/etc/nixos/specs/060-eww-top-bar/quickstart.md`

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

### Workspace Allocation

**Regular Applications** (1-50):
- Standard apps use workspaces 1-50
- Typical allocation: Core apps on 1-9, utilities on 10+
- Hard limit: 50 (enforced by validation)

**PWAs** (50+):
- PWAs use workspaces 50 and above
- No upper bound (can use 50, 51, 52, ..., 100+)
- Typical range: 50-70 for common PWAs
- Example: YouTube (50), Claude (52), GitHub (54), Gmail (56)

**Rationale**: This separation prevents conflicts between regular apps and PWAs, allowing unlimited PWA expansion while keeping core apps in the 1-50 range.

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

### Enhanced Project Selection (Feature 078)

**Status**: MVP IMPLEMENTED (User Story 1)

Fast project switching with fuzzy search and visual feedback.

**Usage**:
1. Enter workspace mode (`CapsLock` on M1, `Ctrl+0` on Hetzner)
2. Type `:` to enter project selection mode
3. Type filter characters (e.g., `nix`, `078`, `dapr`)
4. Press Enter to switch to highlighted project
5. Press Escape to cancel

**Features**:
- Priority-based fuzzy matching (exact > prefix > substring)
- Full scrollable project list with icons
- Real-time filtering (<50ms response)
- Visual selection highlighting
- "No matching projects" empty state

**Technical Details**:
- Python daemon: `home-modules/desktop/i3-project-event-daemon/workspace_mode.py`
- Fuzzy matching: `home-modules/desktop/i3-project-event-daemon/project_filter_service.py`
- Pydantic models: `home-modules/desktop/i3-project-event-daemon/models/project_filter.py`
- Eww widget: `home-modules/desktop/eww-workspace-bar.nix` (project_list widget)
- Workspace preview daemon: `home-modules/tools/sway-workspace-panel/workspace-preview-daemon`

**Tests**: `tests/078-eww-preview-improvement/` (48 tests covering fuzzy matching, rendering, workflow)

**Docs**: `/etc/nixos/specs/078-eww-preview-improvement/quickstart.md`

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

**Single Source of Truth**: `i3-project-event-daemon` owns all workspace-to-monitor assignments. It respects `~/.config/sway/output-states.json` for headless output toggling. The `sway-config-manager` daemon handles only window rules and appearance.

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

## 💾 Session Management (Feature 074)

**⚠️ BREAKING CHANGE**: Old layouts incompatible. Re-save all layouts after upgrade.

Save and restore workspace layouts with terminal working directories and focused states.

### Quick Commands

```bash
i3pm layout save my-layout        # Save current layout
i3pm layout restore my-layout     # Restore saved layout
i3pm layout list                  # List saved layouts
i3pm layout delete old-layout     # Delete layout
```

### Features

✅ **Workspace Focus Restoration**: Automatically returns to focused workspace per project
✅ **Terminal Working Directory**: Terminals reopen in original directories (not `$HOME`)
✅ **Sway Compatible**: Mark-based window correlation (replaces broken i3 swallow)
✅ **AppLauncher Integration**: Wrapper-based restoration with `I3PM_*` environment variables

### Migration Required

Old layout format (before Feature 074) is **incompatible**:

```bash
# 1. Switch to each project and re-save layouts
pswitch nixos && i3pm layout save main
pswitch dotfiles && i3pm layout save main

# 2. Verify new format (should have focused_workspace, cwd, etc.)
cat ~/.local/share/i3pm/layouts/*/main.json | jq .

# 3. Clean up old incompatible layouts
find ~/.local/share/i3pm/layouts -name "*.json" -mtime +7 -delete
```

**Error if old layout detected**:
```
Layout 'old-layout' is incompatible (missing required fields: focused_workspace, cwd).
Migration required: Re-save your layouts with: i3pm layout save <name>
```

**Docs**: `/etc/nixos/specs/074-session-management/quickstart.md`

## 🏷️ Mark-Based App Identification (Feature 076)

**Status**: ✅ IMPLEMENTED (2025-11-14)

Deterministic app identification using Sway marks for idempotent layout restoration.

### Key Features

✅ **Idempotent Restore**: Multiple restores won't create duplicate windows
✅ **Automatic Mark Injection**: Marks injected on window launch (via `window::new` handler)
✅ **Persistent Metadata**: Marks stored in layout files as structured JSON
✅ **Automatic Cleanup**: Marks removed on window close (zero pollution)
✅ **Backward Compatible**: Old layouts without marks still work

### Mark Format

```bash
# Marks injected automatically on app launch:
i3pm_app:terminal       # App registry name
i3pm_project:nixos      # Project scope
i3pm_ws:1               # Workspace number (1-70)
i3pm_scope:scoped       # Scope classification
i3pm_custom:key:value   # Extensible custom metadata
```

### How It Works

```bash
# 1. Launch app (marks injected automatically)
i3pm app launch terminal
# → Marks: i3pm_app:terminal, i3pm_project:nixos, i3pm_ws:1, i3pm_scope:scoped

# 2. Save layout (marks persisted automatically)
i3pm layout save my-layout
# → Layout file contains marks_metadata for all windows

# 3. Restore layout (idempotent - no duplicates)
i3pm layout restore nixos my-layout
# → Existing windows detected by marks, skipped
# → Only missing windows launched
```

### Querying Windows by Marks

```bash
# View all i3pm marks on current windows
swaymsg -t get_marks | grep i3pm_

# Check marks on specific window
swaymsg -t get_tree | jq '..|select(.focused?==true)|.marks'
```

### Debugging

```bash
# Enable mark-related logging
journalctl --user -u i3-project-event-listener -f | grep "Feature 076"

# Verify mark injection on window launch
# Verify mark cleanup on window close
# Verify idempotent restore (no duplicates)
```

**Docs**: `/etc/nixos/specs/076-mark-based-app-identification/quickstart.md`

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

## 📺 Multi-Monitor Window Management (Feature 083)

Event-driven monitor profile system with <100ms top bar updates.

### Quick Commands

```bash
# Switch profiles
set-monitor-profile single   # Single monitor (H1 only)
set-monitor-profile dual     # Dual monitors (H1 + H2)
set-monitor-profile triple   # All three monitors

# Check status
cat ~/.config/sway/monitor-profile.current
cat ~/.config/sway/output-states.json | jq .
```

### Top Bar Integration

The Eww top bar displays:
- **Profile Name**: Current profile (single/dual/triple) in teal pill
- **Output Indicators**: H1/H2/H3 toggle buttons

Updates occur within 100ms of profile switch (event-driven, not polled).

### Architecture

```
set-monitor-profile.sh → monitor-profile.current
                              ↓
                    MonitorProfileWatcher (daemon)
                              ↓
                    MonitorProfileService.handle_profile_change()
                              ↓
              ┌───────────────┼───────────────┐
              ↓               ↓               ↓
    output-states.json   ProfileEvents   EwwPublisher
                                              ↓
                                      eww update monitor_state
```

### Troubleshooting

```bash
# Check daemon logs for profile events
journalctl --user -u i3-project-event-listener -f | grep "Feature 083"

# Restart services if top bar not updating
systemctl --user restart i3-project-event-listener eww-top-bar
```

**Docs**: `/etc/nixos/specs/083-multi-monitor-window-management/quickstart.md`

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
- **Feature 079**: Preview pane UX enhancements - branch number display, worktree hierarchy, space-to-hyphen matching. See `/etc/nixos/specs/079-preview-pane-user-experience/`
- **Feature 078**: Enhanced project selection with fuzzy search and visual feedback. See `/etc/nixos/specs/078-eww-preview-improvement/`
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
- Python 3.11+ (existing daemon standard per Constitution Principle X) (074-session-management)
- JSON layout files in `~/.local/share/i3pm/layouts/<project>/<name>.json` (076-mark-based-app-identification)
- Python 3.11+ (i3pm daemon, workspace-preview-daemon), Nix (Eww widget generation) + i3ipc.aio, Pydantic, Eww (GTK widgets), asyncio (078-eww-preview-improvement)
- JSON project files (`~/.config/i3/projects/*.json`), in-memory daemon state (078-eww-preview-improvement)
- Python 3.11+ (i3-project-event-daemon), TypeScript/Deno 1.40+ (i3pm CLI), Nix (Eww widget generation) + i3ipc.aio (Sway IPC), Pydantic (data models), Eww (GTK widgets), asyncio (event handling), SwayNC (notifications) (079-preview-pane-user-experience)
- JSON project files (`~/.config/i3/projects/`), in-memory daemon state (079-preview-pane-user-experience)
- Python 3.11+ (daemon), Bash (profile scripts), Yuck/GTK (Eww widgets) + i3ipc.aio (Sway IPC), asyncio (event handling), Eww (top bar), systemd (service management) (083-multi-monitor-window-management)
- JSON files (~/.config/sway/output-states.json, monitor-profile.current, monitor-profiles/*.json) (083-multi-monitor-window-management)

## Recent Changes
- 079-preview-pane-user-experience: Enhanced project list with branch numbers ("079 - Display Name"), worktree hierarchy with indentation, space-to-hyphen filter matching, top bar peach accent styling, `i3pm worktree list` CLI command
- 078-eww-preview-improvement: Added enhanced project selection with fuzzy matching, Pydantic models, Eww project list widget (MVP complete)
- 074-session-management: Added Python 3.11+ (existing daemon standard per Constitution Principle X)

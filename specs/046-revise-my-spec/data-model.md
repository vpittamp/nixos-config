# Data Model: Hetzner Cloud Sway Configuration with Headless Wayland

**Feature**: Feature 046 - Hetzner Cloud Sway with Headless Wayland
**Created**: 2025-10-28
**Status**: Planning Phase

## Overview

This document defines the key entities, relationships, and state transitions for running Sway in headless mode on Hetzner Cloud VM with VNC remote access and i3pm daemon integration.

## Core Entities

### 1. Headless Sway Session

**Description**: Wayland compositor instance running with headless backend (no physical displays), creating virtual outputs with in-memory framebuffers.

**Attributes**:
- `session_id` (string): Unique session identifier (systemd unit instance)
- `backend` (string): Always "headless" (from WLR_BACKENDS)
- `renderer` (string): "pixman" (CPU-based software rendering)
- `socket_path` (string): IPC socket path (SWAYSOCK environment variable)
- `virtual_outputs` (array[VirtualOutput]): List of virtual display outputs
- `state` (enum): [starting, running, stopping, crashed]
- `pid` (integer): Sway compositor process ID
- `start_time` (timestamp): Session start time

**Relationships**:
- Has many VirtualOutput instances
- Provides IPC socket for i3pm daemon connection
- Hosts wayvnc server instance
- Manages Window instances via Sway IPC

**State Transitions**:
```
[systemd activation] → starting → running
running → [manual stop] → stopping → [terminated]
running → [crash/error] → crashed → [restart] → starting
```

**Functional Requirements**: FR-001, FR-002, FR-004, FR-005, FR-006, FR-013

---

### 2. Virtual Output

**Description**: In-memory framebuffer representing a headless display with configurable resolution and position.

**Attributes**:
- `name` (string): Output identifier (e.g., "HEADLESS-1", "HEADLESS-2")
- `width` (integer): Horizontal resolution in pixels (default: 1920)
- `height` (integer): Vertical resolution in pixels (default: 1080)
- `scale` (float): HiDPI scaling factor (default: 1.0)
- `position` (object): {x: integer, y: integer} - Position in compositor layout
- `refresh_rate` (integer): Refresh rate in Hz (default: 60)
- `workspaces` (array[integer]): Workspace numbers assigned to this output
- `active` (boolean): Whether output is currently active

**Relationships**:
- Belongs to HeadlessSway session
- Contains Workspace instances
- Exposed via wayvnc for remote access

**State Transitions**:
```
[configuration] → inactive → [Sway init] → active
active → [output disable] → inactive
```

**Functional Requirements**: FR-003, FR-029, FR-030

---

### 3. wayvnc Configuration

**Description**: VNC server settings for providing remote access to headless Sway session.

**Attributes**:
- `address` (string): Listen address (default: "0.0.0.0")
- `port` (integer): Listen port (default: 5900)
- `output` (string): Virtual output to expose (e.g., "HEADLESS-1")
- `enable_auth` (boolean): PAM authentication enabled (default: true)
- `config_path` (string): Path to wayvnc config file (~/.config/wayvnc/config)
- `service_state` (enum): [stopped, starting, running, failed]

**Relationships**:
- Connects to HeadlessSway session via Wayland socket
- Exposes VirtualOutput framebuffer to VNC clients
- Depends on HeadlessSway being in "running" state

**State Transitions**:
```
[systemd activation] → starting → [connect to Sway] → running
running → [Sway crash] → failed → [restart] → starting
running → [manual stop] → stopped
```

**Functional Requirements**: FR-007, FR-008, FR-009, FR-010, FR-011, FR-012

**Configuration Schema** (TOML):
```toml
address=0.0.0.0
port=5900
enable_auth=true
username=vpittamp
# Output selection (auto-detects if only one output)
# output=HEADLESS-1
```

---

### 4. hetzner-sway NixOS Configuration

**Description**: NixOS flake output defining the complete system configuration for headless Sway on Hetzner Cloud VM.

**Attributes**:
- `name` (string): "hetzner-sway"
- `imports` (array[path]): List of imported NixOS modules
  - `configurations/base.nix` (shared base)
  - `hardware/hetzner.nix` (virtual hardware)
  - `modules/desktop/sway.nix` (Sway compositor)
  - `modules/desktop/wayvnc.nix` (VNC server)
  - `modules/services/development.nix` (dev tools)
  - `home-modules/desktop/sway.nix` (home-manager config)
- `environment_variables` (object): Headless-specific env vars
  - `WLR_BACKENDS`: "headless"
  - `WLR_LIBINPUT_NO_DEVICES`: "1"
  - `WLR_RENDERER`: "pixman"
  - (plus all Wayland app support vars from base sway.nix)
- `services` (object): Systemd services configuration
  - `greetd`: Display manager for headless login
  - `wayvnc`: VNC server user service

**Relationships**:
- Parallel to `hetzner` and `m1` configurations in flake
- Imports sway.nix (NOT i3wm.nix)
- Shares application registry and project configurations with other configs

**State Transitions**:
```
[flake evaluation] → [nixos-rebuild build] → [system closure] → [activation] → running
```

**Functional Requirements**: FR-023, FR-024, FR-025, FR-026, FR-027, FR-028

**Configuration Structure**:
```nix
{
  nixosConfigurations.hetzner-sway = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./configurations/hetzner-sway.nix
      home-manager.nixosModules.home-manager
      {
        home-manager.users.vpittamp = import ./home-modules/hetzner-sway.nix;
      }
    ];
  };
}
```

---

### 5. Project Context

**Description**: Active project state managed by i3pm daemon, identical to M1 and Hetzner i3 implementations.

**Attributes**:
- `name` (string): Project identifier (e.g., "nixos", "stacks", "personal")
- `directory` (path): Project root directory
- `display_name` (string): Human-readable project name
- `icon` (string): Unicode emoji icon
- `active` (boolean): Whether project is currently active
- `created_at` (timestamp): Project creation time
- `config_path` (path): Path to project JSON config (~/.config/i3/projects/{name}.json)

**Relationships**:
- Has many Window instances (via project marks)
- Tracked by i3pm daemon
- Persisted in JSON config files

**State Transitions**:
```
[inactive] → [user switches project] → active
active → [user switches to different project] → inactive
active → [user clears project] → inactive
```

**Storage Schema** (JSON):
```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS Configuration",
  "icon": "❄️",
  "created_at": "2025-10-28T10:00:00Z"
}
```

**Active Project Tracking** (`~/.config/i3/active-project.json`):
```json
{
  "project_name": "nixos",
  "project_dir": "/etc/nixos",
  "switched_at": "2025-10-28T14:30:00Z"
}
```

**Functional Requirements**: FR-013, FR-014, FR-015, FR-016, FR-017, FR-018

---

### 6. Window Marks

**Description**: Sway window marks storing project associations and window metadata, using identical syntax to i3.

**Attributes**:
- `mark_string` (string): Full mark value (format: "project:{PROJECT_NAME}:{WINDOW_ID}")
- `project_name` (string): Associated project name
- `window_id` (integer): Unique window identifier
- `window_class` (string): Window class or app_id (Wayland)
- `workspace_number` (integer): Current workspace number
- `floating` (boolean): Whether window is floating
- `geometry` (object): {x, y, width, height} for floating windows
- `scratchpad_origin` (boolean): True if manually placed in scratchpad

**Relationships**:
- Belongs to Window instance
- References ProjectContext via project_name
- Persisted in window-workspace-map.json

**State Transitions**:
```
[window creation] → [daemon marks window] → marked
marked → [project switch & window hidden] → marked + scratchpad
marked + scratchpad → [project switch back] → marked + visible
```

**Persistence Schema** (`~/.config/i3/window-workspace-map.json`):
```json
{
  "version": "1.1",
  "windows": {
    "94532735639728": {
      "workspace_number": 2,
      "project_name": "nixos",
      "app_name": "vscode",
      "window_class": "Code",
      "floating": false,
      "geometry": null,
      "scratchpad_origin": false,
      "last_seen": "2025-10-28T14:35:00Z"
    }
  }
}
```

**Functional Requirements**: FR-017, FR-018, SC-002, SC-003, SC-006

---

## Entity Relationships Diagram

```
┌─────────────────────────────┐
│  HeadlessSway Session       │
│  - socket_path              │
│  - backend: "headless"      │
│  - state: running           │
└─────────────┬───────────────┘
              │
              │ manages
              ▼
      ┌───────────────────┐
      │  VirtualOutput    │◄─────┐
      │  - name           │      │
      │  - resolution     │      │ exposes
      │  - workspaces[]   │      │
      └───────────────────┘      │
                                 │
┌────────────────────────────┐  │
│  wayvnc Configuration      │  │
│  - port: 5900              │──┘
│  - enable_auth: true       │
│  - service_state: running  │
└────────────────────────────┘

┌────────────────────────────┐
│  hetzner-sway NixOS Config │
│  - imports: [sway.nix]     │
│  - env: WLR_BACKENDS=...   │
└────────────────────────────┘


┌─────────────────────────────┐
│  i3pm Daemon                │
│  - connects via SWAYSOCK    │
└─────────────┬───────────────┘
              │
              │ subscribes to
              ▼
      ┌───────────────────┐
      │  Sway IPC Events  │
      │  - window::new    │
      │  - workspace      │
      │  - output         │
      └───────────────────┘

┌─────────────────────────────┐       ┌─────────────────────────────┐
│  ProjectContext             │       │  Window Marks               │
│  - name: "nixos"            │◄──────┤  - mark: "project:nixos:ID" │
│  - directory: "/etc/nixos"  │       │  - workspace_number: 2      │
│  - active: true             │       │  - floating: false          │
└─────────────────────────────┘       └─────────────────────────────┘
```

## Key Data Flows

### 1. Headless Session Startup

```
[greetd login]
  → Start Sway with WLR_BACKENDS=headless
  → Sway creates virtual output (HEADLESS-1)
  → Sets SWAYSOCK=/run/user/1000/sway-ipc.sock
  → wayvnc systemd service starts (After=sway-session.target)
  → wayvnc connects to Sway socket
  → wayvnc listens on port 5900
  → i3pm daemon starts
  → Daemon connects to SWAYSOCK
  → Daemon subscribes to events (window, workspace, output, tick)
  → [Ready for VNC connection]
```

### 2. Window Creation with Project Association

```
[User launches VS Code via Walker]
  → app-launcher-wrapper.sh injects I3PM_PROJECT_NAME=nixos
  → VS Code starts with environment variables
  → Sway emits window::new event
  → i3pm daemon receives event
  → Daemon reads /proc/<pid>/environ for I3PM_PROJECT_NAME
  → Daemon applies mark: "project:nixos:94532735639728"
  → Daemon moves window to workspace 2 (from registry)
  → Daemon persists to window-workspace-map.json
  → [Window visible on workspace 2 via VNC]
```

### 3. Project Switch with Window Filtering

```
[User switches from "nixos" to "stacks"]
  → i3pm project switch stacks
  → Updates active-project.json
  → Sends tick event to Sway
  → Daemon receives tick event
  → Reads all window marks: ["project:nixos:ID1", "project:stacks:ID2"]
  → Filters windows: stacks windows match, nixos windows don't
  → Moves nixos windows to scratchpad (hidden)
  → Keeps stacks windows visible
  → Updates i3bar with new project context
  → [Only stacks windows visible via VNC]
```

### 4. VNC Remote Access

```
[Remote client connects to port 5900]
  → wayvnc receives connection
  → PAM authentication prompt
  → User enters credentials
  → wayvnc queries Sway for framebuffer (HEADLESS-1)
  → Streams framebuffer to VNC client
  → [Client sees Sway desktop]

[User presses Meta+Return in VNC client]
  → VNC sends keyboard event to wayvnc
  → wayvnc injects into Wayland compositor
  → Sway processes keybinding
  → Launches Ghostty terminal
  → [New window appears in VNC session]
```

### 5. Multi-Monitor Workspace Distribution (Virtual Outputs)

```
[System configured with 2 virtual outputs]
  → Sway creates HEADLESS-1 (1920x1080)
  → Sway creates HEADLESS-2 (1920x1080)
  → i3pm daemon receives output events
  → Reads workspace-monitor-mapping.json
  → Assigns workspaces 1-2 to HEADLESS-1
  → Assigns workspaces 3-70 to HEADLESS-2
  → i3pm monitors status shows distribution
  → [wayvnc can switch between outputs if configured]
```

## State Persistence

### Local Storage (Hetzner VM)

**Location**: `~/.config/i3/`

| File | Content | Update Trigger |
|------|---------|----------------|
| `active-project.json` | Current active project | Project switch command |
| `window-workspace-map.json` | Window-workspace associations | Window events, project switches |
| `projects/*.json` | Project definitions | Project create/update commands |
| `workspace-monitor-mapping.json` | Workspace distribution config | Manual edit + reload |

### Volatile State (In-Memory)

| State | Location | Lifetime |
|-------|----------|----------|
| Sway IPC socket | `/run/user/1000/sway-ipc.sock` | Sway session |
| wayvnc socket | Wayland socket | wayvnc service |
| i3pm daemon JSON-RPC | `/run/user/1000/i3pm-daemon.sock` | Daemon process |
| Window marks | Sway internal state | Until window closed |
| Virtual output framebuffers | System memory (EGL) | Sway session |

## Performance Characteristics

### Latency Targets (from Success Criteria)

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Daemon IPC connection | <2s | From session start to connected |
| Window event processing | <100ms | Event received → mark applied |
| Project switch | <500ms | Command → windows hidden/shown |
| Window creation (VNC) | <500ms | Launch → visible in VNC |
| Workspace switch (VNC) | <200ms | Keybind → VNC display updates |
| Keyboard latency (VNC) | <100ms | Key press → application receives |

### Resource Constraints

| Component | Memory | CPU |
|-----------|--------|-----|
| Headless Sway | ~50MB | <5% idle, <20% active |
| wayvnc | <50MB | <5% idle, <10% streaming |
| i3pm daemon | <15MB | <1% idle, <5% event processing |
| Virtual output framebuffer | ~7.9MB per output (1920×1080×4 bytes) | - |

## Validation Queries

### Check Headless Session Running

```bash
# Verify Sway process with headless backend
ps aux | grep sway
echo $SWAYSOCK  # Should be /run/user/1000/sway-ipc.sock
swaymsg -t get_outputs | jq '.[] | {name, make, model}'
# Should show: {"name": "HEADLESS-1", "make": "headless", "model": "headless"}
```

### Check wayvnc Configuration

```bash
systemctl --user status wayvnc
# Should be active (running)

cat ~/.config/wayvnc/config
# Should show port=5900, enable_auth=true

netstat -tlnp | grep 5900
# Should show wayvnc listening on 0.0.0.0:5900
```

### Check i3pm Daemon Window Tracking

```bash
i3pm daemon status
# Should show: Connected to Sway, event subscriptions active

cat ~/.config/i3/window-workspace-map.json | jq '.windows | length'
# Should show count of tracked windows

swaymsg -t get_tree | jq '.. | select(.marks?) | select(.marks | length > 0) | {id, marks, workspace}'
# Should show windows with project marks
```

### Check Project Context

```bash
i3pm project current
# Should show active project or "No active project"

cat ~/.config/i3/active-project.json | jq .
# Should show: {"project_name": "nixos", "project_dir": "/etc/nixos", ...}
```

---

**Next Steps**:
1. Generate contracts/ (Sway IPC, wayvnc, systemd dependencies)
2. Generate quickstart.md (test scenarios for each user story)
3. Complete plan.md with technical context

# Data Model: Multi-Monitor Headless Sway/Wayland Setup

**Feature**: 048-multi-monitor-headless
**Date**: 2025-10-29

## Overview

This document defines the data structures and configuration models for the three-display headless Sway/Wayland setup. Since this is a NixOS system configuration feature (not an application with runtime data storage), the "data model" represents configuration structures and their relationships.

## Entity 1: Headless Output

A virtual display created by the wlroots headless backend, representing one "monitor" in the multi-display setup.

### Attributes:

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| name | String | Sway output identifier | `"HEADLESS-1"`, `"HEADLESS-2"`, `"HEADLESS-3"` |
| resolution | String | Display resolution with refresh rate | `"1920x1080@60Hz"` |
| position | String | X,Y coordinates in logical layout | `"0,0"`, `"1920,0"`, `"3840,0"` |
| scale | String | Display scaling factor | `"1.0"` |
| workspaces | List[Integer] | Assigned workspace numbers | `[1, 2]`, `[3, 4, 5]`, `[6, 7, 8, 9]` |

### Validation Rules:

- **name** MUST match pattern `HEADLESS-N` where N is 1-3
- **resolution** MUST be valid Sway resolution format (`WIDTHxHEIGHT@REFRESH`)
- **position** MUST be valid X,Y coordinates (`X,Y` format)
- **scale** MUST be positive decimal (typically `"1.0"` for headless displays)
- **workspaces** MUST contain unique integers from 1-9, no overlaps between outputs

### State Transitions:

N/A (static configuration, no runtime state changes in MVP)

### Relationships:

- **One-to-one with WayVNC Instance**: Each output is captured by exactly one WayVNC service
- **One-to-many with Workspaces**: Each output can display multiple workspaces

---

## Entity 2: WayVNC Instance

A VNC server process bound to a specific headless output and TCP port, streaming that output's contents.

### Attributes:

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| serviceName | String | Systemd service unit name | `"wayvnc@HEADLESS-1.service"` |
| outputName | String | Target Sway output to capture | `"HEADLESS-1"` |
| port | Integer | TCP port for VNC connections | `5900`, `5901`, `5902` |
| address | String | Bind address for VNC server | `"0.0.0.0"` (all interfaces) |
| enableAuth | Boolean | VNC authentication enabled | `false` (Tailscale provides network security) |

### Validation Rules:

- **serviceName** MUST match systemd service naming: `wayvnc@HEADLESS-N.service`
- **outputName** MUST reference a valid Sway output (HEADLESS-1, HEADLESS-2, HEADLESS-3)
- **port** MUST be unique per instance, in range 5900-5902
- **port** MUST be exposed only on `tailscale0` interface (firewall rule)
- **address** MUST be `"0.0.0.0"` to accept connections from Tailscale network

### State Transitions:

```
┌─────────┐  systemd enable   ┌─────────┐  Sway starts   ┌─────────┐
│ Disabled│──────────────────→│ Enabled │───────────────→│ Running │
└─────────┘                   └─────────┘                └─────────┘
                                                               │
                                                               │ VNC client
                                                               │ connects
                                                               ▼
                                                          ┌─────────┐
                                                          │Streaming│
                                                          └─────────┘
                                                               │
                                                               │ Connection
                                                               │ lost
                                                               ▼
                                                          ┌─────────┐
                                                          │ Running │◀──┐
                                                          └─────────┘   │
                                                               │        │
                                                               │ Failure│ Restart
                                                               ▼        │
                                                          ┌─────────┐   │
                                                          │ Failed  │───┘
                                                          └─────────┘
```

### Relationships:

- **One-to-one with Headless Output**: Each instance captures exactly one output
- **Managed by systemd**: Lifecycle controlled by systemd user services

---

## Entity 3: Workspace Assignment

A mapping between Sway workspace numbers and headless outputs, determining which display shows which workspaces.

### Attributes:

| Attribute | Type | Description | Example |
|-----------|------|-------------|---------|
| workspace | Integer | Workspace number | `1`, `2`, `3`, ..., `9` |
| output | String | Target output name | `"HEADLESS-1"`, `"HEADLESS-2"`, `"HEADLESS-3"` |

### Validation Rules:

- **workspace** MUST be unique integer from 1-9
- **output** MUST reference a valid Sway output
- **Each workspace** MUST be assigned to exactly one output (no overlaps)
- **Assignment pattern** MUST match i3pm 3-monitor distribution:
  - Workspaces 1-2 → HEADLESS-1 (primary)
  - Workspaces 3-5 → HEADLESS-2 (secondary)
  - Workspaces 6-9 → HEADLESS-3 (tertiary)

### State Transitions:

N/A (static configuration in Sway config, though can be changed dynamically via `swaymsg` - not in MVP scope)

### Relationships:

- **Many-to-one with Headless Output**: Multiple workspaces map to one output
- **Queried by i3pm**: Monitor detection reads assignments via Sway IPC `GET_WORKSPACES`

---

## Configuration Data Structures

### Sway Output Configuration (Nix)

```nix
output = {
  "HEADLESS-1" = {
    resolution = "1920x1080@60Hz";
    position = "0,0";
    scale = "1.0";
  };
  "HEADLESS-2" = {
    resolution = "1920x1080@60Hz";
    position = "1920,0";
    scale = "1.0";
  };
  "HEADLESS-3" = {
    resolution = "1920x1080@60Hz";
    position = "3840,0";
    scale = "1.0";
  };
};
```

### Workspace Assignment Configuration (Nix)

```nix
workspaceOutputAssign = [
  # Primary display (HEADLESS-1)
  { workspace = "1"; output = "HEADLESS-1"; }
  { workspace = "2"; output = "HEADLESS-1"; }

  # Secondary display (HEADLESS-2)
  { workspace = "3"; output = "HEADLESS-2"; }
  { workspace = "4"; output = "HEADLESS-2"; }
  { workspace = "5"; output = "HEADLESS-2"; }

  # Tertiary display (HEADLESS-3)
  { workspace = "6"; output = "HEADLESS-3"; }
  { workspace = "7"; output = "HEADLESS-3"; }
  { workspace = "8"; output = "HEADLESS-3"; }
  { workspace = "9"; output = "HEADLESS-3"; }
];
```

### WayVNC Instance Mapping (Conceptual)

This mapping is implicit in the systemd service definitions, not stored as data:

| Output Name  | Service Name               | Port | VNC URL (via Tailscale)      |
|--------------|----------------------------|------|------------------------------|
| HEADLESS-1   | wayvnc@HEADLESS-1.service  | 5900 | vnc://<tailscale-ip>:5900    |
| HEADLESS-2   | wayvnc@HEADLESS-2.service  | 5901 | vnc://<tailscale-ip>:5901    |
| HEADLESS-3   | wayvnc@HEADLESS-3.service  | 5902 | vnc://<tailscale-ip>:5902    |

---

## Environment Variable Configuration

### wlroots Headless Backend

```nix
environment.sessionVariables = {
  WLR_BACKENDS = "headless";
  WLR_HEADLESS_OUTPUTS = "3";  # Create 3 virtual outputs
  WLR_LIBINPUT_NO_DEVICES = "1";
  WLR_RENDERER = "pixman";

  # Wayland environment
  XDG_SESSION_TYPE = "wayland";
  XDG_CURRENT_DESKTOP = "sway";

  # Application compatibility
  QT_QPA_PLATFORM = "wayland";
  GDK_BACKEND = "wayland";
  GSK_RENDERER = "cairo";  # Software rendering for GTK4 apps
};
```

### Firewall Configuration

```nix
networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
  5900  # HEADLESS-1
  5901  # HEADLESS-2
  5902  # HEADLESS-3
];
```

---

## Systemd Service Schema

### Template Pattern (Conceptual)

While the implementation uses explicit service definitions (not templates), the logical pattern is:

```
Service Name: wayvnc@HEADLESS-N.service
Parameters:
  - %i (instance name) = HEADLESS-N
  - Output = HEADLESS-N
  - Port = 5900 + (N - 1)
Dependencies:
  - After: sway-session.target
  - PartOf: sway-session.target
Restart Policy:
  - Restart=on-failure
```

### Actual Implementation (Three Explicit Services)

See `contracts/wayvnc-service-definitions.nix` for full systemd unit definitions.

---

## Querying and Validation

### Runtime State Queries (via Sway IPC)

```bash
# Query outputs (should show 3 headless outputs)
swaymsg -t get_outputs | jq '.[] | {name, active, current_mode, rect}'

# Query workspaces (should show assignments to HEADLESS-1/2/3)
swaymsg -t get_workspaces | jq '.[] | {num, name, output, visible}'

# Query specific output
swaymsg -t get_outputs | jq '.[] | select(.name == "HEADLESS-1")'
```

### i3pm Integration Queries

```bash
# Monitor status (should report 3 outputs)
i3pm monitors status

# Workspace distribution (should show 1-2, 3-5, 6-9 pattern)
i3pm monitors config show
```

### Systemd Service Status

```bash
# Check individual service
systemctl --user status wayvnc@HEADLESS-1.service

# Check all WayVNC services
systemctl --user list-units 'wayvnc@*'

# View service logs
journalctl --user -u wayvnc@HEADLESS-1 -f
```

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ NixOS Configuration (Declarative)                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  greetd wrapper:                                                 │
│    WLR_HEADLESS_OUTPUTS=3 → wlroots → Create 3 outputs          │
│                                                                  │
│  Sway config (home-manager):                                     │
│    output { HEADLESS-1 { ... }, HEADLESS-2 { ... }, ... }       │
│    workspaceOutputAssign [ ... ]                                 │
│                                                                  │
│  Systemd services (home-manager):                                │
│    wayvnc@HEADLESS-1.service → Port 5900                         │
│    wayvnc@HEADLESS-2.service → Port 5901                         │
│    wayvnc@HEADLESS-3.service → Port 5902                         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                            │
                            │ nixos-rebuild switch
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ Runtime State (Managed by Sway + systemd)                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Sway compositor:                                                │
│    Outputs: HEADLESS-1, HEADLESS-2, HEADLESS-3                   │
│    Workspaces: 1-2 on H1, 3-5 on H2, 6-9 on H3                   │
│                                                                  │
│  WayVNC processes:                                               │
│    PID 1234: Capturing HEADLESS-1 → :5900                        │
│    PID 1235: Capturing HEADLESS-2 → :5901                        │
│    PID 1236: Capturing HEADLESS-3 → :5902                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                            │
                            │ VNC protocol over Tailscale
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ VNC Clients (User's local machines)                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Client 1: tailscale-ip:5900 → Views HEADLESS-1 (WS 1-2)         │
│  Client 2: tailscale-ip:5901 → Views HEADLESS-2 (WS 3-5)         │
│  Client 3: tailscale-ip:5902 → Views HEADLESS-3 (WS 6-9)         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Summary

This data model defines three core entities:
1. **Headless Output**: Virtual displays with resolution, position, and workspace assignments
2. **WayVNC Instance**: VNC servers capturing specific outputs on specific ports
3. **Workspace Assignment**: Workspace-to-output mapping following i3pm conventions

All configuration is declarative (Nix expressions), with runtime state managed by Sway and systemd. No persistent application data or databases are required.

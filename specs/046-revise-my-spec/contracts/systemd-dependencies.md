# Contract: Systemd Service Dependencies

**Feature**: Feature 046 - Hetzner Cloud Sway with Headless Wayland
**Created**: 2025-10-28
**Purpose**: Define systemd service dependencies for headless Sway session startup sequence

## Overview

Headless Sway requires precise service ordering to ensure:
1. Display manager (greetd) starts before Sway
2. Sway session completes initialization before wayvnc
3. i3pm daemon starts after Sway IPC socket is available
4. User session persists after logout (user lingering)

## Service Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                    System Boot                              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
            ┌─────────────────────┐
            │  multi-user.target  │
            └──────────┬──────────┘
                       │
                       ▼
            ┌─────────────────────┐
            │   greetd.service    │  (System service)
            │   Display Manager   │
            └──────────┬──────────┘
                       │
                       │ Starts user session with WLR_BACKENDS=headless
                       ▼
            ┌─────────────────────────────────┐
            │  Sway Compositor (user session)  │
            │  - Creates SWAYSOCK              │
            │  - Creates virtual outputs       │
            │  - Emits sway-session.target     │
            └──────────┬──────────────────────┘
                       │
           ┌───────────┴────────────┐
           │                        │
           ▼                        ▼
┌──────────────────────┐  ┌─────────────────────────┐
│ wayvnc.service       │  │ i3pm daemon.service     │
│ (user service)       │  │ (user service)          │
│ After=sway-session   │  │ After=sway-session      │
│ Requires=sway-session│  │ Requires=sway-session   │
└──────────────────────┘  └─────────────────────────┘
```

## System Services (Root Level)

### greetd.service

**Purpose**: Display manager for headless login

**Unit File** (simplified):
```ini
[Unit]
Description=greetd display manager
After=systemd-user-sessions.service
After=plymouth-quit-wait.service

[Service]
Type=simple
ExecStart=/run/current-system/sw/bin/greetd --config /etc/greetd/config.toml
Restart=on-failure
RestartSec=1

# Timeout for session startup
TimeoutStartSec=30s

[Install]
WantedBy=graphical.target
```

**Configuration** (`/etc/greetd/config.toml`):
```toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --remember-user-session --time --cmd 'sway --config /home/vpittamp/.config/sway/config'"
user = "greeter"
```

**Key Directives**:
- `After=systemd-user-sessions.service`: Ensures user sessions enabled
- `Restart=on-failure`: Auto-restart if crash
- `WantedBy=graphical.target`: Starts on graphical boot

**Environment Variables Set**:
```bash
WLR_BACKENDS=headless
WLR_LIBINPUT_NO_DEVICES=1
WLR_RENDERER=pixman
# (plus all Wayland app support vars from sway.nix)
```

**Functional Requirement**: FR-005 (Headless Sway session MUST start automatically on system boot via systemd user service)

---

## User Services (User Session Level)

### User Lingering

**Purpose**: Keep user session active after logout (required for headless server)

**Enable**:
```bash
loginctl enable-linger vpittamp
```

**Verification**:
```bash
loginctl show-user vpittamp | grep Linger
# Expected: Linger=yes
```

**Effect**:
- User services start on system boot (not on login)
- User services continue running after SSH logout
- Required for headless server use case

**Functional Requirement**: Implicit for FR-005 (persistent session)

---

### sway-session.target

**Purpose**: Synchronization point for services that depend on Sway being fully initialized

**Unit File** (`~/.config/systemd/user/sway-session.target`):
```ini
[Unit]
Description=sway compositor session
Documentation=man:systemd.special(7)
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
```

**Usage**: Other services use `After=sway-session.target` to wait for Sway

**Triggered By**: Sway compositor sets `SYSTEMD_USER_UNIT=sway-session.target` on startup

---

### wayvnc.service

**Purpose**: VNC server for remote access to headless Sway

**Unit File** (`~/.config/systemd/user/wayvnc.service`):
```ini
[Unit]
Description=wayvnc - VNC server for Wayland
Documentation=man:wayvnc(1)
After=sway-session.target
Requires=sway-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/run/current-system/sw/bin/wayvnc --config=%h/.config/wayvnc/config
Restart=on-failure
RestartSec=1

# Environment variables (inherited from Sway session)
Environment="WAYLAND_DISPLAY=wayland-1"
Environment="XDG_RUNTIME_DIR=/run/user/%U"

[Install]
WantedBy=sway-session.target
```

**Key Directives**:
- `After=sway-session.target`: Waits for Sway to be ready
- `Requires=sway-session.target`: Fails if Sway not running
- `PartOf=graphical-session.target`: Stops when graphical session stops
- `Restart=on-failure`: Auto-restart if crash
- `WantedBy=sway-session.target`: Starts when Sway session starts

**Functional Requirement**: FR-008 (wayvnc service MUST start automatically after Sway session is running)

---

### i3-project-event-listener.service

**Purpose**: i3pm daemon for project-scoped window management

**Unit File** (`~/.config/systemd/user/i3-project-event-listener.service`):
```ini
[Unit]
Description=i3 Project Management Event Listener
Documentation=file:///etc/nixos/docs/PROJECT_MANAGEMENT.md
After=sway-session.target
Requires=sway-session.target
PartOf=graphical-session.target

[Service]
Type=notify
ExecStart=/run/current-system/sw/bin/i3pm daemon start
Restart=on-failure
RestartSec=2
WatchdogSec=30

# Environment variables
Environment="I3PM_CONFIG_DIR=%h/.config/i3"
Environment="I3PM_LOG_LEVEL=INFO"

# Resource limits
MemoryMax=50M
CPUQuota=10%

[Install]
WantedBy=sway-session.target
```

**Key Directives**:
- `After=sway-session.target`: Waits for Sway IPC socket
- `Requires=sway-session.target`: Fails if Sway not running
- `Type=notify`: Daemon signals readiness via sd_notify
- `WatchdogSec=30`: Daemon must send keepalive every 30s
- `Restart=on-failure`: Auto-restart if crash
- `WantedBy=sway-session.target`: Starts when Sway session starts

**Functional Requirement**: FR-013 (Python daemon MUST connect to Sway via i3ipc library)

---

## Service Startup Sequence

### Timeline (from system boot to ready state)

```
T+0s:   System boot, systemd starts
T+2s:   multi-user.target reached
T+3s:   greetd.service starts
T+4s:   greetd spawns tuigreet (auto-login configured)
T+5s:   tuigreet launches Sway with WLR_BACKENDS=headless
T+6s:   Sway compositor initializes
        - Creates virtual output (HEADLESS-1)
        - Creates IPC socket (/run/user/1000/sway-ipc.<PID>.sock)
        - Sets SWAYSOCK environment variable
T+7s:   Sway emits sway-session.target
T+8s:   wayvnc.service starts (After=sway-session.target)
        - Connects to Sway Wayland socket
        - Listens on port 5900
T+8s:   i3-project-event-listener.service starts (After=sway-session.target)
        - Connects to SWAYSOCK
        - Subscribes to i3 IPC events
        - Sends sd_notify READY=1
T+9s:   System ready for VNC connections
```

**Success Criteria**: SC-002 (i3pm daemon connects to Sway IPC within 2 seconds of session start)

---

## Failure Handling

### Sway Fails to Start

**Scenario**: Sway compositor crashes or fails to initialize

**Effect**:
- `sway-session.target` not reached
- `wayvnc.service` and `i3pm daemon.service` remain in "waiting" state
- System logs show "dependency failed"

**Debug**:
```bash
# Check Sway status
systemctl --user status sway-session.target

# Check greetd logs
journalctl -u greetd.service -n 50

# Check Sway logs (if launched manually)
journalctl --user -n 50 | grep sway
```

**Recovery**:
- Fix Sway configuration error
- Restart greetd: `systemctl restart greetd`
- Or manually start Sway: `sway --config ~/.config/sway/config`

---

### wayvnc Fails to Start

**Scenario**: wayvnc service crashes or fails to connect to Sway

**Effect**:
- Sway session continues running
- No VNC access (but SSH still works)
- i3pm daemon continues running

**Debug**:
```bash
# Check wayvnc status
systemctl --user status wayvnc.service

# Check logs
journalctl --user -u wayvnc.service -n 50

# Test manually
wayvnc --config=~/.config/wayvnc/config
```

**Recovery**:
- Check wayvnc configuration (`~/.config/wayvnc/config`)
- Restart service: `systemctl --user restart wayvnc.service`
- Verify port 5900 not in use: `netstat -tlnp | grep 5900`

---

### i3pm Daemon Fails to Start

**Scenario**: i3pm daemon crashes or fails to connect to Sway IPC

**Effect**:
- Sway session continues running
- wayvnc continues running
- No project management (windows not auto-marked)

**Debug**:
```bash
# Check daemon status
systemctl --user status i3-project-event-listener.service

# Check logs
journalctl --user -u i3-project-event-listener.service -n 50

# Check SWAYSOCK is set
echo $SWAYSOCK
```

**Recovery**:
- Verify SWAYSOCK exists: `ls -la $SWAYSOCK`
- Test IPC manually: `swaymsg -t get_version`
- Restart daemon: `systemctl --user restart i3-project-event-listener.service`

---

## Service Management Commands

### System Services (require root)

```bash
# Check greetd status
systemctl status greetd.service

# Restart greetd (restarts entire session)
systemctl restart greetd.service

# View greetd logs
journalctl -u greetd.service -f
```

---

### User Services (user level)

```bash
# Check all user services
systemctl --user status

# Check specific service
systemctl --user status wayvnc.service
systemctl --user status i3-project-event-listener.service

# Restart service
systemctl --user restart wayvnc.service

# Enable service (start on session start)
systemctl --user enable wayvnc.service

# Disable service (don't start automatically)
systemctl --user disable wayvnc.service

# View logs
journalctl --user -u wayvnc.service -f
journalctl --user -u i3-project-event-listener.service -f
```

---

### Session Management

```bash
# Check user lingering status
loginctl show-user vpittamp | grep Linger

# Enable user lingering (persist after logout)
loginctl enable-linger vpittamp

# Check user sessions
loginctl list-sessions

# Check user state
loginctl user-status vpittamp
```

---

## Testing Procedures

### Test Headless Session Startup

```bash
# Reboot system
sudo reboot

# After reboot, check from SSH session
ssh vpittamp@<hetzner-ip>

# Verify Sway is running
echo $SWAYSOCK
# Expected: /run/user/1000/sway-ipc.<PID>.sock

# Verify sway-session.target reached
systemctl --user is-active sway-session.target
# Expected: active

# Verify virtual output created
swaymsg -t get_outputs | jq '.[] | {name, make}'
# Expected: {"name": "HEADLESS-1", "make": "headless"}
```

**Success Criteria**: FR-005 (Headless Sway session starts automatically on system boot)

---

### Test wayvnc Service Startup

```bash
# Check wayvnc service started
systemctl --user is-active wayvnc.service
# Expected: active

# Check port 5900 listening
netstat -tlnp | grep 5900
# Expected: tcp 0 0 0.0.0.0:5900 0.0.0.0:* LISTEN <PID>/wayvnc

# Check logs for successful startup
journalctl --user -u wayvnc.service -n 20 | grep -i listening
# Expected: "Listening for connections on 0.0.0.0:5900"
```

**Success Criteria**: FR-008 (wayvnc service starts automatically after Sway)

---

### Test i3pm Daemon Startup

```bash
# Check daemon service started
systemctl --user is-active i3-project-event-listener.service
# Expected: active

# Check daemon connected to Sway
i3pm daemon status
# Expected: "Status: Connected to Sway IPC"

# Check daemon subscriptions
i3pm daemon status | grep -A 10 "Event Subscriptions"
# Expected: window, workspace, output, tick events enabled
```

**Success Criteria**: SC-002 (i3pm daemon connects to Sway IPC within 2 seconds)

---

### Test Service Dependencies

```bash
# Stop Sway session (simulates Sway crash)
systemctl --user stop sway-session.target

# Check dependent services stopped
systemctl --user is-active wayvnc.service
# Expected: inactive (dead)

systemctl --user is-active i3-project-event-listener.service
# Expected: inactive (dead)

# Restart Sway session
systemctl --user start sway-session.target

# Verify dependent services restarted
systemctl --user is-active wayvnc.service
# Expected: active

systemctl --user is-active i3-project-event-listener.service
# Expected: active
```

**Success Criteria**: Services correctly depend on sway-session.target

---

## NixOS Configuration

### System Configuration (configurations/hetzner-sway.nix)

```nix
{
  # Enable greetd display manager
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --remember --remember-user-session --time --cmd 'sway --config /home/vpittamp/.config/sway/config'";
        user = "greeter";
      };
    };
  };

  # Enable user lingering (persist after logout)
  systemd.services."user-linger-vpittamp" = {
    description = "Enable user lingering for vpittamp";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger vpittamp";
      RemainAfterExit = true;
    };
  };
}
```

---

### Home Manager Configuration (home-modules/desktop/sway.nix)

```nix
{
  # Sway session target (synchronization point)
  systemd.user.targets.sway-session = {
    Unit = {
      Description = "sway compositor session";
      Documentation = "man:systemd.special(7)";
      BindsTo = "graphical-session.target";
      Wants = "graphical-session-pre.target";
      After = "graphical-session-pre.target";
    };
  };

  # wayvnc service
  systemd.user.services.wayvnc = {
    Unit = {
      Description = "wayvnc - VNC server for Wayland";
      Documentation = "man:wayvnc(1)";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config=%h/.config/wayvnc/config";
      Restart = "on-failure";
      RestartSec = 1;
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/%U"
      ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # i3pm daemon service (already exists, needs After=sway-session.target)
  systemd.user.services.i3-project-event-listener = {
    Unit = {
      After = [ "sway-session.target" ];  # Add this
      Requires = [ "sway-session.target" ];  # Add this
    };
  };
}
```

---

## Functional Requirements Mapping

| Requirement | Service/Directive | Validation |
|-------------|------------------|------------|
| FR-005: Auto-start on boot | greetd.service + user lingering | `loginctl show-user \| grep Linger` |
| FR-008: wayvnc starts after Sway | `After=sway-session.target` | `systemctl --user list-dependencies wayvnc.service` |
| FR-013: Daemon connects to Sway | `After=sway-session.target` | `i3pm daemon status` |
| SC-002: Daemon connects <2s | `RestartSec=2`, `WatchdogSec=30` | `i3pm daemon status \| grep uptime` |

---

## References

- **systemd Documentation**: https://www.freedesktop.org/software/systemd/man/
- **greetd GitHub**: https://github.com/kennylevinsen/greetd
- **User Lingering**: `man loginctl`, search "enable-linger"
- **systemd Targets**: `man systemd.special`

**Validation Status**: ⏳ Pending Feature 046 implementation and testing

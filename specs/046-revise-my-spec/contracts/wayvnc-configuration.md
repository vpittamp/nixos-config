# Contract: wayvnc Configuration

**Feature**: Feature 046 - Hetzner Cloud Sway with Headless Wayland
**Created**: 2025-10-28
**Purpose**: Define wayvnc server configuration for VNC remote access to headless Sway

## Overview

wayvnc is a VNC server for wlroots-based Wayland compositors (including Sway). It provides screen sharing over the VNC protocol with authentication, keyboard/mouse input, and clipboard integration.

## Configuration File

**Location**: `~/.config/wayvnc/config`

**Format**: Plain text, key=value pairs

**Example Configuration**:
```ini
address=0.0.0.0
port=5900
enable_auth=true
username=vpittamp
# Optional: Specify output (auto-detects if only one output exists)
# output=HEADLESS-1
# Optional: Performance tuning
# max_rate=60
# Optional: Encoder selection
# encoder=cpu
```

## Configuration Parameters

### Network Settings

#### address

**Type**: String (IPv4 address)
**Default**: `0.0.0.0` (listen on all interfaces)
**Required**: No

**Values**:
- `0.0.0.0`: Listen on all network interfaces (default)
- `127.0.0.1`: Listen only on localhost (local VNC only)
- Specific IP: Listen on single interface (e.g., `10.0.0.5`)

**Usage**:
```ini
address=0.0.0.0
```

**Security Consideration**: Use `0.0.0.0` for remote access, `127.0.0.1` for SSH tunnel only.

---

#### port

**Type**: Integer (1-65535)
**Default**: `5900`
**Required**: No

**Values**:
- `5900`: Standard VNC port (default)
- `5901+`: Additional VNC displays

**Usage**:
```ini
port=5900
```

**Firewall Requirement**: Ensure port is open in Hetzner Cloud firewall rules.

---

### Authentication Settings

#### enable_auth

**Type**: Boolean
**Default**: `false`
**Required**: Yes (set to `true` for security)

**Values**:
- `true`: Enable PAM authentication (recommended)
- `false`: Disable authentication (INSECURE - for testing only)

**Usage**:
```ini
enable_auth=true
```

**PAM Configuration**: Uses system PAM stack (same as SSH login).

**Functional Requirement**: FR-009 (VNC server MUST listen on port 5900 with PAM authentication enabled)

---

#### username

**Type**: String
**Default**: None
**Required**: Only if `enable_auth=true`

**Values**: Valid system username (e.g., `vpittamp`)

**Usage**:
```ini
username=vpittamp
```

**Authentication Flow**:
1. VNC client connects to port 5900
2. wayvnc prompts for password
3. PAM validates password against system user
4. If valid, connection established

---

### Output Settings

#### output

**Type**: String (output name)
**Default**: Auto-detect (first available output)
**Required**: No (unless multiple outputs exist)

**Values**:
- `HEADLESS-1`: First virtual output
- `HEADLESS-2`: Second virtual output
- `auto`: Let wayvnc choose (default)

**Usage**:
```ini
# Single virtual output (auto-detect works)
# output=HEADLESS-1

# Multiple virtual outputs (explicit selection required)
output=HEADLESS-1
```

**Multi-Output Scenario**:
- If 2 virtual outputs exist (HEADLESS-1, HEADLESS-2)
- wayvnc can only expose ONE output per instance
- To access both outputs, run two wayvnc instances on different ports

**Functional Requirement**: FR-029 (Multi-virtual-output support)

---

### Performance Settings

#### max_rate

**Type**: Integer (frames per second)
**Default**: `60`
**Required**: No

**Values**:
- `30`: Lower bandwidth (acceptable for remote work)
- `60`: Standard refresh rate (default)
- `120`: High refresh (requires more bandwidth)

**Usage**:
```ini
max_rate=30
```

**Bandwidth Impact**:
- 30 FPS: ~5-10 Mbps (text-heavy workloads)
- 60 FPS: ~10-20 Mbps (normal desktop use)

---

#### encoder

**Type**: String (encoder backend)
**Default**: `cpu` (software encoding)
**Required**: No

**Values**:
- `cpu`: Software encoding (default for headless)
- `gpu`: Hardware encoding (requires GPU)

**Usage**:
```ini
encoder=cpu
```

**Headless Consideration**: GPU encoder not available in headless mode. Use CPU encoder.

---

## Systemd Service Integration

### Service Configuration

**File**: `~/.config/systemd/user/wayvnc.service`

**Example Service Unit**:
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
Environment="XDG_RUNTIME_DIR=/run/user/1000"

[Install]
WantedBy=sway-session.target
```

**Key Directives**:
- `After=sway-session.target`: Ensures Sway starts first
- `Requires=sway-session.target`: Fails if Sway not running
- `Restart=on-failure`: Auto-restart if crash
- `RestartSec=1`: Wait 1 second before restart

**Functional Requirement**: FR-008 (wayvnc service MUST start automatically after Sway session is running)

---

### Service Management

**Enable Service** (start on login):
```bash
systemctl --user enable wayvnc.service
```

**Start Service** (immediate):
```bash
systemctl --user start wayvnc.service
```

**Check Status**:
```bash
systemctl --user status wayvnc.service
```

**Expected Output**:
```
● wayvnc.service - wayvnc - VNC server for Wayland
     Loaded: loaded (/home/vpittamp/.config/systemd/user/wayvnc.service; enabled)
     Active: active (running) since Mon 2025-10-28 10:00:00 UTC; 2min ago
   Main PID: 12345 (wayvnc)
     Memory: 15.2M
        CPU: 120ms
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/wayvnc.service
             └─12345 /run/current-system/sw/bin/wayvnc --config=/home/vpittamp/.config/wayvnc/config

Oct 28 10:00:00 hetzner systemd[1234]: Started wayvnc - VNC server for Wayland.
Oct 28 10:00:00 hetzner wayvnc[12345]: Listening for connections on 0.0.0.0:5900
Oct 28 10:00:00 hetzner wayvnc[12345]: Output: HEADLESS-1 (1920x1080@60Hz)
```

**View Logs**:
```bash
journalctl --user -u wayvnc.service -f
```

---

## VNC Client Configuration

### Connection Parameters

**Server Address**: `<hetzner-ip>:5900` or `<hetzner-hostname>:5900`

**Authentication**:
- Username: `vpittamp`
- Password: System user password (PAM)

**Color Depth**: 24-bit (default)

**Compression**: Auto (VNC protocol negotiates)

---

### Recommended VNC Clients

#### Linux

**TigerVNC**:
```bash
vncviewer <hetzner-ip>:5900
```

**RealVNC Viewer**:
```bash
realvnc-viewer <hetzner-ip>:5900
```

---

#### macOS

**Screen Sharing** (built-in):
1. Open Finder → Go → Connect to Server
2. Enter: `vnc://<hetzner-ip>:5900`
3. Authenticate with username and password

**RealVNC Viewer**:
- Download from https://www.realvnc.com/en/connect/download/viewer/
- Enter: `<hetzner-ip>:5900`

---

#### Windows

**TightVNC Viewer**:
- Download from https://www.tightvnc.com/
- Enter: `<hetzner-ip>:5900`

**RealVNC Viewer**:
- Download from https://www.realvnc.com/en/connect/download/viewer/
- Enter: `<hetzner-ip>:5900`

---

## Functional Requirements Mapping

| Requirement | Configuration Parameter | Validation |
|-------------|------------------------|------------|
| FR-007: Provide VNC remote access | `enable=true` (implicit) | Service running |
| FR-008: Start after Sway | `After=sway-session.target` | Service dependencies |
| FR-009: Port 5900 + PAM auth | `port=5900`, `enable_auth=true` | `netstat -tlnp \| grep 5900` |
| FR-010: Keyboard/mouse input | Built-in wayvnc feature | Manual testing via VNC |
| FR-011: Clipboard sharing | Built-in wayvnc feature | Copy/paste test |
| FR-012: Adapt display resolution | wayvnc auto-negotiates | VNC client resize |

---

## Testing Procedures

### Test VNC Server Listening

```bash
# Check port is open
netstat -tlnp | grep 5900
# Expected: tcp 0 0 0.0.0.0:5900 0.0.0.0:* LISTEN 12345/wayvnc

# Check from remote machine
nmap -p 5900 <hetzner-ip>
# Expected: 5900/tcp open vnc
```

**Success Criteria**: SC-001 (User can log into headless Sway session and perform basic window management via VNC)

---

### Test PAM Authentication

```bash
# Attempt connection from VNC client
vncviewer <hetzner-ip>:5900

# Enter credentials:
# Username: vpittamp
# Password: [system password]

# Check wayvnc logs for authentication attempt
journalctl --user -u wayvnc.service | grep -i auth
```

**Expected Log**:
```
Oct 28 10:05:00 hetzner wayvnc[12345]: Client connected from 192.168.1.100
Oct 28 10:05:02 hetzner wayvnc[12345]: PAM authentication successful for user vpittamp
```

**Success Criteria**: FR-009 (VNC server MUST listen on port 5900 with PAM authentication enabled)

---

### Test Keyboard Input

**Procedure**:
1. Connect via VNC client
2. Press `Meta+Return` to open terminal
3. Type `echo "test"` and press Enter
4. Verify output appears in terminal

**Expected Result**: Text appears in VNC session with <100ms latency

**Success Criteria**: SC-005 (Keyboard input latency is under 100ms)

---

### Test Mouse Input

**Procedure**:
1. Connect via VNC client
2. Move mouse cursor across Sway desktop
3. Click on window to focus
4. Right-click to open context menu (if applicable)

**Expected Result**: Mouse events register correctly in Sway

**Success Criteria**: FR-010 (VNC connection MUST support full keyboard and mouse input from remote client)

---

### Test Clipboard Sharing

**Procedure**:
1. Connect via VNC client
2. In VNC session: Copy text from terminal (`Ctrl+Shift+C`)
3. On local machine: Paste text (`Ctrl+V`)
4. On local machine: Copy text
5. In VNC session: Paste text (`Ctrl+Shift+V`)

**Expected Result**: Clipboard content syncs bidirectionally

**Success Criteria**: FR-011 (VNC session MUST support clipboard sharing between remote client and headless Sway)

---

### Test Display Resolution Adaptation

**Procedure**:
1. Connect via VNC client with default resolution (1920x1080)
2. Verify Sway desktop fills VNC window
3. Resize VNC client window
4. Verify Sway adapts (scales or resizes depending on client)

**Expected Result**: Display adapts to VNC client capabilities

**Success Criteria**: FR-012 (System MUST allow VNC server to adapt virtual display resolution based on client capability)

---

## Troubleshooting

### Service Fails to Start

**Symptom**: `systemctl --user status wayvnc` shows `failed`

**Common Causes**:
1. Sway not running (check `echo $SWAYSOCK`)
2. Config file missing or invalid (check `~/.config/wayvnc/config`)
3. Port 5900 already in use (check `netstat -tlnp | grep 5900`)

**Debug Steps**:
```bash
# Check Sway is running
swaymsg -t get_version

# Test wayvnc manually
wayvnc --config=~/.config/wayvnc/config

# Check logs
journalctl --user -u wayvnc.service -n 50
```

---

### Cannot Connect from Remote Client

**Symptom**: VNC client shows "Connection refused" or "Connection timed out"

**Common Causes**:
1. Firewall blocking port 5900
2. wayvnc not listening on 0.0.0.0
3. Incorrect IP address

**Debug Steps**:
```bash
# Check wayvnc is listening
netstat -tlnp | grep 5900

# Check Hetzner firewall rules
# (via Hetzner Cloud Console or CLI)

# Test locally first
vncviewer localhost:5900

# Test from remote machine
telnet <hetzner-ip> 5900
```

---

### Authentication Fails

**Symptom**: VNC client prompts for password but rejects it

**Common Causes**:
1. Incorrect username in config
2. PAM misconfigured
3. User account locked

**Debug Steps**:
```bash
# Verify username matches system user
whoami
# Expected: vpittamp

# Check PAM configuration
cat /etc/pam.d/system-auth

# Test SSH login with same credentials (should work)
ssh vpittamp@localhost

# Check wayvnc logs
journalctl --user -u wayvnc.service | grep -i auth
```

---

### Poor Performance / High Latency

**Symptom**: VNC session feels sluggish, high input latency

**Common Causes**:
1. Network bandwidth limited
2. max_rate too high
3. CPU overloaded (software rendering)

**Debug Steps**:
```bash
# Check network latency
ping <hetzner-ip>

# Check bandwidth
iperf3 -c <hetzner-ip>

# Lower frame rate
echo "max_rate=30" >> ~/.config/wayvnc/config
systemctl --user restart wayvnc

# Check CPU usage
top
# Look for high CPU from Sway or wayvnc
```

---

## Security Considerations

### Authentication

**Requirement**: ALWAYS enable PAM authentication (`enable_auth=true`)

**Risk**: Unauthenticated VNC allows anyone to control your desktop

**Mitigation**:
- Use strong password for system user
- Consider SSH tunnel for additional encryption layer
- Monitor failed authentication attempts via journalctl

---

### Firewall Rules

**Recommendation**: Restrict VNC port to trusted IPs

**Hetzner Cloud Firewall**:
```
Rule: Allow TCP port 5900
Source: [Your IP address or IP range]
Target: [Hetzner VM]
```

**Alternative**: SSH Tunnel (more secure)
```bash
# On local machine
ssh -L 5900:localhost:5900 vpittamp@<hetzner-ip>

# Then connect VNC client to localhost:5900
vncviewer localhost:5900
```

---

### Encryption

**VNC Protocol**: Not encrypted by default (plaintext)

**Options for Encryption**:
1. **SSH Tunnel** (recommended):
   ```bash
   ssh -L 5900:localhost:5900 vpittamp@<hetzner-ip>
   ```

2. **TLS/SSL**: wayvnc doesn't support TLS natively (use stunnel wrapper if needed)

3. **WireGuard/Tailscale**: VPN tunnel for encrypted network layer

---

## References

- **wayvnc GitHub**: https://github.com/any1/wayvnc
- **wayvnc Man Page**: `man wayvnc`
- **VNC Protocol Specification**: RFC 6143
- **PAM Configuration**: `/etc/pam.d/system-auth`

**Validation Status**: ⏳ Pending Feature 046 implementation and testing

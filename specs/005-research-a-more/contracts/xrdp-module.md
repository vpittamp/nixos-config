# Module Contract: services.xrdp

**Feature**: Lightweight X11 Desktop Environment for Hetzner Cloud
**Module Path**: `modules/desktop/xrdp.nix`
**Date**: 2025-10-16

## Purpose

NixOS module for declarative configuration of XRDP (X Remote Desktop Protocol) server. Provides remote desktop access to X11 sessions with audio redirection and PAM authentication.

## Module Options

### Core Configuration

#### `services.xrdp.enable`
- **Type**: `bool`
- **Default**: `false`
- **Description**: Whether to enable the XRDP server for remote desktop access.
- **Example**: `true`

#### `services.xrdp.port`
- **Type**: `int`
- **Default**: `3389`
- **Description**: TCP port for XRDP connections. Default is standard RDP port.
- **Allowed Range**: 1-65535
- **Example**: `3389`

#### `services.xrdp.openFirewall`
- **Type**: `bool`
- **Default**: `false`
- **Description**: Whether to automatically open the XRDP port in the firewall.
- **Example**: `true`

#### `services.xrdp.defaultWindowManager`
- **Type**: `string`
- **Default**: `"${pkgs.xterm}/bin/xterm"`
- **Description**: Path to the window manager/session to launch after authentication. Should be absolute path to executable.
- **Example**: `"${pkgs.i3}/bin/i3"`

### Authentication

#### `services.xrdp.authMethod`
- **Type**: `enum`
- **Default**: `"pam"`
- **Allowed Values**: `"pam"` | `"password"` | `"certificate"`
- **Description**: Authentication method for XRDP connections.
  - `pam`: Use system PAM authentication (recommended)
  - `password`: Simple password file (not recommended)
  - `certificate`: Certificate-based authentication
- **Example**: `"pam"`

### TLS/SSL Configuration

#### `services.xrdp.sslCert`
- **Type**: `path`
- **Default**: Auto-generated self-signed certificate
- **Description**: Path to TLS certificate file for XRDP encryption.
- **Example**: `"/etc/xrdp/cert.pem"`

#### `services.xrdp.sslKey`
- **Type**: `path`
- **Default**: Auto-generated self-signed key
- **Description**: Path to TLS private key file for XRDP encryption.
- **Example**: `"/etc/xrdp/key.pem"`

### Session Management

#### `services.xrdp.sessionPolicy`
- **Type**: `enum`
- **Default**: `"Default"`
- **Allowed Values**: `"Default"` | `"UBD"` | `"UBI"` | `"UBC"`
- **Description**: Session reconnection policy.
  - `Default`: Allow reconnection to existing sessions
  - `UBD`: Unique session per user, display, and bit depth
  - `UBI`: Unique session per user, display, and bit depth, but ignore display
  - `UBC`: Unique session per user and bit depth only
- **Example**: `"Default"`

#### `services.xrdp.maxSessions`
- **Type**: `int`
- **Default**: `50`
- **Description**: Maximum number of concurrent XRDP sessions.
- **Allowed Range**: 1-1000
- **Example**: `50`

### Audio Configuration

#### `services.xrdp.audioRedirection`
- **Type**: `bool`
- **Default**: `true`
- **Description**: Whether to enable PulseAudio audio redirection to client machine.
- **Example**: `true`

#### `services.xrdp.pulseaudioModule`
- **Type**: `package`
- **Default**: `pkgs.pulseaudio-module-xrdp`
- **Description**: PulseAudio module package for XRDP audio support.
- **Example**: `pkgs.pulseaudio-module-xrdp`

### Display Configuration

#### `services.xrdp.display`
- **Type**: `submodule`
- **Default**: `{ resolution = "1920x1080"; colorDepth = 24; }`
- **Description**: Default display settings for XRDP sessions.
- **Submodule Options**:
  - `resolution` (string): Default screen resolution (e.g., "1920x1080")
  - `colorDepth` (int): Color depth in bits (16, 24, or 32)
- **Example**:
```nix
{
  resolution = "1920x1080";
  colorDepth = 24;
}
```

### Advanced Configuration

#### `services.xrdp.extraConfig`
- **Type**: `lines`
- **Default**: `""`
- **Description**: Additional configuration to append to `/etc/xrdp/xrdp.ini`.
- **Example**:
```nix
''
  [Xorg]
  param1=Xorg
  param2=-config
  param3=xrdp/xorg.conf
''
```

#### `services.xrdp.extraSesamanConfig`
- **Type**: `lines`
- **Default**: `""`
- **Description**: Additional configuration to append to `/etc/xrdp/sesman.ini`.
- **Example**:
```nix
''
  [SessionVariables]
  LANG=en_US.UTF-8
''
```

## Generated Files

The module generates the following configuration files:

### `/etc/xrdp/xrdp.ini`
- **Source**: Module options + `extraConfig`
- **Permissions**: 0644 (world-readable)
- **Owner**: root:root
- **Purpose**: Main XRDP server configuration
- **Sections**:
  - `[Globals]`: Port, certificate paths, max connections
  - `[Logging]`: Log levels and file paths
  - `[Channels]`: Audio, clipboard redirection
  - `[Xorg]`: Xorg backend configuration

### `/etc/xrdp/sesman.ini`
- **Source**: Module options + `extraSesamanConfig`
- **Permissions**: 0644 (world-readable)
- **Owner**: root:root
- **Purpose**: XRDP session manager configuration
- **Sections**:
  - `[Globals]`: Session parameters
  - `[Security]`: Authentication settings
  - `[Sessions]`: Session policy
  - `[SessionVariables]`: Environment variables

### `/etc/xrdp/startwm.sh`
- **Source**: Generated from `defaultWindowManager`
- **Permissions**: 0755 (executable)
- **Owner**: root:root
- **Purpose**: Script launched for each XRDP session
- **Content**:
```bash
#!/bin/sh
# XRDP Session Startup Script
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Source system profile
if [ -r /etc/profile ]; then
  . /etc/profile
fi

# Source user profile
if [ -r ~/.profile ]; then
  . ~/.profile
fi

# Launch window manager
exec ${defaultWindowManager}
```

### `/etc/xrdp/cert.pem` and `/etc/xrdp/key.pem`
- **Source**: Auto-generated or user-provided
- **Permissions**: 0600 (key), 0644 (cert)
- **Owner**: xrdp:xrdp
- **Purpose**: TLS encryption for RDP protocol

## System Integration

### systemd Services

The module creates the following systemd services:

#### `xrdp.service`
- **Description**: XRDP Remote Desktop Protocol server
- **After**: `network.target`
- **WantedBy**: `multi-user.target`
- **ExecStart**: `${pkgs.xrdp}/bin/xrdp --nodaemon`
- **Restart**: `on-failure`

#### `xrdp-sesman.service`
- **Description**: XRDP session manager
- **After**: `network.target`
- **WantedBy**: `multi-user.target`
- **ExecStart**: `${pkgs.xrdp}/bin/xrdp-sesman --nodaemon`
- **Restart**: `on-failure`

### User and Group

The module creates:
- **User**: `xrdp` (system user)
- **Group**: `xrdp` (system group)
- **Purpose**: Run XRDP daemon with minimal privileges

### Firewall Rules

When `openFirewall = true`:
```nix
networking.firewall.allowedTCPPorts = [ cfg.port ];
```

### PAM Configuration

When `authMethod = "pam"`:
```nix
security.pam.services.xrdp = {
  allowNullPassword = false;
  startSession = true;
};

security.pam.services.xrdp-sesman = {
  allowNullPassword = false;
  startSession = true;
};
```

## Integration with i3wm

### Complete Setup Example

```nix
{ config, pkgs, ... }:

{
  # Enable X11
  services.xserver.enable = true;

  # Enable i3wm
  services.i3wm = {
    enable = true;
    # ... i3 configuration
  };

  # Set default session
  services.displayManager.defaultSession = "none+i3";

  # Enable XRDP with i3
  services.xrdp = {
    enable = true;
    port = 3389;
    openFirewall = true;
    defaultWindowManager = "${pkgs.i3}/bin/i3";
    authMethod = "pam";
    audioRedirection = true;

    display = {
      resolution = "1920x1080";
      colorDepth = 24;
    };
  };

  # Enable PulseAudio for audio redirection
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
  };

  # Install PulseAudio XRDP module
  environment.systemPackages = [ pkgs.pulseaudio-module-xrdp ];
}
```

## Client Connection

### macOS
```bash
# Use Microsoft Remote Desktop
# Server: <hostname>:3389
# Username: <nixos-user>
# Password: <user-password>
```

### Windows
```powershell
# Use built-in Remote Desktop Connection
mstsc /v:<hostname>:3389
```

### Linux
```bash
# Using FreeRDP
xfreerdp /v:<hostname>:3389 /u:<username> /p:<password> /sound:sys:pulse

# Using Remmina (GUI)
remmina -c rdp://<username>@<hostname>:3389
```

## Validation Rules

The module performs the following validation:

### Port Validation
```nix
assertions = [
  {
    assertion = cfg.port >= 1 && cfg.port <= 65535;
    message = "XRDP port must be between 1 and 65535";
  }
];
```

### Window Manager Validation
```nix
assertions = [
  {
    assertion = cfg.defaultWindowManager != "" && pathExists cfg.defaultWindowManager;
    message = "XRDP defaultWindowManager must be a valid executable path";
  }
];
```

### Audio Validation
```nix
assertions = [
  {
    assertion = cfg.audioRedirection -> config.hardware.pulseaudio.enable;
    message = "XRDP audio redirection requires PulseAudio to be enabled";
  }
];
```

## Security Considerations

### Network Security
- XRDP uses TLS 1.2+ encryption by default
- Firewall should restrict access to trusted networks only
- Recommended: Use Tailscale VPN for remote access instead of public exposure

### Authentication
- PAM authentication integrates with system users
- Supports 1Password authentication via PAM
- Failed login attempts are logged to systemd journal

### Session Security
- Each user gets isolated X11 session
- Sessions run under user privileges (not root)
- X11 SECURITY extension enabled

## Troubleshooting

### Check Service Status
```bash
systemctl status xrdp
systemctl status xrdp-sesman
```

### View Logs
```bash
journalctl -u xrdp
journalctl -u xrdp-sesman
```

### Test Connection Locally
```bash
xfreerdp /v:localhost:3389 /u:$(whoami)
```

### Validate Configuration
```bash
# Check if port is listening
ss -tlnp | grep 3389

# Check firewall rules
nix-shell -p iptables --run "iptables -L -n | grep 3389"

# Verify certificate
openssl s_client -connect localhost:3389 -showcerts
```

## Migration Notes

### From Remote Access Module
If migrating from generic `modules/desktop/remote-access.nix`:

1. Extract XRDP-specific configuration
2. Move to `services.xrdp` options
3. Remove VNC-specific configuration if unused
4. Update `defaultWindowManager` to point to i3

### From Manual XRDP Configuration
If migrating from manually configured XRDP:

1. Copy settings from `/etc/xrdp/xrdp.ini` to module options
2. Copy session script from `/etc/xrdp/startwm.sh` to `defaultWindowManager`
3. Remove manual configuration files
4. Rebuild with module configuration

## Performance Tuning

### For Low Bandwidth
```nix
services.xrdp.extraConfig = ''
  [Xorg]
  bitmap_cache=yes
  bitmap_compression=yes
  bulk_compression=yes
'';
```

### For High Performance Networks
```nix
services.xrdp.display = {
  resolution = "2560x1440";
  colorDepth = 32;
};
```

## See Also

- [data-model.md](../data-model.md) - Complete data model documentation
- [i3wm-module.md](./i3wm-module.md) - i3 window manager module contract
- [quickstart.md](../quickstart.md) - Quick start guide for users
- [XRDP Documentation](http://xrdp.org/) - Official XRDP documentation

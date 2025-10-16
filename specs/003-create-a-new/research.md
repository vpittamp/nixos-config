# Research: MangoWC Desktop Environment for Hetzner Cloud

**Date**: 2025-10-16
**Branch**: `003-create-a-new`

This document consolidates research findings for implementing MangoWC compositor on NixOS Hetzner Cloud with remote desktop access.

## 1. Remote Desktop Protocol Selection

### Decision: wayvnc

**Rationale**: wayvnc is the only production-ready solution that fully supports:
- wlroots-based compositors in headless mode (MangoWC uses wlroots 0.19)
- Session persistence with client disconnection
- Concurrent multi-client connections
- PAM authentication (1Password-compatible)
- Stable NixOS packaging (v0.9.1)
- Proven headless QEMU/KVM operation
- Low latency (<3ms VNC ping) and efficient bandwidth (~12 Mbps)

### Alternatives Considered

**RustDesk (Wayland mode)**: REJECTED
- Experimental Wayland support is unreliable
- Requires physical display connection or dummy HDMI plug
- Headless mode produces black screens
- No PAM authentication support
- Not suitable for unattended headless access

**waypipe**: NOT APPLICABLE
- Application-level forwarding tool (like SSH X forwarding)
- Not designed for full desktop session remote access
- Cannot provide persistent desktop environment

### Trade-offs Accepted

**Audio redirection**: wayvnc has no built-in audio support. Must configure separate PulseAudio/PipeWire network streaming:
- Solution: PipeWire `module-protocol-pulse` on TCP port 4713
- Client connects VNC for video/input, PulseAudio protocol for audio
- One-time configuration, then transparent to user
- Alternative: Could use `pavucontrol` to manually redirect audio sinks

**VNC protocol limitations**: Less feature-rich than RDP (no bi-directional clipboard by default, no RemoteFX)
- Acceptable for development workstation use case
- VNC clipboard forwarding available via client configuration

### Implementation Requirements

**NixOS packages needed**:
- `pkgs.wayvnc` (v0.9.1) - VNC server
- MangoWC compositor (custom package from flake)
- `pkgs.tigervnc` or `pkgs.realvnc-vnc-viewer` (client-side, documentation)

**Configuration approach**:
```nix
# wayvnc configuration file
environment.etc."wayvnc/config".text = ''
  address=0.0.0.0
  port=5900
  enable_auth=true
  enable_pam=true  # Integrates with 1Password-backed PAM
'';

# Systemd service for wayvnc
systemd.services.wayvnc = {
  description = "WayVNC Server for MangoWC";
  after = [ "network.target" ];
  wantedBy = [ "multi-user.target" ];
  environment = {
    WAYLAND_DISPLAY = "wayland-1";
    XDG_RUNTIME_DIR = "/run/user/1000";
  };
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.wayvnc}/bin/wayvnc --gpu --max-fps 120";
    User = "vpittamp";
    Restart = "always";
  };
};
```

**Firewall configuration**:
- TCP port 5900 (VNC)
- TCP port 4713 (PulseAudio/PipeWire network audio)

## 2. MangoWC Compositor Packaging

### Decision: Use MangoWC flake as input

**Rationale**:
- MangoWC not yet available in nixpkgs
- Official flake exists: `github:DreamMaoMao/mangowc`
- Flake provides NixOS modules: `nixosModules.mango`
- Includes required dependencies (wlroots 0.19.1, scenefx, mmsg)

### Implementation Approach

**Add flake input to `/etc/nixos/flake.nix`**:
```nix
inputs = {
  # ... existing inputs ...
  mangowc = {
    url = "github:DreamMaoMao/mangowc";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

**Import MangoWC module in hetzner-mangowc.nix**:
```nix
imports = [
  inputs.mangowc.nixosModules.mango
];

programs.mangowc.enable = true;
```

### Alternatives Considered

**Package MangoWC manually**: REJECTED
- Reinventing wheel when official flake exists
- Would need to track upstream dependency versions (wlroots, scenefx)
- Flake already provides proper NixOS integration

**Wait for nixpkgs inclusion**: NOT FEASIBLE
- MangoWC is relatively new (2025 project)
- No timeline for nixpkgs submission
- Flake input is standard NixOS practice for non-nixpkgs packages

### Dependency Management

**Provided by MangoWC flake**:
- wlroots 0.19.1 (locked version)
- scenefx (window effects, from wlrfx/scenefx flake)
- mmsg (IPC library, from DreamMaoMao/mmsg flake)

**Additional system dependencies** (from MangoWC tutorial):
- foot (terminal emulator) - already in nixpkgs
- wmenu or rofi (application launcher) - already in nixpkgs
- swaybg (wallpaper) - already in nixpkgs
- grim, slurp (screenshots) - already in nixpkgs
- wl-clipboard (clipboard) - already in nixpkgs

## 3. Headless Compositor Configuration

### Decision: wlroots headless backend with virtual display

**Rationale**:
- wlroots provides `WLR_BACKENDS=headless` mode for no-physical-display operation
- Automatically creates virtual output (display)
- wayvnc captures from this virtual output
- Standard approach for headless Wayland compositors on servers

### Environment Variables Required

```nix
environment.variables = {
  # Use headless backend (no physical display needed)
  WLR_BACKENDS = "headless";

  # Disable requirement for input devices
  WLR_LIBINPUT_NO_DEVICES = "1";

  # Set virtual display resolution (client can override)
  WLR_HEADLESS_OUTPUTS = "1";  # Number of virtual displays
  # Resolution set via WLR_OUTPUT env or MangoWC config
};
```

### Virtual Display Resolution

**Default**: 1920x1080 (from spec assumptions)
**Configuration options**:
1. Environment variable: `WLR_OUTPUT_MODE=1920x1080`
2. wlr-randr utility: `wlr-randr --output HEADLESS-1 --mode 1920x1080`
3. MangoWC config: May support display configuration (need to verify)

**Client-side scaling**: VNC clients can scale display resolution independent of server

### Alternatives Considered

**DRM/KMS backend with virtual GPU**: NOT NEEDED
- Hetzner QEMU VM doesn't expose virtio-gpu
- Software rendering (llvmpipe) sufficient for remote desktop
- Headless backend simpler and purpose-built

## 4. Session Management Strategy

### Decision: User-level systemd service with linger

**Rationale**:
- MangoWC session must persist when no VNC clients connected
- User-level systemd service enables per-user compositor instance
- `loginctl enable-linger` keeps user session active on boot
- Matches current Hetzner architecture (SDDM disabled, no console session)

### Service Architecture

```nix
# Enable user lingering (session persists without login)
users.users.vpittamp.linger = true;

# User-level MangoWC service (via home-manager)
systemd.user.services.mangowc = {
  Unit = {
    Description = "MangoWC Wayland Compositor";
    After = [ "graphical-session-pre.target" ];
    PartOf = [ "graphical-session.target" ];
  };

  Service = {
    Type = "simple";
    ExecStart = "${pkgs.mangowc}/bin/mango";
    Restart = "on-failure";
    # Set environment for headless operation
    Environment = [
      "WLR_BACKENDS=headless"
      "WLR_LIBINPUT_NO_DEVICES=1"
    ];
  };

  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};

# wayvnc starts after MangoWC compositor is available
systemd.user.services.wayvnc = {
  Unit = {
    Description = "WayVNC Server";
    After = [ "mangowc.service" ];
    Requires = [ "mangowc.service" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${pkgs.wayvnc}/bin/wayvnc --gpu --max-fps 120";
    Restart = "always";
  };
  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

### Alternatives Considered

**System-level compositor service**: REJECTED
- Compositor needs user session context (XDG_RUNTIME_DIR, Wayland socket)
- User-level service cleaner separation
- Matches Wayland best practices

**Display manager (SDDM/GDM) integration**: NOT APPLICABLE
- Hetzner config explicitly disables SDDM (headless)
- Don't want console session competing with VNC session
- Manual service management gives better control

## 5. Audio Configuration Strategy

### Decision: PipeWire with network audio module

**Rationale**:
- Modern audio system (already used on M1 config)
- Native network audio support via PulseAudio compatibility
- Better than PulseAudio for Wayland (session management)
- Can coexist with existing Hetzner PulseAudio config

### Implementation Approach

```nix
# Enable PipeWire with PulseAudio compatibility
services.pipewire = {
  enable = true;
  pulse.enable = true;  # PulseAudio compatibility layer
  alsa.enable = true;

  extraConfig.pipewire = {
    "context.modules" = [
      {
        name = "libpipewire-module-protocol-pulse";
        args = {
          "server.address" = [ "tcp:0.0.0.0:4713" ];
        };
      }
    ];
  };
};

# Disable conflicting PulseAudio
hardware.pulseaudio.enable = lib.mkForce false;

# Firewall for PulseAudio protocol
networking.firewall.allowedTCPPorts = [ 4713 ];
```

### Client-Side Configuration

Users configure VNC client to connect audio separately:
1. VNC connection: `hetzner.example.com:5900`
2. Audio connection: Configure PulseAudio client to connect to `tcp:hetzner.example.com:4713`

**Tools**:
- `pactl` - Configure PulseAudio sinks/sources
- `pavucontrol` - GUI audio control (can run in VNC session)

### Alternatives Considered

**PulseAudio (current Hetzner setup)**: CONSIDERED
- Current Hetzner config uses PulseAudio with XRDP module
- PipeWire preferred for Wayland sessions (better integration)
- PulseAudio network audio equally functional
- Decision: Switch to PipeWire for consistency with M1 config

**No audio**: NOT ACCEPTABLE
- Spec requires audio redirection (FR-012)
- Development workstation needs audio for meetings, media

## 6. Configuration File Management

### Decision: Declarative generation via environment.etc

**Rationale**:
- Follows NixOS constitution (declarative over imperative)
- MangoWC config.conf is plain text (easy to template)
- Reproducible across rebuilds
- Users can override via home-manager if needed

### MangoWC Configuration Strategy

```nix
# System-level default config
environment.etc."mangowc/config.conf".text = ''
  # Default keybindings from tutorial
  bind=Alt,Return,spawn,foot
  bind=Super,d,spawn,${pkgs.wmenu}/bin/wmenu-run -l 10
  bind=Alt,q,killclient,
  bind=Super,r,reload_config

  # Workspace switching (Ctrl+1-9)
  bind=Ctrl,1,view,1,0
  bind=Ctrl,2,view,2,0
  # ... etc for 3-9

  # Window movement (Alt+1-9)
  bind=Alt,1,tag,1,0
  bind=Alt,2,tag,2,0
  # ... etc for 3-9

  # Layout switching
  bind=Super,n,switch_layout

  # Window focus (arrow keys)
  bind=ALT,Left,focusdir,left
  bind=ALT,Right,focusdir,right
  bind=ALT,Up,focusdir,up
  bind=ALT,Down,focusdir,down

  # Appearance (headless defaults)
  borderpx=4
  rootcolor=0x201b14ff
  focuscolor=0xc9b890ff

  # Layouts (at least tile, scroller, monocle per spec)
  tagrule=id:1,layout_name:tile
  tagrule=id:2,layout_name:scroller
  tagrule=id:3,layout_name:monocle
  # ... etc for tags 4-9
'';

# Autostart script
environment.etc."mangowc/autostart.sh" = {
  mode = "0755";
  text = ''
    #!/bin/sh
    # Wallpaper (if desired)
    ${pkgs.swaybg}/bin/swaybg -i /etc/nixos/assets/wallpapers/default.png &

    # Status bar (waybar could be added later)
    # ${pkgs.waybar}/bin/waybar &
  '';
};
```

### User Customization Path

Users can override via home-manager:
```nix
# home-modules/tools/mangowc-config.nix
home.file.".config/mango/config.conf".text = ''
  # User-specific keybindings
  # Overrides system defaults
'';
```

### Alternatives Considered

**Home-manager only**: REJECTED
- System-level defaults provide sensible baseline
- New users get working config immediately
- Can still customize via home-manager overlay

**Manual configuration**: REJECTED (violates constitution)
- Imperative approach breaks reproducibility
- Config drift between rebuilds

## 7. Package Profile Assignment

### Decision: Development profile

**Rationale**:
- MangoWC is a desktop environment (not minimal tool)
- Hetzner uses "development" or "full" profiles already
- MangoWC packages are small (~30-40MB total)
- Containers/minimal systems wouldn't use graphical compositor

### Package Additions

Add to system packages (not profile-specific since desktop-specific):
```nix
environment.systemPackages = with pkgs; [
  # MangoWC provided by flake input

  # Companion tools (from MangoWC tutorial)
  foot          # Terminal emulator
  wmenu         # Application launcher (Wayland dmenu)
  rofi-wayland  # Alternative launcher
  swaybg        # Wallpaper
  grim          # Screenshot tool
  slurp         # Screen area selection
  wl-clipboard  # Clipboard utilities

  # Remote desktop
  wayvnc        # VNC server

  # Audio (via services, not direct package)
  # pipewire, pulseaudio via services.pipewire

  # Utilities
  wlr-randr     # Display configuration
  wev           # Wayland event viewer (debugging)
];
```

## 8. Firewall and Network Configuration

### Decision: Open VNC (5900) and PulseAudio (4713) ports

**Rationale**:
- Follows existing Hetzner firewall pattern (opens 3389 for XRDP)
- VNC standard port is 5900
- PulseAudio protocol standard port is 4713
- Tailscale VPN already provides secure access channel

### Configuration

```nix
networking.firewall = {
  allowedTCPPorts = [
    22     # SSH (existing)
    5900   # VNC (wayvnc)
    4713   # PulseAudio/PipeWire network audio
    # 3389 # RDP (XRDP) - remove or keep for KDE Plasma fallback
  ];

  # Tailscale (existing)
  checkReversePath = "loose";
};
```

### Security Considerations

**Authentication layers**:
1. Tailscale VPN (primary access control)
2. wayvnc PAM authentication (1Password-backed)
3. SSH key authentication (optional tunneling)

**Encryption**:
- wayvnc supports TLS encryption (optional, can enable later)
- Tailscale provides WireGuard encryption
- SSH tunneling available as additional layer

### Alternatives Considered

**SSH tunneling only**: CONSIDERED
- More secure (no exposed ports)
- Adds latency and complexity
- Decision: Direct access acceptable with Tailscale + PAM auth
- Can document SSH tunnel approach for extra-paranoid users

## 9. Documentation Requirements

### Documents to Create

1. **`docs/MANGOWC_SETUP.md`**
   - Installation instructions
   - VNC client configuration (TigerVNC, RealVNC, etc.)
   - Audio setup (PulseAudio client config)
   - Troubleshooting guide
   - Switching between KDE Plasma and MangoWC configurations

2. **`docs/MANGOWC_KEYBINDINGS.md`**
   - Complete keybinding reference
   - Organized by category (workspaces, windows, layouts, apps)
   - Comparison with KDE Plasma shortcuts
   - Customization guide

3. **Update `CLAUDE.md`**
   - Add hetzner-mangowc build commands
   - Quick start section for MangoWC
   - Troubleshooting tips

4. **Update `README.md`**
   - Add hetzner-mangowc to configuration targets
   - Brief description and use case

### Module Documentation

Inline comments in `modules/desktop/mangowc.nix`:
- Purpose and architecture
- Headless operation explanation
- Session management approach
- Audio configuration rationale
- Customization instructions

## Summary of Decisions

| Area | Decision | Key Rationale |
|------|----------|---------------|
| Remote Desktop Protocol | wayvnc | wlroots-compatible, session persistence, PAM auth, NixOS stable |
| MangoWC Packaging | Flake input | Official flake exists, includes NixOS module |
| Headless Operation | wlroots headless backend | Purpose-built for no-display compositors |
| Session Management | User systemd + linger | Persistent session, clean separation |
| Audio | PipeWire network module | Modern Wayland audio, PulseAudio compatibility |
| Configuration | Declarative via environment.etc | NixOS constitution requirement |
| Package Profile | Development profile | Desktop environment scope |
| Firewall | Open VNC (5900) + Audio (4713) | Standard ports, Tailscale security layer |

## Open Questions

None remaining. All technical decisions finalized with sufficient research.

## Next Steps (Phase 1)

1. Create `data-model.md` - Configuration data structures
2. Create `contracts/mangowc-module-options.md` - NixOS module interface
3. Create `quickstart.md` - User quick start guide
4. Update agent context files with technology stack

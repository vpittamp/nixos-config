# Quick Start: MangoWC on Hetzner Cloud

**Date**: 2025-10-16
**Branch**: `003-create-a-new`

Get up and running with MangoWC desktop environment on your Hetzner Cloud NixOS server in minutes.

## Prerequisites

- Hetzner Cloud NixOS server (existing configuration at `/etc/nixos`)
- SSH access to the server
- VNC client installed locally (TigerVNC, RealVNC, or built-in OS VNC viewer)
- Basic familiarity with NixOS

## Step 1: Build the Configuration

From your local machine (or directly on Hetzner server):

```bash
cd /etc/nixos

# Test the build (dry-run, no changes)
sudo nixos-rebuild dry-build --flake .#hetzner-mangowc

# If build succeeds, apply the configuration
sudo nixos-rebuild switch --flake .#hetzner-mangowc
```

**Expected output**:
```
building the system configuration...
activating the configuration...
setting up /etc...
reloading user units for vpittamp...
setting up tmpfiles
```

**Build time**: 2-5 minutes (depending on package downloads)

## Step 2: Verify Services are Running

```bash
# Check MangoWC compositor status
systemctl --user status mangowc.service

# Check wayvnc remote desktop status
systemctl --user status wayvnc.service

# Check PipeWire audio status
systemctl --user status pipewire.service
```

All services should show `active (running)`.

**Troubleshooting**:
- If services fail to start, check logs: `journalctl --user -u mangowc.service -f`
- Ensure user linger is enabled: `loginctl enable-linger vpittamp`

## Step 3: Connect via VNC

### From macOS

```bash
# Use built-in Screen Sharing
open vnc://your-hetzner-ip:5900

# Or from command line
open vnc://vpittamp@your-hetzner-ip:5900
```

### From Windows

1. Install TigerVNC Viewer: https://tigervnc.org/
2. Run TigerVNC Viewer
3. Enter server address: `your-hetzner-ip:5900`
4. When prompted, enter your system password (managed by 1Password)

### From Linux

```bash
# Using TigerVNC
vncviewer your-hetzner-ip:5900

# Or using Remmina (GUI)
remmina -c vnc://your-hetzner-ip:5900
```

**Authentication**: Use your NixOS user password (synchronized via 1Password)

**First connection**: May take 5-10 seconds to establish and display desktop

## Step 4: Configure Audio (Optional)

If you need audio playback:

### macOS / Linux (PulseAudio)

```bash
# Load PulseAudio tunnel module (run on local machine)
pactl load-module module-tunnel-sink server=tcp:your-hetzner-ip:4713

# Set as default audio output
pacmd set-default-sink tunnel.your-hetzner-ip.tcp

# Test audio
paplay /usr/share/sounds/alsa/Front_Center.wav
```

### Windows (PulseAudio)

1. Install PulseAudio for Windows: https://www.freedesktop.org/wiki/Software/PulseAudio/Ports/Windows/Support/
2. Edit `%USERPROFILE%\.config\pulse\default.pa`:
   ```
   load-module module-tunnel-sink server=tcp:your-hetzner-ip:4713
   ```
3. Restart PulseAudio service

**Alternative**: Use `pavucontrol` (audio mixer) inside the VNC session to configure audio

## Step 5: Learn Basic Keybindings

Once connected via VNC, try these essentials:

### Application Launching

- **Alt + Enter**: Open foot terminal
- **Super + d**: Open application launcher (rofi)
- **Alt + q**: Close focused window

### Workspace Navigation

- **Ctrl + 1-9**: Switch to workspace 1-9
- **Alt + 1-9**: Move current window to workspace 1-9

### Window Management

- **Alt + Arrow Keys**: Focus window in direction
- **Super + n**: Switch window layout (tile → scroller → monocle → ...)
- **Alt + \\**: Toggle floating mode
- **Alt + f**: Toggle fullscreen

### System

- **Super + r**: Reload configuration
- **Super + m**: Quit MangoWC (logs out)

**Full keybinding reference**: See `/etc/nixos/docs/MANGOWC_KEYBINDINGS.md`

## Step 6: Customize Configuration (Optional)

Edit the Hetzner-MangoWC configuration:

```bash
# Edit main configuration
sudo nano /etc/nixos/configurations/hetzner-mangowc.nix

# Add custom keybindings
services.mangowc.keybindings = {
  "SUPER,b" = "spawn,firefox";
  "SUPER,e" = "spawn,nautilus";
};

# Change appearance
services.mangowc.appearance = {
  borderWidth = 2;
  focusColor = "0x00ff00ff";  # Green focused border
};

# Rebuild to apply changes
sudo nixos-rebuild switch --flake .#hetzner-mangowc
```

**In-session reload**: Press `Super + r` to reload config without rebuilding

## Switching Between KDE Plasma and MangoWC

MangoWC and KDE Plasma coexist as separate NixOS configurations:

### Switch to MangoWC
```bash
sudo nixos-rebuild switch --flake .#hetzner-mangowc
```

### Switch back to KDE Plasma
```bash
sudo nixos-rebuild switch --flake .#hetzner
```

**Note**: Both configurations maintain separate desktop environments. Your files and settings persist regardless of which desktop you use.

## Common Tasks

### Take a Screenshot

```bash
# Interactive area selection
grim -g "$(slurp)" ~/screenshot.png

# Fullscreen
grim ~/screenshot.png

# Copy to clipboard
grim -g "$(slurp)" - | wl-copy
```

### Change Wallpaper

```bash
# Edit autostart script
sudo nano /etc/nixos/configurations/hetzner-mangowc.nix

# Update autostart section
services.mangowc.autostart = ''
  swaybg -i /path/to/your/wallpaper.png &
'';

# Rebuild
sudo nixos-rebuild switch --flake .#hetzner-mangowc
```

### Install Additional Applications

```bash
# Edit configuration
sudo nano /etc/nixos/configurations/hetzner-mangowc.nix

# Add packages
environment.systemPackages = with pkgs; [
  firefox
  vscode
  gimp
];

# Rebuild
sudo nixos-rebuild switch --flake .#hetzner-mangowc
```

## Troubleshooting

### VNC Connection Refused

**Problem**: Cannot connect to VNC server

**Solutions**:
1. Check firewall allows port 5900:
   ```bash
   sudo nft list ruleset | grep 5900
   ```
2. Verify wayvnc is running:
   ```bash
   systemctl --user status wayvnc.service
   ```
3. Check Tailscale/VPN connectivity if using private network

### Black Screen After Connecting

**Problem**: VNC connects but shows black screen

**Solutions**:
1. Check MangoWC compositor is running:
   ```bash
   systemctl --user status mangowc.service
   ```
2. Verify headless backend environment:
   ```bash
   journalctl --user -u mangowc.service | grep WLR_BACKENDS
   ```
3. Restart services:
   ```bash
   systemctl --user restart mangowc.service wayvnc.service
   ```

### Authentication Failed

**Problem**: VNC rejects password

**Solutions**:
1. Verify 1Password password management is active:
   ```bash
   sudo systemctl status onepassword-password-management.service
   ```
2. Check PAM configuration:
   ```bash
   cat /etc/wayvnc/config | grep enable_pam
   ```
3. Try SSH into server to verify system password works

### No Audio

**Problem**: Audio doesn't play on client

**Solutions**:
1. Verify PipeWire network audio is enabled:
   ```bash
   systemctl --user status pipewire.service
   netstat -tln | grep 4713
   ```
2. Check firewall allows port 4713:
   ```bash
   sudo nft list ruleset | grep 4713
   ```
3. Configure PulseAudio tunnel on client (see Step 4)

### Performance Issues / Lag

**Problem**: VNC session is slow or laggy

**Solutions**:
1. Reduce VNC frame rate:
   ```nix
   services.wayvnc.maxFPS = 60;  # Lower from default 120
   ```
2. Check network bandwidth:
   ```bash
   iperf3 -c your-hetzner-ip
   ```
3. Use wired connection instead of WiFi on client
4. Consider SSH tunneling for better compression

## Next Steps

- **Learn more keybindings**: Read `/etc/nixos/docs/MANGOWC_KEYBINDINGS.md`
- **Customize appearance**: See `data-model.md` for all appearance options
- **Add status bar**: Install waybar for system information
- **Configure workspaces**: Assign default layouts per workspace
- **Setup clipboard sync**: Install wl-clipboard and cliphist

## Getting Help

- **Logs**: `journalctl --user -u mangowc.service -u wayvnc.service -f`
- **MangoWC Documentation**: https://github.com/DreamMaoMao/mango/wiki/
- **wayvnc Documentation**: https://github.com/any1/wayvnc
- **NixOS Manual**: https://nixos.org/manual/nixos/stable/

## Performance Tips

1. **Use Tailscale VPN**: Significantly improves security and often reduces latency
2. **Close unused applications**: Keep only needed apps in workspaces
3. **Disable animations**: Set `animations=0` in config for better performance
4. **Use keyboard shortcuts**: Faster than mouse for window management
5. **Optimize VNC settings**: Lower FPS or resolution if experiencing lag

---

**Estimated setup time**: 15-20 minutes (including initial build)

**System requirements**:
- Hetzner Cloud CX21 or higher (2 vCPUs, 4GB RAM minimum)
- 10+ Mbps network connection for VNC
- VNC client (any platform)

You're now running MangoWC on Hetzner Cloud! Enjoy your lightweight Wayland desktop environment.

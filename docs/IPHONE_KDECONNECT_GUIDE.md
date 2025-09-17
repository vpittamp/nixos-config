# iPhone + KDE Connect Setup Guide

## Prerequisites
✅ KDE Connect is installed and running on your NixOS system (confirmed)
✅ iPhone and NixOS machine must be on the **same network**

## Step 1: Install KDE Connect on iPhone

1. Open the **App Store** on your iPhone
2. Search for **"KDE Connect"**
3. Install the app (free, by KDE e.V.)
4. **Important**: The iOS version is limited compared to Android

## Step 2: Network Requirements

Both devices MUST be on the same network. Since you're using Hetzner Cloud:

### Option A: Tailscale/VPN (Recommended)
If you have Tailscale or another VPN:
1. Connect iPhone to the same Tailscale network
2. KDE Connect will work over the VPN

### Option B: Local Network Testing
For testing when you're local:
1. Connect iPhone to your local WiFi
2. Use SSH tunnel to forward KDE Connect ports:
   ```bash
   # From your Windows machine
   ssh -L 1716:localhost:1716 vpittamp@<hetzner-ip>
   ```

### Option C: Direct Internet (NOT Recommended)
Opening KDE Connect to the internet is a security risk, but if needed:
1. You would need to open ports 1714-1764 TCP/UDP in Hetzner firewall
2. Not recommended due to security implications

## Step 3: Connect iPhone to KDE Connect

### On iPhone:
1. Open **KDE Connect** app
2. Make sure WiFi is enabled
3. The app will automatically search for devices
4. Your NixOS system should appear as "nixos-hetzner"

### On NixOS:
1. Open KDE Connect from application menu or system tray
2. Click "Refresh" to search for devices
3. Your iPhone should appear in the device list

### Alternative: Use CLI
```bash
# List available devices
kdeconnect-cli -l

# If iPhone appears, request pairing
kdeconnect-cli --pair -d <device-id>
```

## Step 4: Pair Devices

1. **On iPhone**: Tap on your computer name when it appears
2. **On NixOS**: Accept the pairing request notification
3. **Verify**: Both devices will show a pairing code - make sure they match
4. **Accept** on both devices

## Step 5: Test Connection

Test what works on iPhone:
```bash
# Send a file from NixOS to iPhone
kdeconnect-cli -d <device-id> --share /path/to/file

# Check battery level
kdeconnect-cli -d <device-id> --battery

# List all available plugins
kdeconnect-cli -d <device-id> --list-plugins
```

## Working Features with iPhone

✅ **What Works:**
- File sharing (both directions)
- Clipboard sync
- Media remote control
- Battery indicator
- Find my phone (plays sound)
- Photo/video transfer

❌ **What DOESN'T Work (iOS Limitations):**
- SMS/notification sync
- Remote input (use phone as keyboard/mouse)
- Remote commands
- Contacts sync
- Telephony features

## Troubleshooting

### iPhone doesn't appear:
1. **Check network**: Both must be on same network/subnet
   ```bash
   # On NixOS, check IP
   ip addr show

   # On iPhone: Settings → WiFi → (i) → IP Address
   # First 3 octets should match (e.g., 192.168.1.x)
   ```

2. **Restart services**:
   ```bash
   # Kill and restart KDE Connect
   killall kdeconnectd
   kdeconnect-app &
   ```

3. **Check firewall**:
   ```bash
   # Temporarily disable firewall for testing
   sudo systemctl stop firewall
   # Test connection
   # Then re-enable
   sudo systemctl start firewall
   ```

### Connection drops frequently:
- iOS aggressively manages background apps
- Keep KDE Connect app open on iPhone
- Enable "Background App Refresh" for KDE Connect in iPhone Settings

### Can't send files from iPhone:
- iOS requires explicit permission for each file
- Use the "Share" button in Photos/Files app
- Select "KDE Connect" from share sheet

## Alternative Solutions for iPhone

Since KDE Connect is limited on iOS, consider:

### For File Transfer:
- **Syncthing** - Better continuous sync
- **NextCloud** - Self-hosted cloud storage
- **LocalSend** - Cross-platform local file sharing

### For Remote Control:
- **VNC Viewer** - Full desktop control
- **TeamViewer** - Remote desktop
- **Chrome Remote Desktop** - Browser-based

### For Clipboard Sync:
- **Universal Clipboard** (if using Mac as intermediary)
- **Pushbullet** - Cross-platform notifications and clipboard

## Using KDE Connect Over Internet (Hetzner)

Since your NixOS is on Hetzner, the iPhone won't be on the same local network. Options:

1. **Best: Use Tailscale**
   ```bash
   # Check if Tailscale is installed
   tailscale status
   ```
   Install Tailscale on iPhone and connect both devices to same Tailnet

2. **SSH Tunnel Method** (when on same local network as Windows):
   ```bash
   # From Windows/WSL
   ssh -L 1714-1764:localhost:1714-1764 vpittamp@<hetzner-ip>
   ```
   This won't work well due to port range requirements

3. **Port Forwarding** (Security Risk):
   Only as last resort - exposes KDE Connect to internet

## Command Reference

```bash
# List all devices (including non-paired)
kdeconnect-cli --list-available

# Pair with specific device
kdeconnect-cli --pair -d <device-id>

# Send file
kdeconnect-cli --share <file> -d <device-id>

# Ring phone
kdeconnect-cli --ring -d <device-id>

# Check if reachable
kdeconnect-cli --ping -d <device-id>

# Unpair device
kdeconnect-cli --unpair -d <device-id>
```

---
**Note**: Due to iOS sandbox restrictions, KDE Connect on iPhone is significantly limited compared to Android. For full functionality, consider using an Android device or the alternative solutions listed above.
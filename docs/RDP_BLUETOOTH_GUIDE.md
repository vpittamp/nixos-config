# RDP Bluetooth Device Redirection Guide

## Current Limitation
**Direct Bluetooth passthrough via RDP is NOT supported** by the RDP protocol. RDP does not have a Bluetooth redirection channel.

## What RDP CAN Redirect
With the enhanced configuration in `modules/desktop/remote-access.nix`:

1. **Audio Devices** - Bluetooth headphones/speakers that appear as audio devices
2. **USB Devices** - If your Bluetooth adapter is USB-based
3. **Drives** - Storage devices
4. **Clipboard** - Copy/paste between host and remote
5. **Printers** - Network and local printers
6. **Smart Cards** - Authentication devices

## Workarounds for Bluetooth Devices

### Option 1: Audio-Only Devices (Headphones/Speakers)
If your Bluetooth device is audio-only:

**On Windows Host:**
1. Connect Bluetooth device to Windows
2. In RDP connection settings, enable "Play on this computer" for audio
3. The audio will redirect through RDP's audio channel

**In mstsc.exe (Windows Remote Desktop):**
- Go to "Show Options" → "Local Resources" tab
- Under "Remote audio", click "Settings"
- Select "Play on this computer" and "Record from this computer"

### Option 2: USB Bluetooth Dongle Redirection
For full Bluetooth functionality:

**Requirements:**
- USB Bluetooth adapter (not built-in)
- RemoteFX USB Redirection (Windows Pro/Enterprise)

**Setup:**
1. Plug USB Bluetooth adapter into Windows host
2. In RDP settings, redirect the USB device:
   - "Show Options" → "Local Resources" → "More..."
   - Find and check your Bluetooth USB adapter
3. The adapter will appear in NixOS as a local USB device

### Option 3: USB/IP Solution (Network USB)
Share USB devices over network using USB/IP:

**On Windows Host:**
1. Install VirtualHere Server (or similar USB/IP server)
2. Share the Bluetooth adapter through USB/IP

**On NixOS (already configured):**
```bash
# List available USB devices from Windows host
usbip list -r <windows-host-ip>

# Attach the Bluetooth adapter
sudo usbip attach -r <windows-host-ip> -b <bus-id>

# The Bluetooth adapter now appears as local
bluetoothctl
```

### Option 4: KDE Connect + Phone as Bridge
For keyboard/mouse/media control:

1. Install KDE Connect on your phone
2. Pair phone with Windows host via Bluetooth
3. Connect phone to NixOS via KDE Connect (over network)
4. Use phone as a bridge for input devices

## Configuration Applied

The following has been configured in your system:

1. **XRDP Enhanced Settings:**
   - Drive redirection enabled
   - Clipboard streaming enabled
   - Printer redirection enabled
   - Smart card support enabled
   - Maximum color depth (32-bit)

2. **USB/IP Support:**
   - Kernel modules loaded (vhci-hcd, usbip-core, usbip-host)
   - USB/IP tools installed

3. **Audio Optimization:**
   - PulseAudio network streaming configured
   - Reduced audio latency for RDP

## Testing Your Setup

### For Audio Devices:
```bash
# Check if audio is redirecting
pactl list sources
pactl list sinks

# Test audio playback
speaker-test -t wav -c 2
```

### For USB Devices:
```bash
# List USB devices
lsusb

# Check for Bluetooth adapters
hciconfig -a
rfkill list

# If using USB/IP
sudo usbip list -l
```

## Recommendations

1. **For Audio:** Use RDP's built-in audio redirection
2. **For Keyboards/Mice:** Consider using a USB receiver (Logitech Unifying, etc.) and redirect as USB
3. **For Full Bluetooth:** Use a USB Bluetooth adapter with USB redirection
4. **For File Transfer:** Use KDE Connect which works over network

## Alternative: NoMachine/X2Go
If Bluetooth support is critical, consider alternatives to RDP:
- **NoMachine** - Better device redirection support
- **X2Go** - Open source with good peripheral support
- **VNC with USB/IP** - Manual but flexible

## Troubleshooting

If devices don't appear after redirection:
```bash
# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check kernel messages
dmesg | grep -i bluetooth

# Verify USB redirection
lsusb -v | grep -i bluetooth
```

---
*Note: Full Bluetooth passthrough requires either USB redirection of the Bluetooth adapter or using the device as audio-only through RDP's audio channel.*
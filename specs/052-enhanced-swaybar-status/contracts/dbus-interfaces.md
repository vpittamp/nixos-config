# D-Bus Interface Contracts

**Feature**: Enhanced Swaybar Status
**Protocol**: D-Bus (freedesktop.org standard)
**Version**: 1.0

## Overview

The status generator queries system state via D-Bus interfaces provided by system services. All interfaces follow the freedesktop.org D-Bus specification.

## 1. UPower Interface (Battery)

### Service Details
- **Bus**: System bus
- **Service Name**: `org.freedesktop.UPower`
- **Object Path**: `/org/freedesktop/UPower/devices/battery_BAT0`
- **Interface**: `org.freedesktop.UPower.Device`

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `Percentage` | double | Battery charge percentage (0-100) |
| `State` | uint32 | Charging state: 0=Unknown, 1=Charging, 2=Discharging, 3=Empty, 4=Fully charged |
| `TimeToEmpty` | int64 | Seconds until battery is empty (0 if charging/unknown) |
| `TimeToFull` | int64 | Seconds until battery is full (0 if discharging/unknown) |
| `IsPresent` | boolean | Battery is present |
| `PowerSupply` | boolean | Device is a power supply |
| `Type` | uint32 | Device type: 2=Battery |

### Signals

| Signal | Parameters | Description |
|--------|------------|-------------|
| `PropertiesChanged` | interface, changed_properties, invalidated_properties | Emitted when properties change |

### Example Query (Python)
```python
import pydbus

bus = pydbus.SystemBus()
battery = bus.get('org.freedesktop.UPower', '/org/freedesktop/UPower/devices/battery_BAT0')

percentage = battery.Percentage
state = battery.State
time_to_empty = battery.TimeToEmpty
```

### Example Signal Subscription
```python
def on_battery_changed(interface, changed, invalidated):
    if 'Percentage' in changed or 'State' in changed:
        update_battery_status()

battery.PropertiesChanged.connect(on_battery_changed)
```

---

## 2. NetworkManager Interface (WiFi)

### Service Details
- **Bus**: System bus
- **Service Name**: `org.freedesktop.NetworkManager`
- **Object Path**: `/org/freedesktop/NetworkManager`
- **Interface**: `org.freedesktop.NetworkManager`

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `State` | uint32 | Network state: 70=Connected globally, 50=Connected locally, 30=Connecting, 20=Disconnected |
| `ActiveConnections` | array of object paths | Active connection paths |
| `Devices` | array of object paths | Network device paths |

### Device Properties
- **Object Path**: `/org/freedesktop/NetworkManager/Devices/X`
- **Interface**: `org.freedesktop.NetworkManager.Device.Wireless`

| Property | Type | Description |
|----------|------|-------------|
| `ActiveAccessPoint` | object path | Currently connected access point |
| `HwAddress` | string | Hardware MAC address |

### Access Point Properties
- **Object Path**: (from ActiveAccessPoint)
- **Interface**: `org.freedesktop.NetworkManager.AccessPoint`

| Property | Type | Description |
|----------|------|-------------|
| `Ssid` | array of bytes | Network SSID (convert to string) |
| `Strength` | byte | Signal strength (0-100) |

### Signals

| Signal | Parameters | Description |
|--------|------------|-------------|
| `StateChanged` | new_state, old_state, reason | Network state change |
| `PropertiesChanged` | changed_properties | Property change |

### Example Query (Python)
```python
import pydbus

bus = pydbus.SystemBus()
nm = bus.get('org.freedesktop.NetworkManager')

# Get WiFi device
devices = nm.GetDevices()
wifi_device = None
for dev_path in devices:
    dev = bus.get('org.freedesktop.NetworkManager', dev_path)
    if dev.DeviceType == 2:  # WiFi device
        wifi_device = bus.get('org.freedesktop.NetworkManager.Device.Wireless', dev_path)
        break

if wifi_device and wifi_device.ActiveAccessPoint != '/':
    ap = bus.get('org.freedesktop.NetworkManager.AccessPoint', wifi_device.ActiveAccessPoint)
    ssid = bytes(ap.Ssid).decode('utf-8')
    strength = ap.Strength
```

---

## 3. BlueZ Interface (Bluetooth)

### Service Details
- **Bus**: System bus
- **Service Name**: `org.bluez`
- **Object Path**: `/org/bluez/hci0` (adapter)
- **Interface**: `org.bluez.Adapter1`

### Adapter Properties

| Property | Type | Description |
|----------|------|-------------|
| `Powered` | boolean | Adapter is powered on |
| `Discovering` | boolean | Discovery is active |
| `Name` | string | Adapter name |
| `Address` | string | Adapter MAC address |

### Device Properties
- **Object Path**: `/org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX`
- **Interface**: `org.bluez.Device1`

| Property | Type | Description |
|----------|------|-------------|
| `Name` | string | Device name |
| `Address` | string | Device MAC address |
| `Connected` | boolean | Device is connected |
| `Paired` | boolean | Device is paired |

### Signals

| Signal | Parameters | Description |
|--------|------------|-------------|
| `PropertiesChanged` | interface, changed, invalidated | Property change |

### Example Query (Python)
```python
import pydbus

bus = pydbus.SystemBus()
adapter = bus.get('org.bluez', '/org/bluez/hci0')

enabled = adapter.Powered

# Get connected devices
om = bus.get('org.bluez', '/')
objects = om.GetManagedObjects()
devices = []
for path, interfaces in objects.items():
    if 'org.bluez.Device1' in interfaces:
        device_props = interfaces['org.bluez.Device1']
        if device_props.get('Connected', False):
            devices.append({
                'name': device_props.get('Name', 'Unknown'),
                'address': device_props.get('Address'),
                'connected': True
            })
```

---

## 4. PulseAudio Interface (Volume)

### Service Details (via D-Bus)
- **Bus**: Session bus
- **Service Name**: `org.PulseAudio1` (if available)
- **Alternative**: Use `pactl` command-line tool (more reliable)

### Properties (D-Bus - if available)
- **Object Path**: `/org/pulseaudio/core1`
- **Interface**: `org.PulseAudio.Core1`

**Note**: PulseAudio D-Bus support is optional and not always enabled.

### Recommended Approach: pactl Command

Since PulseAudio D-Bus may not be available, use `pactl` subprocess:

```python
import subprocess
import json

def get_volume_state():
    # Get default sink
    result = subprocess.run(['pactl', 'get-default-sink'], capture_output=True, text=True)
    sink_name = result.stdout.strip()

    # Get sink info
    result = subprocess.run(['pactl', '-f', 'json', 'list', 'sinks'], capture_output=True, text=True)
    sinks = json.loads(result.stdout)

    for sink in sinks:
        if sink['name'] == sink_name:
            volume = sink['volume']['front-left']['value_percent'].rstrip('%')
            muted = sink['mute']
            return {
                'level': int(volume),
                'muted': muted,
                'sink_name': sink_name
            }
```

### Volume Change Detection

Monitor volume changes via polling (every 1 second) or subscribe to PulseAudio events:

```bash
# Subscribe to PulseAudio events
pactl subscribe
# Output example:
# Event 'change' on sink #0
```

Parse event output and trigger status update.

---

## 5. PipeWire Interface (Volume - Alternative)

### Service Details
- **Bus**: Session bus
- **Service Name**: `org.freedesktop.portal.Desktop`
- **Interface**: `org.freedesktop.portal.Settings`

**Note**: PipeWire may use XDG Desktop Portal for settings, but direct volume control is typically via `wpctl` command.

### Recommended Approach: wpctl Command

```python
import subprocess

def get_volume_state():
    # Get default sink ID
    result = subprocess.run(['wpctl', 'status'], capture_output=True, text=True)
    # Parse output to find default sink ID

    # Get volume for sink
    result = subprocess.run(['wpctl', 'get-volume', '@DEFAULT_SINK@'], capture_output=True, text=True)
    # Output: "Volume: 0.75 [MUTED]" or "Volume: 0.75"

    output = result.stdout.strip()
    volume = float(output.split()[1])
    muted = 'MUTED' in output

    return {
        'level': int(volume * 100),
        'muted': muted,
        'sink_name': 'default'
    }
```

---

## Error Handling

### Service Unavailable
If D-Bus service is not running (e.g., BlueZ not installed):
- Catch `GLib.Error` or `pydbus.bus.DBusException`
- Return `None` or disabled state
- Hide corresponding status block

### Property Access Errors
If property doesn't exist or access denied:
- Use default/fallback values
- Log error for debugging
- Continue with other status blocks

### Signal Subscription Failures
If signal subscription fails:
- Fall back to periodic polling
- Log warning
- Continue operation

## Testing

### D-Bus Introspection
```bash
# List all D-Bus services
dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames

# Introspect UPower
gdbus introspect --system --dest org.freedesktop.UPower --object-path /org/freedesktop/UPower/devices/battery_BAT0

# Monitor D-Bus signals
dbus-monitor --system "type='signal',sender='org.freedesktop.UPower'"
```

### Mock D-Bus Services
For testing, create mock D-Bus objects:

```python
import pydbus
from gi.repository import GLib

class MockBattery:
    """
    <node>
      <interface name='org.freedesktop.UPower.Device'>
        <property name='Percentage' type='d' access='read'/>
        <property name='State' type='u' access='read'/>
      </interface>
    </node>
    """
    def __init__(self):
        self.Percentage = 85.0
        self.State = 2  # Discharging

bus = pydbus.SessionBus()
bus.publish('org.test.UPower', MockBattery())
```

## Reference Implementation

See `home-modules/desktop/swaybar/blocks/` for individual block implementations using these interfaces.

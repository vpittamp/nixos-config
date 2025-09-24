# Adding Your Apple HomeKit Devices to Home Assistant

## Devices Found on Your Network:
1. **Linksys Router** (HomeKit-enabled)
2. **Circle View Camera 0YE8**
3. **Circle View Camera 2848**

## Setup Process:

### Method 1: HomeKit Controller Integration (Recommended)
This imports your existing HomeKit devices INTO Home Assistant.

#### Steps:
1. **Go to Home Assistant**
   - Navigate to: http://localhost:8123
   - Settings → Devices & Services → Add Integration

2. **Add HomeKit Controller**
   - Search for "HomeKit Controller"
   - It should auto-discover your devices

3. **For Each Device You Want to Add:**

   **IMPORTANT**: You'll need the HomeKit pairing code for each device. These are usually:
   - On a sticker on the device
   - In the device's app
   - On the original packaging

   **Circle View Cameras:**
   - The pairing code is on the camera base or in the Logitech Circle app
   - You may need to reset them to pairing mode:
     - Press and hold the button on the back for 10 seconds
     - LED will flash indicating pairing mode

   **Linksys Router:**
   - Check the bottom of the router for HomeKit code
   - Or in the Linksys app under HomeKit settings

   **Ecobee Thermostat:**
   - Go to Main Menu → Settings → Reset → Reset HomeKit
   - The code will display on screen
   - Or check the back of the thermostat

### Method 2: Keep Devices in Apple Home, Add via iCloud
Since iCloud integration had issues, this is less reliable but keeps devices in Apple Home.

### Method 3: Homebridge Integration
If you have Homebridge set up in your other home:

1. Install Homebridge integration in HA
2. Connect to your Homebridge instance
3. All Homebridge devices appear in HA

## Important Considerations:

### ⚠️ Device Pairing Limitations:
- HomeKit devices can only be paired to **ONE controller at a time**
- If you add them to Home Assistant, they'll be **removed from Apple Home**
- To keep in both, you need to:
  1. Add to Home Assistant first
  2. Then expose back to Apple Home via HA's HomeKit Bridge

### 🔄 Recommended Setup:
1. **Import devices to HA** using HomeKit Controller
2. **Configure them in HA** with automations
3. **Export back to Apple Home** via HomeKit Bridge
4. This gives you control in both systems

## Automation Example for Your Devices:

```yaml
# Circle View Camera Automation
automation:
  - alias: "Circle View Motion Alert"
    trigger:
      - platform: state
        entity_id: binary_sensor.circle_view_0ye8_motion
        to: "on"
    action:
      - service: notify.mobile_app
        data:
          message: "Motion detected on Circle View camera"
          data:
            entity_id: camera.circle_view_0ye8

  - alias: "Ecobee Away Mode"
    trigger:
      - platform: state
        entity_id: device_tracker.your_phone
        to: "not_home"
    action:
      - service: climate.set_preset_mode
        target:
          entity_id: climate.ecobee
        data:
          preset_mode: "away"
```

## Quick Commands:

```bash
# Check if devices are discovered
curl -X GET http://localhost:8123/api/discovery_info \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"

# List all HomeKit devices found
sudo journalctl -u home-assistant | grep -i "homekit_controller" | tail -20
```
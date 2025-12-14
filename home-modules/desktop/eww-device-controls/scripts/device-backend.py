#!/usr/bin/env python3
"""Unified device backend for Eww widgets.

Feature 116: Provides device state queries for volume, brightness, bluetooth,
battery, thermal, and network status.

Usage:
    device-backend.py [--mode MODE] [--listen]

Options:
    --mode MODE    Query mode: full | volume | brightness | bluetooth | battery | thermal | network
    --listen       Stream updates continuously (for deflisten)

Exit Codes:
    0 - Success
    1 - Invalid arguments
    2 - Hardware detection failed
    3 - Permission denied
"""

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Optional


# =============================================================================
# Data Models
# =============================================================================

@dataclass
class AudioDevice:
    """Audio output device."""
    id: int
    name: str
    type: str  # "speaker" | "headphones" | "bluetooth"
    active: bool


@dataclass
class VolumeState:
    """Audio volume state."""
    volume: int  # 0-100
    muted: bool
    icon: str
    current_device: str
    devices: list = field(default_factory=list)


@dataclass
class BrightnessState:
    """Brightness state for displays and keyboard."""
    display: int  # 0-100
    display_device: str
    keyboard: Optional[int] = None  # 0-100 or None
    keyboard_device: Optional[str] = None


@dataclass
class BluetoothDevice:
    """Paired Bluetooth device."""
    mac: str
    name: str
    type: str  # "headphones" | "keyboard" | "mouse" | "speaker" | "other"
    connected: bool
    battery: Optional[int] = None
    icon: str = "󰂯"


@dataclass
class BluetoothState:
    """Bluetooth adapter and device state."""
    enabled: bool
    scanning: bool
    devices: list = field(default_factory=list)


@dataclass
class BatteryState:
    """Battery status."""
    percentage: int  # 0-100
    state: str  # "charging" | "discharging" | "full" | "empty"
    time_remaining: Optional[str] = None
    icon: str = "󰁹"
    level: str = "normal"  # "critical" | "low" | "normal" | "full"
    health: Optional[int] = None
    cycles: Optional[int] = None
    power_draw: Optional[float] = None


@dataclass
class PowerProfileState:
    """Power profile status."""
    current: str  # "performance" | "balanced" | "power-saver"
    on_ac: bool
    available: list = field(default_factory=list)
    icon: str = "󰾅"


@dataclass
class ThermalState:
    """Thermal monitoring state."""
    cpu_temp: int  # Celsius
    cpu_temp_max: int
    level: str  # "cool" | "warm" | "hot" | "critical"
    icon: str = "󰔐"
    fan_speed: Optional[int] = None  # RPM
    fan_speed_max: Optional[int] = None


@dataclass
class NetworkState:
    """Network connection state."""
    wifi_enabled: bool
    wifi_connected: bool
    wifi_ssid: Optional[str] = None
    wifi_signal: Optional[int] = None  # 0-100
    wifi_icon: str = "󰤭"
    tailscale_connected: bool = False
    tailscale_ip: Optional[str] = None


@dataclass
class HardwareCapabilities:
    """Hardware detection flags."""
    has_battery: bool = False
    has_brightness: bool = False
    has_keyboard_backlight: bool = False
    has_bluetooth: bool = False
    has_wifi: bool = False
    has_thermal_sensors: bool = False
    has_fan_control: bool = False
    has_power_profiles: bool = False
    hostname: str = ""
    is_laptop: bool = False


@dataclass
class DeviceState:
    """Complete device state."""
    volume: VolumeState = None
    brightness: Optional[BrightnessState] = None
    bluetooth: BluetoothState = None
    battery: Optional[BatteryState] = None
    power_profile: Optional[PowerProfileState] = None
    thermal: ThermalState = None
    network: NetworkState = None
    hardware: HardwareCapabilities = None


# =============================================================================
# Hardware Detection
# =============================================================================

def detect_hardware() -> HardwareCapabilities:
    """Detect available hardware capabilities."""
    caps = HardwareCapabilities()

    # Hostname
    caps.hostname = os.uname().nodename

    # Battery detection
    battery_path = Path("/sys/class/power_supply")
    if battery_path.exists():
        caps.has_battery = any(battery_path.glob("BAT*"))

    # Brightness detection
    backlight_path = Path("/sys/class/backlight")
    if backlight_path.exists():
        caps.has_brightness = any(backlight_path.iterdir())

    # Keyboard backlight detection
    leds_path = Path("/sys/class/leds")
    if leds_path.exists():
        caps.has_keyboard_backlight = any(
            p for p in leds_path.iterdir()
            if "kbd" in p.name.lower() or "keyboard" in p.name.lower()
        )

    # Bluetooth detection
    bt_path = Path("/sys/class/bluetooth")
    caps.has_bluetooth = bt_path.exists() and any(bt_path.iterdir())

    # WiFi detection
    net_path = Path("/sys/class/net")
    if net_path.exists():
        caps.has_wifi = any(
            p for p in net_path.iterdir()
            if p.name.startswith("wl")
        )

    # Thermal sensors detection
    hwmon_path = Path("/sys/class/hwmon")
    caps.has_thermal_sensors = hwmon_path.exists() and any(hwmon_path.iterdir())

    # Fan detection (check for fan inputs in hwmon)
    if caps.has_thermal_sensors:
        for hwmon in hwmon_path.iterdir():
            if any(hwmon.glob("fan*_input")):
                caps.has_fan_control = True
                break

    # Power profiles detection
    caps.has_power_profiles = (
        subprocess.run(["which", "powerprofilesctl"], capture_output=True).returncode == 0 or
        subprocess.run(["which", "tlp-stat"], capture_output=True).returncode == 0
    )

    # Is laptop (derived from battery)
    caps.is_laptop = caps.has_battery

    return caps


# =============================================================================
# Volume Query Functions
# =============================================================================

def get_volume_icon(volume: int, muted: bool) -> str:
    """Get volume icon based on level and mute state."""
    if muted or volume == 0:
        return "󰝟"
    elif volume <= 33:
        return "󰕿"
    elif volume <= 66:
        return "󰖀"
    else:
        return "󰕾"


def get_audio_devices() -> list[AudioDevice]:
    """Get list of audio output devices from WirePlumber."""
    devices = []
    try:
        result = subprocess.run(
            ["wpctl", "status"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            in_sinks = False
            for line in result.stdout.split("\n"):
                if "Sinks:" in line:
                    in_sinks = True
                    continue
                elif in_sinks and line.strip() and not line.startswith(" "):
                    in_sinks = False
                    break
                elif in_sinks and line.strip():
                    # Parse sink line: " │ * 52. device-name [vol: 0.75]"
                    active = "*" in line
                    parts = line.strip().split(".")
                    if len(parts) >= 2:
                        try:
                            device_id = int(parts[0].replace("*", "").replace("│", "").strip())
                            name_part = ".".join(parts[1:]).split("[")[0].strip()
                            # Determine device type
                            name_lower = name_part.lower()
                            if "bluetooth" in name_lower or "bt" in name_lower:
                                dev_type = "bluetooth"
                            elif "headphone" in name_lower or "headset" in name_lower:
                                dev_type = "headphones"
                            else:
                                dev_type = "speaker"
                            devices.append(AudioDevice(
                                id=device_id,
                                name=name_part,
                                type=dev_type,
                                active=active
                            ))
                        except ValueError:
                            pass
    except Exception:
        pass
    return devices


def query_volume() -> VolumeState:
    """Query current volume state using wpctl."""
    volume = 50
    muted = False
    current_device = "Unknown"

    try:
        # Get volume
        result = subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            output = result.stdout.strip()
            # Format: "Volume: 0.75" or "Volume: 0.75 [MUTED]"
            parts = output.split()
            if len(parts) >= 2:
                try:
                    volume = int(float(parts[1]) * 100)
                except ValueError:
                    pass
            muted = "[MUTED]" in output
    except Exception:
        pass

    # Get devices
    devices = get_audio_devices()
    for dev in devices:
        if dev.active:
            current_device = dev.name
            break

    return VolumeState(
        volume=volume,
        muted=muted,
        icon=get_volume_icon(volume, muted),
        current_device=current_device,
        devices=[asdict(d) for d in devices]
    )


# =============================================================================
# Brightness Query Functions
# =============================================================================

def find_brightness_device() -> tuple[Optional[str], Optional[str]]:
    """Find brightness devices (display and keyboard)."""
    display_device = None
    keyboard_device = None

    backlight_path = Path("/sys/class/backlight")
    if backlight_path.exists():
        for device in backlight_path.iterdir():
            display_device = device.name
            break

    leds_path = Path("/sys/class/leds")
    if leds_path.exists():
        for device in leds_path.iterdir():
            if "kbd" in device.name.lower() or "keyboard" in device.name.lower():
                keyboard_device = device.name
                break

    return display_device, keyboard_device


def query_brightness() -> Optional[BrightnessState]:
    """Query current brightness state."""
    display_device, keyboard_device = find_brightness_device()

    if not display_device:
        return None

    display_brightness = 50

    try:
        # Get display brightness using machine-readable format
        # Format: device,class,current,percent,max
        result = subprocess.run(
            ["brightnessctl", "-d", display_device, "-m"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(",")
            if len(parts) >= 4:
                # Column 4 is percentage like "42%"
                display_brightness = int(parts[3].replace("%", ""))
    except Exception:
        pass

    keyboard_brightness = None
    if keyboard_device:
        try:
            result = subprocess.run(
                ["brightnessctl", "-d", keyboard_device, "-m"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                parts = result.stdout.strip().split(",")
                if len(parts) >= 4:
                    keyboard_brightness = int(parts[3].replace("%", ""))
        except Exception:
            pass

    return BrightnessState(
        display=display_brightness,
        display_device=display_device,
        keyboard=keyboard_brightness,
        keyboard_device=keyboard_device
    )


# =============================================================================
# Bluetooth Query Functions
# =============================================================================

def get_bt_device_icon(device_type: str) -> str:
    """Get icon for Bluetooth device type."""
    icons = {
        "headphones": "󰋋",
        "keyboard": "󰌌",
        "mouse": "󰍽",
        "speaker": "󰓃",
        "audio-card": "󰋋",
    }
    return icons.get(device_type, "󰂯")


def infer_bt_device_type(name: str, icon: str) -> str:
    """Infer Bluetooth device type from name and icon."""
    name_lower = name.lower()
    if any(x in name_lower for x in ["airpods", "headphone", "earbuds", "buds", "pods"]):
        return "headphones"
    elif any(x in name_lower for x in ["keyboard", "keychron", "hhkb"]):
        return "keyboard"
    elif any(x in name_lower for x in ["mouse", "trackpad", "magic"]):
        return "mouse"
    elif any(x in name_lower for x in ["speaker", "soundbar", "homepod"]):
        return "speaker"
    elif "audio" in icon.lower():
        return "headphones"
    return "other"


def query_bluetooth() -> BluetoothState:
    """Query Bluetooth adapter and device state."""
    enabled = False
    scanning = False
    devices = []

    try:
        # Check if adapter is powered
        result = subprocess.run(
            ["bluetoothctl", "show"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.split("\n"):
                if "Powered:" in line:
                    enabled = "yes" in line.lower()
                elif "Discovering:" in line:
                    scanning = "yes" in line.lower()

        # Get paired devices
        result = subprocess.run(
            ["bluetoothctl", "devices", "Paired"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split("\n"):
                if line.startswith("Device "):
                    parts = line.split(" ", 2)
                    if len(parts) >= 3:
                        mac = parts[1]
                        name = parts[2]

                        # Check connection status
                        connected = False
                        battery = None
                        icon = "input-gaming"  # default

                        info_result = subprocess.run(
                            ["bluetoothctl", "info", mac],
                            capture_output=True,
                            text=True,
                            timeout=5
                        )
                        if info_result.returncode == 0:
                            for info_line in info_result.stdout.split("\n"):
                                if "Connected:" in info_line:
                                    connected = "yes" in info_line.lower()
                                elif "Battery Percentage:" in info_line:
                                    try:
                                        battery = int(info_line.split("(")[1].split(")")[0])
                                    except (IndexError, ValueError):
                                        pass
                                elif "Icon:" in info_line:
                                    icon = info_line.split(":")[1].strip()

                        dev_type = infer_bt_device_type(name, icon)
                        devices.append(BluetoothDevice(
                            mac=mac,
                            name=name,
                            type=dev_type,
                            connected=connected,
                            battery=battery,
                            icon=get_bt_device_icon(dev_type)
                        ))
    except Exception:
        pass

    return BluetoothState(
        enabled=enabled,
        scanning=scanning,
        devices=[asdict(d) for d in devices]
    )


# =============================================================================
# Battery Query Functions
# =============================================================================

def get_battery_icon(percentage: int, state: str) -> str:
    """Get battery icon based on percentage and state."""
    if state == "charging":
        return "󰂄"
    elif percentage <= 10:
        return "󰂎"
    elif percentage <= 20:
        return "󰁺"
    elif percentage <= 30:
        return "󰁻"
    elif percentage <= 40:
        return "󰁼"
    elif percentage <= 50:
        return "󰁽"
    elif percentage <= 60:
        return "󰁾"
    elif percentage <= 70:
        return "󰁿"
    elif percentage <= 80:
        return "󰂀"
    elif percentage <= 90:
        return "󰂁"
    else:
        return "󰂂" if state != "full" else "󰁹"


def get_battery_level(percentage: int) -> str:
    """Get battery level category."""
    if percentage <= 10:
        return "critical"
    elif percentage <= 20:
        return "low"
    elif percentage >= 95:
        return "full"
    else:
        return "normal"


def query_battery() -> Optional[BatteryState]:
    """Query battery status using UPower."""
    try:
        # Find battery device
        result = subprocess.run(
            ["upower", "-e"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return None

        battery_path = None
        for line in result.stdout.strip().split("\n"):
            if "BAT" in line or "battery" in line.lower():
                battery_path = line.strip()
                break

        if not battery_path:
            return None

        # Get battery info
        result = subprocess.run(
            ["upower", "-i", battery_path],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return None

        percentage = 100
        state = "full"
        time_remaining = None
        health = None
        power_draw = None

        for line in result.stdout.split("\n"):
            line = line.strip()
            if line.startswith("percentage:"):
                try:
                    percentage = int(line.split(":")[1].strip().replace("%", ""))
                except ValueError:
                    pass
            elif line.startswith("state:"):
                state = line.split(":")[1].strip()
            elif "time to" in line.lower():
                parts = line.split(":")
                if len(parts) >= 2:
                    time_remaining = parts[1].strip()
            elif line.startswith("capacity:"):
                try:
                    health = int(float(line.split(":")[1].strip().replace("%", "")))
                except ValueError:
                    pass
            elif line.startswith("energy-rate:"):
                try:
                    power_draw = float(line.split(":")[1].strip().split()[0])
                except (ValueError, IndexError):
                    pass

        return BatteryState(
            percentage=percentage,
            state=state,
            time_remaining=time_remaining,
            icon=get_battery_icon(percentage, state),
            level=get_battery_level(percentage),
            health=health,
            cycles=None,  # UPower doesn't typically provide this
            power_draw=power_draw
        )
    except Exception:
        return None


# =============================================================================
# Power Profile Query Functions
# =============================================================================

def get_power_profile_icon(profile: str) -> str:
    """Get power profile icon."""
    icons = {
        "performance": "󱐋",
        "balanced": "󰾅",
        "power-saver": "󰾆",
    }
    return icons.get(profile, "󰾅")


def query_power_profile() -> Optional[PowerProfileState]:
    """Query power profile status."""
    try:
        # Try power-profiles-daemon first
        result = subprocess.run(
            ["powerprofilesctl", "get"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            current = result.stdout.strip()

            # Get available profiles
            list_result = subprocess.run(
                ["powerprofilesctl", "list"],
                capture_output=True,
                text=True,
                timeout=5
            )
            available = []
            if list_result.returncode == 0:
                for line in list_result.stdout.split("\n"):
                    line = line.strip()
                    if line.endswith(":"):
                        profile = line.rstrip(":").lstrip("* ")
                        if profile:
                            available.append(profile)

            # Check AC status
            on_ac = False
            ac_path = Path("/sys/class/power_supply/AC")
            if ac_path.exists():
                try:
                    online = (ac_path / "online").read_text().strip()
                    on_ac = online == "1"
                except Exception:
                    pass

            return PowerProfileState(
                current=current,
                on_ac=on_ac,
                available=available or ["balanced"],
                icon=get_power_profile_icon(current)
            )
    except FileNotFoundError:
        pass

    # Try TLP
    try:
        result = subprocess.run(
            ["tlp-stat", "-s"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            current = "balanced"
            on_ac = False
            for line in result.stdout.split("\n"):
                if "Mode:" in line:
                    mode = line.split(":")[1].strip().lower()
                    if "ac" in mode:
                        current = "performance"
                        on_ac = True
                    elif "bat" in mode:
                        current = "power-saver"

            return PowerProfileState(
                current=current,
                on_ac=on_ac,
                available=["performance", "balanced", "power-saver"],
                icon=get_power_profile_icon(current)
            )
    except FileNotFoundError:
        pass

    return None


# =============================================================================
# Thermal Query Functions
# =============================================================================

def get_thermal_icon(level: str) -> str:
    """Get thermal icon based on level."""
    icons = {
        "cool": "󰔏",
        "warm": "󰔐",
        "hot": "󰸁",
        "critical": "󱗗",
    }
    return icons.get(level, "󰔐")


def get_thermal_level(temp: int) -> str:
    """Get thermal level category."""
    if temp < 50:
        return "cool"
    elif temp < 70:
        return "warm"
    elif temp < 85:
        return "hot"
    else:
        return "critical"


def query_thermal() -> ThermalState:
    """Query thermal sensors using lm_sensors."""
    cpu_temp = 0
    cpu_temp_max = 100
    fan_speed = None
    fan_speed_max = None

    try:
        # Use sensors for temperature
        result = subprocess.run(
            ["sensors", "-j"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)

            # Find CPU temperature
            for chip_name, chip_data in data.items():
                if isinstance(chip_data, dict):
                    for sensor_name, sensor_data in chip_data.items():
                        if isinstance(sensor_data, dict):
                            # Look for temp inputs
                            for key, value in sensor_data.items():
                                if key.endswith("_input") and "temp" in key:
                                    if value and (cpu_temp == 0 or "core" in sensor_name.lower() or "tctl" in sensor_name.lower()):
                                        cpu_temp = int(value)
                                elif key.endswith("_max") and "temp" in key:
                                    if value:
                                        cpu_temp_max = int(value)
                                elif key.endswith("_input") and "fan" in key:
                                    if value:
                                        fan_speed = int(value)
                                elif key.endswith("_max") and "fan" in key:
                                    if value:
                                        fan_speed_max = int(value)
    except Exception:
        # Fallback: read from thermal zones
        try:
            thermal_path = Path("/sys/class/thermal")
            for zone in thermal_path.glob("thermal_zone*"):
                temp_file = zone / "temp"
                if temp_file.exists():
                    temp_raw = int(temp_file.read_text().strip())
                    # Temperature is in millidegrees
                    cpu_temp = temp_raw // 1000
                    break
        except Exception:
            pass

    level = get_thermal_level(cpu_temp)

    return ThermalState(
        cpu_temp=cpu_temp,
        cpu_temp_max=cpu_temp_max,
        level=level,
        icon=get_thermal_icon(level),
        fan_speed=fan_speed,
        fan_speed_max=fan_speed_max
    )


# =============================================================================
# Network Query Functions
# =============================================================================

def get_wifi_icon(signal: Optional[int], enabled: bool, connected: bool) -> str:
    """Get WiFi icon based on signal strength."""
    if not enabled:
        return "󰤭"
    if not connected or signal is None:
        return "󰤯"
    elif signal <= 25:
        return "󰤟"
    elif signal <= 50:
        return "󰤢"
    elif signal <= 75:
        return "󰤥"
    else:
        return "󰤨"


def query_network() -> NetworkState:
    """Query network status using nmcli and tailscale."""
    wifi_enabled = False
    wifi_connected = False
    wifi_ssid = None
    wifi_signal = None
    tailscale_connected = False
    tailscale_ip = None

    try:
        # Get WiFi status
        result = subprocess.run(
            ["nmcli", "-t", "-f", "WIFI", "radio"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            wifi_enabled = result.stdout.strip() == "enabled"

        if wifi_enabled:
            # Get current WiFi connection
            result = subprocess.run(
                ["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split("\n"):
                    if line.startswith("yes:"):
                        wifi_connected = True
                        wifi_ssid = line.split(":")[1] if len(line.split(":")) > 1 else None
                        break

            # Get signal strength
            if wifi_connected:
                result = subprocess.run(
                    ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "dev", "wifi"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    for line in result.stdout.strip().split("\n"):
                        if line.startswith("*:"):
                            try:
                                wifi_signal = int(line.split(":")[1])
                            except (ValueError, IndexError):
                                pass
                            break
    except Exception:
        pass

    # Check Tailscale
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            if data.get("Self"):
                tailscale_connected = data["Self"].get("Online", False)
                tailscale_ips = data["Self"].get("TailscaleIPs", [])
                if tailscale_ips:
                    tailscale_ip = tailscale_ips[0]
    except Exception:
        pass

    return NetworkState(
        wifi_enabled=wifi_enabled,
        wifi_connected=wifi_connected,
        wifi_ssid=wifi_ssid,
        wifi_signal=wifi_signal,
        wifi_icon=get_wifi_icon(wifi_signal, wifi_enabled, wifi_connected),
        tailscale_connected=tailscale_connected,
        tailscale_ip=tailscale_ip
    )


# =============================================================================
# Main Query Function
# =============================================================================

def query_device_state(mode: str, hardware: HardwareCapabilities) -> dict:
    """Query device state based on mode."""
    if mode == "volume":
        return asdict(query_volume())
    elif mode == "brightness":
        state = query_brightness()
        return asdict(state) if state else {"error": True, "code": "BRIGHTNESS_UNAVAILABLE"}
    elif mode == "bluetooth":
        return asdict(query_bluetooth())
    elif mode == "battery":
        state = query_battery()
        return asdict(state) if state else {"error": True, "code": "BATTERY_UNAVAILABLE"}
    elif mode == "thermal":
        return asdict(query_thermal())
    elif mode == "network":
        return asdict(query_network())
    elif mode == "full":
        # Query all available states
        result = {
            "volume": asdict(query_volume()),
            "bluetooth": asdict(query_bluetooth()),
            "thermal": asdict(query_thermal()),
            "network": asdict(query_network()),
            "hardware": asdict(hardware),
        }

        # Add optional states based on hardware
        if hardware.has_brightness:
            brightness = query_brightness()
            result["brightness"] = asdict(brightness) if brightness else None

        if hardware.has_battery:
            battery = query_battery()
            result["battery"] = asdict(battery) if battery else None
            power_profile = query_power_profile()
            result["power_profile"] = asdict(power_profile) if power_profile else None
        else:
            result["brightness"] = None
            result["battery"] = None
            result["power_profile"] = None

        return result
    else:
        return {"error": True, "message": f"Unknown mode: {mode}", "code": "INVALID_MODE"}


# =============================================================================
# Main Entry Point
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Device backend for Eww widgets")
    parser.add_argument(
        "--mode",
        choices=["full", "volume", "brightness", "bluetooth", "battery", "thermal", "network"],
        default="full",
        help="Query mode"
    )
    parser.add_argument(
        "--listen",
        action="store_true",
        help="Stream updates continuously"
    )

    args = parser.parse_args()

    # Detect hardware capabilities once
    hardware = detect_hardware()

    if args.listen:
        # Streaming mode for deflisten
        interval = 1 if args.mode == "volume" else 2
        while True:
            try:
                state = query_device_state(args.mode, hardware)
                print(json.dumps(state), flush=True)
                time.sleep(interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(json.dumps({"error": True, "message": str(e)}), flush=True)
                time.sleep(interval)
    else:
        # Single query mode
        state = query_device_state(args.mode, hardware)
        print(json.dumps(state))


if __name__ == "__main__":
    main()

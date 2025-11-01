"""Pytest configuration and fixtures for swaybar status generator tests."""

import pytest
from typing import Dict, Any


@pytest.fixture
def mock_dbus_battery():
    """Mock D-Bus response for battery state (UPower)."""
    return {
        "Percentage": 85.0,
        "State": 2,  # Discharging
        "TimeToEmpty": 12240,  # ~3.4 hours in seconds
        "TimeToFull": 0,
        "IsPresent": True
    }


@pytest.fixture
def mock_dbus_battery_charging():
    """Mock D-Bus response for battery charging state."""
    return {
        "Percentage": 65.0,
        "State": 1,  # Charging
        "TimeToEmpty": 0,
        "TimeToFull": 4500,  # ~1.25 hours
        "IsPresent": True
    }


@pytest.fixture
def mock_dbus_network_connected():
    """Mock D-Bus response for connected WiFi network (NetworkManager)."""
    return {
        "State": 70,  # NM_DEVICE_STATE_ACTIVATED
        "ActiveAccessPoint": {
            "Ssid": b"MyNetwork",
            "Strength": 87
        }
    }


@pytest.fixture
def mock_dbus_network_disconnected():
    """Mock D-Bus response for disconnected WiFi."""
    return {
        "State": 30,  # NM_DEVICE_STATE_DISCONNECTED
        "ActiveAccessPoint": None
    }


@pytest.fixture
def mock_dbus_bluetooth_connected():
    """Mock D-Bus response for Bluetooth with connected devices (BlueZ)."""
    return {
        "Powered": True,
        "Devices": [
            {"Name": "Headphones", "Address": "AA:BB:CC:DD:EE:FF", "Connected": True},
            {"Name": "Keyboard", "Address": "11:22:33:44:55:66", "Connected": True},
            {"Name": "Mouse", "Address": "77:88:99:AA:BB:CC", "Connected": False}
        ]
    }


@pytest.fixture
def mock_dbus_bluetooth_disabled():
    """Mock D-Bus response for disabled Bluetooth."""
    return {
        "Powered": False,
        "Devices": []
    }


@pytest.fixture
def mock_pactl_output_unmuted():
    """Mock pactl output for unmuted volume at 75%."""
    return """
Sink #0
\tState: RUNNING
\tVolume: front-left: 49151 /  75% / -7.50 dB,   front-right: 49151 /  75% / -7.50 dB
\tMute: no
\tName: alsa_output.pci-0000_00_1f.3.analog-stereo
"""


@pytest.fixture
def mock_pactl_output_muted():
    """Mock pactl output for muted volume."""
    return """
Sink #0
\tState: RUNNING
\tVolume: front-left: 32768 /  50% / 0.00 dB,   front-right: 32768 /  50% / 0.00 dB
\tMute: yes
\tName: alsa_output.pci-0000_00_1f.3.analog-stereo
"""


@pytest.fixture
def sample_config():
    """Sample configuration for testing."""
    from home_modules.desktop.swaybar.blocks.config import Config
    return Config()


@pytest.fixture
def sample_status_block():
    """Sample status block for testing."""
    from home_modules.desktop.swaybar.blocks.models import StatusBlock
    return StatusBlock(
        name="test",
        full_text="Test Block",
        color="#a6e3a1"
    )

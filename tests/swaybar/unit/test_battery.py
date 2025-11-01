"""Unit tests for battery status block."""

import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..', 'home-modules/desktop/swaybar'))

from blocks.battery import BatteryState, BatteryStatus
from blocks.config import Config


class TestBatteryState:
    """Test BatteryState dataclass and methods."""

    def test_get_icon_charging(self):
        """Test charging battery icon."""
        state = BatteryState(
            percentage=50,
            status=BatteryStatus.CHARGING
        )
        assert state.get_icon() == "󰂄"  # nf-md-battery_charging

    def test_get_icon_high(self):
        """Test high battery icon (>= 90%)."""
        state = BatteryState(
            percentage=95,
            status=BatteryStatus.DISCHARGING
        )
        assert state.get_icon() == "󰁹"  # nf-md-battery_90

    def test_get_icon_medium(self):
        """Test medium battery icon (50-69%)."""
        state = BatteryState(
            percentage=55,
            status=BatteryStatus.DISCHARGING
        )
        assert state.get_icon() == "󰂀"  # nf-md-battery_50

    def test_get_icon_low(self):
        """Test low battery icon (< 10%)."""
        state = BatteryState(
            percentage=5,
            status=BatteryStatus.DISCHARGING
        )
        assert state.get_icon() == "󰂃"  # nf-md-battery_alert

    def test_get_color_charging(self):
        """Test charging battery color."""
        config = Config()
        state = BatteryState(
            percentage=50,
            status=BatteryStatus.CHARGING
        )
        assert state.get_color(config) == config.theme.battery.charging

    def test_get_color_high(self):
        """Test high battery color (>= 50%)."""
        config = Config()
        state = BatteryState(
            percentage=80,
            status=BatteryStatus.DISCHARGING
        )
        assert state.get_color(config) == config.theme.battery.high

    def test_get_color_medium(self):
        """Test medium battery color (20-49%)."""
        config = Config()
        state = BatteryState(
            percentage=30,
            status=BatteryStatus.DISCHARGING
        )
        assert state.get_color(config) == config.theme.battery.medium

    def test_get_color_low(self):
        """Test low battery color (< 20%)."""
        config = Config()
        state = BatteryState(
            percentage=15,
            status=BatteryStatus.DISCHARGING
        )
        assert state.get_color(config) == config.theme.battery.low

    def test_get_tooltip_discharging(self):
        """Test tooltip for discharging battery."""
        state = BatteryState(
            percentage=85,
            status=BatteryStatus.DISCHARGING,
            time_to_empty=12240  # ~3.4 hours
        )
        tooltip = state.get_tooltip()

        assert "85%" in tooltip
        assert "3h" in tooltip
        assert "24m" in tooltip
        assert "remaining" in tooltip

    def test_get_tooltip_charging(self):
        """Test tooltip for charging battery."""
        state = BatteryState(
            percentage=65,
            status=BatteryStatus.CHARGING,
            time_to_full=4500  # ~1.25 hours
        )
        tooltip = state.get_tooltip()

        assert "65%" in tooltip
        assert "1h" in tooltip
        assert "15m" in tooltip
        assert "until full" in tooltip

    def test_get_tooltip_no_time(self):
        """Test tooltip when time estimate unavailable."""
        state = BatteryState(
            percentage=75,
            status=BatteryStatus.FULLY_CHARGED
        )
        tooltip = state.get_tooltip()

        assert "75%" in tooltip
        assert "fully charged" in tooltip.lower()

    def test_to_status_block(self):
        """Test status block conversion."""
        config = Config()
        state = BatteryState(
            percentage=85,
            status=BatteryStatus.DISCHARGING,
            time_to_empty=7200
        )
        block = state.to_status_block(config)

        assert block.name == "battery"
        assert "85%" in block.full_text
        assert block.short_text == "85%"
        assert block.urgent is False

    def test_to_status_block_low_urgent(self):
        """Test status block with urgent flag for low battery."""
        config = Config()
        state = BatteryState(
            percentage=8,
            status=BatteryStatus.DISCHARGING
        )
        block = state.to_status_block(config)

        assert block.urgent is True
        assert block.color == config.theme.battery.low

    def test_to_status_block_not_present(self):
        """Test status block returns None when battery not present."""
        config = Config()
        state = BatteryState(
            percentage=0,
            status=BatteryStatus.UNKNOWN,
            present=False
        )
        block = state.to_status_block(config)

        assert block is None

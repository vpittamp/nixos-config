"""Unit tests for volume status block."""

import pytest
from unittest.mock import Mock, patch
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..', 'home-modules/desktop/swaybar'))

from blocks.volume import VolumeState, get_volume_state
from blocks.config import Config


class TestVolumeState:
    """Test VolumeState dataclass and methods."""

    def test_get_icon_muted(self):
        """Test muted volume icon."""
        state = VolumeState(level=50, muted=True, sink_name="test")
        assert state.get_icon() == "󰝟"  # nf-md-volume_mute

    def test_get_icon_high(self):
        """Test high volume icon (>= 70%)."""
        state = VolumeState(level=75, muted=False, sink_name="test")
        assert state.get_icon() == "󰕾"  # nf-md-volume_high

    def test_get_icon_medium(self):
        """Test medium volume icon (30-69%)."""
        state = VolumeState(level=50, muted=False, sink_name="test")
        assert state.get_icon() == "󰖀"  # nf-md-volume_medium

    def test_get_icon_low(self):
        """Test low volume icon (< 30%)."""
        state = VolumeState(level=20, muted=False, sink_name="test")
        assert state.get_icon() == "󰕿"  # nf-md-volume_low

    def test_get_color_normal(self):
        """Test normal volume color."""
        config = Config()
        state = VolumeState(level=50, muted=False, sink_name="test")
        assert state.get_color(config) == config.theme.volume.normal

    def test_get_color_muted(self):
        """Test muted volume color."""
        config = Config()
        state = VolumeState(level=50, muted=True, sink_name="test")
        assert state.get_color(config) == config.theme.volume.muted

    def test_to_status_block(self):
        """Test status block conversion."""
        config = Config()
        state = VolumeState(level=75, muted=False, sink_name="test")
        block = state.to_status_block(config)

        assert block.name == "volume"
        assert "75%" in block.full_text
        assert block.short_text == "75%"
        assert block.color == config.theme.volume.normal
        assert block.markup == "pango"

    def test_to_status_block_muted(self):
        """Test status block conversion when muted."""
        config = Config()
        state = VolumeState(level=50, muted=True, sink_name="test")
        block = state.to_status_block(config)

        assert block.name == "volume"
        assert "󰝟" in block.full_text  # Mute icon
        assert block.color == config.theme.volume.muted


class TestGetVolumeState:
    """Test get_volume_state function."""

    @patch('blocks.volume.subprocess.run')
    def test_get_volume_state_success(self, mock_run):
        """Test successful volume query."""
        mock_run.return_value = Mock(
            stdout="""
Sink #0
    State: RUNNING
    Volume: front-left: 49151 /  75% / -7.50 dB
    Mute: no
    Name: alsa_output.test
""",
            returncode=0
        )

        state = get_volume_state()

        assert state is not None
        assert state.level == 75
        assert state.muted is False
        assert "alsa_output.test" in state.sink_name

    @patch('blocks.volume.subprocess.run')
    def test_get_volume_state_muted(self, mock_run):
        """Test volume query when muted."""
        mock_run.return_value = Mock(
            stdout="""
Sink #0
    Volume: front-left: 32768 /  50% / 0.00 dB
    Mute: yes
    Name: test_sink
""",
            returncode=0
        )

        state = get_volume_state()

        assert state is not None
        assert state.level == 50
        assert state.muted is True

    @patch('blocks.volume.subprocess.run')
    def test_get_volume_state_timeout(self, mock_run):
        """Test handling of pactl timeout."""
        mock_run.side_effect = TimeoutError()

        state = get_volume_state()

        assert state is None

    @patch('blocks.volume.subprocess.run')
    def test_get_volume_state_not_found(self, mock_run):
        """Test handling of missing pactl."""
        mock_run.side_effect = FileNotFoundError()

        state = get_volume_state()

        assert state is None

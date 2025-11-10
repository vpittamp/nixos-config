"""
Unit tests for FloatingWindowConfig validation (Feature 001: T044)

Tests the Pydantic validation of floating window configurations.
"""

import pytest
from pydantic import ValidationError
import sys
import os

# Add daemon path to sys.path for imports
sys.path.insert(0, "/etc/nixos/home-modules/desktop/i3-project-event-daemon")

from models.floating_config import (
    FloatingWindowConfig,
    FloatingSize,
    Scope,
)


def test_floating_window_config_minimal():
    """Test minimal valid floating window config (floating=true only)"""
    config = FloatingWindowConfig(
        floating=True,
        app_name="btop",
        app_id="btop",
    )

    assert config.floating is True
    assert config.floating_size is None  # Default
    assert config.scope == Scope.SCOPED  # Default
    assert config.app_name == "btop"


def test_floating_window_config_with_size():
    """Test floating window config with explicit size preset"""
    config = FloatingWindowConfig(
        floating=True,
        floating_size=FloatingSize.MEDIUM,
        app_name="btop",
        app_id="btop",
    )

    assert config.floating is True
    assert config.floating_size == FloatingSize.MEDIUM
    assert config.scope == Scope.SCOPED


def test_floating_window_config_global_scope():
    """Test floating window with global scope"""
    config = FloatingWindowConfig(
        floating=True,
        floating_size=FloatingSize.LARGE,
        scope=Scope.GLOBAL,
        app_name="pavucontrol",
        app_id="org.pulseaudio.pavucontrol",
    )

    assert config.floating is True
    assert config.floating_size == FloatingSize.LARGE
    assert config.scope == Scope.GLOBAL


def test_floating_false_ignores_size():
    """Test that floating=false makes size/scope irrelevant"""
    config = FloatingWindowConfig(
        floating=False,
        floating_size=FloatingSize.SMALL,  # Ignored
        app_name="firefox",
        app_id="firefox",
    )

    assert config.floating is False
    # Size/scope present but irrelevant when floating=False


def test_floating_size_enum_values():
    """Test all FloatingSize enum values are valid"""
    for size in [FloatingSize.SCRATCHPAD, FloatingSize.SMALL, FloatingSize.MEDIUM, FloatingSize.LARGE]:
        config = FloatingWindowConfig(
            floating=True,
            floating_size=size,
            app_name="test",
            app_id="test",
        )
        assert config.floating_size == size


def test_scope_enum_values():
    """Test all Scope enum values are valid"""
    for scope in [Scope.SCOPED, Scope.GLOBAL]:
        config = FloatingWindowConfig(
            floating=True,
            scope=scope,
            app_name="test",
            app_id="test",
        )
        assert config.scope == scope


def test_invalid_floating_size_string():
    """Test that invalid floating_size string fails validation"""
    with pytest.raises(ValidationError) as exc_info:
        FloatingWindowConfig(
            floating=True,
            floating_size="huge",  # Invalid
            app_name="test",
            app_id="test",
        )

    assert "floating_size" in str(exc_info.value)


def test_invalid_scope_string():
    """Test that invalid scope string fails validation"""
    with pytest.raises(ValidationError) as exc_info:
        FloatingWindowConfig(
            floating=True,
            scope="project-specific",  # Invalid
            app_name="test",
            app_id="test",
        )

    assert "scope" in str(exc_info.value)


def test_missing_app_name_fails():
    """Test that missing app_name fails validation"""
    with pytest.raises(ValidationError) as exc_info:
        FloatingWindowConfig(
            floating=True,
            app_id="test",
        )

    assert "app_name" in str(exc_info.value)


def test_missing_app_id_fails():
    """Test that missing app_id fails validation"""
    with pytest.raises(ValidationError) as exc_info:
        FloatingWindowConfig(
            floating=True,
            app_name="test",
        )

    assert "app_id" in str(exc_info.value)

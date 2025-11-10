"""
Unit tests for floating size preset dimensions (Feature 001: T045)

Tests the FLOATING_SIZE_DIMENSIONS constant and size-to-dimension mapping.
"""

import pytest
import sys
import os

# Add daemon path to sys.path for imports
sys.path.insert(0, "/etc/nixos/home-modules/desktop/i3-project-event-daemon")

from models.floating_config import (
    FloatingSize,
    FLOATING_SIZE_DIMENSIONS,
)


def test_floating_size_dimensions_constant_exists():
    """Test that FLOATING_SIZE_DIMENSIONS constant is defined"""
    assert FLOATING_SIZE_DIMENSIONS is not None
    assert isinstance(FLOATING_SIZE_DIMENSIONS, dict)


def test_all_floating_sizes_have_dimensions():
    """Test that all FloatingSize enum values have dimension mappings"""
    for size in FloatingSize:
        assert size in FLOATING_SIZE_DIMENSIONS, f"Missing dimension for {size.value}"


def test_scratchpad_size_dimensions():
    """Test scratchpad preset is 1200×600 (Feature 062)"""
    assert FLOATING_SIZE_DIMENSIONS[FloatingSize.SCRATCHPAD] == (1200, 600)


def test_small_size_dimensions():
    """Test small preset is 800×500"""
    assert FLOATING_SIZE_DIMENSIONS[FloatingSize.SMALL] == (800, 500)


def test_medium_size_dimensions():
    """Test medium preset is 1200×800"""
    assert FLOATING_SIZE_DIMENSIONS[FloatingSize.MEDIUM] == (1200, 800)


def test_large_size_dimensions():
    """Test large preset is 1600×1000"""
    assert FLOATING_SIZE_DIMENSIONS[FloatingSize.LARGE] == (1600, 1000)


def test_dimensions_are_tuples():
    """Test that all dimensions are (width, height) tuples"""
    for size, dimensions in FLOATING_SIZE_DIMENSIONS.items():
        assert isinstance(dimensions, tuple), f"{size.value} dimensions not a tuple"
        assert len(dimensions) == 2, f"{size.value} dimensions not (width, height)"
        width, height = dimensions
        assert isinstance(width, int), f"{size.value} width not an int"
        assert isinstance(height, int), f"{size.value} height not an int"
        assert width > 0, f"{size.value} width not positive"
        assert height > 0, f"{size.value} height not positive"


def test_dimensions_increase_with_size():
    """Test that dimensions generally increase from small→medium→large"""
    scratchpad_w, scratchpad_h = FLOATING_SIZE_DIMENSIONS[FloatingSize.SCRATCHPAD]
    small_w, small_h = FLOATING_SIZE_DIMENSIONS[FloatingSize.SMALL]
    medium_w, medium_h = FLOATING_SIZE_DIMENSIONS[FloatingSize.MEDIUM]
    large_w, large_h = FLOATING_SIZE_DIMENSIONS[FloatingSize.LARGE]

    # Width increases (scratchpad and medium share same width)
    assert small_w < medium_w < large_w
    assert scratchpad_w == medium_w  # Both 1200px wide

    # Height increases for regular presets (scratchpad is special case)
    assert small_h < medium_h < large_h


def test_aspect_ratios_are_reasonable():
    """Test that all presets have reasonable aspect ratios (between 1:1 and 2:1)"""
    for size, (width, height) in FLOATING_SIZE_DIMENSIONS.items():
        aspect_ratio = width / height
        assert 1.0 <= aspect_ratio <= 2.0, (
            f"{size.value} aspect ratio {aspect_ratio:.2f} outside reasonable range (1.0-2.0)"
        )


def test_small_size_fits_laptop_screen():
    """Test that small preset fits on 1366×768 laptop screens"""
    width, height = FLOATING_SIZE_DIMENSIONS[FloatingSize.SMALL]
    assert width <= 1366, "Small preset too wide for laptop"
    assert height <= 768, "Small preset too tall for laptop"


def test_large_size_reasonable_for_displays():
    """Test that large preset fits on common displays"""
    width, height = FLOATING_SIZE_DIMENSIONS[FloatingSize.LARGE]
    assert width <= 1920, "Large preset width should fit on 1080p displays"
    assert height <= 1080, "Large preset height should fit on 1080p displays"

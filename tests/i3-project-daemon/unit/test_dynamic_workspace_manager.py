"""Unit tests for DynamicWorkspaceManager.

Feature 049: US3 - Distribution Engine
"""
import pytest
from unittest.mock import AsyncMock, Mock
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..'))

from home_modules.desktop.i3_project_event_daemon.workspace_manager import DynamicWorkspaceManager


@pytest.mark.asyncio
async def test_assign_monitor_roles_3_monitors():
    """Test role assignment with 3 monitors."""
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-2", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]
    
    manager = DynamicWorkspaceManager(mock_i3)
    roles = await manager.assign_monitor_roles()

    assert roles["HEADLESS-1"] == "primary"
    assert roles["HEADLESS-2"] == "secondary"
    assert roles["HEADLESS-3"] == "tertiary"


@pytest.mark.asyncio
async def test_assign_monitor_roles_1_monitor():
    """Test role assignment with 1 monitor."""
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True)
    ]
    
    manager = DynamicWorkspaceManager(mock_i3)
    roles = await manager.assign_monitor_roles()

    assert roles["HEADLESS-1"] == "primary"
    assert len(roles) == 1


@pytest.mark.asyncio
async def test_assign_monitor_roles_overflow():
    """Test role assignment with 4+ monitors."""
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name=f"HDMI-{i}", active=True) for i in range(1, 6)
    ]
    
    manager = DynamicWorkspaceManager(mock_i3)
    roles = await manager.assign_monitor_roles()

    assert roles["HDMI-1"] == "primary"
    assert roles["HDMI-2"] == "secondary"
    assert roles["HDMI-3"] == "tertiary"
    assert roles["HDMI-4"] == "overflow"
    assert roles["HDMI-5"] == "overflow"


def test_calculate_distribution():
    """Test distribution calculation delegates to WorkspaceDistribution."""
    mock_i3 = AsyncMock()
    manager = DynamicWorkspaceManager(mock_i3)
    dist = manager.calculate_distribution(3)

    assert dist.monitor_count == 3
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[5] == "secondary"
    assert dist.workspace_to_role[9] == "tertiary"

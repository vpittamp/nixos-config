"""Unit tests for WorkspaceDistribution model.

Feature 049: US3 - Built-in Smart Distribution Rules
"""
import pytest
from home_modules.desktop.i3_project_event_daemon.models import WorkspaceDistribution


def test_distribution_1_monitor():
    """Test workspace distribution with 1 monitor."""
    dist = WorkspaceDistribution.calculate(1)
    assert dist.monitor_count == 1
    assert all(dist.workspace_to_role[ws] == "primary" for ws in range(1, 71))


def test_distribution_2_monitors():
    """Test workspace distribution with 2 monitors."""
    dist = WorkspaceDistribution.calculate(2)
    assert dist.monitor_count == 2
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[2] == "primary"
    assert dist.workspace_to_role[3] == "secondary"
    assert dist.workspace_to_role[70] == "secondary"


def test_distribution_3_monitors():
    """Test workspace distribution with 3 monitors."""
    dist = WorkspaceDistribution.calculate(3)
    assert dist.monitor_count == 3
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[2] == "primary"
    assert dist.workspace_to_role[3] == "secondary"
    assert dist.workspace_to_role[5] == "secondary"
    assert dist.workspace_to_role[6] == "tertiary"
    assert dist.workspace_to_role[70] == "tertiary"


def test_distribution_4_monitors():
    """Test workspace distribution with 4+ monitors."""
    dist = WorkspaceDistribution.calculate(4)
    assert dist.monitor_count == 4
    assert dist.workspace_to_role[1] == "primary"
    assert dist.workspace_to_role[5] == "secondary"
    assert dist.workspace_to_role[9] == "tertiary"
    assert dist.workspace_to_role[10] == "overflow"
    assert dist.workspace_to_role[70] == "overflow"


def test_distribution_validation_coverage():
    """Test validation ensures all workspaces covered."""
    with pytest.raises(ValueError, match="Missing workspace assignments"):
        WorkspaceDistribution(
            monitor_count=1,
            workspace_to_role={1: "primary"}  # Missing WS 2-70
        )


def test_distribution_validation_roles():
    """Test validation ensures valid roles."""
    with pytest.raises(ValueError, match="Invalid role"):
        workspace_to_role = {ws: "invalid_role" for ws in range(1, 71)}
        WorkspaceDistribution(
            monitor_count=1,
            workspace_to_role=workspace_to_role
        )

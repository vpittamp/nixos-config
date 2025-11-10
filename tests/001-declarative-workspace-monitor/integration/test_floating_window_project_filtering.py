"""
Integration tests for floating window project filtering (Feature 001: T047, T048)

Tests:
- T047: Scoped floating windows hide on project switch
- T048: Global floating windows persist across projects
"""

import pytest
from i3ipc.aio import Connection

pytestmark = pytest.mark.asyncio


@pytest.fixture
async def sway_conn():
    """Provide async Sway IPC connection"""
    conn = await Connection(auto_reconnect=True).connect()
    yield conn
    conn.main_quit()


async def test_scoped_floating_window_hides_on_project_switch(sway_conn):
    """
    Test that scoped floating window (btop) hides when switching projects

    Given: btop running with floating=true, scope="scoped"
    When: Switch from project "nixos" to "test-project"
    Then: btop window moved to scratchpad (not visible)
    """
    # Launch btop (scoped floating window)
    await sway_conn.command("[app_id=\"btop\"] kill")
    await sway_conn.command("exec btop")

    # Wait for window to appear
    import asyncio
    await asyncio.sleep(1)

    # Verify btop is visible and floating
    tree = await sway_conn.get_tree()
    btop_windows = tree.find_named("^btop")
    assert len(btop_windows) > 0, "btop window not found"
    btop_window = btop_windows[0]
    assert btop_window.floating == "user_on", "btop should be floating"

    # Switch to test-project (assumes i3pm project switch command)
    await sway_conn.command("exec i3pm project switch test-project")
    await asyncio.sleep(0.5)  # Allow time for filtering

    # Verify btop is hidden (in scratchpad or not in tree)
    tree = await sway_conn.get_tree()
    visible_btop_windows = [w for w in tree.find_named("^btop") if w.workspace() is not None]
    assert len(visible_btop_windows) == 0, "Scoped btop should be hidden after project switch"


async def test_scoped_floating_window_restores_on_project_switch_back(sway_conn):
    """
    Test that scoped floating window restores when switching back to original project

    Given: btop hidden after project switch
    When: Switch back to "nixos" project
    Then: btop window restored to original workspace
    """
    # Launch btop and switch projects (from previous test)
    await sway_conn.command("[app_id=\"btop\"] kill")
    await sway_conn.command("exec btop")

    import asyncio
    await asyncio.sleep(1)

    # Switch away
    await sway_conn.command("exec i3pm project switch test-project")
    await asyncio.sleep(0.5)

    # Switch back to nixos project
    await sway_conn.command("exec i3pm project switch nixos")
    await asyncio.sleep(0.5)

    # Verify btop is visible again
    tree = await sway_conn.get_tree()
    visible_btop_windows = [w for w in tree.find_named("^btop") if w.workspace() is not None]
    assert len(visible_btop_windows) > 0, "Scoped btop should be restored after switching back"


async def test_global_floating_window_persists_across_projects(sway_conn):
    """
    Test that global floating window (pavucontrol) persists when switching projects

    Given: pavucontrol running with floating=true, scope="global"
    When: Switch from project "nixos" to "test-project"
    Then: pavucontrol window remains visible
    """
    # Launch pavucontrol (global floating window)
    await sway_conn.command("[app_id=\"org.pulseaudio.pavucontrol\"] kill")
    await sway_conn.command("exec pavucontrol")

    # Wait for window to appear
    import asyncio
    await asyncio.sleep(1)

    # Verify pavucontrol is visible and floating
    tree = await sway_conn.get_tree()
    pavucontrol_windows = tree.find_named("pavucontrol")
    assert len(pavucontrol_windows) > 0, "pavucontrol window not found"
    pavucontrol_window = pavucontrol_windows[0]
    assert pavucontrol_window.floating == "user_on", "pavucontrol should be floating"

    # Switch to test-project
    await sway_conn.command("exec i3pm project switch test-project")
    await asyncio.sleep(0.5)

    # Verify pavucontrol is still visible (global scope)
    tree = await sway_conn.get_tree()
    visible_pavucontrol = [w for w in tree.find_named("pavucontrol") if w.workspace() is not None]
    assert len(visible_pavucontrol) > 0, "Global pavucontrol should persist across project switches"


async def test_multiple_global_floating_windows_persist(sway_conn):
    """
    Test that multiple global floating windows persist together

    Given: Multiple global floating windows (pavucontrol, blueman-manager)
    When: Switch projects multiple times
    Then: All global floating windows remain visible
    """
    # Launch multiple global floating windows
    await sway_conn.command("[app_id=\"org.pulseaudio.pavucontrol\"] kill")
    await sway_conn.command("[app_id=\"blueman-manager\"] kill")
    await sway_conn.command("exec pavucontrol")
    await sway_conn.command("exec blueman-manager")

    # Wait for windows to appear
    import asyncio
    await asyncio.sleep(2)

    # Switch projects multiple times
    await sway_conn.command("exec i3pm project switch test-project")
    await asyncio.sleep(0.5)
    await sway_conn.command("exec i3pm project switch another-project")
    await asyncio.sleep(0.5)

    # Verify both windows still visible
    tree = await sway_conn.get_tree()
    visible_pavucontrol = [w for w in tree.find_named("pavucontrol") if w.workspace() is not None]
    visible_blueman = [w for w in tree.find_named("blueman") if w.workspace() is not None]

    assert len(visible_pavucontrol) > 0, "Global pavucontrol should persist"
    assert len(visible_blueman) > 0, "Global blueman should persist"


async def test_mixed_scoped_and_global_windows(sway_conn):
    """
    Test behavior when both scoped and global floating windows are present

    Given: Both scoped (btop) and global (pavucontrol) floating windows
    When: Switch projects
    Then: Scoped windows hide, global windows persist
    """
    # Launch both types
    await sway_conn.command("[app_id=\"btop\"] kill")
    await sway_conn.command("[app_id=\"org.pulseaudio.pavucontrol\"] kill")
    await sway_conn.command("exec btop")
    await sway_conn.command("exec pavucontrol")

    # Wait for windows to appear
    import asyncio
    await asyncio.sleep(2)

    # Switch project
    await sway_conn.command("exec i3pm project switch test-project")
    await asyncio.sleep(0.5)

    # Verify scoped hidden, global visible
    tree = await sway_conn.get_tree()
    visible_btop = [w for w in tree.find_named("^btop") if w.workspace() is not None]
    visible_pavucontrol = [w for w in tree.find_named("pavucontrol") if w.workspace() is not None]

    assert len(visible_btop) == 0, "Scoped btop should be hidden"
    assert len(visible_pavucontrol) > 0, "Global pavucontrol should persist"

"""Integration tests for layout save/restore functionality.

Tests the LayoutManager and WindowLauncher classes with real i3 environment.
"""

import pytest
import asyncio
from pathlib import Path
import sys
import json
import os

# Add i3pm to path
sys.path.insert(
    0,
    str(
        Path(__file__).parent.parent.parent.parent
        / "home-modules"
        / "tools"
        / "i3_project_manager"
    ),
)

from testing.integration import IntegrationTestFramework
from core.layout import (
    LayoutManager,
    LayoutSaveRequest,
    LayoutRestoreRequest,
    LayoutDeleteRequest,
    LayoutExportRequest,
    RestoreAllRequest,
    CloseAllRequest,
)
from core.models import Project


async def mark_xterm_windows_with_project(framework, project_name: str):
    """Helper to mark all XTerm windows with unique project marks.

    i3 marks must be unique per window, so we use project:name:windowN format.
    """
    tree = await framework.i3.get_tree()
    xterm_windows = []
    for con in tree.descendants():
        if con.window and con.window_class == "XTerm":
            xterm_windows.append(con)

    # Mark each window with a unique project mark
    for i, con in enumerate(xterm_windows):
        mark = f'project:{project_name}:window{i+1}'
        await framework.i3.command(f'[con_id={con.id}] mark --add {mark}')
        await asyncio.sleep(0.1)

    return len(xterm_windows)


@pytest.fixture
async def integration_env():
    """Create integration test environment."""
    async with IntegrationTestFramework(display=":99") as framework:
        yield framework


@pytest.fixture
async def layout_manager(integration_env):
    """Create LayoutManager instance."""
    framework = integration_env

    # Create a mock project manager
    class MockProjectManager:
        def __init__(self, config_dir):
            self.config_dir = config_dir
            self.projects = {}

        async def get_project(self, name):
            if name not in self.projects:
                # Create a test project
                project_dir = framework.env.temp_dir / name
                project_dir.mkdir(parents=True, exist_ok=True)

                self.projects[name] = Project(
                    name=name,
                    display_name=f"Test {name}",
                    directory=str(project_dir),
                    icon="🧪",
                    scoped_classes=["XTerm", "Ghostty", "Code"],  # Add scoped classes
                    saved_layouts=[],
                    auto_launch=[],
                )
            return self.projects[name]

        async def save_project(self, project):
            self.projects[project.name] = project

    project_manager = MockProjectManager(framework.env.config_dir)

    # Create LayoutManager
    manager = LayoutManager(
        i3_connection=framework.i3,
        config_dir=framework.env.config_dir,
        project_manager=project_manager,
    )

    return manager


@pytest.mark.integration
@pytest.mark.asyncio
async def test_save_layout_basic(integration_env, layout_manager):
    """Test saving a basic layout with windows.

    Duration: ~10s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: Save Layout Basic ===")

    # Launch test windows
    print("\nLaunching 2 test windows...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await asyncio.sleep(0.5)  # Small delay between launches
    proc2 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)

    # Wait for both windows to be fully registered in i3
    await asyncio.sleep(1.0)

    # Mark windows with project mark
    print("\nMarking windows with project:test-project...")

    # Find all XTerm windows
    tree = await framework.i3.get_tree()
    xterm_windows = []
    for con in tree.descendants():
        if con.window and con.window_class == "XTerm":
            xterm_windows.append(con)
            print(f"  Window found: {con.window_class} (id={con.window}, con_id={con.id})")

    print(f"  Found {len(xterm_windows)} XTerm windows total")

    # Mark each window by first focusing it, then marking it
    for i, con in enumerate(xterm_windows):
        # Focus the window first
        focus_result = await framework.i3.command(f'[con_id={con.id}] focus')
        print(f"  Focused window {i+1} con_id={con.id}, result: {focus_result}")
        await asyncio.sleep(0.1)

        # Now mark the focused window with a unique mark AND the project mark
        # Use unique marks first to test if multi-mark works
        unique_mark = f'testwindow{i+1}'
        mark_result1 = await framework.i3.command(f'mark --add {unique_mark}')
        print(f"  Added unique mark '{unique_mark}', result: {mark_result1}")
        await asyncio.sleep(0.1)

        # Add the project mark
        mark_result2 = await framework.i3.command('mark --add project_test_project')  # Use underscore instead of colon
        print(f"  Added project mark, result: {mark_result2}")
        await asyncio.sleep(0.2)

    # Wait for all marks to be fully applied
    await asyncio.sleep(0.5)

    # Verify marks were applied
    tree = await framework.i3.get_tree()
    marked_count = 0
    for con in tree.descendants():
        if con.window and "project_test_project" in (con.marks or []):
            marked_count += 1
            print(f"  Found marked window: {con.window_class} (id={con.window}, con_id={con.id}) with marks {con.marks}")
    print(f"  Total marked windows with project mark: {marked_count}")

    if marked_count != len(xterm_windows):
        print(f"  WARNING: Only {marked_count}/{len(xterm_windows)} windows were marked successfully")
        # Print all windows for debugging
        print(f"  All windows in tree:")
        for con in tree.descendants():
            if con.window:
                print(f"    {con.window_class} (id={con.window}, con_id={con.id}) marks={con.marks}")

    # Manually mark windows with the project mark format for the layout manager
    # The layout manager expects "project:project-name" format
    # Note: i3 marks need to be unique per window, so we use the unique marks
    # that were already applied (testwindow1, testwindow2) and also add window IDs
    for i, con in enumerate(xterm_windows):
        # Use a unique project mark for each window
        project_mark = f'project:test-project:window{i+1}'
        await framework.i3.command(f'[con_id={con.id}] mark --add {project_mark}')
        await asyncio.sleep(0.1)
        print(f"  Applied mark '{project_mark}' to window {i+1}")

    print("\n  All windows now have unique project marks")

    # Save layout
    print("\nSaving layout 'test-layout'...")
    request = LayoutSaveRequest(
        project_name="test-project",
        layout_name="test-layout",
        capture_launch_commands=True,
        capture_environment=False,  # Skip env capture for speed
    )

    response = await manager.save_layout(request)

    print(f"\nLayout save response:")
    print(f"  Success: {response.success}")
    print(f"  Windows captured: {response.windows_captured}")
    print(f"  Workspaces captured: {response.workspaces_captured}")
    print(f"  Layout path: {response.layout_path}")

    # Verify response
    assert response.success, f"Save failed: {response.error}"
    assert response.windows_captured == 2, f"Expected 2 windows, got {response.windows_captured}"
    assert response.workspaces_captured >= 1
    assert response.layout_path.exists()

    # Verify layout file structure
    with open(response.layout_path) as f:
        layout_data = json.load(f)
        assert layout_data["layout_name"] == "test-layout"
        assert layout_data["project_name"] == "test-project"
        assert len(layout_data["workspaces"]) >= 1
        # Check that we captured 2 windows
        total_windows = sum(len(ws["windows"]) for ws in layout_data["workspaces"])
        assert total_windows == 2, f"Expected 2 windows total, got {total_windows}"

    # Cleanup
    await framework.close_all_windows()

    print("\n✅ Save layout basic test passed")


@pytest.mark.integration
@pytest.mark.asyncio
async def test_restore_layout_with_relaunch(integration_env, layout_manager):
    """Test restoring a layout by relaunching windows.

    Duration: ~15s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: Restore Layout with Relaunch ===")

    # First, create a layout
    print("\nStep 1: Creating initial layout...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await framework.i3.command('[class="XTerm"] mark --add project:test-project')
    await asyncio.sleep(0.5)

    save_request = LayoutSaveRequest(
        project_name="test-project",
        layout_name="restore-test",
        capture_launch_commands=True,
        capture_environment=False,
    )

    save_response = await manager.save_layout(save_request)
    assert save_response.success

    # Close all windows
    print("\nStep 2: Closing all windows...")
    await framework.close_all_windows()
    await asyncio.sleep(0.5)

    # Verify windows closed
    window_count = await framework._get_window_count()
    assert window_count == 0, "Windows should be closed"

    # Restore layout
    print("\nStep 3: Restoring layout (should relaunch windows)...")
    restore_request = LayoutRestoreRequest(
        project_name="test-project",
        layout_name="restore-test",
        relaunch_missing=True,
        reposition_existing=True,
    )

    restore_response = await manager.restore_layout(restore_request)

    print(f"\nLayout restore response:")
    print(f"  Success: {restore_response.success}")
    print(f"  Windows restored: {restore_response.windows_restored}")
    print(f"  Windows launched: {restore_response.windows_launched}")
    print(f"  Windows failed: {restore_response.windows_failed}")
    print(f"  Duration: {restore_response.duration:.2f}s")

    # Verify response
    assert restore_response.success, f"Restore failed: {restore_response.error}"
    assert restore_response.windows_launched >= 1, "Should have launched at least 1 window"
    assert restore_response.windows_failed == 0
    assert restore_response.duration < 30.0, "Should complete within 30s"

    # Verify windows appeared
    await asyncio.sleep(1.0)
    window_count = await framework._get_window_count()
    assert window_count >= 1, "Windows should be restored"

    # Cleanup
    await framework.close_all_windows()

    print("\n✅ Restore layout with relaunch test passed")


@pytest.mark.integration
@pytest.mark.asyncio
async def test_delete_layout(integration_env, layout_manager):
    """Test deleting a saved layout.

    Duration: ~5s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: Delete Layout ===")

    # Create a layout
    print("\nStep 1: Creating layout to delete...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await framework.i3.command('[class="XTerm"] mark --add project:test-project')
    await asyncio.sleep(0.5)

    save_request = LayoutSaveRequest(
        project_name="test-project",
        layout_name="delete-me",
        capture_launch_commands=True,
        capture_environment=False,
    )

    save_response = await manager.save_layout(save_request)
    assert save_response.success
    layout_path = save_response.layout_path
    assert layout_path.exists()

    # Delete layout
    print("\nStep 2: Deleting layout...")
    delete_request = LayoutDeleteRequest(
        project_name="test-project",
        layout_name="delete-me",
        confirmed=True,
    )

    delete_response = await manager.delete_layout(delete_request)

    print(f"\nDelete response:")
    print(f"  Success: {delete_response.success}")
    print(f"  Layout name: {delete_response.layout_name}")

    # Verify deletion
    assert delete_response.success, f"Delete failed: {delete_response.error}"
    assert not layout_path.exists(), "Layout file should be deleted"

    # Cleanup
    await framework.close_all_windows()

    print("\n✅ Delete layout test passed")


@pytest.mark.integration
@pytest.mark.asyncio
async def test_export_layout(integration_env, layout_manager):
    """Test exporting a layout to file.

    Duration: ~5s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: Export Layout ===")

    # Create a layout
    print("\nStep 1: Creating layout to export...")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    await framework.i3.command('[class="XTerm"] mark --add project:test-project')
    await asyncio.sleep(0.5)

    save_request = LayoutSaveRequest(
        project_name="test-project",
        layout_name="export-test",
        capture_launch_commands=True,
        capture_environment=False,
    )

    save_response = await manager.save_layout(save_request)
    assert save_response.success

    # Export layout
    print("\nStep 2: Exporting layout...")
    export_path = framework.env.temp_dir / "exported-layout.json"

    export_request = LayoutExportRequest(
        project_name="test-project",
        layout_name="export-test",
        export_path=export_path,
        include_metadata=True,
    )

    export_response = await manager.export_layout(export_request)

    print(f"\nExport response:")
    print(f"  Success: {export_response.success}")
    print(f"  Export path: {export_response.export_path}")
    print(f"  File size: {export_response.file_size} bytes")

    # Verify export
    assert export_response.success, f"Export failed: {export_response.error}"
    assert export_path.exists(), "Export file should exist"
    assert export_response.file_size > 0

    # Verify exported data
    with open(export_path) as f:
        exported_data = json.load(f)
        assert "exported_at" in exported_data
        assert "exported_from" in exported_data

    # Cleanup
    await framework.close_all_windows()

    print("\n✅ Export layout test passed")


@pytest.mark.integration
@pytest.mark.asyncio
async def test_list_layouts(integration_env, layout_manager):
    """Test listing saved layouts with metadata.

    Duration: ~10s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: List Layouts ===")

    # Create multiple layouts
    print("\nStep 1: Creating 3 test layouts...")
    for i in range(3):
        proc = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
        await framework.i3.command('[class="XTerm"] mark --add project:test-project')
        await asyncio.sleep(0.5)

        save_request = LayoutSaveRequest(
            project_name="test-project",
            layout_name=f"layout-{i+1}",
            capture_launch_commands=True,
            capture_environment=False,
        )

        save_response = await manager.save_layout(save_request)
        assert save_response.success

        await framework.close_all_windows()
        await asyncio.sleep(0.5)

    # List layouts
    print("\nStep 2: Listing layouts...")
    layouts = await manager.list_layouts("test-project")

    print(f"\nFound {len(layouts)} layouts:")
    for layout in layouts:
        print(f"  - {layout.layout_name}: {layout.window_count} windows, "
              f"{layout.workspace_count} workspaces, {layout.monitor_config}")

    # Verify listing
    assert len(layouts) >= 3, f"Expected at least 3 layouts, got {len(layouts)}"

    for layout in layouts:
        assert layout.window_count >= 1
        assert layout.workspace_count >= 1
        assert layout.monitor_config in ["single", "dual", "triple"]

    print("\n✅ List layouts test passed")


@pytest.mark.integration
@pytest.mark.asyncio
async def test_close_all_windows(integration_env, layout_manager):
    """Test closing all project-scoped windows.

    Duration: ~5s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: Close All Windows ===")

    # Launch windows with project mark
    print("\nStep 1: Launching 3 windows with project mark...")
    for i in range(3):
        proc = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)

    # Wait for all windows to be fully registered
    await asyncio.sleep(1.0)

    # Mark all windows with unique project marks
    marked_count = await mark_xterm_windows_with_project(framework, "test-project")
    await asyncio.sleep(0.5)

    # Verify windows exist and are marked
    window_count = await framework._get_window_count()
    assert window_count >= 3, "Should have at least 3 windows"
    assert marked_count >= 3, f"Expected to mark 3 windows, marked {marked_count}"

    # Close all
    print("\nStep 2: Closing all project windows...")
    close_request = CloseAllRequest(
        project_name="test-project",
        force=False,
    )

    close_response = await manager.close_all(close_request)

    print(f"\nClose all response:")
    print(f"  Success: {close_response.success}")
    print(f"  Windows closed: {close_response.windows_closed}")
    print(f"  Windows failed: {close_response.windows_failed}")

    # Verify close
    assert close_response.success, f"Close all failed: {close_response.error}"
    assert close_response.windows_closed >= 3
    assert close_response.windows_failed == 0

    # Verify windows closed
    await asyncio.sleep(0.5)
    window_count = await framework._get_window_count()
    assert window_count == 0, "All windows should be closed"

    print("\n✅ Close all windows test passed")


@pytest.mark.integration
@pytest.mark.slow
@pytest.mark.asyncio
async def test_complete_layout_workflow(integration_env, layout_manager):
    """Test complete layout workflow: save -> close -> restore.

    Duration: ~20s
    """
    framework = integration_env
    manager = layout_manager

    print("\n=== Test: Complete Layout Workflow ===")

    # Step 1: Launch windows
    print("\nStep 1: Launching 3 windows across 2 workspaces...")
    await framework.i3.command("workspace number 1")
    proc1 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)
    proc2 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)

    await framework.i3.command("workspace number 2")
    proc3 = await framework.launch_application("xterm", wait_for_window=True, timeout=5.0)

    # Wait for all windows to be fully registered
    await asyncio.sleep(1.0)

    # Mark all windows with unique project marks
    marked_count = await mark_xterm_windows_with_project(framework, "workflow-test")
    await asyncio.sleep(0.5)
    assert marked_count >= 3, f"Expected to mark 3 windows, marked {marked_count}"

    # Step 2: Save layout
    print("\nStep 2: Saving layout...")
    save_request = LayoutSaveRequest(
        project_name="workflow-test",
        layout_name="complete-workflow",
        capture_launch_commands=True,
        capture_environment=False,
    )

    save_response = await manager.save_layout(save_request)
    assert save_response.success
    assert save_response.windows_captured == 3
    assert save_response.workspaces_captured == 2

    print(f"  Saved {save_response.windows_captured} windows across "
          f"{save_response.workspaces_captured} workspaces")

    # Step 3: Close all windows
    print("\nStep 3: Closing all windows...")
    close_request = CloseAllRequest(
        project_name="workflow-test",
        force=False,
    )

    close_response = await manager.close_all(close_request)
    assert close_response.success
    assert close_response.windows_closed == 3

    await asyncio.sleep(1.0)

    # Verify empty
    window_count = await framework._get_window_count()
    assert window_count == 0, "All windows should be closed"

    # Step 4: Restore layout
    print("\nStep 4: Restoring layout (relaunching windows)...")
    restore_request = LayoutRestoreRequest(
        project_name="workflow-test",
        layout_name="complete-workflow",
        relaunch_missing=True,
        reposition_existing=True,
    )

    restore_response = await manager.restore_layout(restore_request)
    assert restore_response.success, f"Restore failed: {restore_response.error}"
    assert restore_response.windows_launched >= 3

    print(f"  Restored {restore_response.windows_launched} windows in "
          f"{restore_response.duration:.2f}s")

    await asyncio.sleep(1.0)

    # Verify windows restored
    window_count = await framework._get_window_count()
    assert window_count >= 3, f"Expected at least 3 windows, got {window_count}"

    # Cleanup
    await framework.close_all_windows()

    print("\n✅ Complete layout workflow test passed")


if __name__ == "__main__":
    """Allow running directly for quick testing."""
    import sys

    print("Running layout management integration tests...")
    print("These tests verify save/restore/delete/export functionality.\\n")

    # Run with pytest
    sys.exit(
        pytest.main(
            [
                __file__,
                "-v",
                "-s",
                "-m",
                "integration",
                "--tb=short",
            ]
        )
    )

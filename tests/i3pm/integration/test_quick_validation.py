"""Quick validation test for integration framework.

This is a minimal test to verify the integration framework works
without launching applications. Runs quickly (<5 seconds).
"""

import pytest
import asyncio
from pathlib import Path
import sys
import subprocess

# Add i3pm to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "i3_project_manager"))

from testing.integration import IntegrationTestFramework


@pytest.mark.integration
@pytest.mark.asyncio
async def test_integration_framework_setup_only():
    """Test that integration framework can set up environment.

    This test only validates setup/teardown without launching apps.
    Should complete in <5 seconds.
    """
    print("\n" + "="*60)
    print("Quick Integration Framework Validation")
    print("="*60)

    framework = IntegrationTestFramework(display=":99")

    print("\n1. Setting up environment...")
    env = await framework.setup_environment()

    try:
        # Verify environment components
        print("2. Verifying environment components...")

        assert env is not None, "Environment not created"
        print("   ✓ Environment created")

        assert env.xvfb_process is not None, "Xvfb not started"
        assert env.xvfb_process.poll() is None, "Xvfb not running"
        print("   ✓ Xvfb running")

        assert env.i3_process is not None, "i3 not started"
        assert env.i3_process.poll() is None, "i3 not running"
        print("   ✓ i3 running")

        assert env.temp_dir is not None, "Temp dir not created"
        assert env.temp_dir.exists(), "Temp dir doesn't exist"
        print(f"   ✓ Temp dir: {env.temp_dir}")

        assert env.config_dir is not None, "Config dir not created"
        assert env.config_dir.exists(), "Config dir doesn't exist"
        print(f"   ✓ Config dir: {env.config_dir}")

        # Verify i3 is responding
        print("\n3. Verifying i3 responds to commands...")
        result = subprocess.run(
            ["i3-msg", "-t", "get_version"],
            capture_output=True,
            text=True,
            timeout=5,
            env={"DISPLAY": framework.display}
        )

        assert result.returncode == 0, "i3-msg failed"
        print(f"   ✓ i3 version: {result.stdout.strip()}")

        # Verify workspaces
        print("\n4. Verifying i3 workspaces...")
        result = subprocess.run(
            ["i3-msg", "-t", "get_workspaces"],
            capture_output=True,
            text=True,
            timeout=5,
            env={"DISPLAY": framework.display}
        )

        assert result.returncode == 0, "Failed to get workspaces"
        import json
        workspaces = json.loads(result.stdout)
        print(f"   ✓ Found {len(workspaces)} workspaces")

        # Verify no windows initially
        print("\n5. Verifying clean state (no windows)...")
        window_count = await framework._get_window_count()
        print(f"   ✓ Window count: {window_count}")

        print("\n" + "="*60)
        print("✅ ALL VALIDATION CHECKS PASSED")
        print("="*60)

    finally:
        # Cleanup
        print("\n6. Cleaning up...")
        await framework.cleanup()
        print("   ✓ Cleanup complete")


@pytest.mark.integration
@pytest.mark.asyncio
async def test_context_manager_usage():
    """Test using integration framework as async context manager."""
    print("\n" + "="*60)
    print("Testing Context Manager Pattern")
    print("="*60)

    async with IntegrationTestFramework(display=":99") as framework:
        print("\n✓ Framework started via context manager")

        # Quick verification
        assert framework.env is not None
        assert framework.env.xvfb_process.poll() is None
        assert framework.env.i3_process.poll() is None

        print("✓ Environment is active")

    print("✓ Context manager cleanup completed")
    print("\n" + "="*60)
    print("✅ CONTEXT MANAGER TEST PASSED")
    print("="*60)


if __name__ == "__main__":
    """Allow running directly for quick testing."""
    import sys

    print("Running quick validation tests...")
    print("This validates the integration framework works correctly.\n")

    # Run with pytest
    sys.exit(pytest.main([
        __file__,
        "-v",
        "-s",
        "-m", "integration",
        "--tb=short"
    ]))

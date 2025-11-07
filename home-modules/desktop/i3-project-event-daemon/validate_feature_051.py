#!/usr/bin/env python3
"""
Direct validation script for Feature 051 (Run-Raise-Hide) implementation.
This script validates that all components are correctly implemented without relying on pytest.
"""

import sys
import asyncio
from typing import Dict, Any
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from models.window_state import (
    WindowState,
    WindowStateInfo,
    RunMode,
    RunRequest,
    RunResponse,
)


def validate_models() -> Dict[str, Any]:
    """Validate that all data models are correctly defined."""
    results = {"passed": [], "failed": []}

    # Test WindowState enum
    try:
        assert len(WindowState) == 5, "WindowState should have exactly 5 states"
        assert WindowState.NOT_FOUND.value == "not_found"
        assert WindowState.DIFFERENT_WORKSPACE.value == "different_workspace"
        assert WindowState.SAME_WORKSPACE_UNFOCUSED.value == "same_workspace_unfocused"
        assert WindowState.SAME_WORKSPACE_FOCUSED.value == "same_workspace_focused"
        assert WindowState.SCRATCHPAD.value == "scratchpad"
        results["passed"].append("WindowState enum (5 states)")
    except AssertionError as e:
        results["failed"].append(f"WindowState enum: {e}")

    # Test RunMode enum
    try:
        assert len(RunMode) == 3, "RunMode should have exactly 3 modes"
        assert RunMode.SUMMON.value == "summon"
        assert RunMode.HIDE.value == "hide"
        assert RunMode.NOHIDE.value == "nohide"
        results["passed"].append("RunMode enum (3 modes)")
    except AssertionError as e:
        results["failed"].append(f"RunMode enum: {e}")

    # Test RunRequest model
    try:
        req = RunRequest(app_name="firefox", mode="summon", force_launch=False)
        assert req.app_name == "firefox"
        assert req.mode == "summon"
        assert req.force_launch is False

        # Test defaults
        req2 = RunRequest(app_name="firefox")
        assert req2.mode == "summon"
        assert req2.force_launch is False

        results["passed"].append("RunRequest Pydantic model")
    except Exception as e:
        results["failed"].append(f"RunRequest model: {e}")

    # Test RunResponse model
    try:
        resp = RunResponse(
            action="launched",
            window_id=12345,
            focused=True,
            message="Launched Firefox"
        )
        assert resp.action == "launched"
        assert resp.window_id == 12345
        assert resp.focused is True
        assert resp.message == "Launched Firefox"

        # Test with None window_id
        resp2 = RunResponse(
            action="launched",
            window_id=None,
            focused=False,
            message="Launched"
        )
        assert resp2.window_id is None

        results["passed"].append("RunResponse Pydantic model")
    except Exception as e:
        results["failed"].append(f"RunResponse model: {e}")

    # Test WindowStateInfo dataclass
    try:
        info = WindowStateInfo(
            state=WindowState.NOT_FOUND,
            window=None,
            current_workspace="1",
            window_workspace=None,
            is_focused=False
        )
        assert info.state == WindowState.NOT_FOUND
        assert info.window_id is None
        assert info.is_floating is False
        assert info.geometry is None

        results["passed"].append("WindowStateInfo dataclass")
    except Exception as e:
        results["failed"].append(f"WindowStateInfo dataclass: {e}")

    return results


def validate_manager_class() -> Dict[str, Any]:
    """Validate that RunRaiseManager class exists and has required methods."""
    results = {"passed": [], "failed": []}

    try:
        # Add parent directory to sys.path for proper package imports
        desktop_path = str(Path(__file__).parent.parent)
        if desktop_path not in sys.path:
            sys.path.insert(0, desktop_path)

        # Import using the i3_project_event_daemon package name (symlink)
        from i3_project_event_daemon.services.run_raise_manager import RunRaiseManager

        # Check class exists
        assert RunRaiseManager is not None
        results["passed"].append("RunRaiseManager class exists")

        # Check required methods
        required_methods = [
            "detect_window_state",
            "execute_transition",
            "_transition_launch",
            "_transition_focus",
            "_transition_goto",
            "_transition_summon",
            "_transition_hide",
            "_transition_show",
            "register_window",
            "unregister_window",
        ]

        for method_name in required_methods:
            if hasattr(RunRaiseManager, method_name):
                results["passed"].append(f"RunRaiseManager.{method_name}() exists")
            else:
                results["failed"].append(f"RunRaiseManager.{method_name}() missing")

    except ImportError as e:
        results["failed"].append(f"RunRaiseManager import failed: {e}")
    except Exception as e:
        results["failed"].append(f"RunRaiseManager validation error: {e}")

    return results


def validate_cli_command() -> Dict[str, Any]:
    """Validate that CLI command exists and is functional."""
    results = {"passed": [], "failed": []}

    import subprocess

    try:
        # Test help command
        result = subprocess.run(
            ["i3pm", "run", "--help"],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            output = result.stdout

            # Check for required content in help
            required_strings = [
                "i3pm run",
                "--summon",
                "--hide",
                "--nohide",
                "--force",
                "--json",
                "STATE MACHINE",
            ]

            for req_str in required_strings:
                if req_str in output:
                    results["passed"].append(f"CLI help contains '{req_str}'")
                else:
                    results["failed"].append(f"CLI help missing '{req_str}'")
        else:
            results["failed"].append(f"CLI help command failed with code {result.returncode}")

    except subprocess.TimeoutExpired:
        results["failed"].append("CLI help command timed out")
    except FileNotFoundError:
        results["failed"].append("i3pm command not found in PATH")
    except Exception as e:
        results["failed"].append(f"CLI validation error: {e}")

    return results


def print_results(category: str, results: Dict[str, Any]):
    """Print validation results for a category."""
    print(f"\n{'='*70}")
    print(f"  {category}")
    print(f"{'='*70}")

    if results["passed"]:
        print(f"\n✅ PASSED ({len(results['passed'])} tests):")
        for item in results["passed"]:
            print(f"  ✓ {item}")

    if results["failed"]:
        print(f"\n❌ FAILED ({len(results['failed'])} tests):")
        for item in results["failed"]:
            print(f"  ✗ {item}")

    return len(results["failed"]) == 0


def main():
    """Run all validations and report results."""
    print("\n" + "="*70)
    print("  Feature 051: Run-Raise-Hide Implementation Validation")
    print("="*70)

    all_passed = True

    # Validate models
    model_results = validate_models()
    all_passed &= print_results("Data Models", model_results)

    # Validate manager class
    manager_results = validate_manager_class()
    all_passed &= print_results("RunRaiseManager Class", manager_results)

    # Validate CLI
    cli_results = validate_cli_command()
    all_passed &= print_results("CLI Command", cli_results)

    # Final summary
    print(f"\n{'='*70}")
    total_passed = sum(len(r["passed"]) for r in [model_results, manager_results, cli_results])
    total_failed = sum(len(r["failed"]) for r in [model_results, manager_results, cli_results])

    if all_passed:
        print(f"  ✅ ALL VALIDATION PASSED ({total_passed} tests)")
    else:
        print(f"  ⚠️  SOME VALIDATION FAILED: {total_failed} failures, {total_passed} passed")

    print(f"{'='*70}\n")

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())

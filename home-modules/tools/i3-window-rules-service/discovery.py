"""
Window pattern discovery service.

Launches applications and captures their window properties to generate verified patterns.
"""

import asyncio
import subprocess
import time
from typing import Optional
from datetime import datetime

try:
    from .models import (
        Window,
        Pattern,
        PatternType,
        ApplicationDefinition,
        DiscoveryResult,
    )
    from .i3_client import I3Client
except ImportError:
    from models import (
        Window,
        Pattern,
        PatternType,
        ApplicationDefinition,
        DiscoveryResult,
    )
    from i3_client import I3Client


async def launch_application_direct(command: str) -> bool:
    """
    Launch application using direct command execution.

    Args:
        command: Command to execute

    Returns:
        True if launch successful, False otherwise
    """
    try:
        # Launch in background with detached process
        subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except Exception:
        return False


async def launch_via_rofi(app_name: str) -> bool:
    """
    Launch application by simulating rofi launcher workflow.

    Args:
        app_name: Application name as it appears in rofi

    Returns:
        True if launch successful, False otherwise
    """
    try:
        # Trigger rofi with Meta+D
        subprocess.run(["xdotool", "key", "super+d"], check=True)
        await asyncio.sleep(0.5)  # Wait for rofi to appear

        # Type application name
        subprocess.run(["xdotool", "type", app_name], check=True)
        await asyncio.sleep(0.2)

        # Press Enter to launch
        subprocess.run(["xdotool", "key", "Return"], check=True)
        return True
    except Exception:
        return False


def generate_pattern(window: Window) -> tuple[Pattern, float]:
    """
    Generate a window matching pattern from captured window properties.

    Args:
        window: Captured window

    Returns:
        Tuple of (Pattern, confidence_score)
    """
    # Detect terminal emulators - use title-based matching
    if window.is_terminal:
        # Extract command from title if possible
        title = window.title
        # Common terminal title formats:
        # "lazygit - ~/project"
        # "vim: file.txt"
        # "~/.config/i3"

        # Try to extract command name from title
        if " - " in title:
            command_part = title.split(" - ")[0].strip()
        elif ":" in title:
            command_part = title.split(":")[0].strip()
        else:
            command_part = title.strip()

        # If we have a clear command name, use it
        if command_part and len(command_part) > 0 and not command_part.startswith("~"):
            pattern = Pattern(
                type=PatternType.TITLE,
                value=command_part,
                description=f"Terminal application: {command_part}",
                priority=10,
                case_sensitive=False,
            )
            confidence = 0.9  # High confidence for extracted command
        else:
            # Fall back to full title match
            pattern = Pattern(
                type=PatternType.TITLE,
                value=title,
                description=f"Terminal with title: {title}",
                priority=10,
                case_sensitive=False,
            )
            confidence = 0.7  # Lower confidence for full title

        return pattern, confidence

    # Detect PWAs - use exact class match
    if window.is_pwa:
        pattern = Pattern(
            type=PatternType.CLASS,
            value=window.window_class,
            description=f"PWA: {window.window_class}",
            priority=5,
            case_sensitive=True,
        )
        return pattern, 1.0  # Exact match

    # Standard GUI applications - use class match
    # Check if class is specific enough
    generic_classes = ["Unknown", "Xdg-desktop-portal-gtk", "Gnome-", "Kde-"]
    is_generic = any(window.window_class.startswith(g) for g in generic_classes)

    if not is_generic and window.window_class != "Unknown":
        pattern = Pattern(
            type=PatternType.CLASS,
            value=window.window_class,
            description=f"GUI application: {window.window_class}",
            priority=10,
            case_sensitive=True,
        )
        return pattern, 1.0  # Exact class match

    # Fall back to title-based matching if class is generic
    pattern = Pattern(
        type=PatternType.TITLE,
        value=window.title,
        description=f"Title-based match: {window.title}",
        priority=10,
        case_sensitive=False,
    )
    return pattern, 0.7  # Lower confidence


async def discover_application(
    app_def: ApplicationDefinition,
    launch_method: str = "direct",
    timeout: float = 10.0,
    keep_window: bool = False,
    project_dir: Optional[str] = None,
) -> DiscoveryResult:
    """
    Discover window pattern for an application.

    Args:
        app_def: Application definition
        launch_method: "direct" or "rofi"
        timeout: Maximum time to wait for window (seconds)
        keep_window: If True, don't close window after discovery
        project_dir: Project directory for parameter substitution

    Returns:
        DiscoveryResult with captured window and generated pattern
    """
    start_time = time.time()
    errors = []
    warnings = []

    # Get full command with parameter substitution
    kwargs = {}
    if project_dir:
        kwargs["project_dir"] = project_dir
    full_command = app_def.get_full_command(**kwargs)

    # Connect to i3
    i3 = I3Client()
    try:
        await i3.connect()
    except Exception as e:
        errors.append(f"Failed to connect to i3: {e}")
        return DiscoveryResult(
            application_name=app_def.display_name,
            launch_command=full_command,
            launch_method=launch_method,
            wait_duration=time.time() - start_time,
            success=False,
            errors=errors,
        )

    # Launch application
    launch_success = False
    if launch_method == "rofi":
        rofi_name = app_def.rofi_name or app_def.display_name
        launch_success = await launch_via_rofi(rofi_name)
        if not launch_success:
            warnings.append("Rofi launch failed, falling back to direct command")
            launch_method = "direct"

    if launch_method == "direct":
        launch_success = await launch_application_direct(full_command)

    if not launch_success:
        errors.append(f"Failed to launch application with command: {full_command}")
        await i3.disconnect()
        return DiscoveryResult(
            application_name=app_def.display_name,
            launch_command=full_command,
            launch_method=launch_method,
            wait_duration=time.time() - start_time,
            success=False,
            errors=errors,
            warnings=warnings,
        )

    # Wait for window to appear
    try:
        window = await i3.wait_for_window_event(timeout=timeout)
    except Exception as e:
        errors.append(f"Error waiting for window: {e}")
        window = None

    wait_duration = time.time() - start_time

    if window is None:
        errors.append(f"Window did not appear within {timeout}s timeout")
        await i3.disconnect()
        return DiscoveryResult(
            application_name=app_def.display_name,
            launch_command=full_command,
            launch_method=launch_method,
            wait_duration=wait_duration,
            success=False,
            errors=errors,
            warnings=warnings,
        )

    # Generate pattern
    pattern, confidence = generate_pattern(window)

    # Validate pattern matches expected values if provided
    if app_def.expected_class:
        if window.window_class != app_def.expected_class:
            warnings.append(
                f"Window class '{window.window_class}' differs from expected '{app_def.expected_class}'"
            )

    if app_def.expected_title_contains:
        if app_def.expected_title_contains not in window.title:
            warnings.append(
                f"Title '{window.title}' does not contain expected '{app_def.expected_title_contains}'"
            )

    # Close window if requested
    if not keep_window:
        await i3.close_window(window.id)

    await i3.disconnect()

    return DiscoveryResult(
        application_name=app_def.display_name,
        launch_command=full_command,
        launch_method=launch_method,
        window=window,
        capture_time=datetime.now(),
        wait_duration=wait_duration,
        generated_pattern=pattern,
        confidence=confidence,
        success=True,
        warnings=warnings,
        errors=errors,
    )


async def discover_from_open_windows() -> list[DiscoveryResult]:
    """
    Discover patterns from currently open windows via i3 IPC.

    This is MUCH faster than launch-based discovery:
    - No app launching required (instant vs 15s per app)
    - Works with currently running applications
    - Non-disruptive (no window opening/closing)

    Returns:
        List of discovery results for all open windows
    """
    start_time = time.time()
    results = []

    # Connect to i3
    i3 = I3Client()
    try:
        await i3.connect()
    except Exception as e:
        print(f"✗ Failed to connect to i3: {e}")
        return results

    # Get all windows
    try:
        windows = await i3.get_windows()
    except Exception as e:
        print(f"✗ Failed to query windows: {e}")
        await i3.disconnect()
        return results

    # Generate patterns for each window
    for window in windows:
        pattern, confidence = generate_pattern(window)

        result = DiscoveryResult(
            application_name=window.window_class or window.title,
            launch_command="N/A - discovered from open window",
            launch_method="scan",
            window=window,
            capture_time=datetime.now(),
            wait_duration=0.0,  # Instant discovery
            generated_pattern=pattern,
            confidence=confidence,
            success=True,
            warnings=[],
            errors=[],
        )
        results.append(result)

    await i3.disconnect()

    scan_duration = time.time() - start_time
    print(f"\n✓ Scanned {len(results)} open windows in {scan_duration:.2f}s")

    return results


async def discover_from_registry(
    registry_apps: list[ApplicationDefinition],
    timeout: float = 10.0,
    delay: float = 1.0,
) -> list[DiscoveryResult]:
    """
    Discover patterns for multiple applications from registry.

    Args:
        registry_apps: List of application definitions
        timeout: Timeout per application
        delay: Delay between launches to avoid overwhelming WM

    Returns:
        List of discovery results
    """
    results = []

    for i, app_def in enumerate(registry_apps, 1):
        print(f"[{i}/{len(registry_apps)}] Discovering {app_def.display_name}...")

        result = await discover_application(
            app_def,
            launch_method="direct",
            timeout=timeout,
            keep_window=False,
        )

        results.append(result)

        # Show result
        if result.success:
            print(f"  ✓ {result.generated_pattern.type.value}:{result.generated_pattern.value} ({result.wait_duration:.1f}s)")
        else:
            print(f"  ✗ Failed: {', '.join(result.errors)}")

        # Delay before next application
        if i < len(registry_apps):
            await asyncio.sleep(delay)

    return results

"""Launch correlation assertions for test scenarios.

Feature 041: IPC Launch Context - T015

This module provides assertion functions for validating launch notification and
window correlation via the daemon's IPC server.
"""

import logging
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class LaunchAssertions:
    """Assertions for launch notification and correlation validation."""

    def __init__(self, daemon_client):
        """Initialize launch assertions.

        Args:
            daemon_client: Client for communicating with daemon (DaemonClient instance)
        """
        self.daemon_client = daemon_client

    async def assert_window_correlated(
        self,
        window_state: Dict[str, Any],
        expected_project: str,
        expected_confidence_min: float = 0.6
    ) -> None:
        """
        Assert that a window was successfully correlated to a launch.

        Args:
            window_state: Window state dict from daemon (from get_window_state or similar)
            expected_project: Expected project name the window should be assigned to
            expected_confidence_min: Minimum acceptable confidence score (default: 0.6)

        Raises:
            AssertionError: If window was not correlated or confidence is too low
        """
        # Check if window has project assignment
        actual_project = window_state.get("project")
        if actual_project != expected_project:
            raise AssertionError(
                f"Window {window_state.get('window_id')} was assigned to project "
                f"'{actual_project}', expected '{expected_project}'"
            )

        # Check if correlation info exists (if available in window state)
        correlation = window_state.get("correlation")
        if correlation:
            # Validate correlation confidence
            confidence = correlation.get("confidence", 0.0)
            if confidence < expected_confidence_min:
                raise AssertionError(
                    f"Window {window_state.get('window_id')} correlation confidence "
                    f"{confidence:.2f} is below minimum {expected_confidence_min:.2f}"
                )

            # Check that it was matched via launch
            if not correlation.get("matched_via_launch", False):
                raise AssertionError(
                    f"Window {window_state.get('window_id')} project assignment was not "
                    f"via launch correlation"
                )

            confidence_level = correlation.get("confidence_level", "UNKNOWN")
            logger.info(
                f"✓ Window {window_state.get('window_id')} correlated to project "
                f"'{expected_project}' with confidence {confidence:.2f} ({confidence_level})"
            )
        else:
            # No correlation data, just verify project assignment
            logger.info(
                f"✓ Window {window_state.get('window_id')} assigned to project "
                f"'{expected_project}' (correlation data not available)"
            )

    async def assert_launch_registered(
        self,
        daemon_client,
        launch_id: str
    ) -> None:
        """
        Assert that a launch notification was successfully registered.

        Args:
            daemon_client: DaemonClient instance for IPC queries
            launch_id: Launch identifier returned by notify_launch

        Raises:
            AssertionError: If launch is not found in pending launches
        """
        # Query pending launches (including matched ones)
        result = await daemon_client.send_request(
            "get_pending_launches",
            {"include_matched": True}
        )
        launches = result.get("launches", [])

        # Find launch by ID
        found = False
        for launch in launches:
            if launch.get("launch_id") == launch_id:
                found = True
                logger.info(
                    f"✓ Launch {launch_id} found in registry "
                    f"(app={launch.get('app_name')}, project={launch.get('project_name')}, "
                    f"matched={launch.get('matched')})"
                )
                break

        if not found:
            raise AssertionError(
                f"Launch '{launch_id}' not found in pending launches. "
                f"Available launches: {[l.get('launch_id') for l in launches]}"
            )

    async def assert_launch_expired(
        self,
        daemon_client,
        launch_id: str
    ) -> None:
        """
        Assert that a launch has been removed due to expiration.

        Args:
            daemon_client: DaemonClient instance for IPC queries
            launch_id: Launch identifier that should have expired

        Raises:
            AssertionError: If launch still exists in pending launches
        """
        # Query pending launches (including matched ones)
        result = await daemon_client.send_request(
            "get_pending_launches",
            {"include_matched": True}
        )
        launches = result.get("launches", [])

        # Verify launch is NOT in the list
        for launch in launches:
            if launch.get("launch_id") == launch_id:
                raise AssertionError(
                    f"Launch '{launch_id}' still exists in pending launches "
                    f"(age={launch.get('age'):.2f}s), expected it to be expired"
                )

        logger.info(f"✓ Launch {launch_id} has been expired and removed from registry")

    async def assert_launch_matched(
        self,
        daemon_client,
        launch_id: str,
        expected_matched: bool = True
    ) -> None:
        """
        Assert that a launch has the expected matched status.

        Args:
            daemon_client: DaemonClient instance for IPC queries
            launch_id: Launch identifier to check
            expected_matched: Expected matched status (default: True)

        Raises:
            AssertionError: If launch matched status doesn't match expectation
        """
        # Query pending launches (including matched ones)
        result = await daemon_client.send_request(
            "get_pending_launches",
            {"include_matched": True}
        )
        launches = result.get("launches", [])

        # Find launch and check matched status
        for launch in launches:
            if launch.get("launch_id") == launch_id:
                actual_matched = launch.get("matched", False)
                if actual_matched != expected_matched:
                    raise AssertionError(
                        f"Launch '{launch_id}' matched status is {actual_matched}, "
                        f"expected {expected_matched}"
                    )

                logger.info(
                    f"✓ Launch {launch_id} matched status is {expected_matched} "
                    f"(app={launch.get('app_name')}, project={launch.get('project_name')})"
                )
                return

        raise AssertionError(
            f"Launch '{launch_id}' not found in pending launches"
        )

    async def assert_launch_stats(
        self,
        daemon_client,
        expected_pending: Optional[int] = None,
        expected_matched: Optional[int] = None,
        expected_expired: Optional[int] = None,
        min_match_rate: Optional[float] = None
    ) -> None:
        """
        Assert launch registry statistics match expected values.

        Args:
            daemon_client: DaemonClient instance for IPC queries
            expected_pending: Expected number of pending launches (optional)
            expected_matched: Expected number of total matched launches (optional)
            expected_expired: Expected number of total expired launches (optional)
            min_match_rate: Minimum acceptable match rate percentage (optional)

        Raises:
            AssertionError: If any statistic doesn't match expectation
        """
        # Query launch stats
        stats = await daemon_client.send_request("get_launch_stats", {})

        # Check each provided expectation
        if expected_pending is not None:
            actual_pending = stats.get("total_pending", 0)
            if actual_pending != expected_pending:
                raise AssertionError(
                    f"Expected {expected_pending} pending launches, got {actual_pending}"
                )
            logger.info(f"✓ Pending launches: {expected_pending}")

        if expected_matched is not None:
            actual_matched = stats.get("total_matched", 0)
            if actual_matched != expected_matched:
                raise AssertionError(
                    f"Expected {expected_matched} total matched, got {actual_matched}"
                )
            logger.info(f"✓ Total matched: {expected_matched}")

        if expected_expired is not None:
            actual_expired = stats.get("total_expired", 0)
            if actual_expired != expected_expired:
                raise AssertionError(
                    f"Expected {expected_expired} total expired, got {actual_expired}"
                )
            logger.info(f"✓ Total expired: {expected_expired}")

        if min_match_rate is not None:
            actual_match_rate = stats.get("match_rate", 0.0)
            if actual_match_rate < min_match_rate:
                raise AssertionError(
                    f"Match rate {actual_match_rate:.1f}% is below minimum {min_match_rate:.1f}%"
                )
            logger.info(f"✓ Match rate: {actual_match_rate:.1f}% (>= {min_match_rate:.1f}%)")

        # Log full stats summary
        logger.info(
            f"Launch stats: pending={stats.get('total_pending')}, "
            f"matched={stats.get('total_matched')}, "
            f"expired={stats.get('total_expired')}, "
            f"failed={stats.get('total_failed_correlation')}, "
            f"match_rate={stats.get('match_rate'):.1f}%, "
            f"expiration_rate={stats.get('expiration_rate'):.1f}%"
        )

    async def assert_correlation_confidence(
        self,
        window_id: int,
        daemon_client,
        min_confidence: float,
        expected_signals: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Assert that window correlation confidence meets minimum threshold.

        Args:
            window_id: i3 window ID to check
            daemon_client: DaemonClient instance for IPC queries
            min_confidence: Minimum acceptable confidence score (0.0-1.0)
            expected_signals: Expected correlation signals dict (optional)

        Raises:
            AssertionError: If confidence is below threshold or signals don't match
        """
        # Get window state (would need window state query endpoint)
        # This is a placeholder for when window state API includes correlation info
        try:
            window_state = await daemon_client.send_request(
                "windows.getState",
                {"window_id": window_id}
            )
        except Exception as e:
            raise AssertionError(
                f"Failed to get window state for {window_id}: {e}"
            )

        correlation = window_state.get("correlation")
        if not correlation:
            raise AssertionError(
                f"Window {window_id} has no correlation information"
            )

        confidence = correlation.get("confidence", 0.0)
        if confidence < min_confidence:
            raise AssertionError(
                f"Window {window_id} confidence {confidence:.2f} is below "
                f"minimum {min_confidence:.2f}"
            )

        logger.info(
            f"✓ Window {window_id} correlation confidence {confidence:.2f} "
            f">= {min_confidence:.2f}"
        )

        # Check expected signals if provided
        if expected_signals:
            actual_signals = correlation.get("signals_used", {})
            for key, expected_value in expected_signals.items():
                actual_value = actual_signals.get(key)
                if actual_value != expected_value:
                    raise AssertionError(
                        f"Window {window_id} correlation signal '{key}' is {actual_value}, "
                        f"expected {expected_value}"
                    )
                logger.info(f"✓ Signal '{key}': {actual_value}")

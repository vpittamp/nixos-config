"""
Workspace Assignment Service

Implements 4-tier priority system for workspace assignment:
1. App-specific handlers (VS Code title parsing, etc.)
2. I3PM_TARGET_WORKSPACE environment variable
3. I3PM_APP_NAME registry lookup
4. Window class matching (tiered: exact → instance → normalized)

Part of Feature 039 - Tasks T027, T054
"""

import re
import time
from typing import Optional, Dict, Any, Tuple, Callable, Awaitable
from dataclasses import dataclass
from datetime import datetime
import logging

# Feature 039 T054: Use consolidated window_identifier service
from .window_identifier import (
    normalize_class,
    match_window_class,
    match_with_registry,
)

logger = logging.getLogger(__name__)


@dataclass
class WorkspaceAssignment:
    """Result of workspace assignment operation."""
    success: bool
    workspace: int
    source: str  # Which tier was used: "app_handler", "env_var", "registry", "class_match", "fallback"
    duration_ms: float
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None  # Additional context (e.g., project override)


# DEPRECATED: Use window_identifier service instead
# Kept temporarily for backward compatibility during migration
class WindowIdentifier:
    """
    Window class normalization and matching.

    DEPRECATED: This class is deprecated in Feature 039.
    Use services.window_identifier module instead.
    """

    @staticmethod
    def normalize_class(class_name: str) -> str:
        """DEPRECATED: Use window_identifier.normalize_class() instead."""
        return normalize_class(class_name)

    @staticmethod
    def match_class(expected: str, actual_class: str, actual_instance: str = "") -> Tuple[bool, str]:
        """DEPRECATED: Use window_identifier.match_window_class() instead."""
        matched, match_type = match_window_class(expected, actual_class, actual_instance)
        return (matched, match_type)


# Type alias for app-specific handlers
AppSpecificHandler = Callable[[str, str, Optional[Any]], Awaitable[Optional[Dict[str, Any]]]]


class WorkspaceAssigner:
    """
    Workspace assignment service implementing 4-tier priority system.

    This service is responsible for determining which workspace a window
    should be assigned to, using multiple fallback strategies.
    """

    def __init__(self):
        """Initialize workspace assigner."""
        self.app_specific_handlers: Dict[str, AppSpecificHandler] = {}
        self._register_default_handlers()

        # Performance metrics
        self.assignments_total = 0
        self.assignments_by_tier = {
            "app_handler": 0,
            "env_var": 0,
            "registry": 0,
            "class_match": 0,
            "fallback": 0
        }
        self.average_latency_ms = 0.0

    def _register_default_handlers(self):
        """Register default app-specific handlers."""
        self.register_handler("Code", self._vscode_handler)
        # Additional handlers can be registered here or via register_handler()

    def register_handler(self, window_class: str, handler: AppSpecificHandler):
        """
        Register an app-specific handler.

        Args:
            window_class: Window class to handle
            handler: Async function that returns workspace assignment or None
        """
        self.app_specific_handlers[window_class] = handler
        logger.debug(f"Registered app-specific handler for {window_class}")

    async def _vscode_handler(
        self,
        window_id: int,
        window_title: str,
        i3pm_env: Optional[Any]
    ) -> Optional[Dict[str, Any]]:
        """
        VS Code app-specific handler.

        Extracts project name from window title for workspace lookup.
        Title format: "project - workspace - Visual Studio Code"

        Returns:
            Dict with 'workspace' and optional 'project' override, or None
        """
        # Parse project from title
        match = re.match(r"(?:Code - )?([^-]+) -", window_title)
        if match:
            project = match.group(1).strip().lower()

            # VS Code uses workspace 2 (configurable)
            return {
                "workspace": 2,
                "project": project,
                "handler": "vscode_title_parser"
            }

        return None

    async def assign_workspace(
        self,
        window_id: int,
        window_class: str,
        window_title: str,
        window_instance: str,
        i3pm_env: Optional[Any],
        application_registry: Optional[Dict[str, Any]],
        current_workspace: int
    ) -> WorkspaceAssignment:
        """
        Assign workspace to window using 4-tier priority system.

        Priority Order:
        1. App-specific handlers (e.g., VS Code title parsing)
        2. I3PM_TARGET_WORKSPACE environment variable
        3. I3PM_APP_NAME registry lookup
        4. Window class matching (exact → instance → normalized)
        5. Fallback to current workspace

        Args:
            window_id: i3 window container ID
            window_class: WM_CLASS class field
            window_title: Window title
            window_instance: WM_CLASS instance field
            i3pm_env: I3PM environment variables (or None)
            application_registry: Application registry dict (or None)
            current_workspace: Current workspace number

        Returns:
            WorkspaceAssignment with result and metadata
        """
        start_time = time.perf_counter()
        self.assignments_total += 1

        try:
            # Priority 1: App-specific handler
            if window_class in self.app_specific_handlers:
                handler_result = await self.app_specific_handlers[window_class](
                    window_id, window_title, i3pm_env
                )

                if handler_result and "workspace" in handler_result:
                    workspace = handler_result["workspace"]

                    if self._validate_workspace(workspace):
                        duration_ms = (time.perf_counter() - start_time) * 1000
                        self.assignments_by_tier["app_handler"] += 1
                        self._update_avg_latency(duration_ms)

                        logger.info(
                            f"[Priority 1] Assigned window {window_id} to workspace {workspace} "
                            f"via app-specific handler ({window_class})"
                        )

                        return WorkspaceAssignment(
                            success=True,
                            workspace=workspace,
                            source="app_handler",
                            duration_ms=duration_ms,
                            metadata=handler_result
                        )

            # Priority 2: I3PM_TARGET_WORKSPACE environment variable
            if i3pm_env and hasattr(i3pm_env, 'target_workspace') and i3pm_env.target_workspace:
                workspace = i3pm_env.target_workspace

                if self._validate_workspace(workspace):
                    duration_ms = (time.perf_counter() - start_time) * 1000
                    self.assignments_by_tier["env_var"] += 1
                    self._update_avg_latency(duration_ms)

                    logger.info(
                        f"[Priority 2] Assigned window {window_id} to workspace {workspace} "
                        f"via I3PM_TARGET_WORKSPACE"
                    )

                    return WorkspaceAssignment(
                        success=True,
                        workspace=workspace,
                        source="env_var",
                        duration_ms=duration_ms,
                        metadata={"app_name": getattr(i3pm_env, 'app_name', None)}
                    )

            # Priority 3: I3PM_APP_NAME registry lookup
            if i3pm_env and hasattr(i3pm_env, 'app_name') and i3pm_env.app_name and application_registry:
                app_name = i3pm_env.app_name
                app_def = application_registry.get(app_name)

                if app_def and "preferred_workspace" in app_def:
                    workspace = app_def["preferred_workspace"]

                    if self._validate_workspace(workspace):
                        duration_ms = (time.perf_counter() - start_time) * 1000
                        self.assignments_by_tier["registry"] += 1
                        self._update_avg_latency(duration_ms)

                        logger.info(
                            f"[Priority 3] Assigned window {window_id} to workspace {workspace} "
                            f"via registry lookup (app={app_name})"
                        )

                        return WorkspaceAssignment(
                            success=True,
                            workspace=workspace,
                            source="registry",
                            duration_ms=duration_ms,
                            metadata={"app_name": app_name, "app_def": app_def}
                        )

            # Priority 4: Window class matching
            # Feature 039 - T081: PWA Workspace Rules Support
            # PWAs are supported through tiered matching:
            # - Chrome PWAs: Matched by instance field (class is generic "Google-chrome")
            # - Firefox PWAs: Matched by class field (unique FFPWA-* class)
            if application_registry:
                for app_name, app_def in application_registry.items():
                    expected_class = app_def.get("expected_class", "")
                    if not expected_class:
                        continue

                    matched, match_type = WindowIdentifier.match_class(
                        expected_class, window_class, window_instance
                    )

                    if matched:
                        workspace = app_def.get("preferred_workspace")

                        if workspace and self._validate_workspace(workspace):
                            duration_ms = (time.perf_counter() - start_time) * 1000
                            self.assignments_by_tier["class_match"] += 1
                            self._update_avg_latency(duration_ms)

                            logger.info(
                                f"[Priority 4] Assigned window {window_id} to workspace {workspace} "
                                f"via window class matching (class={window_class}, instance={window_instance}, "
                                f"match_type={match_type}, app={app_name})"
                            )

                            return WorkspaceAssignment(
                                success=True,
                                workspace=workspace,
                                source="class_match",
                                duration_ms=duration_ms,
                                metadata={
                                    "app_name": app_name,
                                    "match_type": match_type,
                                    "expected_class": expected_class,
                                    "window_instance": window_instance
                                }
                            )

            # Fallback: Current workspace
            duration_ms = (time.perf_counter() - start_time) * 1000
            self.assignments_by_tier["fallback"] += 1
            self._update_avg_latency(duration_ms)

            logger.debug(
                f"[Fallback] Window {window_id} stays on current workspace {current_workspace} "
                f"(no assignment rules matched)"
            )

            return WorkspaceAssignment(
                success=True,
                workspace=current_workspace,
                source="fallback",
                duration_ms=duration_ms,
                metadata={"reason": "no_rules_matched"}
            )

        except Exception as e:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.error(f"Error assigning workspace for window {window_id}: {e}", exc_info=True)

            return WorkspaceAssignment(
                success=False,
                workspace=current_workspace,  # Fallback on error
                source="fallback",
                duration_ms=duration_ms,
                error=str(e)
            )

    def _validate_workspace(self, workspace: int) -> bool:
        """
        Validate workspace number is in valid range.

        Args:
            workspace: Workspace number to validate

        Returns:
            True if valid (1-10), False otherwise
        """
        if not isinstance(workspace, int):
            return False

        # i3 default workspace range is 1-10 (configurable, but this is typical)
        return 1 <= workspace <= 10

    def _update_avg_latency(self, duration_ms: float):
        """Update rolling average latency metric."""
        # Simple moving average
        if self.assignments_total == 1:
            self.average_latency_ms = duration_ms
        else:
            self.average_latency_ms = (
                (self.average_latency_ms * (self.assignments_total - 1) + duration_ms)
                / self.assignments_total
            )

    def get_metrics(self) -> Dict[str, Any]:
        """
        Get performance metrics.

        Returns:
            Dict with assignment statistics
        """
        return {
            "assignments_total": self.assignments_total,
            "assignments_by_tier": self.assignments_by_tier.copy(),
            "average_latency_ms": round(self.average_latency_ms, 2),
            "tier_percentages": {
                tier: round((count / self.assignments_total * 100), 1) if self.assignments_total > 0 else 0
                for tier, count in self.assignments_by_tier.items()
            }
        }

    def reset_metrics(self):
        """Reset performance metrics (for testing)."""
        self.assignments_total = 0
        self.assignments_by_tier = {k: 0 for k in self.assignments_by_tier}
        self.average_latency_ms = 0.0


# Singleton instance
_workspace_assigner_instance: Optional[WorkspaceAssigner] = None


def get_workspace_assigner() -> WorkspaceAssigner:
    """Get singleton workspace assigner instance."""
    global _workspace_assigner_instance

    if _workspace_assigner_instance is None:
        _workspace_assigner_instance = WorkspaceAssigner()

    return _workspace_assigner_instance

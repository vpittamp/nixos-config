"""Detection result data model for window class detection."""

from dataclasses import dataclass, field
from typing import Literal, Optional
from datetime import datetime


@dataclass
class DetectionResult:
    """Result of automated window class detection.

    Attributes:
        desktop_file: Path to .desktop file (e.g., "/usr/share/applications/code.desktop")
        app_name: Application name from .desktop file (e.g., "Visual Studio Code")
        detected_class: Detected WM_CLASS (e.g., "Code") or None if detection failed
        detection_method: How window class was determined
        confidence: Confidence score [0.0, 1.0] for detection reliability
        error_message: Error details if detection_method == "failed"
        timestamp: ISO 8601 timestamp of detection

    Examples:
        >>> result = DetectionResult(
        ...     desktop_file="/usr/share/applications/code.desktop",
        ...     app_name="Visual Studio Code",
        ...     detected_class="Code",
        ...     detection_method="xvfb",
        ...     confidence=1.0
        ... )
        >>> result.detection_method
        'xvfb'

        >>> failed = DetectionResult(
        ...     desktop_file="/usr/share/applications/broken.desktop",
        ...     app_name="Broken App",
        ...     detected_class=None,
        ...     detection_method="failed",
        ...     confidence=0.0,
        ...     error_message="Xvfb process timed out after 10 seconds"
        ... )
        >>> failed.error_message
        'Xvfb process timed out after 10 seconds'
    """

    desktop_file: str
    app_name: str
    detected_class: Optional[str]
    detection_method: Literal["xvfb", "desktop_file", "heuristic", "failed"]
    confidence: float = 1.0
    error_message: Optional[str] = None
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())

    def __post_init__(self):
        """Validate detection result."""
        if not self.desktop_file:
            raise ValueError("desktop_file cannot be empty")

        if not self.app_name:
            raise ValueError("app_name cannot be empty")

        if not (0.0 <= self.confidence <= 1.0):
            raise ValueError(f"confidence must be in [0.0, 1.0], got {self.confidence}")

        if self.detection_method == "failed" and not self.error_message:
            raise ValueError("error_message required when detection_method is 'failed'")

        if self.detection_method != "failed" and not self.detected_class:
            raise ValueError(
                f"detected_class required when detection_method is '{self.detection_method}'"
            )

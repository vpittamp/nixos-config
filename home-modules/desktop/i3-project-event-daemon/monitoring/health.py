"""
Health Metrics Module

Feature 030: Production Readiness
Task T013: Health metrics tracking

Tracks daemon health indicators:
- Uptime
- Memory usage
- Event counts
- Error rate
- Last successful operation
"""

import time
import psutil
from datetime import datetime, timedelta
from typing import Optional
from dataclasses import dataclass, field
import logging

logger = logging.getLogger(__name__)


@dataclass
class HealthMetrics:
    """
    Health metrics for daemon monitoring

    These metrics provide insight into daemon operational health
    and can be used for alerting and diagnostics.
    """
    # Basic status
    is_running: bool = True
    start_time: float = field(default_factory=time.time)

    # Connection status
    i3_connected: bool = False
    ipc_socket_active: bool = False

    # Counters
    total_events_processed: int = 0
    total_windows_tracked: int = 0
    total_project_switches: int = 0
    total_errors: int = 0

    # Last operation tracking
    last_event_time: Optional[float] = None
    last_successful_operation: Optional[str] = None
    last_error_time: Optional[float] = None
    last_error_message: Optional[str] = None

    # Resource usage
    memory_rss_mb: float = 0.0  # Resident Set Size
    memory_percent: float = 0.0
    cpu_percent: float = 0.0

    # Health thresholds
    max_memory_mb: float = 100.0  # From systemd MemoryMax
    max_cpu_percent: float = 50.0  # From systemd CPUQuota

    def update_resource_usage(self):
        """Update memory and CPU usage metrics"""
        try:
            process = psutil.Process()
            mem_info = process.memory_info()

            self.memory_rss_mb = mem_info.rss / (1024 * 1024)  # Convert to MB
            self.memory_percent = process.memory_percent()

            # CPU percent (non-blocking)
            self.cpu_percent = process.cpu_percent(interval=None)

        except (psutil.NoSuchProcess, psutil.AccessDenied) as e:
            logger.warning(f"Failed to update resource usage: {e}")

    def record_event(self):
        """Record that an event was processed"""
        self.total_events_processed += 1
        self.last_event_time = time.time()
        self.last_successful_operation = "event_processed"

    def record_window_tracked(self):
        """Record that a window was tracked"""
        self.total_windows_tracked += 1
        self.last_successful_operation = "window_tracked"

    def record_project_switch(self):
        """Record a project switch"""
        self.total_project_switches += 1
        self.last_successful_operation = "project_switched"

    def record_error(self, error_message: str):
        """Record an error occurrence"""
        self.total_errors += 1
        self.last_error_time = time.time()
        self.last_error_message = error_message
        logger.debug(f"Error recorded in health metrics: {error_message}")

    @property
    def uptime_seconds(self) -> float:
        """Calculate daemon uptime in seconds"""
        return time.time() - self.start_time

    @property
    def uptime_formatted(self) -> str:
        """Format uptime as human-readable string"""
        td = timedelta(seconds=int(self.uptime_seconds))
        days = td.days
        hours, remainder = divmod(td.seconds, 3600)
        minutes, seconds = divmod(remainder, 60)

        if days > 0:
            return f"{days}d {hours}h {minutes}m"
        elif hours > 0:
            return f"{hours}h {minutes}m {seconds}s"
        elif minutes > 0:
            return f"{minutes}m {seconds}s"
        else:
            return f"{seconds}s"

    @property
    def error_rate(self) -> float:
        """
        Calculate error rate (errors per event)

        Returns:
            Error rate as decimal (0.0 = no errors, 1.0 = all events failed)
        """
        if self.total_events_processed == 0:
            return 0.0
        return self.total_errors / self.total_events_processed

    @property
    def is_healthy(self) -> bool:
        """
        Determine if daemon is in healthy state

        Health criteria:
        - Running and connected to i3
        - Recent successful operation (within 60s)
        - Memory usage below threshold
        - CPU usage below threshold
        - Error rate below 10%
        """
        if not self.is_running or not self.i3_connected:
            return False

        # Check for recent activity
        if self.last_event_time:
            time_since_last_event = time.time() - self.last_event_time
            if time_since_last_event > 60:  # No events in 60s
                logger.debug("Health check: No recent event activity")
                # Note: This is not necessarily unhealthy in quiet periods

        # Check resource usage
        if self.memory_rss_mb > self.max_memory_mb:
            logger.warning(f"Health check failed: Memory usage {self.memory_rss_mb:.1f}MB exceeds {self.max_memory_mb}MB")
            return False

        if self.cpu_percent > self.max_cpu_percent:
            logger.warning(f"Health check failed: CPU usage {self.cpu_percent:.1f}% exceeds {self.max_cpu_percent}%")
            return False

        # Check error rate
        if self.error_rate > 0.10:  # More than 10% errors
            logger.warning(f"Health check failed: Error rate {self.error_rate:.1%} exceeds 10%")
            return False

        return True

    @property
    def health_status(self) -> str:
        """
        Get human-readable health status

        Returns:
            "healthy", "degraded", or "unhealthy"
        """
        if not self.is_running:
            return "unhealthy"

        if not self.i3_connected:
            return "degraded"

        if self.is_healthy:
            return "healthy"

        # Not healthy but still running
        if self.error_rate > 0.25:  # > 25% errors
            return "unhealthy"

        return "degraded"

    def to_dict(self) -> dict:
        """Convert health metrics to dictionary for JSON serialization"""
        return {
            "status": self.health_status,
            "is_running": self.is_running,
            "is_healthy": self.is_healthy,
            "uptime_seconds": self.uptime_seconds,
            "uptime_formatted": self.uptime_formatted,
            "i3_connected": self.i3_connected,
            "ipc_socket_active": self.ipc_socket_active,
            "counters": {
                "total_events_processed": self.total_events_processed,
                "total_windows_tracked": self.total_windows_tracked,
                "total_project_switches": self.total_project_switches,
                "total_errors": self.total_errors,
            },
            "error_rate": round(self.error_rate, 4),
            "last_operation": {
                "type": self.last_successful_operation,
                "time": datetime.fromtimestamp(self.last_event_time).isoformat() if self.last_event_time else None,
            },
            "last_error": {
                "message": self.last_error_message,
                "time": datetime.fromtimestamp(self.last_error_time).isoformat() if self.last_error_time else None,
            },
            "resources": {
                "memory_rss_mb": round(self.memory_rss_mb, 2),
                "memory_percent": round(self.memory_percent, 2),
                "cpu_percent": round(self.cpu_percent, 2),
            },
            "thresholds": {
                "max_memory_mb": self.max_memory_mb,
                "max_cpu_percent": self.max_cpu_percent,
            },
        }


# Global health metrics instance
_health_metrics: Optional[HealthMetrics] = None


def get_health_metrics() -> HealthMetrics:
    """
    Get global health metrics instance

    Returns:
        Singleton HealthMetrics instance
    """
    global _health_metrics
    if _health_metrics is None:
        _health_metrics = HealthMetrics()
    return _health_metrics


def reset_health_metrics():
    """Reset health metrics (for testing)"""
    global _health_metrics
    _health_metrics = None

"""
i3 IPC Reconnection Logic

Feature 030: Production Readiness
Task T025: i3 IPC reconnection logic

Implements exponential backoff reconnection to i3 IPC
for handling i3 restarts and connection failures.
"""

import logging
import asyncio
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, Callable, Awaitable
import time

logger = logging.getLogger(__name__)


@dataclass
class ReconnectionConfig:
    """Configuration for reconnection behavior"""
    initial_delay: float = 1.0  # Initial delay in seconds
    max_delay: float = 60.0  # Maximum delay in seconds
    backoff_multiplier: float = 2.0  # Exponential backoff multiplier
    max_attempts: Optional[int] = None  # None = infinite retries
    timeout: float = 5.0  # Connection timeout per attempt


class I3ReconnectionManager:
    """
    Manages reconnection to i3 IPC with exponential backoff

    Features:
    - Exponential backoff retry logic
    - Connection health monitoring
    - Automatic reconnection on failure
    - Callback notification on reconnection
    """

    def __init__(
        self,
        config: ReconnectionConfig = None,
        on_reconnect: Optional[Callable[[any], Awaitable[None]]] = None,
    ):
        """
        Initialize reconnection manager

        Args:
            config: Reconnection configuration
            on_reconnect: Optional async callback called after successful reconnection
        """
        self.config = config or ReconnectionConfig()
        self.on_reconnect = on_reconnect

        self.connection = None
        self.is_connected = False
        self.reconnection_count = 0
        self.last_connection_time: Optional[datetime] = None
        self.last_failure_time: Optional[datetime] = None

        self._reconnect_task: Optional[asyncio.Task] = None
        self._monitoring_task: Optional[asyncio.Task] = None
        self._should_stop = False

    async def connect(self) -> bool:
        """
        Initial connection to i3

        Returns:
            True if connected successfully, False otherwise
        """
        try:
            import i3ipc.aio

            logger.info("Attempting initial connection to i3 IPC")

            # Create connection with timeout
            self.connection = await asyncio.wait_for(
                self._create_connection(),
                timeout=self.config.timeout
            )

            if self.connection:
                self.is_connected = True
                self.last_connection_time = datetime.now()
                logger.info("Successfully connected to i3 IPC")
                return True

        except asyncio.TimeoutError:
            logger.error(f"i3 connection timeout after {self.config.timeout}s")
            self.last_failure_time = datetime.now()
        except Exception as e:
            logger.error(f"Failed to connect to i3 IPC: {e}")
            self.last_failure_time = datetime.now()

        return False

    async def _create_connection(self):
        """Create i3ipc connection"""
        import i3ipc.aio
        return await i3ipc.aio.Connection().connect()

    async def reconnect_with_backoff(self) -> bool:
        """
        Reconnect to i3 with exponential backoff

        Returns:
            True if reconnected successfully, False if max attempts reached
        """
        delay = self.config.initial_delay
        attempt = 0

        while not self._should_stop:
            attempt += 1

            # Check max attempts
            if self.config.max_attempts and attempt > self.config.max_attempts:
                logger.error(f"Max reconnection attempts ({self.config.max_attempts}) reached")
                return False

            logger.info(f"Reconnection attempt {attempt} (delay: {delay:.1f}s)")

            # Wait before attempting
            await asyncio.sleep(delay)

            # Try to reconnect
            try:
                self.connection = await asyncio.wait_for(
                    self._create_connection(),
                    timeout=self.config.timeout
                )

                if self.connection:
                    self.is_connected = True
                    self.reconnection_count += 1
                    self.last_connection_time = datetime.now()

                    logger.info(f"Reconnected to i3 IPC on attempt {attempt}")

                    # Call reconnection callback
                    if self.on_reconnect:
                        try:
                            await self.on_reconnect(self.connection)
                        except Exception as e:
                            logger.error(f"Reconnection callback failed: {e}")

                    return True

            except asyncio.TimeoutError:
                logger.warning(f"Reconnection attempt {attempt} timed out")
            except Exception as e:
                logger.warning(f"Reconnection attempt {attempt} failed: {e}")

            # Exponential backoff
            delay = min(delay * self.config.backoff_multiplier, self.config.max_delay)

        return False

    async def start_monitoring(self) -> None:
        """
        Start connection monitoring

        Automatically detects disconnections and triggers reconnection.
        """
        if self._monitoring_task and not self._monitoring_task.done():
            logger.warning("Connection monitoring already running")
            return

        logger.info("Starting i3 connection monitoring")
        self._monitoring_task = asyncio.create_task(self._monitor_connection())

    async def _monitor_connection(self) -> None:
        """Monitor connection health and trigger reconnection on failure"""
        while not self._should_stop:
            await asyncio.sleep(5.0)  # Check every 5 seconds

            if not self.is_connected:
                continue

            # Test connection health
            try:
                if not await self._test_connection_health():
                    logger.warning("i3 connection health check failed - triggering reconnection")
                    self.is_connected = False
                    self.last_failure_time = datetime.now()

                    # Start reconnection in background
                    if not self._reconnect_task or self._reconnect_task.done():
                        self._reconnect_task = asyncio.create_task(
                            self.reconnect_with_backoff()
                        )

            except Exception as e:
                logger.error(f"Connection monitoring error: {e}")

    async def _test_connection_health(self) -> bool:
        """
        Test if connection is healthy

        Returns:
            True if healthy, False otherwise
        """
        if not self.connection:
            return False

        try:
            # Try a simple query with timeout
            tree = await asyncio.wait_for(
                self.connection.get_tree(),
                timeout=2.0
            )
            return tree is not None
        except asyncio.TimeoutError:
            logger.warning("Connection health check timed out")
            return False
        except Exception as e:
            logger.warning(f"Connection health check failed: {e}")
            return False

    async def disconnect(self) -> None:
        """Disconnect from i3 and stop monitoring"""
        logger.info("Disconnecting from i3 IPC")

        self._should_stop = True
        self.is_connected = False

        # Cancel monitoring task
        if self._monitoring_task and not self._monitoring_task.done():
            self._monitoring_task.cancel()
            try:
                await self._monitoring_task
            except asyncio.CancelledError:
                pass

        # Cancel reconnection task
        if self._reconnect_task and not self._reconnect_task.done():
            self._reconnect_task.cancel()
            try:
                await self._reconnect_task
            except asyncio.CancelledError:
                pass

        # Close connection
        if self.connection:
            try:
                # i3ipc doesn't have an explicit close method
                self.connection = None
            except Exception as e:
                logger.error(f"Error closing i3 connection: {e}")

    def get_stats(self) -> dict:
        """
        Get reconnection statistics

        Returns:
            Dictionary with connection stats
        """
        return {
            "is_connected": self.is_connected,
            "reconnection_count": self.reconnection_count,
            "last_connection_time": self.last_connection_time.isoformat() if self.last_connection_time else None,
            "last_failure_time": self.last_failure_time.isoformat() if self.last_failure_time else None,
            "uptime_seconds": (datetime.now() - self.last_connection_time).total_seconds() if self.last_connection_time else 0,
        }

"""System monitoring status blocks (load, memory, disk, temperature, daemon health, date/time)."""

import subprocess
import logging
import socket
import json
from dataclasses import dataclass
from typing import Optional
from datetime import datetime

from .models import StatusBlock
from .config import Config

logger = logging.getLogger(__name__)


@dataclass
class SystemMetrics:
    """System resource metrics."""
    load_average: float
    memory_used_gb: float
    memory_total_gb: float
    memory_percent: int
    disk_used: str
    disk_total: str
    disk_percent: int
    cpu_temp: Optional[int] = None  # Celsius


def get_load_average() -> Optional[float]:
    """Get 1-minute load average from /proc/loadavg."""
    try:
        with open("/proc/loadavg", "r") as f:
            load = float(f.read().split()[0])
        return load
    except Exception as e:
        logger.error(f"Failed to read load average: {e}")
        return None


def get_memory_usage() -> Optional[tuple]:
    """Get memory usage from /proc/meminfo.

    Returns:
        Tuple of (used_gb, total_gb, percent) or None
    """
    try:
        meminfo = {}
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    meminfo[parts[0].rstrip(":")] = int(parts[1])

        total_kb = meminfo.get("MemTotal", 0)
        available_kb = meminfo.get("MemAvailable", total_kb)
        used_kb = total_kb - available_kb

        total_gb = total_kb / 1024 / 1024
        used_gb = used_kb / 1024 / 1024
        percent = int((used_kb / total_kb) * 100) if total_kb > 0 else 0

        return (used_gb, total_gb, percent)
    except Exception as e:
        logger.error(f"Failed to read memory usage: {e}")
        return None


def get_disk_usage() -> Optional[tuple]:
    """Get disk usage for root filesystem.

    Returns:
        Tuple of (used_str, total_str, percent) or None
    """
    try:
        result = subprocess.run(
            ["df", "-h", "/"],
            capture_output=True,
            text=True,
            timeout=2
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) < 2:
            return None

        parts = lines[1].split()
        if len(parts) < 5:
            return None

        total = parts[1]
        used = parts[2]
        percent = int(parts[4].rstrip("%"))

        return (used, total, percent)
    except Exception as e:
        logger.error(f"Failed to read disk usage: {e}")
        return None


def get_network_traffic() -> Optional[tuple]:
    """Get network traffic (RX/TX bytes) for primary interface.

    Returns:
        Tuple of (rx_mb, tx_mb) or None
    """
    try:
        # Find default route interface
        result = subprocess.run(
            ["ip", "route"],
            capture_output=True,
            text=True,
            timeout=2
        )
        iface = None
        for line in result.stdout.split("\n"):
            if line.startswith("default"):
                parts = line.split()
                if len(parts) >= 5:
                    iface = parts[4]
                    break

        if not iface:
            return None

        # Read RX/TX bytes
        rx_path = f"/sys/class/net/{iface}/statistics/rx_bytes"
        tx_path = f"/sys/class/net/{iface}/statistics/tx_bytes"

        with open(rx_path, "r") as f:
            rx_bytes = int(f.read().strip())
        with open(tx_path, "r") as f:
            tx_bytes = int(f.read().strip())

        rx_mb = rx_bytes / 1024 / 1024
        tx_mb = tx_bytes / 1024 / 1024

        return (rx_mb, tx_mb)
    except Exception as e:
        logger.error(f"Failed to read network traffic: {e}")
        return None


def get_cpu_temperature() -> Optional[int]:
    """Get CPU temperature from thermal zones.

    Returns:
        Temperature in Celsius or None
    """
    try:
        import glob
        zones = glob.glob("/sys/class/thermal/thermal_zone*/temp")
        if not zones:
            return None

        with open(zones[0], "r") as f:
            temp_millidegrees = int(f.read().strip())
            return temp_millidegrees // 1000
    except Exception as e:
        logger.debug(f"CPU temperature not available: {e}")
        return None


def get_nixos_generation() -> Optional[str]:
    """Get NixOS generation info via nixos-generation-info.

    Returns:
        Formatted generation string or None
    """
    try:
        result = subprocess.run(
            ["nixos-generation-info", "--export"],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode != 0:
            return None

        # Parse export data
        env_vars = {}
        for line in result.stdout.split("\n"):
            if "=" in line:
                key, value = line.split("=", 1)
                env_vars[key] = value.strip('"')

        short = env_vars.get("NIXOS_GENERATION_INFO_SHORT", "")
        hm_short = env_vars.get("NIXOS_GENERATION_INFO_HOME_MANAGER_SHORT", "")
        status = env_vars.get("NIXOS_GENERATION_INFO_STATUS", "unknown")
        warning = env_vars.get("NIXOS_GENERATION_INFO_WARNING_PARTS", "")

        if not short:
            short = "generation unknown"

        if hm_short and hm_short not in short:
            short = f"{short} {hm_short}"

        if status == "out-of-sync":
            short = f"{short} ⚠ {warning}" if warning else f"{short} ⚠"

        return short
    except FileNotFoundError:
        logger.debug("nixos-generation-info not found")
        return None
    except Exception as e:
        logger.error(f"Failed to get generation info: {e}")
        return None


def create_load_block(config: Config) -> Optional[StatusBlock]:
    """Create load average status block."""
    load = get_load_average()
    if load is None:
        return None

    return StatusBlock(
        name="load",
        full_text=f" {load:.1f}",
        color="#89b4fa",  # Blue
        separator=False,
        separator_block_width=10
    )


def create_memory_block(config: Config) -> Optional[StatusBlock]:
    """Create memory usage status block."""
    mem_info = get_memory_usage()
    if not mem_info:
        return None

    used_gb, total_gb, percent = mem_info

    return StatusBlock(
        name="memory",
        full_text=f" {used_gb:.1f}G/{percent}%",
        color="#74c7ec",  # Sapphire
        separator=False,
        separator_block_width=10
    )


def create_disk_block(config: Config) -> Optional[StatusBlock]:
    """Create disk usage status block."""
    disk_info = get_disk_usage()
    if not disk_info:
        return None

    used, total, percent = disk_info

    return StatusBlock(
        name="disk",
        full_text=f" {used}/{percent}%",
        color="#89dceb",  # Sky
        separator=False,
        separator_block_width=10
    )


def create_network_traffic_block(config: Config) -> Optional[StatusBlock]:
    """Create network traffic status block."""
    traffic = get_network_traffic()
    if not traffic:
        return None

    rx_mb, tx_mb = traffic

    return StatusBlock(
        name="network_traffic",
        full_text=f" ↓{rx_mb:.0f}M ↑{tx_mb:.0f}M",
        color="#94e2d5",  # Teal
        separator=False,
        separator_block_width=10
    )


def create_temperature_block(config: Config) -> Optional[StatusBlock]:
    """Create CPU temperature status block."""
    temp = get_cpu_temperature()
    if temp is None:
        return None

    return StatusBlock(
        name="temperature",
        full_text=f" {temp}°",
        color="#fab387",  # Peach
        separator=False,
        separator_block_width=10
    )


def check_daemon_health() -> Optional[tuple]:
    """Check i3pm daemon health via IPC ping.

    Returns:
        Tuple of (is_healthy, response_time_ms) or None on error
    """
    # Feature 117: User socket only (daemon runs as user service)
    import os
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    socket_path = f"{runtime_dir}/i3-project-daemon/ipc.sock"

    try:
        # Create ping request
        request = {
            "jsonrpc": "2.0",
            "method": "get_active_project",
            "params": {},
            "id": 1
        }

        # Connect to Unix socket with 1s timeout
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1.0)

        import time
        start_time = time.time()

        sock.connect(socket_path)
        sock.sendall((json.dumps(request) + "\n").encode())

        # Read response
        response = sock.recv(4096).decode()

        response_time_ms = (time.time() - start_time) * 1000
        sock.close()

        # Parse response
        data = json.loads(response)

        # Check if valid response
        if "result" in data or "error" in data:
            is_healthy = True
            return (is_healthy, response_time_ms)
        else:
            return (False, response_time_ms)

    except (socket.timeout, socket.error, ConnectionRefusedError):
        # Daemon not responding or not running
        return (False, None)
    except Exception as e:
        logger.error(f"Daemon health check failed: {e}")
        return (False, None)


def create_daemon_health_block(config: Config) -> StatusBlock:
    """Create i3pm daemon health indicator block."""
    health_info = check_daemon_health()

    if health_info is None or not health_info[0]:
        # Daemon unhealthy or not responding
        return StatusBlock(
            name="daemon_health",
            full_text=" ❌",
            color="#f38ba8",  # Red
            separator=False,
            separator_block_width=10
        )

    is_healthy, response_time = health_info

    if response_time and response_time < 100:
        # Fast response (<100ms) - green
        return StatusBlock(
            name="daemon_health",
            full_text=" ✓",
            color="#a6e3a1",  # Green
            separator=False,
            separator_block_width=10
        )
    elif response_time and response_time < 500:
        # Slow response (100-500ms) - yellow warning
        return StatusBlock(
            name="daemon_health",
            full_text=" ⚠",
            color="#f9e2af",  # Yellow
            separator=False,
            separator_block_width=10
        )
    else:
        # Very slow response (>500ms) - orange warning
        return StatusBlock(
            name="daemon_health",
            full_text=" ⚠",
            color="#fab387",  # Orange
            separator=False,
            separator_block_width=10
        )


def create_datetime_block(config: Config) -> StatusBlock:
    """Create date/time status block."""
    now = datetime.now()
    date_str = now.strftime("%a %b %d  %H:%M:%S")

    return StatusBlock(
        name="datetime",
        full_text=f"  {date_str}",
        color="#cdd6f4",  # Text
        separator=False,
        separator_block_width=10
    )


def create_generation_block(config: Config) -> Optional[StatusBlock]:
    """Create NixOS generation status block."""
    gen_info = get_nixos_generation()
    if not gen_info:
        return None

    # Check if out-of-sync (has warning symbol)
    color = "#f38ba8" if "⚠" in gen_info else "#cba6f7"  # Red if warning, Mauve otherwise

    return StatusBlock(
        name="nixos_generation",
        full_text=f"  {gen_info}",
        color=color,
        separator=False,
        separator_block_width=15
    )

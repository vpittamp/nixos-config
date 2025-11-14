#!/usr/bin/env python3
"""System metrics collection for Eww top bar

Aggregates system metrics into single JSON output for efficient polling.
Reads /proc and /sys filesystems for CPU load, memory, disk, network, temperature.

Output format:
{
  "cpu_load": "1.23",
  "mem_used_pct": "45",
  "mem_used_gb": "7.2",
  "mem_total_gb": "16",
  "disk_used_pct": "68",
  "disk_used_gb": "245",
  "disk_total_gb": "360",
  "net_rx_mbps": "1.2",
  "net_tx_mbps": "0.3",
  "temp_celsius": "52",
  "temp_available": true
}
"""
import json
import os
import time
from pathlib import Path
from typing import Optional


def get_load_average() -> Optional[str]:
    """Get 1-minute CPU load average from /proc/loadavg

    Returns:
        Load average as string (e.g., "1.23") or None on error
    """
    try:
        with open("/proc/loadavg", "r") as f:
            load_1min = f.read().split()[0]
            return load_1min
    except Exception:
        return None


def get_memory_usage() -> tuple[Optional[str], Optional[str], Optional[str]]:
    """Get memory usage from /proc/meminfo

    Returns:
        Tuple of (used_pct, used_gb, total_gb) or (None, None, None) on error
    """
    try:
        mem_info = {}
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if ":" in line:
                    key, value = line.split(":")
                    # Extract numeric value (kB)
                    mem_info[key.strip()] = int(value.strip().split()[0])

        total_kb = mem_info.get("MemTotal", 0)
        free_kb = mem_info.get("MemFree", 0)
        available_kb = mem_info.get("MemAvailable", free_kb)  # Fallback to MemFree
        buffers_kb = mem_info.get("Buffers", 0)
        cached_kb = mem_info.get("Cached", 0)

        # Used = Total - Available
        used_kb = total_kb - available_kb

        # Convert to GB
        total_gb = total_kb / (1024 * 1024)
        used_gb = used_kb / (1024 * 1024)

        # Calculate percentage
        used_pct = int((used_kb / total_kb) * 100) if total_kb > 0 else 0

        return (str(used_pct), f"{used_gb:.1f}", f"{total_gb:.0f}")
    except Exception:
        return (None, None, None)


def get_disk_usage() -> tuple[Optional[str], Optional[str], Optional[str]]:
    """Get disk usage for root filesystem using os.statvfs()

    Returns:
        Tuple of (used_pct, used_gb, total_gb) or (None, None, None) on error
    """
    try:
        stat = os.statvfs("/")
        total_bytes = stat.f_blocks * stat.f_frsize
        free_bytes = stat.f_bfree * stat.f_frsize
        used_bytes = total_bytes - free_bytes

        # Convert to GB
        total_gb = total_bytes / (1024 ** 3)
        used_gb = used_bytes / (1024 ** 3)

        # Calculate percentage
        used_pct = int((used_bytes / total_bytes) * 100) if total_bytes > 0 else 0

        return (str(used_pct), f"{used_gb:.0f}", f"{total_gb:.0f}")
    except Exception:
        return (None, None, None)


# Global state for network traffic calculation
_prev_net_stats = None
_prev_net_time = None


def get_network_traffic() -> tuple[Optional[str], Optional[str]]:
    """Get network traffic rates from /sys/class/net/

    Calculates RX/TX rates in Mbps by comparing with previous sample.
    Averages across all active interfaces (ignoring loopback).

    Returns:
        Tuple of (rx_mbps, tx_mbps) or (None, None) on error
    """
    global _prev_net_stats, _prev_net_time

    try:
        net_path = Path("/sys/class/net")
        if not net_path.exists():
            return (None, None)

        current_time = time.time()
        total_rx_bytes = 0
        total_tx_bytes = 0

        # Sum bytes across all non-loopback interfaces
        for iface_dir in net_path.iterdir():
            if not iface_dir.is_dir():
                continue

            iface_name = iface_dir.name
            if iface_name == "lo":  # Skip loopback
                continue

            # Read RX/TX bytes
            rx_bytes_file = iface_dir / "statistics" / "rx_bytes"
            tx_bytes_file = iface_dir / "statistics" / "tx_bytes"

            if rx_bytes_file.exists() and tx_bytes_file.exists():
                with open(rx_bytes_file, "r") as f:
                    total_rx_bytes += int(f.read().strip())
                with open(tx_bytes_file, "r") as f:
                    total_tx_bytes += int(f.read().strip())

        # Calculate rates if we have previous sample
        if _prev_net_stats is not None and _prev_net_time is not None:
            time_delta = current_time - _prev_net_time
            if time_delta > 0:
                rx_bytes_delta = total_rx_bytes - _prev_net_stats[0]
                tx_bytes_delta = total_tx_bytes - _prev_net_stats[1]

                # Convert to Mbps (bytes/sec * 8 / 1e6)
                rx_mbps = (rx_bytes_delta / time_delta) * 8 / 1e6
                tx_mbps = (tx_bytes_delta / time_delta) * 8 / 1e6

                # Update state for next call
                _prev_net_stats = (total_rx_bytes, total_tx_bytes)
                _prev_net_time = current_time

                return (f"{rx_mbps:.1f}", f"{tx_mbps:.1f}")

        # First call - initialize state, return zeros
        _prev_net_stats = (total_rx_bytes, total_tx_bytes)
        _prev_net_time = current_time
        return ("0.0", "0.0")

    except Exception:
        return (None, None)


def get_temperature() -> tuple[Optional[str], bool]:
    """Get CPU temperature from /sys/class/thermal/thermal_zone*

    Averages temperatures across all thermal zones.

    Returns:
        Tuple of (temp_celsius, available) where available indicates if thermal sensors exist
    """
    try:
        thermal_path = Path("/sys/class/thermal")
        if not thermal_path.exists():
            return (None, False)

        temps = []
        for zone_dir in thermal_path.glob("thermal_zone*"):
            temp_file = zone_dir / "temp"
            if temp_file.exists():
                with open(temp_file, "r") as f:
                    # Temperature is in millidegrees Celsius
                    temp_millidegrees = int(f.read().strip())
                    temps.append(temp_millidegrees / 1000.0)

        if not temps:
            return (None, False)

        avg_temp = sum(temps) / len(temps)
        return (f"{avg_temp:.0f}", True)

    except Exception:
        return (None, False)


def main():
    """Aggregate all metrics and output JSON"""
    cpu_load = get_load_average()
    mem_used_pct, mem_used_gb, mem_total_gb = get_memory_usage()
    disk_used_pct, disk_used_gb, disk_total_gb = get_disk_usage()
    net_rx_mbps, net_tx_mbps = get_network_traffic()
    temp_celsius, temp_available = get_temperature()

    metrics = {
        "cpu_load": cpu_load or "0.00",
        "mem_used_pct": mem_used_pct or "0",
        "mem_used_gb": mem_used_gb or "0.0",
        "mem_total_gb": mem_total_gb or "0",
        "disk_used_pct": disk_used_pct or "0",
        "disk_used_gb": disk_used_gb or "0",
        "disk_total_gb": disk_total_gb or "0",
        "net_rx_mbps": net_rx_mbps or "0.0",
        "net_tx_mbps": net_tx_mbps or "0.0",
        "temp_celsius": temp_celsius or "0",
        "temp_available": temp_available,
    }

    print(json.dumps(metrics))


if __name__ == "__main__":
    main()

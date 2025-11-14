#!/usr/bin/env python3
"""Volume monitoring for Eww top bar widgets

Listens to PulseAudio/PipeWire volume changes via D-Bus and outputs JSON
with volume percentage and muted state for deflisten consumption.

Output format:
{
  "volume_pct": "75",
  "muted": false
}

Usage:
  python3 volume-monitor.py

Exits with code 0 on normal termination, 1 on errors.
"""

import json
import sys
from typing import Optional

try:
    from pydbus import SessionBus
    from gi.repository import GLib
except ImportError:
    print(json.dumps({"volume_pct": "0", "muted": True, "error": "pydbus not available"}))
    sys.exit(1)


class VolumeMonitor:
    """Monitor PulseAudio/PipeWire volume changes via D-Bus"""

    def __init__(self):
        self.bus = SessionBus()
        self.volume_pct = 0
        self.muted = False
        self.sink_path = None

        # Connect to PulseAudio D-Bus interface
        try:
            self.pulse = self.bus.get("org.PulseAudio.Server", "/org/pulseaudio/server1")
            self._initialize_sink()
        except Exception as e:
            # Fallback: try PipeWire (which also uses PulseAudio protocol)
            try:
                self.pulse = self.bus.get("org.PulseAudio1", "/org/pulseaudio/server1")
                self._initialize_sink()
            except Exception:
                print(json.dumps({"volume_pct": "0", "muted": True, "error": f"Failed to connect: {e}"}))
                sys.exit(1)

    def _initialize_sink(self):
        """Get default sink and initial volume/mute state"""
        try:
            # Get fallback sink (default output device)
            fallback_sink = self.pulse.FallbackSink
            if not fallback_sink:
                print(json.dumps({"volume_pct": "0", "muted": True, "error": "No default sink"}))
                sys.exit(1)

            self.sink_path = fallback_sink
            sink = self.bus.get("org.PulseAudio.Core1.Device", self.sink_path)

            # Get initial volume (array of per-channel volumes, use first channel)
            volumes = sink.Volume
            if volumes:
                # PulseAudio volume is in range 0-65536 (0x10000), convert to percentage
                self.volume_pct = int((volumes[0] / 65536.0) * 100)

            # Get initial mute state
            self.muted = bool(sink.Mute)

            # Subscribe to property changes
            sink.onPropertiesChanged = self._on_properties_changed

            # Output initial state
            self._output_state()

        except Exception as e:
            print(json.dumps({"volume_pct": "0", "muted": True, "error": f"Initialization failed: {e}"}))
            sys.exit(1)

    def _on_properties_changed(self, interface, changed_properties, invalidated_properties):
        """Handle D-Bus property changes for volume/mute"""
        if "Volume" in changed_properties:
            volumes = changed_properties["Volume"]
            if volumes:
                self.volume_pct = int((volumes[0] / 65536.0) * 100)

        if "Mute" in changed_properties:
            self.muted = bool(changed_properties["Mute"])

        self._output_state()

    def _output_state(self):
        """Output current volume state as JSON"""
        state = {
            "volume_pct": str(self.volume_pct),
            "muted": self.muted
        }
        print(json.dumps(state), flush=True)

    def run(self):
        """Start GLib main loop to listen for D-Bus events"""
        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            loop.quit()


if __name__ == "__main__":
    monitor = VolumeMonitor()
    monitor.run()

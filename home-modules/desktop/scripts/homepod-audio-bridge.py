#!/usr/bin/env python3
"""PipeWire virtual sink -> Apple HomePod (AirPlay 2 / RAOP) audio bridge.

Watches the active PipeWire/PulseAudio default sink:
- When `sink-homepod-office` is selected as the default sink, opens an AirPlay 2
  session to the Office HomePod via `pyatv`, moves active application streams to
  `sink-homepod-office`, syncs volume/mute state, and streams low-latency PCM
  from `sink-homepod-office.monitor`.
- When another output device (e.g. Bluetooth headset or onboard audio) is
  selected, moves active application streams to the new default sink and
  immediately tears down the AirPlay session so the HomePod is released.
"""

from __future__ import annotations

import asyncio
from contextlib import suppress
import json
import logging
import os
import re
import signal
import subprocess
import sys
from typing import Optional

import pyatv
from pyatv.const import Protocol
from pyatv.interface import MediaMetadata
from pyatv.protocols.airplay.utils import dbfs_to_pct
import pyatv.protocols.raop as pyatv_raop
from pyatv.protocols.raop.audio_source import AudioSource
from pyatv.protocols.raop.protocols import StreamContext
from pyatv.storage.memory_storage import MemoryStorage

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
LOG = logging.getLogger("homepod-audio-bridge")

HOMEPOD_SINK = os.environ.get("HOMEPOD_SINK_NAME", "sink-homepod-office")
HOMEPOD_IDENTIFIER = os.environ.get("HOMEPOD_IDENTIFIER", "E6:46:E9:DD:E0:B6")
HOMEPOD_FALLBACK_HOST = os.environ.get("HOMEPOD_FALLBACK_HOST", "10.0.0.100")
HOMEPOD_CONTROL_PORT = int(os.environ.get("HOMEPOD_CONTROL_PORT", "6001"))
HOMEPOD_TIMING_PORT = int(os.environ.get("HOMEPOD_TIMING_PORT", "6002"))

PACTL = os.environ.get("PACTL_BIN", "pactl")
PAREC = os.environ.get("PAREC_BIN", "parec")
PW_DUMP = os.environ.get("PW_DUMP_BIN", "pw-dump")
PW_CLI = os.environ.get("PW_CLI_BIN", "pw-cli")

SAMPLE_RATE = 44100
CHANNELS = 2
SAMPLE_SIZE = 2  # 16-bit signed PCM (s16be)
BYTES_PER_FRAME = CHANNELS * SAMPLE_SIZE
FRAMES_PER_PACKET = 352
PACKET_BYTES = FRAMES_PER_PACKET * BYTES_PER_FRAME
# AirPlay 2 SETUP negotiates latencyMin=11025 frames (250ms at 44.1kHz),
# whereas pyatv defaults StreamContext.latency to 66150 frames (1500ms).
RAOP_LATENCY_FRAMES = int(os.environ.get("HOMEPOD_RAOP_LATENCY_FRAMES", "11025"))
# Total playback latency reported to PipeWire/PulseAudio clients (Chrome/YouTube)
# for automatic video/audio lip-sync compensation (250ms RAOP + ~15ms capture/network).
SINK_LATENCY_OFFSET_NSEC = int(
    os.environ.get("HOMEPOD_LATENCY_OFFSET_NSEC", str(int((RAOP_LATENCY_FRAMES / SAMPLE_RATE + 0.015) * 1_000_000_000)))
)
# Cap the jitter buffer at ~32ms (4 packets) so capture latency stays minimal.
MAX_BUFFER_BYTES = PACKET_BYTES * 4
TARGET_BUFFER_BYTES = PACKET_BYTES * 2


class PipeWireRawAudioSource(AudioSource):
    """Low-latency live PCM source backed by `parec` on the virtual sink monitor."""

    def __init__(self, monitor_source: str) -> None:
        self._monitor_source = monitor_source
        self._proc: Optional[asyncio.subprocess.Process] = None
        self._reader_task: Optional[asyncio.Task] = None
        self._buf = bytearray()
        self._closed = False
        self._muted = False

    def set_muted(self, muted: bool) -> None:
        self._muted = muted

    async def start(self) -> None:
        self._proc = await asyncio.create_subprocess_exec(
            PAREC,
            f"--device={self._monitor_source}",
            "--format=s16be",
            f"--rate={SAMPLE_RATE}",
            f"--channels={CHANNELS}",
            "--latency-msec=10",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        self._reader_task = asyncio.create_task(self._pump_stdout())

    async def _pump_stdout(self) -> None:
        assert self._proc is not None and self._proc.stdout is not None
        try:
            while not self._closed:
                chunk = await self._proc.stdout.read(PACKET_BYTES)
                if not chunk:
                    break
                self._buf.extend(chunk)
                if len(self._buf) > MAX_BUFFER_BYTES:
                    drop = len(self._buf) - TARGET_BUFFER_BYTES
                    # Align drop to frame boundary (4 bytes)
                    drop -= drop % BYTES_PER_FRAME
                    if drop > 0:
                        del self._buf[:drop]
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            LOG.debug("parec reader loop ended: %s", exc)

    async def close(self) -> None:
        self._closed = True
        if self._reader_task:
            self._reader_task.cancel()
            with suppress(asyncio.CancelledError):
                await self._reader_task
            self._reader_task = None
        if self._proc:
            with suppress(ProcessLookupError):
                self._proc.terminate()
            try:
                await asyncio.wait_for(self._proc.wait(), timeout=1.5)
            except asyncio.TimeoutError:
                with suppress(ProcessLookupError):
                    self._proc.kill()
            self._proc = None
        self._buf.clear()

    async def readframes(self, nframes: int) -> bytes:
        if self._closed:
            return AudioSource.NO_FRAMES
        need = nframes * BYTES_PER_FRAME
        if len(self._buf) >= need:
            data = bytes(self._buf[:need])
            del self._buf[:need]
        elif len(self._buf) > 0:
            # Pad partial frame alignment with silence without blocking the RTP clock
            aligned = len(self._buf) - (len(self._buf) % BYTES_PER_FRAME)
            data = bytes(self._buf[:aligned]) + (b"\x00" * (need - aligned))
            del self._buf[:aligned]
        else:
            data = b"\x00" * need

        if self._muted:
            return b"\x00" * need
        return data

    async def get_metadata(self) -> MediaMetadata:
        return MediaMetadata(
            title="Ryzen Desktop Audio",
            artist="PipeWire",
            album="NixOS",
            duration=0.0,
        )

    @property
    def sample_rate(self) -> int:
        return SAMPLE_RATE

    @property
    def channels(self) -> int:
        return CHANNELS

    @property
    def sample_size(self) -> int:
        return SAMPLE_SIZE

    @property
    def duration(self) -> int:
        return 0


_orig_open_source = pyatv_raop.open_source


async def _patched_open_source(source, sample_rate: int, channels: int, sample_size: int):
    if isinstance(source, AudioSource):
        return source
    return await _orig_open_source(source, sample_rate, channels, sample_size)


pyatv_raop.open_source = _patched_open_source

_orig_stream_context_reset = StreamContext.reset


def _patched_stream_context_reset(self) -> None:
    _orig_stream_context_reset(self)
    # pyatv hardcodes 22050 + sample_rate (66150 frames = 1500ms at 44.1kHz),
    # which tells the HomePod via RTP/NTP sync packets to buffer for 1.5s.
    # AirPlay 2 SETUP negotiates latencyMin=11025 (250ms), so use that instead.
    self.latency = RAOP_LATENCY_FRAMES


StreamContext.reset = _patched_stream_context_reset


def run_cmd(args: list[str]) -> str:
    try:
        res = subprocess.run(
            args,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3.0,
        )
        return res.stdout if res.returncode == 0 else ""
    except Exception:
        return ""


def get_default_sink() -> str:
    out = run_cmd([PACTL, "info"])
    for line in out.splitlines():
        if line.startswith("Default Sink: "):
            return line.split(": ", 1)[1].strip()
    return ""


def sink_exists(sink_name: str) -> bool:
    out = run_cmd([PACTL, "list", "short", "sinks"])
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1].strip() == sink_name:
            return True
    return False


def apply_sink_latency_offset(sink_name: str, latency_nsec: int) -> None:
    """Set PipeWire Props.latencyOffsetNsec on `sink_name` so browsers delay video to match AirPlay audio."""
    out = run_cmd([PW_DUMP])
    if not out:
        return
    try:
        items = json.loads(out)
    except Exception:
        return
    for item in items:
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        props = (item.get("info") or {}).get("props") or {}
        if props.get("node.name") == sink_name:
            node_id = item.get("id")
            if node_id is not None:
                run_cmd(
                    [
                        PW_CLI,
                        "set-param",
                        str(node_id),
                        "Props",
                        f"{{ latencyOffsetNsec = {int(latency_nsec)} }}",
                    ]
                )
            return


def get_sink_volume_and_mute(sink_name: str) -> tuple[Optional[float], bool]:
    """Return (volume_percent 0..100, muted) for `sink_name`."""
    vol_out = run_cmd([PACTL, "get-sink-volume", sink_name])
    mute_out = run_cmd([PACTL, "get-sink-mute", sink_name])
    muted = "yes" in mute_out.lower()
    m = re.search(r"(\d+)%", vol_out)
    vol_pct = float(int(m.group(1))) if m else None
    return vol_pct, muted


def set_sink_volume_percent(sink_name: str, pct: float) -> None:
    clamped = max(0, min(100, int(round(pct))))
    run_cmd([PACTL, "set-sink-volume", sink_name, f"{clamped}%"])


def move_movable_sink_inputs(target_sink: str) -> None:
    """Move application sink-inputs to `target_sink`, skipping pinned keepalive streams."""
    if not target_sink or not sink_exists(target_sink):
        return
    out = run_cmd([PACTL, "list", "sink-inputs"])
    current_id: Optional[str] = None
    app_name = ""
    media_name = ""

    def _maybe_move(input_id: Optional[str], app: str, media: str) -> None:
        if not input_id:
            return
        hay = f"{app} {media}".lower()
        # Never move the Jabra A2DP silent keepalive stream or Sunshine loopback
        if "pw-cat" in hay or "jabra" in hay or "sunshine" in hay:
            return
        run_cmd([PACTL, "move-sink-input", input_id, target_sink])

    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Sink Input #"):
            _maybe_move(current_id, app_name, media_name)
            current_id = s.split("#", 1)[1].strip()
            app_name = ""
            media_name = ""
        elif s.startswith("application.name = "):
            app_name = s.split("=", 1)[1].strip().strip('"')
        elif s.startswith("media.name = "):
            media_name = s.split("=", 1)[1].strip().strip('"')
    _maybe_move(current_id, app_name, media_name)


def has_active_app_streams_on_homepod() -> bool:
    """Return True if any non-keepalive stream is currently corked=no on the HomePod sink."""
    out = run_cmd([PW_DUMP])
    if not out:
        return True
    try:
        items = json.loads(out)
    except Exception:
        return True
    for item in items:
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        props = (item.get("info") or {}).get("props") or {}
        if props.get("media.class") == "Stream/Output/Audio":
            state = (item.get("info") or {}).get("state")
            app = str(props.get("application.name") or "").lower()
            if "pw-cat" in app:
                continue
            if state == "running":
                return True
    return False


async def discover_homepod(loop: asyncio.AbstractEventLoop, storage: MemoryStorage):
    # Fast path: unicast scan against known IP first (~0.3s)
    if HOMEPOD_FALLBACK_HOST:
        try:
            devices = await pyatv.scan(
                loop,
                hosts=[HOMEPOD_FALLBACK_HOST],
                timeout=2,
                protocol=Protocol.RAOP,
                storage=storage,
            )
            for dev in devices:
                if HOMEPOD_IDENTIFIER in dev.all_identifiers or dev.name == "Office":
                    return dev
            if devices:
                return devices[0]
        except Exception as exc:
            LOG.debug("Unicast scan failed (%s), falling back to multicast", exc)

    # Fallback: multicast mDNS scan by HomePod identifier
    devices = await pyatv.scan(
        loop,
        identifier=HOMEPOD_IDENTIFIER,
        timeout=4,
        protocol=Protocol.RAOP,
        storage=storage,
    )
    return devices[0] if devices else None


async def run_streaming_session(
    loop: asyncio.AbstractEventLoop,
    stop_requested: asyncio.Event,
) -> bool:
    """Connect to the HomePod and stream audio until `stop_requested` is set.

    Returns True if stopped cleanly due to user switching sinks, or False if
    the stream ended due to remote interruption / network error.
    """
    storage = MemoryStorage()
    conf = await discover_homepod(loop, storage)
    if not conf:
        LOG.warning("HomePod (%s) not found on LAN", HOMEPOD_IDENTIFIER)
        return False

    settings = await storage.get_settings(conf)
    settings.protocols.raop.control_port = HOMEPOD_CONTROL_PORT
    settings.protocols.raop.timing_port = HOMEPOD_TIMING_PORT

    LOG.info("Connecting to HomePod '%s' at %s...", conf.name, conf.address)
    atv = await pyatv.connect(conf, loop, protocol=Protocol.RAOP, storage=storage)
    source = PipeWireRawAudioSource(f"{HOMEPOD_SINK}.monitor")
    await source.start()

    stream_task = asyncio.create_task(atv.stream.stream_file(source))
    synced_initial_volume = False
    last_vol_pct: Optional[float] = None
    last_muted: Optional[bool] = None

    try:
        while not stop_requested.is_set() and not stream_task.done():
            default_sink = get_default_sink()
            if default_sink != HOMEPOD_SINK:
                LOG.info(
                    "Default sink switched from %s to %s; stopping HomePod stream",
                    HOMEPOD_SINK,
                    default_sink,
                )
                stop_requested.set()
                break

            # Once StreamClient is initialized, sync initial volume and mirror changes
            playback_mgr = getattr(atv.stream, "playback_manager", None)
            stream_client = getattr(playback_mgr, "stream_client", None) if playback_mgr else None
            if stream_client is not None:
                if not synced_initial_volume and stream_client.info:
                    synced_initial_volume = True
                    init_dbfs = stream_client.info.get("initialVolume")
                    pw_vol, pw_muted = get_sink_volume_and_mute(HOMEPOD_SINK)
                    if isinstance(init_dbfs, (int, float)):
                        hp_pct = max(15.0, min(100.0, dbfs_to_pct(float(init_dbfs))))
                        # If PipeWire sink is sitting at default 100%, adopt the HomePod's
                        # current hardware volume so we never unexpectedly blast at 100%.
                        if pw_vol is None or pw_vol >= 98.0:
                            set_sink_volume_percent(HOMEPOD_SINK, hp_pct)
                            pw_vol = round(hp_pct)
                    last_vol_pct = pw_vol
                    last_muted = pw_muted
                    source.set_muted(pw_muted)
                    if pw_vol is not None and not pw_muted:
                        effective = min(100.0, max(0.0, pw_vol))
                        with suppress(Exception):
                            await atv.audio.set_volume(effective)

                elif synced_initial_volume:
                    pw_vol, pw_muted = get_sink_volume_and_mute(HOMEPOD_SINK)
                    source.set_muted(pw_muted)
                    if pw_vol is not None and (
                        pw_vol != last_vol_pct or pw_muted != last_muted
                    ):
                        last_vol_pct = pw_vol
                        last_muted = pw_muted
                        if not pw_muted:
                            effective = min(100.0, max(0.0, pw_vol))
                            with suppress(Exception):
                                await atv.audio.set_volume(effective)

            await asyncio.sleep(0.25)

        if stop_requested.is_set():
            playback_mgr = getattr(atv.stream, "playback_manager", None)
            stream_client = getattr(playback_mgr, "stream_client", None) if playback_mgr else None
            if stream_client is not None:
                stream_client.stop()
            await source.close()
            try:
                await asyncio.wait_for(stream_task, timeout=2.5)
            except (asyncio.TimeoutError, Exception):
                stream_task.cancel()
            return True

        # Stream task ended on its own (e.g. remote takeover or network error)
        exc = stream_task.exception()
        if exc:
            LOG.warning("HomePod stream ended with error: %s", exc)
        else:
            LOG.info("HomePod stream closed by receiver")
        return False
    finally:
        await source.close()
        if not stream_task.done():
            stream_task.cancel()
            with suppress(asyncio.CancelledError, Exception):
                await stream_task
        close_res = atv.close()
        if close_res:
            with suppress(Exception):
                await asyncio.gather(*close_res, return_exceptions=True)


async def main() -> None:
    loop = asyncio.get_running_loop()
    shutdown_event = asyncio.Event()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown_event.set)

    # Wait for PulseAudio/PipeWire server and virtual sink
    for _ in range(60):
        if shutdown_event.is_set():
            return
        if sink_exists(HOMEPOD_SINK):
            break
        await asyncio.sleep(0.5)

    # Configure PipeWire latencyOffsetNsec on the HomePod virtual sink so
    # PulseAudio/PipeWire clients (Chrome/YouTube) automatically lip-sync video.
    apply_sink_latency_offset(HOMEPOD_SINK, SINK_LATENCY_OFFSET_NSEC)

    # Initialize virtual sink volume to a safe 35% if currently at 100%
    vol, _ = get_sink_volume_and_mute(HOMEPOD_SINK)
    if vol is not None and vol >= 99.0:
        set_sink_volume_percent(HOMEPOD_SINK, 35.0)

    LOG.info(
        "HomePod audio bridge ready (watching sink '%s', raop_latency=%d frames / %.0fms, offset=%dms)",
        HOMEPOD_SINK,
        RAOP_LATENCY_FRAMES,
        (RAOP_LATENCY_FRAMES / SAMPLE_RATE) * 1000.0,
        SINK_LATENCY_OFFSET_NSEC // 1_000_000,
    )
    was_selected = False
    wait_for_active_audio = False

    while not shutdown_event.is_set():
        default_sink = get_default_sink()
        is_selected = default_sink == HOMEPOD_SINK

        if is_selected and not was_selected:
            # User just switched default output to HomePod (Office)
            was_selected = True
            wait_for_active_audio = False
            apply_sink_latency_offset(HOMEPOD_SINK, SINK_LATENCY_OFFSET_NSEC)
            move_movable_sink_inputs(HOMEPOD_SINK)

        elif not is_selected and was_selected:
            # User switched away from HomePod (Office) to another sink (e.g. Bluetooth)
            was_selected = False
            wait_for_active_audio = False
            if default_sink:
                move_movable_sink_inputs(default_sink)

        if is_selected:
            if wait_for_active_audio and not has_active_app_streams_on_homepod():
                await asyncio.sleep(0.5)
                continue

            stop_stream = asyncio.Event()
            try:
                clean_stop = await run_streaming_session(loop, stop_stream)
                if not clean_stop:
                    # If the HomePod closed the session while Ryzen is silent,
                    # wait for active app audio before reconnecting so we don't
                    # fight Siri / iPhone AirPlay when Ryzen is idle.
                    if not has_active_app_streams_on_homepod():
                        wait_for_active_audio = True
                    await asyncio.sleep(2.0)
            except Exception as exc:
                LOG.warning("HomePod session failed: %s", exc)
                await asyncio.sleep(2.5)
        else:
            await asyncio.sleep(0.35)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)

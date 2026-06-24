#!/usr/bin/env python3
"""dictation-level — emit the live input level (0-100) of the PipeWire default
source, ~20x/sec, one integer per line on stdout.

Drives the dictation overlay's "is the mic actually hearing me?" meter. It reads
the SAME "default" source voxtype captures, so a flat meter while you speak means
the wrong/muted mic is selected (the real reliability failure mode) rather than a
transcription problem.

Quickshell starts this only while voxtype is recording and SIGTERMs it when
recording stops; we spawn pw-record as a child and always terminate it on exit so
the mic is never left tapped.

argv[1] (optional): path to the pw-record binary (default: "pw-record" on PATH).
"""
import array
import signal
import subprocess
import sys

PW_RECORD = sys.argv[1] if len(sys.argv) > 1 else "pw-record"
FRAME = 800  # samples per emit (~50 ms @ 16 kHz) -> ~20 updates/sec

proc = subprocess.Popen(
    [PW_RECORD, "--rate=16000", "--channels=1", "--format=s16",
     "--latency=30ms", "-"],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)


def _stop(*_):
    try:
        proc.terminate()
    except Exception:
        pass
    sys.exit(0)


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)

out = sys.stdout
src = proc.stdout
warmup = 3  # drop the stream-startup spike before reporting real levels
try:
    while True:
        chunk = src.read(FRAME * 2)
        if not chunk:
            break
        if len(chunk) % 2:
            chunk = chunk[:-1]
        samples = array.array("h")
        samples.frombytes(chunk)
        if not samples:
            continue
        if warmup > 0:
            warmup -= 1
            continue
        peak = 0
        for s in samples:
            v = -s if s < 0 else s
            if v > peak:
                peak = v
        # sqrt curve so quiet speech registers clearly; clamp the top.
        level = int((peak / 32768.0) ** 0.5 * 140)
        if level > 100:
            level = 100
        out.write(f"{level}\n")
        out.flush()
finally:
    try:
        proc.terminate()
    except Exception:
        pass

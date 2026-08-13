#!/usr/bin/env python3
"""touch-longpress - hold a finger still to get a right click.

A touchscreen has no second button, so context menus are simply unreachable by
touch: nothing in the stack turns a long press into a right click. libinput does
not do it, sway does not do it, and only some toolkits do it for their own
widgets. This daemon supplies it system-wide.

The click has to carry a position, and it is dotool that supplies one:

    Sway does not move its pointer to the touch point. Measured directly — a
    finger at (822, 696) followed by a bare synthetic BTN_RIGHT opened the menu
    about 220px away, wherever the pointer happened to be sitting.

    A hand-rolled uinput device carrying ABS_X/ABS_Y does not help either:
    without INPUT_PROP_DIRECT libinput classifies it as a plain pointer and
    ignores the absolute axes, so the button still lands wherever the cursor
    already was. dotool builds a device libinput does honour, and `mouseto`
    takes a fraction of the whole layout — measured landing within 3px.

Positions are therefore converted device -> that touchscreen's output rect ->
fraction of the entire layout, which is what makes this correct with more than
one screen attached.

Only single-finger contacts become right clicks. A second finger cancels that —
but TWO fingers held still are their own gesture: dictation toggle, the glass
twin of the touchpad's hold:4 binding. Moving multi-finger contacts (pinches,
scrolls, lisgd swipes) cancel both holds by exceeding the movement tolerance.
"""
import errno
import json
import os
import selectors
import subprocess
import sys
import time

from evdev import InputDevice, ecodes as e

HOLD_SECONDS = float(os.environ.get("TOUCH_LONGPRESS_SECONDS", "0.6"))
# Movement allowance while holding, as a fraction of the screen. A fingertip
# rolls a little over half a second; too tight and the gesture never fires, too
# loose and a slow drag becomes a right click.
MOVE_TOLERANCE = float(os.environ.get("TOUCH_LONGPRESS_TOLERANCE", "0.02"))
STATE_FILE = os.environ.get(
    "TOUCH_MAP_STATE",
    os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "touch-map.state"),
)


def log(msg):
    print(f"touch-longpress: {msg}", file=sys.stderr, flush=True)


def sway(*args):
    try:
        out = subprocess.run(["swaymsg", "-t", *args],
                             capture_output=True, text=True, timeout=5).stdout
        return json.loads(out)
    except Exception as exc:
        log(f"swaymsg {' '.join(args)} failed: {exc}")
        return None


def layout_bounds(outputs):
    """Bounding box of every active output, in layout coordinates."""
    rects = [o["rect"] for o in outputs if o.get("active")]
    if not rects:
        return None
    x0 = min(r["x"] for r in rects)
    y0 = min(r["y"] for r in rects)
    x1 = max(r["x"] + r["width"] for r in rects)
    y1 = max(r["y"] + r["height"] for r in rects)
    return x0, y0, x1 - x0, y1 - y0


def read_bindings():
    """identifier -> output name, from touch-map's published state."""
    out = {}
    try:
        with open(STATE_FILE) as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3 and parts[2] == "touch":
                    out[parts[0]] = parts[1]
    except OSError:
        pass
    return out


def sway_identifier(dev):
    """Rebuild sway's vendor:product:name identifier for an evdev device."""
    return f"{dev.info.vendor}:{dev.info.product}:{dev.name.replace(' ', '_')}"


def open_touch_devices(bindings):
    """Devices touch-map bound, that we can actually read."""
    found = []
    for path in sorted(os.listdir("/dev/input")):
        if not path.startswith("event"):
            continue
        full = f"/dev/input/{path}"
        try:
            dev = InputDevice(full)
        except OSError as exc:
            if exc.errno not in (errno.EACCES, errno.ENODEV):
                log(f"{full}: {exc}")
            continue
        ident = sway_identifier(dev)
        if ident in bindings:
            caps = dict(dev.capabilities().get(e.EV_ABS, []))
            ax = caps.get(e.ABS_MT_POSITION_X) or caps.get(e.ABS_X)
            ay = caps.get(e.ABS_MT_POSITION_Y) or caps.get(e.ABS_Y)
            if ax and ay:
                found.append((dev, ident, bindings[ident], ax, ay))
                continue
        dev.close()
    return found


DOTOOL = os.environ.get("DOTOOL_BIN", "dotool")
# Two fingers held still toggle dictation — the glass twin of the touchpad's
# hold:4 binding, for when speaking beats pecking at an on-screen keyboard.
DICTATION_BIN = os.environ.get(
    "DICTATION_BIN",
    os.path.expanduser("~/.local/bin/dictation"),
)


def right_click_at(fx, fy):
    """Move the pointer to a fraction of the layout and right click there.

    dotool reports trouble on stderr while still exiting 0 — notably
    "could not open device file" when it cannot reach /dev/uinput, which is the
    likely failure here because uinput group membership only takes effect for a
    session started after the group was granted. Say so rather than let the
    gesture look like it simply did nothing.
    """
    try:
        res = subprocess.run(
            [DOTOOL],
            input=f"mouseto {fx:.5f} {fy:.5f}\nclick right\n",
            text=True, capture_output=True, timeout=5, check=False,
        )
    except Exception as exc:
        log(f"dotool could not be run: {exc}")
        return False
    err = (res.stderr or "").strip()
    if res.returncode != 0 or err:
        log(f"dotool failed (rc={res.returncode}): {err or '(no message)'}")
        if "device file" in err:
            log("  /dev/uinput is not reachable — log out and back in so the "
                "session picks up the 'uinput' group")
        return False
    return True


def main():
    bindings = read_bindings()
    if not bindings:
        log(f"no touchscreens in {STATE_FILE}; nothing to do")
        return 0

    devices = open_touch_devices(bindings)
    if not devices:
        log("no readable touchscreen among the bound devices")
        return 0

    outputs = sway("get_outputs") or []
    bounds = layout_bounds(outputs)
    if not bounds:
        log("no active outputs")
        return 0
    out_rects = {o["name"]: o["rect"] for o in outputs if o.get("active")}

    log(f"hold {HOLD_SECONDS}s to right click; watching "
        + ", ".join(f"{d.path} ({ident})" for d, ident, _, _, _ in devices))

    sel = selectors.DefaultSelector()
    for entry in devices:
        sel.register(entry[0], selectors.EVENT_READ, entry)

    # Per device: current contact state.
    state = {ident: {} for _, ident, _, _, _ in devices}

    def fire(ident, output, ax, ay, raw_x, raw_y):
        rect = out_rects.get(output)
        if not rect:
            log(f"output {output} is gone; not clicking")
            return
        # device -> that output's rect -> fraction of the whole layout
        fx = min(max(raw_x / ax.max, 0.0), 1.0)
        fy = min(max(raw_y / ay.max, 0.0), 1.0)
        lx = rect["x"] + fx * rect["width"]
        ly = rect["y"] + fy * rect["height"]
        bx, by, bw, bh = bounds
        if right_click_at((lx - bx) / bw, (ly - by) / bh):
            log(f"right click at layout ({lx:.0f}, {ly:.0f}) on {output}")

    def state_mtime():
        try:
            return os.stat(STATE_FILE).st_mtime
        except OSError:
            return 0.0

    seen_mtime = state_mtime()
    next_check = time.monotonic() + 2.0

    while True:
        # touch-map rewrites its state file whenever the touchscreen set or
        # its output bindings change (hot-plug, iptsd restart). Our fds go
        # stale at exactly those moments — a destroyed device's fd just stops
        # delivering, silently — so re-exec and open the current set fresh.
        if time.monotonic() >= next_check:
            next_check = time.monotonic() + 2.0
            if state_mtime() != seen_mtime:
                log("touch mapping changed; re-execing to reopen devices")
                os.execv(sys.executable, [sys.executable] + sys.argv)

        # Short timeout so a hold can mature even when the device goes quiet —
        # a perfectly still finger emits nothing at all after touching down.
        for key, _ in sel.select(timeout=0.05):
            dev, ident, output, ax, ay = key.data
            try:
                events = list(dev.read())
            except (BlockingIOError, OSError):
                continue
            st = state[ident]
            for ev in events:
                if ev.type == e.EV_ABS:
                    if ev.code == e.ABS_MT_SLOT:
                        st["slot"] = ev.value
                    elif ev.code == e.ABS_MT_TRACKING_ID:
                        if ev.value == -1:
                            st["fingers"] = max(0, st.get("fingers", 1) - 1)
                            st["armed"] = False
                            # Any lift ends a two-finger hold too — a matured
                            # one has already fired, an immature one is a tap.
                            st["armed2"] = False
                        else:
                            st["fingers"] = st.get("fingers", 0) + 1
                            # A second finger ends the single-finger hold and
                            # starts the two-finger one (touch dictation, the
                            # glass twin of the touchpad's hold:4). Per-slot
                            # baselines: st["x"] interleaves both fingers'
                            # positions, which reads as wild movement.
                            if st["fingers"] == 2:
                                st["armed"] = False
                                st["multi"] = True
                                st["armed2"] = True
                                st["down2"] = time.monotonic()
                                st["base2"] = dict(st.get("pos", {}))
                            elif st["fingers"] > 2:
                                st["armed"] = False
                                st["armed2"] = False
                    elif ev.code in (e.ABS_MT_POSITION_X, e.ABS_X):
                        st["x"] = ev.value
                        if ev.code == e.ABS_MT_POSITION_X:
                            slot = st.get("slot", 0)
                            pos = st.setdefault("pos", {})
                            pos[slot] = (ev.value, pos.get(slot, (0, 0))[1])
                    elif ev.code in (e.ABS_MT_POSITION_Y, e.ABS_Y):
                        st["y"] = ev.value
                        if ev.code == e.ABS_MT_POSITION_Y:
                            slot = st.get("slot", 0)
                            pos = st.setdefault("pos", {})
                            pos[slot] = (pos.get(slot, (0, 0))[0], ev.value)
                elif ev.type == e.EV_KEY and ev.code == e.BTN_TOUCH:
                    if ev.value == 1:
                        st.update(down=time.monotonic(), armed=True, multi=False,
                                  fingers=max(1, st.get("fingers", 0)),
                                  x0=st.get("x"), y0=st.get("y"))
                    else:
                        st.update(armed=False, multi=False, fingers=0,
                                  armed2=False, pos={})

            # Movement cancels the hold.
            if st.get("armed") and st.get("x0") is not None:
                dx = abs(st.get("x", st["x0"]) - st["x0"]) / ax.max
                dy = abs(st.get("y", st["y0"]) - st["y0"]) / ay.max
                if max(dx, dy) > MOVE_TOLERANCE:
                    st["armed"] = False

            # Two-finger hold: each finger is judged against its own start
            # point. A pinch or scroll moves at least one finger well past the
            # tolerance and cancels; two fingers resting still do not. The
            # second finger's first position can arrive after the baseline was
            # taken, so it is adopted late rather than read as a jump.
            if st.get("armed2"):
                base = st.setdefault("base2", {})
                for slot, xy in st.get("pos", {}).items():
                    if slot not in base:
                        base[slot] = xy
                        continue
                    if (abs(xy[0] - base[slot][0]) / ax.max > MOVE_TOLERANCE
                            or abs(xy[1] - base[slot][1]) / ay.max > MOVE_TOLERANCE):
                        st["armed2"] = False
                        break

        # Mature any held contact.
        for dev, ident, output, ax, ay in devices:
            st = state[ident]
            if st.get("armed2") and st.get("fingers") == 2 \
                    and time.monotonic() - st.get("down2", 0) >= HOLD_SECONDS:
                st["armed2"] = False
                log("two-finger hold -> dictation toggle")
                try:
                    subprocess.Popen([DICTATION_BIN, "toggle"],
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
                except Exception as exc:
                    log(f"dictation toggle failed: {exc}")
            if not st.get("armed") or st.get("multi"):
                continue
            if time.monotonic() - st.get("down", 0) >= HOLD_SECONDS:
                st["armed"] = False
                if st.get("x") is not None and st.get("y") is not None:
                    fire(ident, output, ax, ay, st["x"], st["y"])


if __name__ == "__main__":
    sys.exit(main())

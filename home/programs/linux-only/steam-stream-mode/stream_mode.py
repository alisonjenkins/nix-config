"""Match a niri output's mode to a Steam Remote Play client's resolution.

Steam Remote Play captures a whole output rather than a window, so a client
receives the entire panel scaled into its own screen. On an ultrawide that
means most of the client's pixels are letterbox: a 5120x1440 panel sent to a
1280x800 Steam Deck arrives as 1280x360 of content inside an 800-line frame.

Steam has no prep-command hook, so there is nothing to hang a mode switch on.
It does, however, log both ends of a session and the resolution the client
asked for, which is enough to drive the switch from outside:

    >>> Starting desktop stream
    >>> Capture resolution set to 1280x800
    >>> Stopped desktop stream

`watch` follows that log and narrows the output to match the client for the
duration of a session, restoring the previous mode afterwards.
"""

import json
import os
import re
import signal
import subprocess
import sys
import time

OUTPUT = os.environ.get("STREAM_MODE_OUTPUT", "DP-2")
LOG = os.environ.get(
    "STREAM_MODE_LOG",
    os.path.expanduser("~/.local/share/Steam/logs/streaming_log.txt"),
)
NIRI = os.environ.get("STREAM_MODE_NIRI", "niri")

START_RE = re.compile(r">>> Starting desktop stream")
STOP_RE = re.compile(r">>> Stopped desktop stream")
RES_RE = re.compile(r">>> Capture resolution set to (\d+)x(\d+)")


def log(message):
    print(message, flush=True)


def pick_mode(modes, want_w, want_h):
    """Choose the mode that best serves a client of want_w x want_h.

    An exact match is always best: the client renders it 1:1 with no
    resampling at either end.

    Failing that, the aspect ratio matters more than the resolution, because a
    mismatched ratio is what produces the letterboxing in the first place.
    Among modes of equally good ratio, prefer the smallest that still covers
    the client — a larger one only adds encode work and downscale blur — and
    fall back to the largest when nothing covers it.
    """
    if not modes:
        return None

    exact = [m for m in modes if m["width"] == want_w and m["height"] == want_h]
    if exact:
        return max(exact, key=lambda m: m["refresh_rate"])

    target = want_w / want_h

    def score(mode):
        ratio = mode["width"] / mode["height"]
        area = mode["width"] * mode["height"]
        covers = mode["width"] >= want_w and mode["height"] >= want_h
        return (
            round(abs(ratio - target), 4),
            0 if covers else 1,
            area if covers else -area,
            -mode["refresh_rate"],
        )

    return min(modes, key=score)


def mode_string(mode):
    return "{}x{}@{:.3f}".format(
        mode["width"], mode["height"], mode["refresh_rate"] / 1000
    )


def niri_outputs():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "outputs"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(raw)


def output_state(name=OUTPUT):
    outputs = niri_outputs()
    if name not in outputs:
        raise SystemExit("stream-mode: output {} not found".format(name))
    out = outputs[name]
    modes = out.get("modes") or []
    index = out.get("current_mode")
    current = modes[index] if index is not None and index < len(modes) else None
    return modes, current


def apply_mode(mode, name=OUTPUT):
    subprocess.run(
        [NIRI, "msg", "output", name, "mode", mode_string(mode)],
        check=True,
    )
    log("stream-mode: {} set to {}".format(name, mode_string(mode)))


class Session:
    """Tracks one streaming session's mode change so it can be undone once."""

    def __init__(self):
        self.saved = None

    def start(self, want_w, want_h):
        if self.saved is not None:
            # Already applied for this session. Steam re-logs the capture
            # resolution after the output changes under it, and reacting to
            # that would chase its own tail.
            return

        modes, current = output_state()
        chosen = pick_mode(modes, want_w, want_h)
        if chosen is None or current is None:
            log("stream-mode: no usable mode for {}x{}".format(want_w, want_h))
            return
        if (chosen["width"], chosen["height"]) == (current["width"], current["height"]):
            log("stream-mode: already {}x{}, leaving it".format(want_w, want_h))
            return

        self.saved = current
        apply_mode(chosen)

    def restore(self):
        if self.saved is None:
            return
        saved, self.saved = self.saved, None
        try:
            apply_mode(saved)
        except (subprocess.CalledProcessError, OSError) as exc:
            log("stream-mode: could not restore mode: {}".format(exc))


def follow(path, seek_to_end=True, idle_yield=False):
    """Yield lines appended to path, surviving truncation and replacement.

    Steam truncates this log on client restart and rotates it to
    streaming_log.previous.txt, so a plain read loop silently goes deaf.

    seek_to_end skips whatever the file already holds, which is what a watcher
    wants on startup: a past session's start line must not be replayed as if
    it were live. Pass False to read from the beginning.

    idle_yield emits None whenever a poll finds nothing, so a caller with a
    deadline to honour is not blocked until the next line happens to arrive.
    """
    handle = None
    inode = None
    pending = b""
    # Only the very first open honours seek_to_end. A later reopen means the
    # file was truncated or replaced, and the lines that triggered it are
    # exactly the ones worth reading — skipping to the end there would lose a
    # whole session.

    # Binary mode deliberately: a text-mode tell() returns an opaque cookie
    # rather than a byte offset, so comparing it against st_size to detect
    # truncation does not reliably work.
    while True:
        try:
            if handle is None:
                handle = open(path, "rb")
                inode = os.fstat(handle.fileno()).st_ino
                pending = b""
                if seek_to_end:
                    handle.seek(0, os.SEEK_END)
                    seek_to_end = False

            chunk = handle.readline()
            if chunk:
                pending += chunk
                if pending.endswith(b"\n"):
                    line, pending = pending, b""
                    yield line.decode("utf-8", "replace")
                continue

            try:
                stat = os.stat(path)
            except FileNotFoundError:
                handle.close()
                handle = None
                time.sleep(1.0)
                continue

            if stat.st_ino != inode or stat.st_size < handle.tell():
                handle.close()
                handle = None
                continue

            time.sleep(0.25)
            if idle_yield:
                yield None
        except OSError:
            if handle is not None:
                handle.close()
                handle = None
            time.sleep(1.0)


# --- Session supervision ---------------------------------------------------
#
# Steam is single-instance, so a headless gamescope session and the desktop
# client cannot coexist; something has to decide which is running. Streaming
# wins: when a stream starts against the desktop session, the machine flips to
# headless. That costs the client one reconnect, because the flip kills the
# very Steam serving the connection, but it is the only unambiguous trigger.
#
# A client connection is deliberately *not* the trigger. A Steam Deck
# broadcasts on 27036 continuously just by being awake and logs a connection
# whenever it pairs, so triggering on that would kill the desktop client at
# random.

HEADLESS_UNIT = os.environ.get("STREAM_MODE_HEADLESS_UNIT", "steam-headless.service")
DESKTOP_STEAM = os.environ.get("STREAM_MODE_DESKTOP_STEAM", "steam")
REVERT_AFTER = float(os.environ.get("STREAM_MODE_REVERT_AFTER", "600"))


def unit_active(unit=HEADLESS_UNIT):
    result = subprocess.run(
        ["systemctl", "--user", "is-active", "--quiet", unit],
        check=False,
    )
    return result.returncode == 0


def enter_headless():
    if unit_active():
        return False
    log("stream-mode: stream started, switching to the headless session")
    # --no-block: the unit's ExecStart *is* the session and does not return.
    subprocess.run(
        ["systemctl", "--user", "start", "--no-block", HEADLESS_UNIT],
        check=False,
    )
    return True


def leave_headless():
    if not unit_active():
        return False
    log("stream-mode: idle, returning to the desktop Steam client")
    subprocess.run(["systemctl", "--user", "stop", HEADLESS_UNIT], check=False)
    try:
        subprocess.Popen(
            [DESKTOP_STEAM],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        log("stream-mode: could not relaunch the desktop client: {}".format(exc))
    return True


def supervise():
    log("stream-mode: supervising {} (revert after {:.0f}s idle)".format(LOG, REVERT_AFTER))
    revert_at = None

    for line in follow(LOG, idle_yield=True):
        now = time.monotonic()

        if line is None:
            if revert_at is not None and now >= revert_at:
                revert_at = None
                leave_headless()
            continue

        if START_RE.search(line):
            # A stream against the headless session logs this too; entering is
            # a no-op there, and cancelling the timer is what keeps a
            # reconnect from being treated as the session going idle.
            revert_at = None
            enter_headless()
        elif STOP_RE.search(line):
            if unit_active():
                revert_at = now + REVERT_AFTER


def watch():
    session = Session()

    def bail(_signum, _frame):
        # Leaving the panel narrowed because the service stopped mid-session
        # would be worse than never having switched.
        session.restore()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGINT, bail)

    log("stream-mode: watching {} for {}".format(LOG, OUTPUT))
    armed = False
    try:
        for line in follow(LOG):
            if START_RE.search(line):
                armed = True
                continue
            if STOP_RE.search(line):
                armed = False
                session.restore()
                continue
            if armed:
                match = RES_RE.search(line)
                if match:
                    session.start(int(match.group(1)), int(match.group(2)))
    finally:
        session.restore()


def main(argv):
    if len(argv) >= 2 and argv[1] == "watch":
        watch()
        return 0

    if len(argv) >= 2 and argv[1] == "supervise":
        supervise()
        return 0

    if len(argv) == 3 and argv[1] == "match":
        try:
            want_w, want_h = (int(part) for part in argv[2].split("x", 1))
        except ValueError:
            print("stream-mode: expected WIDTHxHEIGHT", file=sys.stderr)
            return 2
        modes, _ = output_state()
        chosen = pick_mode(modes, want_w, want_h)
        if chosen is None:
            print("stream-mode: no modes available", file=sys.stderr)
            return 1
        apply_mode(chosen)
        return 0

    if len(argv) == 2 and argv[1] == "restore":
        modes, _ = output_state()
        preferred = [m for m in modes if m.get("is_preferred")]
        if not preferred:
            print("stream-mode: no preferred mode to restore", file=sys.stderr)
            return 1
        apply_mode(max(preferred, key=lambda m: m["refresh_rate"]))
        return 0

    if len(argv) == 2 and argv[1] == "status":
        _, current = output_state()
        print("stream-mode: {} at {}".format(OUTPUT, mode_string(current)))
        return 0

    print(
        "usage: stream-mode [supervise|watch|match WIDTHxHEIGHT|restore|status]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

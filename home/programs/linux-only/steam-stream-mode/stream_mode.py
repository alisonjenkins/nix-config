"""Point niri's dynamic cast target at whichever game Steam is streaming.

Steam Remote Play captures a whole output, so a client receives the entire
panel: on a 5120x1440 ultrawide a 1280x800 Steam Deck gets 1280x360 of
content inside an 800-line frame, and whatever happens to be on screen rather
than the game.

Narrowing the output does not fix either half. The PipeWire capture is
negotiated when the session starts and does not follow a later mode change —
Steam keeps reporting the old geometry and churns through renegotiation,
which shows as flicker — and a smaller desktop is still a desktop, with the
game still a window on it.

niri's dynamic cast target (25.05+) solves both at once. It is a PipeWire
stream that follows one chosen window, offered to portal clients as "niri
Dynamic Cast Target". Casting a window means the stream is the window: its
size is the window's size, so there is no output geometry to fight and
nothing else in frame.

Steam logs the pid of each game window it starts streaming:

    Adding window 4194306 (4) for process 2331545 and gameID 2854740

which is enough to find the matching niri window and cast it, with no
interaction on the host — the point being that this has to work when nobody
is at the machine.
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
ADD_WINDOW_RE = re.compile(r"Adding window \d+ \(\d+\) for process (\d+) and gameID (\d+)")
REMOVE_PROC_RE = re.compile(r"Removing process (\d+) for gameID (\d+)")


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


# --- Dynamic cast targeting -------------------------------------------------


def niri_windows():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "windows"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(raw)


def parent_pids(pid, limit=8):
    """Walk up the process tree, nearest ancestor first.

    A game's own pid often owns no niri window: under gamescope or
    pressure-vessel the window belongs to an ancestor, so the pid Steam logs
    has to be resolved upwards before giving up.
    """
    chain = []
    current = pid
    for _ in range(limit):
        try:
            with open("/proc/{}/stat".format(current)) as fh:
                # comm can contain spaces and parentheses; ppid is the field
                # after the last ')'.
                fields = fh.read().rpartition(")")[2].split()
            current = int(fields[1])
        except (OSError, ValueError, IndexError):
            break
        if current <= 1:
            break
        chain.append(current)
    return chain


def window_for_pid(pid, windows=None):
    """Find the niri window belonging to pid, or to its nearest ancestor."""
    if windows is None:
        windows = niri_windows()

    by_pid = {}
    for window in windows:
        if window.get("pid") is not None:
            by_pid.setdefault(window["pid"], window)

    if pid in by_pid:
        return by_pid[pid]
    for ancestor in parent_pids(pid):
        if ancestor in by_pid:
            return by_pid[ancestor]
    return None


def set_cast_window(window_id):
    subprocess.run(
        [NIRI, "msg", "action", "set-dynamic-cast-window", "--id", str(window_id)],
        check=True,
    )


def clear_cast():
    subprocess.run(
        [NIRI, "msg", "action", "clear-dynamic-cast-target"],
        check=False,
    )


class Cast:
    """Casts one game window at a time, and clears when that game goes away."""

    def __init__(self, settle_attempts=10, settle_delay=0.5):
        self.game_pid = None
        self.settle_attempts = settle_attempts
        self.settle_delay = settle_delay

    def target(self, pid, game_id):
        # The niri window frequently does not exist yet when Steam logs the
        # pid, so this retries rather than resolving once and giving up.
        for _ in range(self.settle_attempts):
            try:
                window = window_for_pid(pid)
            except (subprocess.CalledProcessError, ValueError, OSError) as exc:
                log("stream-mode: could not query niri windows: {}".format(exc))
                return False
            if window is not None:
                try:
                    set_cast_window(window["id"])
                except (subprocess.CalledProcessError, OSError) as exc:
                    log("stream-mode: could not cast window: {}".format(exc))
                    return False
                self.game_pid = pid
                log(
                    "stream-mode: casting {} (window {}, pid {}, game {})".format(
                        window.get("app_id") or window.get("title") or "window",
                        window["id"],
                        pid,
                        game_id,
                    )
                )
                return True
            time.sleep(self.settle_delay)

        log("stream-mode: no niri window found for pid {} (game {})".format(pid, game_id))
        return False

    def release(self, pid=None):
        if self.game_pid is None:
            return False
        if pid is not None and pid != self.game_pid:
            return False
        self.game_pid = None
        clear_cast()
        log("stream-mode: cleared the cast target")
        return True


def watch():
    cast = Cast()

    def bail(_signum, _frame):
        cast.release()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGINT, bail)

    log("stream-mode: watching {} for streamed game windows".format(LOG))
    try:
        for line in follow(LOG):
            match = ADD_WINDOW_RE.search(line)
            if match:
                cast.target(int(match.group(1)), int(match.group(2)))
                continue

            match = REMOVE_PROC_RE.search(line)
            if match:
                cast.release(int(match.group(1)))
                continue

            if STOP_RE.search(line):
                cast.release()
    finally:
        cast.release()


def main(argv):
    if len(argv) >= 2 and argv[1] == "watch":
        watch()
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

    if len(argv) == 3 and argv[1] == "cast":
        try:
            pid = int(argv[2])
        except ValueError:
            print("stream-mode: expected a pid", file=sys.stderr)
            return 2
        return 0 if Cast().target(pid, 0) else 1

    if len(argv) == 2 and argv[1] == "uncast":
        clear_cast()
        return 0

    if len(argv) == 2 and argv[1] == "status":
        _, current = output_state()
        print("stream-mode: {} at {}".format(OUTPUT, mode_string(current)))
        return 0

    print(
        "usage: stream-mode "
        "[watch|cast PID|uncast|match WIDTHxHEIGHT|restore|status]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

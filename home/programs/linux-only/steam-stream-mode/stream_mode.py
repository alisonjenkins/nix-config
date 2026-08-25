"""Give Steam Remote Play a virtual output sized to the streaming client.

Steam Remote Play captures a whole output, and asks the portal for MONITOR
sources only — its picker has no "Window" tab, while other clients' pickers on
the same portal do. So no window-scoped source can reach it, and on a
5120x1440 ultrawide a 1280x800 Steam Deck otherwise receives about 1280x360 of
content inside an 800-line frame, showing whatever happens to be on screen.

Narrowing the physical output does not fix it either: the PipeWire stream is
negotiated when the session starts and does not follow a later mode change, so
Steam keeps reporting the original geometry and the renegotiation churn shows
as flicker.

What works is giving Steam a different monitor to capture. niri (patched with
virtual output support) can create an output at the client's exact resolution,
which the game is placed on, leaving the physical display untouched.

The timings come from Steam's own logs:

    remote_connections.txt:
        Client 1774... (ali-steam-deck) connected via direct connection
    streaming_log.txt:
        >>> Starting desktop stream
        >>> Capture resolution set to 1280x800
        Adding window 4194306 (4) for process 2331545 and gameID 2854740
        Removing process 2163386 for gameID 2854740
        >>> Stopped desktop stream

The output has to exist *before* a session starts, because Steam selects its
capture source then — and because a remembered selection naming an output that
does not exist cannot be honoured. Connect is therefore the trigger, which is
safe here: creating an output destroys nothing, unlike the Steam restart that
made connect unusable as a trigger for the abandoned headless design.
"""

import json
import os
import re
import signal
import subprocess
import sys
import time

NIRI = os.environ.get("STREAM_MODE_NIRI", "niri")
LOG = os.environ.get(
    "STREAM_MODE_LOG",
    os.path.expanduser("~/.local/share/Steam/logs/streaming_log.txt"),
)
CONNECTIONS_LOG = os.environ.get(
    "STREAM_MODE_CONNECTIONS_LOG",
    os.path.expanduser("~/.local/share/Steam/logs/remote_connections.txt"),
)
STATE = os.environ.get(
    "STREAM_MODE_STATE",
    os.path.join(
        os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
        "stream-mode",
        "clients.json",
    ),
)
DEFAULT_WIDTH = int(os.environ.get("STREAM_MODE_DEFAULT_WIDTH", "1280"))
DEFAULT_HEIGHT = int(os.environ.get("STREAM_MODE_DEFAULT_HEIGHT", "800"))
DEFAULT_REFRESH = int(os.environ.get("STREAM_MODE_DEFAULT_REFRESH", "60"))
# Long enough that a reconnect is not mistaken for the session ending. Removing
# the output mid-reconnect would drop the client's remembered capture source.
REMOVE_AFTER = float(os.environ.get("STREAM_MODE_REMOVE_AFTER", "120"))
# How long to keep looking for a game's window after Steam reports its pid.
# Generous because the gap is not a race but a real wait: Proton prefix setup,
# shader compilation and launchers routinely take minutes before anything is
# mapped. A five-second budget gave up long before the window existed.
STAGE_TIMEOUT = float(os.environ.get("STREAM_MODE_STAGE_TIMEOUT", "300"))
# Fixed rather than niri's generated HEADLESS-N. Steam remembers its capture
# source by name, and a generated name is sequential: an output removed and
# recreated comes back as HEADLESS-2, HEADLESS-3 and so on, so the remembered
# selection silently stops resolving and the client goes black.
OUTPUT_NAME = os.environ.get("STREAM_MODE_OUTPUT_NAME", "steam")

START_RE = re.compile(r">>> Starting desktop stream")
STOP_RE = re.compile(r">>> Stopped desktop stream")
RES_RE = re.compile(r">>> Capture resolution set to (\d+)x(\d+)")
ADD_WINDOW_RE = re.compile(r"Adding window \d+ \(\d+\) for process (\d+) and gameID (\d+)")
REMOVE_PROC_RE = re.compile(r"Removing process (\d+) for gameID (\d+)")
CONNECT_RE = re.compile(r"Client (\d+) \(([^)]*)\) connected via direct connection")
CREATED_RE = re.compile(r"Created virtual output:\s*(\S+)")


def log(message):
    print(message, flush=True)


# --- niri ------------------------------------------------------------------


def niri_windows():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "windows"], check=True, capture_output=True, text=True
    ).stdout
    return json.loads(raw)


def niri_outputs():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "outputs"], check=True, capture_output=True, text=True
    ).stdout
    return json.loads(raw)


def output_logical_size(name):
    logical = (niri_outputs().get(name) or {}).get("logical") or {}
    width, height = logical.get("width"), logical.get("height")
    if width is None or height is None:
        return None
    return (width, height)


def create_virtual_output(width, height, refresh, name=None):
    """Create a virtual output under a fixed name, returning that name.

    The name is passed rather than read back so it stays stable across
    sessions; niri still reports it, which is what is returned.
    """
    name = name or OUTPUT_NAME
    result = subprocess.run(
        [
            NIRI, "msg", "create-virtual-output",
            "--width", str(width),
            "--height", str(height),
            "--refresh-rate", str(refresh),
            "--name", name,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    match = CREATED_RE.search(result.stdout or "")
    return match.group(1) if match else None


def existing_output_names():
    try:
        return set(niri_outputs().keys())
    except (subprocess.CalledProcessError, ValueError, OSError):
        return set()


def remove_virtual_output(name):
    subprocess.run(
        [NIRI, "msg", "remove-virtual-output", name], check=False
    )


def move_window_to_output(window_id, output):
    subprocess.run(
        [NIRI, "msg", "action", "move-window-to-monitor", output, "--id", str(window_id)],
        check=True,
    )


def fullscreen_window(window_id):
    subprocess.run(
        [NIRI, "msg", "action", "fullscreen-window", "--id", str(window_id)], check=True
    )


def focus_window(window_id):
    subprocess.run(
        [NIRI, "msg", "action", "focus-window", "--id", str(window_id)], check=False
    )


def is_fullscreen(window, output_size):
    """Infer fullscreen by geometry.

    niri exposes no fullscreen flag on windows and offers only a *toggle*
    action, so a blind toggle would un-fullscreen a game that already is.
    """
    if output_size is None:
        return False
    size = (window.get("layout") or {}).get("window_size")
    if not size or len(size) != 2:
        return False
    return int(size[0]) == int(output_size[0]) and int(size[1]) == int(output_size[1])


def parent_pids(pid, limit=8):
    """Walk up the process tree, nearest ancestor first.

    A game's own pid often owns no niri window: under gamescope or
    pressure-vessel the window belongs to an ancestor.
    """
    chain = []
    current = pid
    for _ in range(limit):
        try:
            with open("/proc/{}/stat".format(current)) as fh:
                # comm can contain spaces and parentheses; ppid follows the
                # last ')'.
                fields = fh.read().rpartition(")")[2].split()
            current = int(fields[1])
        except (OSError, ValueError, IndexError):
            break
        if current <= 1:
            break
        chain.append(current)
    return chain


def window_for_game(pid, game_id, windows=None):
    """Find the niri window for a streamed game.

    Steam reports a pid, but which process owns the window varies by how the
    game runs, and a pid match alone is not enough:

    - X11 titles reach niri through xwayland-satellite, whose process owns the
      window. That pid is neither the game's nor an ancestor of it, so a pid
      walk finds nothing. These carry `steam_app_<id>` as their app id, which
      is the game id Steam already logged.
    - gamescope owns its own window and is usually an *ancestor* of the game.
    - a game that launches gamescope itself owns a *descendant* window.

    So app id is tried first as the most direct evidence, then pid in both
    directions.
    """
    if windows is None:
        windows = niri_windows()

    wanted_app_id = "steam_app_{}".format(game_id)
    for window in windows:
        if (window.get("app_id") or "") == wanted_app_id:
            return window

    by_pid = {}
    for window in windows:
        if window.get("pid") is not None:
            by_pid.setdefault(window["pid"], window)

    if pid in by_pid:
        return by_pid[pid]

    for ancestor in parent_pids(pid):
        if ancestor in by_pid:
            return by_pid[ancestor]

    # The window may belong to a descendant instead — a game that spawns
    # gamescope rather than running under one.
    for window_pid, window in by_pid.items():
        if pid in parent_pids(window_pid):
            return window

    return None


# --- learned client resolutions --------------------------------------------


def load_clients(path=None):
    try:
        with open(path or STATE) as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_clients(clients, path=None):
    path = path or STATE
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            json.dump(clients, fh, indent=1)
            fh.write("\n")
    except OSError as exc:
        log("stream-mode: could not persist client sizes: {}".format(exc))


def client_size(client_id, clients):
    """Resolution to build the output at, defaulting until one is learned."""
    entry = clients.get(str(client_id))
    if isinstance(entry, list) and len(entry) == 2:
        return int(entry[0]), int(entry[1])
    return DEFAULT_WIDTH, DEFAULT_HEIGHT


# --- session ----------------------------------------------------------------


class Session:
    """Owns the virtual output and what sits on it, for one client at a time."""

    def __init__(self, stage_timeout=None):
        self.output = None
        self.client_id = None
        self.game_pid = None
        self.pending = None
        self.reported_wait = False
        self.learned = False
        self.clients = load_clients()
        self.stage_timeout = STAGE_TIMEOUT if stage_timeout is None else stage_timeout

    # -- lifecycle

    def ensure_output(self, width=None, height=None):
        """Make sure the virtual output exists, adopting one already present.

        Called at startup as well as on connect, because the output must
        outlive this process: Steam remembers its capture source and resolves
        it when a session starts, so an output that disappears — including
        across a service restart — leaves that request failing.
        """
        if self.output is not None:
            return False

        if OUTPUT_NAME in existing_output_names():
            self.output = OUTPUT_NAME
            log("stream-mode: adopted the existing {} output".format(OUTPUT_NAME))
            return False

        if width is None or height is None:
            width, height = client_size(self.client_id, self.clients)

        try:
            name = create_virtual_output(width, height, DEFAULT_REFRESH)
        except (subprocess.CalledProcessError, OSError) as exc:
            log("stream-mode: could not create a virtual output: {}".format(exc))
            return False
        if name is None:
            log("stream-mode: niri did not report a virtual output name")
            return False

        self.output = name
        log("stream-mode: created {} at {}x{}".format(name, width, height))
        return True

    def connect(self, client_id, client_name):
        self.client_id = client_id
        self.learned = False
        width, height = client_size(client_id, self.clients)

        # Resize by replacing, but only if the client actually needs a
        # different size — recreating it otherwise would invalidate the
        # capture source Steam has remembered.
        if self.output is not None:
            current = output_logical_size(self.output)
            if current is not None and current != (width, height):
                log(
                    "stream-mode: {} is {}x{}, client wants {}x{}; rebuilding".format(
                        self.output, current[0], current[1], width, height
                    )
                )
                remove_virtual_output(self.output)
                self.output = None

        created = self.ensure_output(width, height)
        log("stream-mode: {} connected".format(client_name or client_id))
        return created

    def teardown(self):
        """Remove the output. Only on shutdown — see `idle`."""
        if self.output is None:
            return False
        name, self.output = self.output, None
        self.game_pid = None
        remove_virtual_output(name)
        log("stream-mode: removed {}".format(name))
        return True

    def idle(self):
        """Called when streaming has been idle; deliberately keeps the output.

        Removing it between sessions is what broke streaming: Steam remembers
        its capture source and resolves it when the next session starts, so an
        output that came and went leaves the request failing. Steam issues that
        request on its main loop, so the failure stalled the loop past its
        15-second watchdog and the client segfaulted in libtier0.

        The output is cheap to leave in place and its name is fixed, so it
        stays for the lifetime of the service.
        """
        self.game_pid = None
        return False

    # -- learning

    def learn(self, width, height):
        """Record the resolution the client asked for, once per session.

        Steam re-logs the capture resolution after negotiation with a derived
        value, so only the first of a session is the client's own.
        """
        if self.learned or self.client_id is None:
            return False
        self.learned = True
        key = str(self.client_id)
        if self.clients.get(key) == [width, height]:
            return False
        self.clients[key] = [width, height]
        save_clients(self.clients)
        log(
            "stream-mode: learned {}x{} for client {}; used from next connect".format(
                width, height, self.client_id
            )
        )
        return True

    # -- placing the game

    def request(self, pid, game_id):
        """Note that a game is starting; its window is resolved later.

        Steam logs the pid as soon as it spawns the game, long before a window
        exists. Waiting here would block the watcher — it follows two logs and
        has an idle timer to service — so the work is left pending and retried
        from the main loop.
        """
        if self.output is None:
            # A game can start before any connect is seen — a client that
            # connected while this was not running, for instance.
            self.ensure_output()
        if self.output is None:
            log("stream-mode: no virtual output, cannot stage game {}".format(game_id))
            return False
        self.pending = (pid, game_id, time.monotonic() + self.stage_timeout)
        self.reported_wait = False
        log(
            "stream-mode: game {} starting (pid {}), waiting for its window".format(
                game_id, pid
            )
        )
        return True

    def poll(self):
        """Try to place a pending game. Called from the watcher loop."""
        if self.pending is None:
            return False

        pid, game_id, deadline = self.pending

        try:
            windows = niri_windows()
            window = window_for_game(pid, game_id, windows)
        except (subprocess.CalledProcessError, ValueError, OSError) as exc:
            log("stream-mode: could not query niri windows: {}".format(exc))
            return False

        if window is None:
            if time.monotonic() < deadline:
                # Say once what is actually on screen. Staying silent until the
                # deadline hid three separate faults behind "nothing happened".
                if not self.reported_wait:
                    self.reported_wait = True
                    seen = [
                        "{}({})".format(w.get("app_id") or "?", w.get("pid"))
                        for w in windows
                    ]
                    log(
                        "stream-mode: no window for steam_app_{} yet; "
                        "windows are: {}".format(game_id, ", ".join(seen) or "none")
                    )
                return False
            self.pending = None
            seen = ["{}({})".format(w.get("app_id") or "?", w.get("pid")) for w in windows]
            log(
                "stream-mode: gave up on pid {} / steam_app_{} after {:.0f}s; "
                "windows were: {}".format(
                    pid, game_id, self.stage_timeout, ", ".join(seen) or "none"
                )
            )
            return False

        self.pending = None
        self.reported_wait = False
        self.game_pid = pid
        try:
            move_window_to_output(window["id"], self.output)
        except (subprocess.CalledProcessError, OSError) as exc:
            log("stream-mode: could not move window: {}".format(exc))
            return False
        focus_window(window["id"])
        self._ensure_fullscreen(window["id"])
        log(
            "stream-mode: staged {} (window {}, pid {}, game {}) on {}".format(
                window.get("app_id") or "game", window["id"], pid, game_id, self.output
            )
        )
        return True

    def _ensure_fullscreen(self, window_id):
        try:
            output_size = output_logical_size(self.output)
            window = next(
                (w for w in niri_windows() if w.get("id") == window_id), None
            )
        except (subprocess.CalledProcessError, ValueError, OSError):
            return
        if window is None or is_fullscreen(window, output_size):
            return
        try:
            fullscreen_window(window_id)
        except (subprocess.CalledProcessError, OSError) as exc:
            log("stream-mode: could not fullscreen window: {}".format(exc))

    def unstage(self, pid=None):
        if self.game_pid is None:
            return False
        if pid is not None and pid != self.game_pid:
            return False
        self.game_pid = None
        return True


# --- log following ----------------------------------------------------------


def follow(path, seek_to_end=True, idle_yield=False):
    """Yield lines appended to path, surviving truncation and replacement.

    Steam truncates these logs on client restart, so a plain read loop silently
    goes deaf.

    seek_to_end skips whatever the file already holds, which is what a watcher
    wants on startup: a past session's lines must not be replayed as if live.

    idle_yield emits None whenever a poll finds nothing, so a caller with a
    deadline to honour is not blocked until the next line arrives.
    """
    handle = None
    inode = None
    pending = b""
    # Only the very first open honours seek_to_end. A later reopen means the
    # file was truncated or replaced, and the lines that triggered it are
    # exactly the ones worth reading.
    #
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
                if idle_yield:
                    yield None
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
            if idle_yield:
                yield None


def watch():
    session = Session()

    def bail(_signum, _frame):
        # Deliberately does not remove the output: it has to survive a service
        # restart, or Steam's remembered capture source stops resolving.
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGINT, bail)

    log("stream-mode: watching {} and {}".format(CONNECTIONS_LOG, LOG))
    # Before any client connects: the output must exist for Steam to resolve a
    # remembered capture source, and a client that connected while this was
    # not running would otherwise never trigger its creation.
    session.ensure_output()
    streaming = follow(LOG, idle_yield=True)
    connections = follow(CONNECTIONS_LOG, idle_yield=True)
    remove_at = None

    try:
        while True:
            now = time.monotonic()

            line = next(connections)
            if line is not None:
                match = CONNECT_RE.search(line)
                if match:
                    remove_at = None
                    session.connect(int(match.group(1)), match.group(2))

            line = next(streaming)
            if line is not None:
                match = ADD_WINDOW_RE.search(line)
                if match:
                    remove_at = None
                    session.request(int(match.group(1)), int(match.group(2)))
                    continue

                match = RES_RE.search(line)
                if match:
                    session.learn(int(match.group(1)), int(match.group(2)))
                    continue

                match = REMOVE_PROC_RE.search(line)
                if match:
                    session.unstage(int(match.group(1)))
                    continue

                if START_RE.search(line):
                    remove_at = None
                elif STOP_RE.search(line):
                    remove_at = now + REMOVE_AFTER

            session.poll()

            if remove_at is not None and time.monotonic() >= remove_at:
                remove_at = None
                session.idle()
    finally:
        # The output is left in place on purpose; see bail().
        pass


def main(argv):
    if len(argv) >= 2 and argv[1] == "watch":
        watch()
        return 0

    if len(argv) >= 2 and argv[1] == "create":
        width = int(argv[2]) if len(argv) > 2 else DEFAULT_WIDTH
        height = int(argv[3]) if len(argv) > 3 else DEFAULT_HEIGHT
        if OUTPUT_NAME in existing_output_names():
            remove_virtual_output(OUTPUT_NAME)
        name = create_virtual_output(width, height, DEFAULT_REFRESH)
        print(name or "")
        return 0 if name else 1

    if len(argv) == 3 and argv[1] == "remove":
        remove_virtual_output(argv[2])
        return 0

    if len(argv) == 2 and argv[1] == "status":
        outputs = niri_outputs()
        for name, out in outputs.items():
            logical = out.get("logical") or {}
            print(
                "{}: {}x{} ({})".format(
                    name, logical.get("width"), logical.get("height"), out.get("make")
                )
            )
        print("learned clients: {}".format(load_clients()))
        return 0

    print(
        "usage: stream-mode [watch|create [W H]|remove NAME|status]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

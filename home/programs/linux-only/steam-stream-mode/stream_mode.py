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
import select
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
# Published while a client is streaming, and removed when it stops. Read by
# the steam-display-filter LD_PRELOAD shim, which reports this size to Steam as
# the whole desktop: Steam sizes its capture from its own idea of the desktop
# rather than from the stream the portal gave it, so on a wider monitor the
# client otherwise receives the desktop's shape letterboxed into its frame.
# One line, "WIDTHxHEIGHT" -- the filter hooks SDL, which has no notion of the
# compositor's output names, so the size is all it can use. Absence means "not
# streaming", which is what leaves desktop play untouched.
TARGET_FILE = os.environ.get(
    "STREAM_MODE_TARGET_FILE",
    os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "stream-mode", "target"
    ),
)

START_RE = re.compile(r">>> Starting desktop stream")
STOP_RE = re.compile(r">>> Stopped desktop stream")
# The client's own panel, relayed into the host's log by the client.
#
# This, rather than Steam's ">>> Capture resolution set to WxH": while the
# display filter is armed the capture resolution is the size we told Steam, so
# learning from it would only ever confirm our own default back to us and a
# client with a different panel would never be sized correctly. "output size"
# comes from the client and is unaffected -- it stays at the client's panel
# even in logs where the video size had been fitted to the wrong desktop.
CLIENT_SIZE_RE = re.compile(
    r"CLIENT: Video size: \d+x\d+, output size: (\d+)x(\d+)"
)
ADD_WINDOW_RE = re.compile(r"Adding window \d+ \(\d+\) for process (\d+) and gameID (\d+)")
REMOVE_PROC_RE = re.compile(r"Removing process (\d+) for gameID (\d+)")
CONNECT_RE = re.compile(r"Client (\d+) \(([^)]*)\) connected via direct connection")
# Clients that do not announce themselves the Deck's way.
#
# The Android client never logs "connected via direct connection": it
# authorises by device ID and then sends a streaming request. Matching only the
# Deck's phrasing left such a client unidentified, so nothing was ever learned
# for it and it stayed on the default size permanently — which is what a
# television did on its first connect.
STREAM_REQUEST_RE = re.compile(r"Received streaming request \d+ with device ID (\d+)")


def log(message):
    print(message, flush=True)



# --- niri ------------------------------------------------------------------


def live_niri_socket():
    """Find the socket of a niri that is actually running.

    NIRI_SOCKET is inherited from whenever this service was started, so after
    a logout it names a compositor that no longer exists — every call then
    fails against a dead socket while a live niri sits alongside it. That cost
    a long debugging session, with the service and a shell talking to two
    different compositors and disagreeing about which outputs existed.

    niri names its socket after the session and its own pid, so a live one can
    be identified without trusting the environment.
    """
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        return None

    best = None
    try:
        entries = os.listdir(runtime_dir)
    except OSError:
        return None

    for entry in entries:
        if not (entry.startswith("niri.") and entry.endswith(".sock")):
            continue
        # niri.<display>.<pid>.sock
        parts = entry[:-len(".sock")].split(".")
        if len(parts) < 3:
            continue
        try:
            pid = int(parts[-1])
        except ValueError:
            continue
        try:
            os.kill(pid, 0)
        except (ProcessLookupError, PermissionError, OSError):
            if not isinstance(sys.exc_info()[1], PermissionError):
                continue
        path = os.path.join(runtime_dir, entry)
        if best is None or pid > best[0]:
            best = (pid, path)

    return best[1] if best else None


def niri_env():
    """Environment for a niri call, with a socket known to be live."""
    env = dict(os.environ)
    socket = env.get("NIRI_SOCKET")
    if socket and os.path.exists(socket):
        return env
    live = live_niri_socket()
    if live:
        if socket != live:
            log("stream-mode: niri socket moved to {}".format(live))
        env["NIRI_SOCKET"] = live
    return env


def niri_windows():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "windows"],
        check=True, capture_output=True, text=True, env=niri_env(),
    ).stdout
    return json.loads(raw)


def niri_outputs():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "outputs"],
        check=True, capture_output=True, text=True, env=niri_env(),
    ).stdout
    return json.loads(raw)


def output_logical_size(name):
    logical = (niri_outputs().get(name) or {}).get("logical") or {}
    width, height = logical.get("width"), logical.get("height")
    if width is None or height is None:
        return None
    return (width, height)


def set_output_mode(name, width, height, refresh):
    """Resize the virtual output to a client's panel.

    Resizing rather than replacing: Steam remembers its capture source and
    resolves it when a session starts, so an output that came and went leaves
    that request failing — which stalled Steam's main loop past its 15-second
    watchdog and segfaulted the client.
    """
    result = subprocess.run(
        [NIRI, "msg", "output", name, "mode", "{}x{}@{}".format(width, height, refresh)],
        check=False, capture_output=True, text=True, env=niri_env(),
    )
    if result.returncode != 0:
        log(
            "stream-mode: could not set {} to {}x{}@{}: {}".format(
                name, width, height, refresh, (result.stderr or "").strip()
            )
        )
        return False
    return True


def set_output_enabled(name, enabled):
    """Take the virtual output in or out of the layout.

    Off between sessions on purpose: an idle output still accepts windows, and
    is where niri puts the workspaces when the physical output goes away — a
    KVM switching machines, a monitor sleeping — which emptied the desktop
    onto it. It stays declared and listed either way, so Steam's remembered
    capture source keeps resolving.
    """
    result = subprocess.run(
        [NIRI, "msg", "output", name, "on" if enabled else "off"],
        check=False, capture_output=True, text=True, env=niri_env(),
    )
    if result.returncode != 0:
        log(
            "stream-mode: could not turn {} {}: {}".format(
                name, "on" if enabled else "off", (result.stderr or "").strip()
            )
        )
        return False
    return True


def publish_target(output, width, height, refresh=None):
    """Announce the size the display filter should report to Steam.

    Plain "WIDTHxHEIGHT" rather than JSON. The filter needs the streamed size
    and nothing else -- it stopped matching outputs by name once the only thing
    it hooks became SDL, which has no notion of the compositor's output names.
    Keeping the format to one line also means anyone can drive the filter from
    another compositor by hand, with STEAM_STREAM_SIZE=1280x800 and no watcher
    at all. The output name and refresh stay in the log line, where they help a
    person reading it, rather than in a format the filter has to parse.
    """
    try:
        os.makedirs(os.path.dirname(TARGET_FILE), exist_ok=True)
        # Written whole then renamed: the shim reads this from a game launch
        # that can happen at any moment, and must never see a half-written file.
        tmp = TARGET_FILE + ".new"
        with open(tmp, "w") as fh:
            fh.write("{}x{}\n".format(width, height))
        os.replace(tmp, TARGET_FILE)
    except OSError as exc:
        log("stream-mode: could not publish the stream target: {}".format(exc))
        return False
    log("stream-mode: published target {} {}x{}".format(output, width, height))
    return True


def withdraw_target():
    try:
        os.remove(TARGET_FILE)
    except FileNotFoundError:
        return False
    except OSError as exc:
        log("stream-mode: could not withdraw the stream target: {}".format(exc))
        return False
    log("stream-mode: withdrew the stream target")
    return True


def niri_workspaces():
    raw = subprocess.run(
        [NIRI, "msg", "--json", "workspaces"],
        check=True, capture_output=True, text=True, env=niri_env(),
    ).stdout
    return json.loads(raw)


def usable_output_names():
    """Outputs niri lists — the ones that actually work.

    A virtual output that has been through a physical output's disconnect
    survives as a name but comes back permanently not connected: absent from
    this list, impossible to enable, and only recoverable by removing and
    making it again.
    """
    try:
        return set(niri_outputs().keys())
    except (subprocess.CalledProcessError, ValueError, OSError):
        return set()


def taken_output_names():
    """Names niri will refuse to create, whether or not they work.

    A stuck output still holds its name, and the workspaces sitting on it
    still report it, so this is wider than the usable set. Keeping the two
    apart matters: the usable set decides whether to adopt, this one decides
    whether creating would collide.
    """
    names = usable_output_names()
    try:
        names |= {w.get("output") for w in niri_workspaces() if w.get("output")}
    except (subprocess.CalledProcessError, ValueError, OSError):
        pass
    return names


def move_window_to_output(window_id, output):
    subprocess.run(
        [NIRI, "msg", "action", "move-window-to-monitor", output, "--id", str(window_id)],
        check=True,
        env=niri_env(),
    )


def fullscreen_window(window_id):
    subprocess.run(
        [NIRI, "msg", "action", "fullscreen-window", "--id", str(window_id)],
        check=True, env=niri_env(),
    )


def focus_window(window_id):
    subprocess.run(
        [NIRI, "msg", "action", "focus-window", "--id", str(window_id)],
        check=False, env=niri_env(),
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
        self.streaming = False
        self.game_pid = None
        self.pending = None
        self.reported_wait = False
        self.last_windows = []
        self.learned = False
        # Reset per session: a new client gets its own Big Picture placement,
        # and the user is free to move it afterwards without it snapping back.
        self.big_picture_placed = False
        self.clients = load_clients()
        self.stage_timeout = STAGE_TIMEOUT if stage_timeout is None else stage_timeout

    # -- lifecycle

    def ensure_output(self, width=None, height=None):
        """Find the declared virtual output. It is not created here.

        The output is declared in niri's config
        (custom.niri.virtualOutputs), so it exists from the moment the
        compositor starts and outlives this service. That is what Steam needs:
        it remembers its capture source and resolves it when a session starts,
        so an output that only appears once a client connects is one Steam can
        fail to find.
        """
        if self.output is not None:
            return False

        if OUTPUT_NAME not in usable_output_names():
            log(
                "stream-mode: no {} output; niri lists {}. Declare it with "
                "custom.niri.virtualOutputs and check niri has virtual output "
                "support.".format(OUTPUT_NAME, sorted(usable_output_names()) or "nothing")
            )
            return False

        self.output = OUTPUT_NAME
        return True

    def connect(self, client_id, client_name):
        """A client has connected: size the output for it and turn it on."""
        self.client_id = client_id
        self.learned = False
        self.big_picture_placed = False
        width, height = client_size(client_id, self.clients)

        self.ensure_output()
        if self.output is None:
            log(
                "stream-mode: {} connected but there is no output to give it".format(
                    client_name or client_id
                )
            )
            return False

        # Resize only when the client actually needs a different size, so a
        # reconnect from the same client does not disturb the layout.
        current = output_logical_size(self.output)
        if current != (width, height):
            set_output_mode(self.output, width, height, DEFAULT_REFRESH)

        # Published before the output is enabled, not after. Steam re-reads the
        # monitor list when the X server reports outputs changing, and enabling
        # this one is that change; the display filter reads this file on every
        # such query and does nothing while it is absent. Publishing afterwards
        # would arm the filter just too late to affect the read it was meant
        # for, leaving Steam sized to the desktop monitor for the session.
        publish_target(self.output, width, height, DEFAULT_REFRESH)
        set_output_enabled(self.output, True)
        log(
            "stream-mode: {} connected; {} on at {}x{}".format(
                client_name or client_id, self.output, width, height
            )
        )
        return True

    def teardown(self):
        """Turn the output off. Only on shutdown — see `idle`."""
        if self.output is None:
            return False
        name, self.output = self.output, None
        self.game_pid = None
        set_output_enabled(name, False)
        log("stream-mode: turned {} off".format(name))
        return True

    def begin_stream(self):
        """A stream has started: say where to render."""
        self.streaming = True
        if self.output is None:
            self.ensure_output()
        if self.output is None:
            return False
        # On already if a client connected first, but a stream can also be the
        # first thing seen — after a service restart mid-session, say.
        set_output_enabled(self.output, True)

        # The client we are serving decides the size, in preference to whatever
        # mode the output was last left in. A stream can start without a fresh
        # connect line, and the output keeps its previous mode — set for an
        # earlier client, or by hand at the command line. Preferring the
        # output's own size meant a Deck streamed at 1600x900 simply because
        # that is what the output happened to be at the time.
        if self.client_id is not None:
            width, height = client_size(self.client_id, self.clients)
        else:
            size = output_logical_size(self.output) or (DEFAULT_WIDTH, DEFAULT_HEIGHT)
            width, height = size

        published = publish_target(self.output, width, height, DEFAULT_REFRESH)
        if output_logical_size(self.output) != (width, height):
            set_output_mode(self.output, width, height, DEFAULT_REFRESH)
        if not published:
            log("stream-mode: WARNING games will launch at the desktop's size")
        return published

    def end_stream(self):
        """Streaming has stopped: stop redirecting launches, park the output.

        Turned off rather than removed. The output is declared in niri's
        config, so removing it is not ours to do — and Steam remembers its
        capture source and resolves it when the next session starts, so an
        output that came and went left that request failing, stalling Steam's
        main loop past its 15-second watchdog into a segfault in libtier0.

        Off is not merely cosmetic: an enabled output still accepts windows,
        and niri moves workspaces onto it when the physical output goes away,
        which is what emptied the desktop onto it during a KVM switch.
        """
        self.streaming = False

        # Off first, target withdrawn second -- the reverse of connect, and for
        # the same reason. Between the two there is a state where the output
        # exists and the filter is inert, and Steam re-reads the monitor list
        # whenever outputs change. Withdrawing first left that window open
        # until the next client arrived: Steam recomputed its desktop as the
        # union of both monitors, cached it, and sized the next stream to the
        # 6400x1440 it had learned while unfiltered.
        #
        # The name falls back to the configured one rather than trusting
        # self.output. A disconnect that arrives when it is already None -- a
        # second notification, or a restart mid-session -- would otherwise skip
        # turning the output off entirely and leave it on indefinitely, which
        # is exactly the state that produced the wrong aspect above.
        name = self.output if self.output is not None else OUTPUT_NAME
        self.output = None
        set_output_enabled(name, False)
        withdraw_target()
        log("stream-mode: turned {} off until the next client".format(name))
        return True

    def idle(self):
        """Called when streaming has been idle; the output stays declared.

        Nothing to do here now that the output is config-declared: it is
        turned off when a stream ends, and it is never removed, so Steam's
        remembered capture source keeps resolving between sessions.
        """
        self.game_pid = None
        return False

    # -- learning

    def learn(self, width, height):
        """Record the client's panel, and use it for this session too.

        Once per session: the client reports its size repeatedly while
        streaming and there is nothing to gain from acting on every one.

        Applied immediately rather than only remembered. A client connecting
        for the first time has nothing to size the output from, so it gets the
        default; leaving the correction until the next connect would let that
        whole first session run letterboxed, which is the thing this service
        exists to prevent. Republished before the resize for the reason connect
        does the same: the resize is the display change Steam re-reads on, and
        the filter has to already be reporting the new size when it does.
        """
        if self.learned or self.client_id is None:
            return False
        self.learned = True
        key = str(self.client_id)
        known = self.clients.get(key) == [width, height]
        if not known:
            self.clients[key] = [width, height]
            save_clients(self.clients)
            log(
                "stream-mode: learned {}x{} for client {}".format(
                    width, height, self.client_id
                )
            )

        if self.output is None:
            return not known
        if output_logical_size(self.output) == (width, height):
            return not known

        publish_target(self.output, width, height, DEFAULT_REFRESH)
        set_output_mode(self.output, width, height, DEFAULT_REFRESH)
        log(
            "stream-mode: resized {} to {}x{} for this session".format(
                self.output, width, height
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
            "stream-mode: game {} starting (pid {}); will move it to {} when its "
            "window appears".format(game_id, pid, self.output)
        )
        return True

    def place_big_picture(self, windows):
        """Put Steam's own Big Picture window on the streamed output.

        Only game windows were staged, because the Deck launches straight into
        one. A phone or a television streams the Steam UI itself, and Big
        Picture opened on the desktop monitor instead — so the client watched
        whatever happened to be behind it.

        Moved once per session rather than on every window event: niri emits
        the list on any change, and re-issuing the move each time would fight
        the user dragging it somewhere else.
        """
        if not self.streaming or self.output is None or self.big_picture_placed:
            return False

        for w in windows:
            if (w.get("app_id") or "") != "steam":
                continue
            if "Big Picture" not in (w.get("title") or ""):
                continue
            self.big_picture_placed = True
            try:
                move_window_to_output(w["id"], self.output)
            except (subprocess.CalledProcessError, OSError) as exc:
                log("stream-mode: could not move Big Picture: {}".format(exc))
                return False
            log("stream-mode: moved Big Picture to {}".format(self.output))
            return True
        return False

    def on_windows(self, windows):
        """React to niri's window list changing.

        Fed by the compositor's event stream rather than polled: the previous
        design re-listed windows several times a second and still had to guess
        a deadline, because a game's window can appear minutes after Steam
        reports its pid.
        """
        self.place_big_picture(windows)

        if self.pending is None:
            return False

        pid, game_id, deadline = self.pending

        window = window_for_game(pid, game_id, windows)
        if window is None:
            if time.monotonic() >= deadline:
                self.pending = None
                seen = [
                    "{}({})".format(w.get("app_id") or "?", w.get("pid")) for w in windows
                ]
                log(
                    "stream-mode: gave up on pid {} / steam_app_{} after {:.0f}s; "
                    "windows were: {}".format(
                        pid, game_id, self.stage_timeout, ", ".join(seen) or "none"
                    )
                )
            elif not self.reported_wait:
                self.reported_wait = True
                seen = [
                    "{}({})".format(w.get("app_id") or "?", w.get("pid")) for w in windows
                ]
                log(
                    "stream-mode: no window for steam_app_{} yet; windows are: {}".format(
                        game_id, ", ".join(seen) or "none"
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

    def on_outputs_changed(self, output_names):
        """React to the set of outputs changing.

        Replaces a ten-second watchdog: the compositor says when an output
        appears or disappears, so there is nothing to poll for.
        """
        if self.output is None or self.output in output_names:
            return False
        log("stream-mode: {} has gone away, rebuilding".format(self.output))
        self.output = None
        return self.ensure_output()

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
        log("stream-mode: staged game (pid {}) exited".format(self.game_pid))
        self.game_pid = None
        return True


# --- log following ----------------------------------------------------------


def spawn_tail(path):
    """Follow a log without polling.

    `tail -F` waits on the kernel rather than re-reading, and handles the
    truncation and replacement Steam does to these files when its client
    restarts.
    """
    return subprocess.Popen(
        ["tail", "-n", "0", "-F", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )


def spawn_event_stream():
    """Subscribe to niri's compositor events.

    The compositor reports window and workspace changes as they happen, which
    is what staging and output tracking need — previously both were polled,
    which raced asynchronous creation and rebuilt outputs that already existed.
    """
    return subprocess.Popen(
        [NIRI, "msg", "--json", "event-stream"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
        env=niri_env(),
    )


def outputs_from_workspaces(workspaces):
    return {w.get("output") for w in workspaces if w.get("output")}


def stream_in_progress(path=None):
    """Is a stream running right now, judged from the log's last marker?

    The start marker may already have passed when this service starts — a
    restart mid-stream, which happens often while iterating — and nothing
    would then publish a target until the next stream began.
    """
    path = path or LOG
    try:
        with open(path, "rb") as fh:
            # The markers are rare; the tail is enough and the file is large.
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - 200_000))
            tail = fh.read().decode("utf-8", "replace")
    except OSError:
        return False

    last = None
    for line in tail.splitlines():
        if START_RE.search(line):
            last = True
        elif STOP_RE.search(line):
            last = False
    return last is True


def watch():
    session = Session()

    def bail(_signum, _frame):
        withdraw_target()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGINT, bail)

    session.ensure_output()
    withdraw_target()
    if stream_in_progress():
        log("stream-mode: a stream is already in progress")
        session.begin_stream()

    log(
        "stream-mode: state — output={} streaming={} target={}".format(
            session.output or "<none>",
            session.streaming,
            "published" if os.path.exists(TARGET_FILE) else "absent",
        )
    )

    procs = {
        "events": spawn_event_stream(),
        "stream": spawn_tail(LOG),
        "clients": spawn_tail(CONNECTIONS_LOG),
    }
    log(
        "stream-mode: watching niri events, {} and {}".format(
            os.path.basename(LOG), os.path.basename(CONNECTIONS_LOG)
        )
    )

    # Only source of periodic work left: the delay before dropping the output
    # once streaming stops, and the deadline for a game that never appears.
    remove_at = None

    try:
        while True:
            readable = {p.stdout for p in procs.values() if p.stdout}
            timeout = 1.0 if (remove_at or session.pending) else 30.0
            ready, _, _ = select.select(list(readable), [], [], timeout)

            for name, proc in list(procs.items()):
                if proc.poll() is not None:
                    log("stream-mode: {} reader exited, restarting it".format(name))
                    procs[name] = (
                        spawn_event_stream() if name == "events"
                        else spawn_tail(LOG if name == "stream" else CONNECTIONS_LOG)
                    )

            for handle in ready:
                line = handle.readline()
                if not line:
                    continue

                if procs["events"].stdout is handle:
                    handle_niri_event(session, line)
                elif procs["clients"].stdout is handle:
                    match = CONNECT_RE.search(line)
                    if match:
                        remove_at = None
                        session.connect(int(match.group(1)), match.group(2))
                    else:
                        match = STREAM_REQUEST_RE.search(line)
                        # Only when it names a client we are not already
                        # serving: this line repeats through a session, and
                        # reconnecting the current client must not restart it.
                        if match and int(match.group(1)) != session.client_id:
                            remove_at = None
                            session.connect(int(match.group(1)), "device")
                else:
                    remove_at = handle_steam_line(session, line, remove_at)

            now = time.monotonic()
            if session.pending and now >= session.pending[2]:
                # Let the deadline be reported even if no window event arrives.
                session.on_windows(session.last_windows)
            if remove_at is not None and now >= remove_at:
                remove_at = None
                session.end_stream()
    finally:
        for proc in procs.values():
            proc.terminate()
        withdraw_target()


def handle_steam_line(session, line, remove_at):
    """Act on one line of Steam's streaming log. Returns the new remove_at."""
    match = ADD_WINDOW_RE.search(line)
    if match:
        session.request(int(match.group(1)), int(match.group(2)))
        session.on_windows(session.last_windows)
        return None

    match = CLIENT_SIZE_RE.search(line)
    if match:
        session.learn(int(match.group(1)), int(match.group(2)))
        return remove_at

    match = REMOVE_PROC_RE.search(line)
    if match:
        session.unstage(int(match.group(1)))
        return remove_at

    if START_RE.search(line):
        log("stream-mode: stream started")
        session.begin_stream()
        return None

    if STOP_RE.search(line):
        log("stream-mode: stream stopped, dropping the output in {:.0f}s".format(
            REMOVE_AFTER
        ))
        return time.monotonic() + REMOVE_AFTER

    return remove_at


def handle_niri_event(session, line):
    """Act on one compositor event."""
    try:
        event = json.loads(line)
    except ValueError:
        return

    if "WindowsChanged" in event:
        session.last_windows = event["WindowsChanged"].get("windows") or []
        session.on_windows(session.last_windows)
        return

    if "WindowOpenedOrChanged" in event:
        window = event["WindowOpenedOrChanged"].get("window")
        if window:
            session.last_windows = [
                w for w in session.last_windows if w.get("id") != window.get("id")
            ] + [window]
            log(
                "stream-mode: window {} appeared ({}, pid {})".format(
                    window.get("id"), window.get("app_id") or "?", window.get("pid")
                )
            )
            session.on_windows(session.last_windows)
        return

    if "WindowClosed" in event:
        closed = event["WindowClosed"].get("id")
        session.last_windows = [
            w for w in session.last_windows if w.get("id") != closed
        ]
        return

    if "WorkspacesChanged" in event:
        outputs = outputs_from_workspaces(event["WorkspacesChanged"].get("workspaces") or [])
        session.on_outputs_changed(outputs)
        return


def main(argv):
    if len(argv) >= 2 and argv[1] == "watch":
        watch()
        return 0

    # `on` and `off` rather than `create` and `remove`: the output is declared
    # in niri's config and is not this program's to create or destroy.
    if len(argv) >= 2 and argv[1] == "on":
        width = int(argv[2]) if len(argv) > 2 else DEFAULT_WIDTH
        height = int(argv[3]) if len(argv) > 3 else DEFAULT_HEIGHT
        if OUTPUT_NAME not in usable_output_names():
            print("no {} output declared".format(OUTPUT_NAME), file=sys.stderr)
            return 1
        set_output_mode(OUTPUT_NAME, width, height, DEFAULT_REFRESH)
        return 0 if set_output_enabled(OUTPUT_NAME, True) else 1

    if len(argv) >= 2 and argv[1] == "off":
        name = argv[2] if len(argv) > 2 else OUTPUT_NAME
        return 0 if set_output_enabled(name, False) else 1

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

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
# How often to check that Steam still exists while a game is staged. Steam
# dying is silent from here -- its logs simply stop -- so there is nothing to
# react to and it has to be looked for. Slow on purpose: a game outliving Steam
# by a few seconds costs nothing, and the check reads every process's name.
STEAM_CHECK_INTERVAL = float(os.environ.get("STREAM_MODE_STEAM_CHECK_INTERVAL", "10"))
# How long to wait before restarting a reader that has exited, and the ceiling
# that wait grows to. A compositor restart takes the event stream with it and
# every immediate respawn dies at once: 587 restarts in 45 seconds during one
# relog, which is a busy loop rather than a retry.
READER_BACKOFF_MIN = float(os.environ.get("STREAM_MODE_READER_BACKOFF_MIN", "0.25"))
READER_BACKOFF_MAX = float(os.environ.get("STREAM_MODE_READER_BACKOFF_MAX", "5"))
# When to look again at a window after staging it. A game has been seen on the
# desktop monitor after a staging that reported success, correcting itself only
# when the window was next focused -- so the evidence disappears in the act of
# observing it. These re-read it on a timer instead, spread wide enough to
# catch both a quick correction and a slow one.
# How many times to take focus back for one window. gamescope draws at the
# size it was last activated with, so a game that never gets focus is drawn at
# half the output while niri reports it fullscreen. Bounded so a deliberate
# switch to something else on the desktop is not fought indefinitely.
REFOCUS_LIMIT = int(os.environ.get("STREAM_MODE_REFOCUS_LIMIT", "3"))
# How many times to widen one window. niri opens windows at
# `default-column-width` -- a proportion of the output, 0.5 here -- so a game
# arrives at half the streamed output's width. Capped so a window that cannot
# be widened, such as one with a fixed size, is not fought forever.
WIDEN_LIMIT = int(os.environ.get("STREAM_MODE_WIDEN_LIMIT", "5"))
STAGE_AUDIT_DELAYS = [
    float(v) for v in
    os.environ.get("STREAM_MODE_AUDIT_DELAYS", "1,3,10,30").split(",") if v
]
# Fixed rather than niri's generated HEADLESS-N. Steam remembers its capture
# source by name, and a generated name is sequential: an output removed and
# recreated comes back as HEADLESS-2, HEADLESS-3 and so on, so the remembered
# selection silently stops resolving and the client goes black.
OUTPUT_NAME = os.environ.get("STREAM_MODE_OUTPUT_NAME", "steam")
# The workspace niri's window rules send games to.
#
# Games do not arrive on the streamed output by accident of timing -- they are
# placed by a window rule, `open-on-workspace "game"`, and that workspace lives
# on the desktop monitor. Chasing each window afterwards was a race against the
# compositor's own configuration, and it showed: a game appeared on the desktop
# monitor first, sized as gamescope's 2560 borderless column, and was dragged
# across and resized a moment later.
#
# Moving the workspace instead means the rule and the stream agree rather than
# fight. It also covers every game the rule matches, not only those whose window
# this service manages to identify.
GAME_WORKSPACE = os.environ.get("STREAM_MODE_GAME_WORKSPACE", "game")
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


def steam_is_running():
    """Whether a Steam client process exists.

    Read from /proc rather than shelling out to pgrep: this is checked on a
    timer, and the answer decides whether to kill something.
    """
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(os.path.join("/proc", entry, "comm")) as fh:
                if fh.read().strip() == "steam":
                    return True
        except OSError:
            continue
    return False


def signal_process(pid, sig):
    """Send a signal, treating an already-dead process as success."""
    try:
        os.kill(pid, sig)
    except ProcessLookupError:
        return True
    except OSError as exc:
        log("stream-mode: could not signal {}: {}".format(pid, exc))
        return False
    return True


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


def workspace_output(name):
    """Which output a named workspace currently sits on, if it exists."""
    try:
        for ws in niri_workspaces():
            if ws.get("name") == name:
                return ws.get("output")
    except (subprocess.CalledProcessError, ValueError, OSError) as exc:
        log("stream-mode: could not read workspaces: {}".format(exc))
    return None


def move_workspace_to_output(name, output):
    """Move a named workspace to an output without focusing it.

    --reference names the workspace, so this does not steal focus or disturb
    what is on screen.
    """
    result = subprocess.run(
        [NIRI, "msg", "action", "move-workspace-to-monitor", output,
         "--reference", name],
        capture_output=True, text=True, env=niri_env(),
    )
    if result.returncode != 0:
        log("stream-mode: could not move workspace {} to {}: {}".format(
            name, output, (result.stderr or "").strip()
        ))
        return False
    return True


def window_location(window_id):
    """Where a window is and how big, as one string for the log.

    Which output a window is on is not on the window itself: it is a property
    of its workspace, so it takes both listings to answer. Worth the two calls
    because "it appeared on the wrong monitor and then corrected itself while
    I looked at it" cannot be diagnosed from the staging line alone.
    """
    try:
        windows = niri_windows()
        outputs = {ws.get("id"): ws.get("output") for ws in niri_workspaces()}
    except (subprocess.CalledProcessError, ValueError, OSError) as exc:
        return "unknown ({})".format(exc)

    window = next((w for w in windows if w.get("id") == window_id), None)
    if window is None:
        return "gone"
    size = (window.get("layout") or {}).get("window_size")
    return "output={} size={} focused={}".format(
        outputs.get(window.get("workspace_id")), size, window.get("is_focused")
    )


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


def set_window_fullscreen(window_id, is_fullscreen=True):
    """Put a window in or out of fullscreen, by id.

    Fullscreen rather than a maximised column, which is what this used to do.
    A column is laid out inside the working area, so anything reserving an
    exclusive zone on the streamed output takes its space: the desktop bar
    reserved 34px, and a client asking for 1280x800 received 1280x766 of game
    with a status bar above it. Fullscreen ignores struts, gaps and borders,
    so it covers the output without dictating what may run on the desktop.

    `set-window-fullscreen` says what the state should be rather than flipping
    it, so this is idempotent and needs no reading of the current state -- the
    IPC exposes none, and inferring it from geometry once turned an
    already-fullscreen game back into a windowed one. Upstream niri offers
    only the toggle (niri-wm/niri#338); the action used here is added by
    patches/niri-virtual-outputs.patch, which is why the patched build is
    required.
    """
    result = subprocess.run(
        [NIRI, "msg", "action", "set-window-fullscreen",
         "--id", str(window_id),
         "--is-fullscreen", "true" if is_fullscreen else "false"],
        capture_output=True, text=True, env=niri_env(),
    )
    if result.returncode != 0:
        log("stream-mode: could not set fullscreen={} on window {}: {}".format(
            is_fullscreen, window_id, (result.stderr or "").strip()
        ))
        return False
    return True


def focus_window(window_id):
    """Focus a window, and say so if it did not work.

    This used to discard both the exit status and the error. Focus turned out
    to matter more than it looks: gamescope renders its contents at the size
    it was given until something activates it, so a game could sit fullscreen
    by niri's geometry and still be drawn at half the output. Tapping the
    window fixed it instantly, which is the same thing this does.
    """
    result = subprocess.run(
        [NIRI, "msg", "action", "focus-window", "--id", str(window_id)],
        capture_output=True, text=True, env=niri_env(),
    )
    if result.returncode != 0:
        log("stream-mode: could not focus window {}: {}".format(
            window_id, (result.stderr or "").strip()
        ))
        return False
    return True


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
        # (deadline, window_id) pairs; see run_due_audits.
        self.audits = []
        # Where the game workspace lived before a stream borrowed it.
        self.game_workspace_home = None
        # Windows this service moved to the streamed output for a game. Only
        # these are resized or focused: acting on whatever happened to be on
        # the output resized a terminal that drifted there during teardown.
        self.staged_windows = set()
        # Windows we put into fullscreen, so the stream can take them back out
        # of it and leave the desktop as it found it.
        self.fullscreened = set()
        # window id -> how many times focus has been taken back for it.
        self.refocus_attempts = {}
        # window id -> how many times it has been fullscreened to the output.
        self.widen_attempts = {}
        # Windows already reported as not covering the output, so the warning
        # is made once rather than on every event.
        self.size_warned = set()
        # workspace id -> output name, kept current from the event stream so a
        # trace line can say which monitor a window moved to without asking.
        self.workspace_outputs = {}
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
        self.staged_windows = set()
        self.fullscreened = set()
        self.refocus_attempts = {}
        self.widen_attempts = {}
        self.size_warned = set()
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
        # Before the game is launched, so its window rule places it correctly
        # the first time rather than being corrected afterwards.
        self.borrow_game_workspace()
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
        # Back to its own monitor before the output it is sitting on is turned
        # off, or niri has to find somewhere for it on our behalf.
        self.return_game_workspace()
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

    def check_steam_alive(self):
        """Clean up a game that Steam left behind when it died.

        Steam's client/helper pipe breaks if a stream ends while a game is
        running -- measured twice, both times as
        "CCrossProcessPipe::BWrite: 32 (Broken pipe)" followed by "Fatal
        assert; application exiting" -- and it exits without taking the game
        with it. The game keeps rendering to an output nobody is looking at,
        and has to be found and killed by hand.

        Only ever acts on the game this service staged, and only when no Steam
        client exists at all, because killing someone's game on a wrong guess
        is far worse than leaving one running. SIGTERM rather than SIGKILL, so
        a game that saves on exit still can.
        """
        # Nothing to tidy up unless we are in the middle of something. Steam
        # not running is the ordinary state between sessions.
        if self.game_pid is None and not self.streaming:
            return False
        if steam_is_running():
            return False

        pid, self.game_pid = self.game_pid, None
        if pid is not None:
            log(
                "stream-mode: Steam is gone but game pid {} is not; "
                "asking it to exit".format(pid)
            )
            signal_process(pid, signal.SIGTERM)
        else:
            # Previously this only fired with a game staged, so a Steam that
            # died after its game had already exited left the session standing:
            # target published, game workspace still on the streamed output,
            # and nothing to end it. Measured lasting forty minutes.
            log("stream-mode: Steam is gone; ending the stream it left behind")
        self.end_stream()
        return True

    def warn_if_short_of_output(self, window_id, size, output_size):
        """Say so when a widened window still does not cover the output.

        Widening maximises the column, which is not the same as fullscreen:
        the docs are explicit that a maximised column still leaves room for
        gaps and struts, and the window keeps its borders. Here the game
        workspace sets `gaps 0` and the window rule turns borders off, so a
        maximised column comes out exactly the output's size -- but that is a
        property of the configuration rather than of what this asks for.

        Change the gaps, or land a game on a workspace that has them, and the
        stream quietly gains a border that nothing would otherwise report.
        Niri exposes no fullscreen state to ask for instead (niri-wm/niri#2836)
        and offers only a toggle to set it (#338), so this cannot be made exact
        -- but it can at least stop being silent.
        """
        if tuple(int(v) for v in size) == tuple(int(v) for v in output_size):
            self.size_warned.discard(window_id)
            return False
        if window_id in self.size_warned:
            return False
        self.size_warned.add(window_id)
        log(
            "stream-mode: window {} is {} on a {} output after widening; "
            "the client will see the difference as a border. Gaps or borders "
            "on this workspace would explain it.".format(
                window_id, list(size), list(output_size)
            )
        )
        return True

    def fill_streamed_output(self, windows):
        """Fullscreen a staged game that is not covering the streamed output.

        Driven by compositor events rather than a timer: niri reports every
        window open and every layout change, so a window that opens small or
        is later resized is corrected as it happens.

        Acts on windows this service staged, and -- while a game is staged --
        on anything else that arrives on the streamed output, because a game
        with a splash screen replaces its window after staging has already
        happened and the replacement is nobody's by name.

        It used to act on anything on the output regardless, which resized a
        terminal that drifted there ninety seconds *after* the game exited:
        harmless as a width, considerably less so as a fullscreen. A staged
        game's pid is cleared when it exits, which is what tells the two
        cases apart.

        Safe to run on every event because setting fullscreen is idempotent
        and this only acts when the window is smaller than the output.
        Attempts are still capped per window, so one that refuses -- a fixed
        size, say -- is not fought forever, and the budget resets once it is
        covering the output.
        """
        if not self.streaming or self.output is None:
            return False

        try:
            output_size = output_logical_size(self.output)
        except (subprocess.CalledProcessError, ValueError, OSError):
            return False
        if output_size is None:
            return False

        for w in windows:
            window_id = w.get("id")
            if window_id is None:
                continue
            if window_id not in self.staged_windows and self.game_pid is None:
                continue
            if self.workspace_outputs.get(w.get("workspace_id")) != self.output:
                continue
            size = (w.get("layout") or {}).get("window_size")
            if not size or len(size) != 2:
                continue
            if (int(size[0]), int(size[1])) >= (int(output_size[0]), int(output_size[1])):
                self.widen_attempts.pop(window_id, None)
                self.warn_if_short_of_output(window_id, size, output_size)
                continue
            attempts = self.widen_attempts.get(window_id, 0)
            if attempts >= WIDEN_LIMIT:
                continue
            self.widen_attempts[window_id] = attempts + 1
            log("stream-mode: window {} is {} on a {} output; "
                "fullscreening ({}/{})".format(
                    window_id, size, list(output_size), attempts + 1, WIDEN_LIMIT
                ))
            if set_window_fullscreen(window_id, True):
                self.fullscreened.add(window_id)
            return True
        return False

    def refocus_streamed_window(self, windows):
        """Keep the game the focused window while a stream is running.

        Focus is asked for once when a window arrives, but it does not always
        stick: another window opening, or a splash closing, takes it back, and
        the game is then drawn at whatever size it last thought it had. This
        re-asserts it, at most a few times per window, so a genuine attempt to
        focus something else on the desktop is not fought indefinitely.
        """
        if not self.streaming or self.output is None:
            return False

        for w in windows:
            window_id = w.get("id")
            if window_id is None or window_id not in self.fullscreened:
                continue
            if self.workspace_outputs.get(w.get("workspace_id")) != self.output:
                continue
            if w.get("is_focused"):
                self.refocus_attempts.pop(window_id, None)
                continue
            attempts = self.refocus_attempts.get(window_id, 0)
            if attempts >= REFOCUS_LIMIT:
                continue
            self.refocus_attempts[window_id] = attempts + 1
            log("stream-mode: window {} on {} lost focus; taking it back ({}/{})".format(
                window_id, self.output, attempts + 1, REFOCUS_LIMIT
            ))
            focus_window(window_id)
            return True
        return False

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
        self.fill_streamed_output(windows)
        self.refocus_streamed_window(windows)

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
        log(
            "stream-mode: window {} before staging: {}".format(
                window["id"], window_location(window["id"])
            )
        )
        try:
            move_window_to_output(window["id"], self.output)
        except (subprocess.CalledProcessError, OSError) as exc:
            log("stream-mode: could not move window: {}".format(exc))
            return False
        # Moved and focused only. The size is corrected by
        # fill_streamed_output when the compositor reports the layout, rather
        # than guessed at here from a reading taken before the move lands.
        self.staged_windows.add(window["id"])
        focus_window(window["id"])
        log(
            "stream-mode: staged {} (window {}, pid {}, game {}) on {}; now {}".format(
                window.get("app_id") or "game", window["id"], pid, game_id,
                self.output, window_location(window["id"])
            )
        )
        # Look again later, without anybody having to be watching. A game has
        # been seen on the desktop monitor after a staging that reported
        # success, correcting itself only when the window was next focused --
        # which destroys the evidence in the act of observing it.
        self.audits = [
            (time.monotonic() + delay, window["id"]) for delay in STAGE_AUDIT_DELAYS
        ]
        return True

    def borrow_game_workspace(self):
        """Bring the workspace niri opens games on to the streamed output.

        The alternative was moving each game window after the fact, which is a
        race against the compositor's own rule and was losing it visibly: the
        game appeared on the desktop monitor, sized as gamescope's borderless
        column for that monitor, and was dragged across a moment later.

        Where it came from is remembered rather than assumed, so a desktop with
        a different monitor layout gets its own arrangement back.
        """
        if self.output is None:
            return False
        current = workspace_output(GAME_WORKSPACE)
        if current is None or current == self.output:
            return False
        self.game_workspace_home = current
        if not move_workspace_to_output(GAME_WORKSPACE, self.output):
            self.game_workspace_home = None
            return False
        log("stream-mode: moved workspace {} from {} to {}".format(
            GAME_WORKSPACE, current, self.output
        ))
        return True

    def fallback_workspace_home(self):
        """Somewhere to put the game workspace when no home was recorded.

        Sorted rather than any member of the set, so a desktop with two
        monitors gets the same answer every time instead of one that follows
        set iteration order.
        """
        candidates = usable_output_names() - {self.output, OUTPUT_NAME}
        return sorted(candidates)[0] if candidates else None

    def return_game_workspace(self):
        """Put the game workspace back where it was before the stream.

        Falls back to any other output when no home was recorded but the
        workspace is sitting on the streamed one. Borrowing takes an early
        exit when the workspace is already there -- the state a service
        restart mid-stream leaves behind -- and that exit records no home, so
        this used to find None and silently do nothing. The game was then
        stranded on an output that gets turned off, with every later stream
        re-entering the same early exit, and no way to reach it.
        """
        # Out of fullscreen before it goes back to the desktop monitor. The
        # niri window rule deliberately stopped forcing fullscreen on games
        # because it overrode gamescope's own borderless sizing, so a game
        # that outlives the stream must not keep what the stream gave it.
        for window_id in sorted(self.fullscreened):
            set_window_fullscreen(window_id, False)
        self.fullscreened = set()

        home = self.game_workspace_home
        self.game_workspace_home = None
        if home is None:
            where = workspace_output(GAME_WORKSPACE)
            if where != (self.output if self.output is not None else OUTPUT_NAME):
                return False
            home = self.fallback_workspace_home()
            if home is None:
                return False
            log(
                "stream-mode: workspace {} was left on {} with no recorded "
                "home; returning it to {}".format(GAME_WORKSPACE, where, home)
            )
        if home not in usable_output_names():
            # The monitor it came from is gone -- a KVM switch, or unplugged
            # mid-session. Leaving it here beats moving it somewhere invented.
            log("stream-mode: {} is gone; leaving workspace {} where it is".format(
                home, GAME_WORKSPACE
            ))
            return False
        if not move_workspace_to_output(GAME_WORKSPACE, home):
            return False
        log("stream-mode: returned workspace {} to {}".format(GAME_WORKSPACE, home))
        return True

    def watched_windows(self):
        """Windows currently under audit, by id."""
        return {window_id for _deadline, window_id in self.audits}

    def trace(self, window_id, what, layout=None, workspace_id=None):
        """Note a compositor event about a window being audited.

        The event stream says exactly when a window moved or was resized,
        which polling cannot: an audit at +1s and +3s shows a window in two
        places without saying when or how often it changed in between. Limited
        to audited windows so this does not narrate the whole desktop.
        """
        if window_id not in self.watched_windows():
            return False
        size = (layout or {}).get("window_size")
        where = self.workspace_outputs.get(workspace_id) if workspace_id else None
        log(
            "stream-mode: trace window {} {}{}{}".format(
                window_id,
                what,
                " size={}".format(size) if size is not None else "",
                " output={}".format(where) if where else "",
            )
        )
        return True

    def run_due_audits(self, now):
        """Log where an audited window has ended up, when its time comes."""
        if not self.audits:
            return False
        due = [entry for entry in self.audits if now >= entry[0]]
        if not due:
            return False
        self.audits = [entry for entry in self.audits if now < entry[0]]
        for _deadline, window_id in due:
            log(
                "stream-mode: audit window {}: {}".format(
                    window_id, window_location(window_id)
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


def next_reader_backoff(current):
    """How long to wait before the next restart of a reader that keeps dying.

    Doubles from READER_BACKOFF_MIN to a ceiling, so a compositor that is
    away for a while is retried a few times a minute rather than thousands of
    times a minute. The ceiling is low because the reader is how every window
    event arrives: being slow to reconnect costs real responsiveness.
    """
    return min(max(current * 2, READER_BACKOFF_MIN), READER_BACKOFF_MAX)


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
    # A start marker with no stop is only evidence of a stream if Steam is
    # still there to be streaming. Steam that dies mid-stream never writes the
    # stop marker, so the log stays that way for good -- and this service,
    # restarted afterwards, read it as a live stream, published a target and
    # held the game workspace on the streamed output with no Steam at all.
    if stream_in_progress() and steam_is_running():
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
    # once streaming stops, the deadline for a game that never appears, and
    # noticing that Steam has died under a game that has not.
    remove_at = None
    next_steam_check = 0.0
    # Per reader: when it may next be restarted, and how long the wait has
    # grown to. Both reset once a reader delivers a line.
    restart_at = {name: 0.0 for name in procs}
    backoff = {name: 0.0 for name in procs}

    try:
        while True:
            # A reader that has exited is left out. Its stdout sits at EOF and
            # would be reported readable immediately, every iteration, which
            # turns waiting for a compositor to come back into a busy loop --
            # 587 restarts in 45 seconds during one relog.
            readable = {
                p.stdout for p in procs.values()
                if p.stdout and p.poll() is None
            }
            # A pending audit has to wake the loop too, or it would not be
            # logged until the next event happened to arrive — and the whole
            # point of auditing is to see what happens when nothing does.
            timeout = 1.0 if (remove_at or session.pending or session.audits) else 30.0
            if len(readable) < len(procs):
                # Something is waiting to be restarted; wake for it.
                timeout = min(timeout, READER_BACKOFF_MAX)
            ready, _, _ = select.select(list(readable), [], [], timeout)

            now = time.monotonic()
            for name, proc in list(procs.items()):
                if proc.poll() is None:
                    continue
                if now < restart_at[name]:
                    continue
                backoff[name] = next_reader_backoff(backoff[name])
                restart_at[name] = now + backoff[name]
                log("stream-mode: {} reader exited, restarting it in {:.2f}s".format(
                    name, backoff[name]
                ))
                procs[name] = (
                    spawn_event_stream() if name == "events"
                    else spawn_tail(LOG if name == "stream" else CONNECTIONS_LOG)
                )

            for handle in ready:
                line = handle.readline()
                if not line:
                    continue

                # A reader that delivered a line is working; forget that it
                # ever failed, so a later outage starts from a short wait
                # rather than the ceiling the last one reached.
                for name, proc in procs.items():
                    if proc.stdout is handle:
                        backoff[name] = 0.0
                        break

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
            # Steam dying is silent from here: its logs simply stop, so there
            # is no line to react to. Polled, but only while a game is staged,
            # and slowly -- a game outliving Steam by a few seconds costs
            # nothing, and reading every process's name is not free.
            session.run_due_audits(now)
            if (session.game_pid is not None or session.streaming) \
                    and now >= next_steam_check:
                next_steam_check = now + STEAM_CHECK_INTERVAL
                if session.check_steam_alive():
                    remove_at = None
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
        # The workspace comes back now rather than with the output. Dropping
        # the output is delayed so a reconnect does not have to rebuild it,
        # but a game left running by Stop Streaming must not spend that delay
        # on a display nobody is watching and nobody can reach. A reconnect
        # inside the delay borrows it again on the next start marker.
        session.return_game_workspace()
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
            session.trace(
                window.get("id"), "opened or changed",
                layout=window.get("layout"), workspace_id=window.get("workspace_id"),
            )
            session.on_windows(session.last_windows)
        return

    if "WindowLayoutsChanged" in event:
        changes = event["WindowLayoutsChanged"].get("changes") or []
        for window_id, layout in changes:
            session.trace(window_id, "layout changed", layout=layout)
        # A resize is exactly when a window may have stopped filling the
        # output, so correct it here rather than waiting for some other event.
        # The layout event carries no workspace, so the known windows are
        # updated from it and re-examined.
        for window_id, layout in changes:
            for w in session.last_windows:
                if w.get("id") == window_id:
                    w["layout"] = layout
        session.fill_streamed_output(session.last_windows)
        return

    if "WindowClosed" in event:
        closed = event["WindowClosed"].get("id")
        session.last_windows = [
            w for w in session.last_windows if w.get("id") != closed
        ]
        return

    if "WorkspacesChanged" in event:
        workspaces = event["WorkspacesChanged"].get("workspaces") or []
        # Which output a window is on is a property of its workspace, so this
        # map is what lets a trace line name the monitor without asking niri.
        session.workspace_outputs = {
            ws.get("id"): ws.get("output") for ws in workspaces
        }
        session.on_outputs_changed(outputs_from_workspaces(workspaces))
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

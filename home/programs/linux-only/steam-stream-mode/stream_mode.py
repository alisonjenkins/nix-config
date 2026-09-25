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
        Streaming started to ali-steam-deck at 0.0.0.0:0, ...
        >>> Capture resolution set to 1280x800
        Adding window 4194306 (4) for process 2331545 and gameID 2854740
        Removing process 2163386 for gameID 2854740
        PipeWire: Deinitializing streaming

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
XPROP = os.environ.get("STREAM_MODE_XPROP", "xprop")
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
# The same target, for the one consumer that is compositor-aware. The gamescope
# shim sets --prefer-output and -r as well as the size, and neither the output
# name nor the refresh fits in a bare WIDTHxHEIGHT.
TARGET_JSON_FILE = os.environ.get(
    "STREAM_MODE_TARGET_JSON_FILE", TARGET_FILE + ".json"
)

# The session, not the video source. ">>> Starting/Stopped desktop stream"
# mark Steam swapping between desktop and game capture, several times a
# session; read as the end, a swap into game capture tore the stream down two
# minutes later. These two pair exactly, once per session.
START_RE = re.compile(r"Streaming started to (.+?) at ")
STOP_RE = re.compile(r"PipeWire: Deinitializing streaming")
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
# The client's resolution limit, sent when the stream starts. Steam scales its
# capture down to fit inside it, so any output pixels beyond it are rendered
# and then thrown away.
MAX_CAPTURE_RE = re.compile(r"Maximum capture: (\d+)x(\d+)(?: ([\d.]+) FPS)?")
# How long the client's reported size has to hold before the output follows
# it. Its window opens at the size of our output and only then goes
# fullscreen, so the first reports are our own size echoed back. Acting on the
# echo is how a Mac got learned as 4470x1676 and kept it. Measured: the echo
# held for 7s, a transitional size for 2s.
CLIENT_SIZE_SETTLE = float(os.environ.get("STREAM_MODE_CLIENT_SIZE_SETTLE", "10"))
# Steam switching the stream to the game's overlay, and that capture actually
# starting. Once it never started, and the stream stayed black until focus
# moved off the game and back.
GAME_STREAM_RE = re.compile(r">>> Switching video stream from \S+ to GameOverlay_MovieStream_\d+")
GAME_CAPTURE_RE = re.compile(r">>> Capture method set to Game ")
# The client's connection report, every 5s: the clock stalls and nudges are
# judged by, rather than one of our own. Working starts took up to 8s after
# the switch; the stall lasted six minutes, reports going by at ~185 kbit/s
# with no video. Six reports, about 30s, leaves the slow starts alone: a
# nudge on a capture that was about to start broke it (13:01:40, 13:09:23).
CLIENT_HEARTBEAT_RE = re.compile(r"CLIENT: SteamNetworkingSockets connection: ")
CAPTURE_STALL_HEARTBEATS = 6
# How much of a log to scan on start for a session or connection still open.
# Steam rotates these logs at about 1 MB; a 200 KB window lost a session's
# start marker after roughly 110 minutes of the ~1.8 KB/min keep-alive lines.
LOG_SCAN_BYTES = 2_000_000
GAMEPAD_INFO = os.environ.get(
    "STREAM_MODE_VIRTUAL_GAMEPAD_INFO",
    os.path.expanduser("~/.local/share/Steam/config/virtualgamepadinfo.txt"),
)
CAPTURE_NUDGE_LIMIT = int(os.environ.get("STREAM_MODE_CAPTURE_NUDGE_LIMIT", "3"))
ADD_WINDOW_RE = re.compile(r"Adding window \d+ \(\d+\) for process (\d+) and gameID (\d+)")
REMOVE_PROC_RE = re.compile(r"Removing process (\d+) for gameID (\d+)")
CONNECT_RE = re.compile(r"Client (\d+) \(([^)]*)\) connected via (?:direct|indirect) connection")
# Logged for every connect, with reasons such as "ping timeout",
# "disconnecting all" (Steam shutting down) and "told us it was offline".
DISCONNECT_RE = re.compile(r"Client (\d+) \(([^)]*)\) disconnected: ")
# A client on the same LAN as the host logs "indirect" for a moment before
# upgrading to "direct" a couple seconds later, so both match here. connect()
# re-runs its per-session setup (resizing, re-enabling the output) on the
# second, immediate connect() for the same client, which is harmless since
# nothing has changed yet at that point -- not idempotence, just an early
# no-op. A client with no direct path at all (relayed the whole session, e.g.
# off-LAN over Tailscale) never logs "direct" and previously never turned the
# output on for that reason.
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


def output_refresh(name):
    """The output's current refresh in whole Hz, or None if niri does not say."""
    output = niri_outputs().get(name) or {}
    modes, current = output.get("modes") or [], output.get("current_mode")
    if not isinstance(current, int) or not 0 <= current < len(modes):
        return None
    millihertz = modes[current].get("refresh_rate")
    return round(millihertz / 1000) if millihertz else None


def set_output_mode(name, width, height, refresh):
    """Resize the virtual output to a client's panel.

    Resizing rather than replacing: Steam remembers its capture source and
    resolves it when a session starts, so an output that came and went leaves
    that request failing — which stalled Steam's main loop past its 15-second
    watchdog and segfaulted the client.

    Set twice, first one Hz off. X clients through xwayland-satellite see a
    virtual output's mode change one change late, so after a single change X
    still reported the previous size and HD2 sized its borderless window to
    1280x800 on a 1728x1080 output. The second change carries the size.
    """
    for step in (refresh + 1, refresh):
        result = subprocess.run(
            [NIRI, "msg", "output", name, "mode", "{}x{}@{}".format(width, height, step)],
            check=False, capture_output=True, text=True, env=niri_env(),
        )
        if result.returncode != 0:
            log(
                "stream-mode: could not set {} to {}x{}@{}: {}".format(
                    name, width, height, step, (result.stderr or "").strip()
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


def _write_atomically(path, contents):
    """Write a file whole and rename it into place.

    Both targets are read from a game launch that can happen at any moment, so
    neither may ever be seen half-written.
    """
    tmp = path + ".new"
    with open(tmp, "w") as fh:
        fh.write(contents)
    os.replace(tmp, path)


def publish_target(output, width, height, refresh=None):
    """Announce the streamed target to everything that needs it.

    Two files, because the two consumers want different things and neither
    should have to carry the other's format.

    TARGET_FILE is plain "WIDTHxHEIGHT". The display filter hooks SDL, which
    has no notion of the compositor's output names, so the size is all it can
    use -- and keeping it to one line is what lets someone on another
    compositor drive the filter by hand with STEAM_STREAM_SIZE=1280x800 and no
    watcher at all. That file is the compositor-agnostic contract.

    TARGET_JSON_FILE carries the same target plus the output name and refresh,
    for the gamescope shim, which sets --prefer-output and -r as well as the
    size. It is the only consumer that knows what a compositor output is.

    Publishing just the size was briefly the whole interface, and silently
    broke the shim: it found no file, took that for "not streaming" as it is
    designed to, and launched games at the desktop's geometry to be scaled into
    the streamed output afterwards -- the exact letterboxing it exists to
    prevent.
    """
    payload = {"output": output, "width": width, "height": height}
    if refresh is not None:
        payload["refresh"] = refresh
    try:
        os.makedirs(os.path.dirname(TARGET_FILE), exist_ok=True)
        _write_atomically(TARGET_FILE, "{}x{}\n".format(width, height))
        _write_atomically(TARGET_JSON_FILE, json.dumps(payload) + "\n")
    except OSError as exc:
        log("stream-mode: could not publish the stream target: {}".format(exc))
        return False
    log("stream-mode: published target {} {}x{}".format(output, width, height))
    return True


def withdraw_target():
    """Remove both targets, and say so if either was there.

    Both go together: a game launched after a stream ends must not still be
    sized for a client that has gone. Each is removed independently so a
    half-published state -- one file present, the other not -- is still
    cleaned up rather than left behind.
    """
    removed = False
    for path in (TARGET_FILE, TARGET_JSON_FILE):
        try:
            os.remove(path)
            removed = True
        except FileNotFoundError:
            continue
        except OSError as exc:
            log("stream-mode: could not withdraw {}: {}".format(path, exc))
            return False
    if removed:
        log("stream-mode: withdrew the stream target")
    return removed


def clear_gamescope_atoms():
    """Remove GAMESCOPE_* atoms from the host X root window.

    gamescope opens the host display to copy its cursor and leaves these
    behind. Steam then acts as if it runs inside gamescope, reads focus from
    GAMESCOPE_FOCUSED_APP, gets app id 0, and flips a stream between game and
    desktop mode. Returns the atoms removed.
    """
    try:
        listing = subprocess.run(
            [XPROP, "-root"], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        log("stream-mode: could not read the X root to clear gamescope atoms: {}".format(exc))
        return []
    if listing.returncode != 0:
        log("stream-mode: xprop -root failed: {}".format((listing.stderr or "").strip()))
        return []

    names = sorted({
        line.split("(", 1)[0].split(":", 1)[0].strip()
        for line in listing.stdout.splitlines()
        if line.startswith("GAMESCOPE_")
    })
    removed = []
    for name in names:
        try:
            result = subprocess.run(
                [XPROP, "-root", "-remove", name],
                capture_output=True, text=True, timeout=5,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            log("stream-mode: could not remove {}: {}".format(name, exc))
            continue
        if result.returncode != 0:
            log("stream-mode: could not remove {}: {}".format(
                name, (result.stderr or "").strip()))
            continue
        removed.append(name)
    if removed:
        log("stream-mode: removed stale gamescope atoms: {}".format(", ".join(removed)))
    return removed


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


def other_active_outputs(name):
    """Enabled outputs besides name. niri reports a disabled one without a logical."""
    try:
        outputs = niri_outputs()
    except (subprocess.CalledProcessError, ValueError, OSError):
        return None
    return {n for n, o in outputs.items() if n != name and (o or {}).get("logical")}


GAMEPAD_SLOT_RE = re.compile(r"^\[slot (\d+)\]", re.MULTILINE)
# Steam's virtual gamepads are uinput devices named for their slot, the same
# slot number virtualgamepadinfo.txt uses.
STEAM_PAD_NAME_RE = re.compile(r"^Microsoft X-Box 360 pad (\d+)$")


def gamepad_slots(info_text):
    """Slots Steam lists in virtualgamepadinfo.txt."""
    return {int(n) for n in GAMEPAD_SLOT_RE.findall(info_text)}


def steam_virtual_pads(root="/sys/class/input"):
    """Steam's virtual gamepads: slot -> device node.

    Only uinput devices, under /devices/virtual: a physical Xbox 360 pad
    carries the same name.
    """
    pads = {}
    try:
        entries = os.listdir(root)
    except OSError:
        return pads
    for event in entries:
        if not event.startswith("event"):
            continue
        base = os.path.join(root, event)
        if "/devices/virtual/" not in os.path.realpath(base):
            continue
        try:
            with open(os.path.join(base, "device", "name")) as fh:
                match = STEAM_PAD_NAME_RE.match(fh.read().strip())
        except OSError:
            continue
        if match:
            pads[int(match.group(1))] = "/dev/input/" + event
    return pads


def device_in_use(path):
    """Does any process we can see have this device node open?

    A pad the game already has must not be announced again: Proton adds it
    a second time and the game loses the controller it was using.
    """
    try:
        target = os.stat(path)
    except OSError:
        return False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = "/proc/{}/fd".format(pid)
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                st = os.stat(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if (st.st_dev, st.st_ino) == (target.st_dev, target.st_ino):
                return True
    return False


def touch_device(path):
    """Update a device node's timestamps, which inotify reports as IN_ATTRIB.

    SDL treats IN_ATTRIB on /dev/input as a device that may now be usable,
    because permissions are applied after a node appears; that re-check is
    what picks up a Steam gamepad it rejected on arrival. Needs only write
    access to the node, which the seat's uaccess ACL already gives.
    """
    try:
        os.utime(path, None)
    except OSError as exc:
        log("stream-mode: could not re-announce {}: {}".format(path, exc))
        return False
    return True


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


def move_window_to_tiling(window_id):
    """Take a window out of the floating layer, so fullscreen covers the output."""
    result = subprocess.run(
        [NIRI, "msg", "action", "move-window-to-tiling", "--id", str(window_id)],
        capture_output=True, text=True, env=niri_env(),
    )
    if result.returncode != 0:
        log("stream-mode: could not tile window {}: {}".format(
            window_id, (result.stderr or "").strip()
        ))
        return False
    return True


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


def focus_workspace(output, reference):
    """Focus a workspace on output, by index or name.

    niri resolves an index on the focused output, so that output is focused
    first: with DP-2 focused, the index would pick one of DP-2's workspaces.
    """
    for action in (["focus-monitor", output], ["focus-workspace", str(reference)]):
        result = subprocess.run(
            [NIRI, "msg", "action", *action],
            capture_output=True, text=True, env=niri_env(),
        )
        if result.returncode != 0:
            log("stream-mode: could not focus workspace {} on {}: {} failed: {}".format(
                reference, output, action[0], (result.stderr or "").strip()
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


# Smaller than any game renders; Wine's systray fallback window is 160x20.
HELPER_WINDOW_MAX = (320, 240)


def is_helper_window(window):
    """A popup or tray window that shares the game's app id but is not the game.

    Wine shows its own tray window when a game (HD2's GameGuard) adds a tray
    icon, with the game's `steam_app_<id>` app id. Treating it as the game
    fullscreened a blank window, and Steam streamed that instead of the game.

    Judged by size alone. Floating is no sign: niri floats a game whose first
    window is a fixed-size splash, and FH6 then stayed a floating 1272x717
    window on the streamed output, never staged or fullscreened.
    """
    size = (window.get("layout") or {}).get("window_size")
    if not size or len(size) != 2:
        return False
    return int(size[0]) < HELPER_WINDOW_MAX[0] or int(size[1]) < HELPER_WINDOW_MAX[1]


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
    # A tiled window before a floating one: a game's dialog floats beside it.
    windows = sorted((w for w in windows if not is_helper_window(w)),
                     key=lambda w: bool(w.get("is_floating")))

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


def _size_pair(value):
    if isinstance(value, list) and len(value) == 2:
        try:
            width, height = int(value[0]), int(value[1])
        except (TypeError, ValueError):
            return None
        if width > 0 and height > 0:
            return width, height
    return None


def fit_within(width, height, bound):
    """Scale down to fit inside bound, keeping the aspect. Never scales up."""
    if bound is None:
        return width, height
    scale = min(1.0, bound[0] / width, bound[1] / height)
    if scale >= 1.0:
        return width, height
    # Even, because the encoder works in 2x2 chroma blocks.
    return (
        max(2, int(round(width * scale)) // 2 * 2),
        max(2, int(round(height * scale)) // 2 * 2),
    )


def client_record(client_id, clients):
    """The client's last settled output size and resolution limit.

    A bare [w, h] is the older format, which stored whatever was reported
    first. It is read as an output size with no known limit.
    """
    entry = clients.get(str(client_id))
    if isinstance(entry, dict):
        return _size_pair(entry.get("output")), _size_pair(entry.get("max_capture"))
    return _size_pair(entry), None


def client_size(client_id, clients, max_capture=None):
    """Resolution to build the output at, defaulting until one is learned.

    The client's own shape, fitted inside its resolution limit: this
    session's limit when it has been sent, the remembered one otherwise.
    """
    output, remembered = client_record(client_id, clients)
    if output is None:
        return DEFAULT_WIDTH, DEFAULT_HEIGHT
    return fit_within(output[0], output[1], max_capture or remembered)


def client_refresh(client_id, clients, fps=None):
    """Refresh to drive the output at: the frame rate the client asked for.

    Whole Hz, because that is what niri's custom modes take. A game that
    follows the display otherwise renders frames the stream drops, or too
    few for a 120 Hz client.
    """
    if fps is None:
        entry = clients.get(str(client_id))
        fps = entry.get("refresh") if isinstance(entry, dict) else None
    try:
        refresh = round(float(fps))
    except (TypeError, ValueError):
        return DEFAULT_REFRESH
    return refresh if refresh > 0 else DEFAULT_REFRESH


# --- session ----------------------------------------------------------------


class Session:
    """Owns the virtual output and what sits on it, for one client at a time."""

    def __init__(self, stage_timeout=None):
        self.output = None
        self.client_id = None
        self.streaming = False
        self.game_pid = None
        self.game_id = None
        self.pending = None
        self.reported_wait = False
        self.last_windows = []
        # This session's resolution limit, and the client's latest reported
        # size with the monotonic time it may be acted on. See
        # CLIENT_SIZE_SETTLE.
        self.max_capture = None
        self.max_fps = None
        self.reported_output = None
        self.settle_at = None
        # client name -> id, from connect lines; the stream-start line names
        # its client but carries no id.
        self.known_clients = {}
        # A game capture Steam has switched to but not started, the client
        # reports since, the nudges it has had, and the window a nudge in
        # progress returns to. See client_heartbeat.
        self.capture_waiting = False
        self.capture_heartbeats = 0
        self.nudge_return_to = None
        self.capture_nudges = 0
        # See check_gamepad_info. None until first read, so a watcher started
        # mid-game re-announces the listed pads once.
        self.gamepad_info_path = GAMEPAD_INFO
        self.gamepad_info_mtime = None
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

    def apply_mode(self, width, height, refresh):
        """Set the output's mode unless it already has it."""
        current_refresh = output_refresh(self.output)
        if output_logical_size(self.output) == (width, height) and \
                current_refresh in (None, refresh):
            return False
        return set_output_mode(self.output, width, height, refresh)

    def connect(self, client_id, client_name):
        """A client has connected: size the output for it and turn it on."""
        self.client_id = client_id
        if client_name:
            self.known_clients[client_name] = client_id
        self.max_capture = None
        self.max_fps = None
        self.reported_output = None
        self.settle_at = None
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

        refresh = client_refresh(client_id, self.clients)
        # Resize only when the client actually needs a different mode, so a
        # reconnect from the same client does not disturb the layout.
        self.apply_mode(width, height, refresh)

        # Published before the output is enabled, not after. Steam re-reads the
        # monitor list when the X server reports outputs changing, and enabling
        # this one is that change; the display filter reads this file on every
        # such query and does nothing while it is absent. Publishing afterwards
        # would arm the filter just too late to affect the read it was meant
        # for, leaving Steam sized to the desktop monitor for the session.
        publish_target(self.output, width, height, refresh)
        set_output_enabled(self.output, True)
        log(
            "stream-mode: {} connected; {} on at {}x{}".format(
                client_name or client_id, self.output, width, height
            )
        )
        return True

    def disconnect(self, client_id):
        """The client has gone: disarm, unless a stream is still winding down.

        The target stays published for as long as the client is connected,
        because a game launched from the client starts before the stream
        does and the shim reads the target at launch. A 45-second connect
        timeout withdrew it from a client still browsing, and the next launch
        from it went through gamescope. Mid-stream, the stop marker and its
        grace period already govern the teardown.
        """
        if client_id != self.client_id:
            return False
        self.client_id = None
        if self.streaming:
            return False
        log("stream-mode: client {} disconnected".format(client_id))
        return self.end_stream()

    def teardown(self):
        """Turn the output off. Only on shutdown — see `idle`."""
        if self.output is None:
            return False
        name, self.output = self.output, None
        self.game_pid = None
        set_output_enabled(name, False)
        log("stream-mode: turned {} off".format(name))
        return True

    def begin_stream(self, client_name=None):
        """A stream has started: say where to render.

        client_name is the one Steam names in "Streaming started to", which is
        the client actually streaming. The last client to connect need not
        be: the Deck connected and the Mac reconnected in the same second, the
        Deck streamed, and its size was saved as the Mac's.
        """
        streaming_id = self.known_clients.get(client_name)
        if streaming_id is not None and streaming_id != self.client_id:
            log("stream-mode: streaming to {}, not the last client to connect".format(client_name))
            self.client_id = streaming_id
        # "Maximum capture" follows this line, so the last session's limit
        # must not stand in for this one's.
        self.max_capture = None
        self.max_fps = None
        self.reported_output = None
        self.settle_at = None
        # Not on each switch to game capture: every nudge's return logs one.
        self.capture_nudges = 0
        self.streaming = True
        clear_gamescope_atoms()
        if self.output is None:
            self.ensure_output()
        if self.output is None:
            return False

        # The client we are serving decides the size, in preference to whatever
        # mode the output was last left in. A stream can start without a fresh
        # connect line, and the output keeps its previous mode — set for an
        # earlier client, or by hand at the command line. Preferring the
        # output's own size meant a Deck streamed at 1600x900 simply because
        # that is what the output happened to be at the time.
        if self.client_id is not None:
            width, height = client_size(self.client_id, self.clients, self.max_capture)
            refresh = client_refresh(self.client_id, self.clients, self.max_fps)
        else:
            size = output_logical_size(self.output) or (DEFAULT_WIDTH, DEFAULT_HEIGHT)
            width, height = size
            refresh = output_refresh(self.output) or DEFAULT_REFRESH

        # Published and resized before the output is enabled, not after --
        # the same ordering connect() uses and for the same reason: enabling
        # an off output is the change Steam re-reads its monitor list on, and
        # the display filter has to already be reporting the new size when it
        # does. This output can already be on (a client connected first) or
        # off (a stream starting after the connect-timeout withdrew the
        # target, or a service restart mid-session with no fresh connect
        # line) -- enabling first left the second case sized to whatever the
        # output happened to be at, or unfiltered outright.
        published = publish_target(self.output, width, height, refresh)
        self.apply_mode(width, height, refresh)
        set_output_enabled(self.output, True)
        # Before the game is launched, so its window rule places it correctly
        # the first time rather than being corrected afterwards.
        self.borrow_game_workspace()
        self.readopt_running_game()
        if not published:
            log("stream-mode: WARNING games will launch at the desktop's size")
        return published

    def game_capture_requested(self):
        """Steam moved the stream to the game's overlay; expect frames soon."""
        self.capture_waiting = True
        self.capture_heartbeats = 0

    def game_capture_started(self):
        # A nudge in flight still returns at the next report: capture that
        # starts while focus is away would otherwise leave it there.
        self.capture_waiting = False
        self.capture_nudges = 0

    def client_heartbeat(self):
        """The client's periodic report: the clock a stall is judged by.

        Steam binds game capture when the recorded window changes, and a
        rebind is what got a stalled capture going, so a stall is answered by
        moving focus off the game. Bounded, because a capture that never
        starts should not have focus bounced forever.
        """
        if self.nudge_return_to is not None:
            # A report later, not straight away: returning at once, even on
            # Steam's "Changing record window" line, Steam missed the return
            # and stayed on the other window, a desktop capture showing black.
            return self.finish_nudge()
        if not self.capture_waiting:
            return False
        self.capture_heartbeats += 1
        if self.capture_heartbeats < CAPTURE_STALL_HEARTBEATS:
            return False
        self.capture_heartbeats = 0
        if self.capture_nudges >= CAPTURE_NUDGE_LIMIT:
            log("stream-mode: game capture never started; giving up on nudging it")
            self.capture_waiting = False
            return False
        game = next((w for w in self.last_windows
                     if self.belongs_to_game(w) and not is_helper_window(w)), None)
        if game is None:
            return False
        away = self.nudge_away_target(game)
        if away is None:
            log("stream-mode: game capture has not started, and there is no empty "
                "workspace or other window to move focus to")
            return False
        self.capture_nudges += 1
        log("stream-mode: game capture has not started; moving focus off window {} "
            "and back ({}/{})".format(game["id"], self.capture_nudges, CAPTURE_NUDGE_LIMIT))
        self.nudge_return_to = game["id"]
        away()
        return True

    def nudge_away_target(self, game):
        """Somewhere to put focus that is not the game, as a callable.

        An empty workspace on the streamed output first: niri keeps one at
        the end of every output, so it needs no other window, and it leaves
        the desktop's windows alone. Steam then records no window at all.
        Failing that, any window that is not Steam's own: given one of its
        own, Steam recorded it instead of the game.
        """
        try:
            workspaces = niri_workspaces()
        except (subprocess.CalledProcessError, ValueError, OSError):
            workspaces = []
        empty = [w for w in workspaces
                 if w.get("output") == self.output and w.get("active_window_id") is None]
        if empty:
            # The unnamed one niri keeps at the end, over an empty named one.
            best = max(empty, key=lambda w: (w.get("name") is None, w.get("idx") or 0))
            return lambda: focus_workspace(self.output, best.get("idx"))
        other = next((w for w in self.last_windows if all((
            w.get("id") != game.get("id"),
            not (w.get("app_id") or "").startswith("steam"),
        ))), None)
        if other is not None:
            return lambda: focus_window(other["id"])
        return None

    def finish_nudge(self):
        window_id, self.nudge_return_to = self.nudge_return_to, None
        focus_window(window_id)
        return True

    def check_gamepad_info(self):
        """Re-announce Steam's listed virtual gamepads when the list changes.

        SDL inside Proton uses a Steam virtual gamepad only once Steam lists
        it in virtualgamepadinfo.txt, and decides when the device appears. A
        client reconnecting mid-game gets a new pad that Steam lists after
        creating it, so SDL rejected it and the game kept the dead one: the
        camera worked through the mouse, nothing else did. Touching the node
        makes SDL look again now that the pad is listed. Only pads nothing
        has open: Proton adds a touched pad again even when it already has
        it, and the game then loses the one it was using.
        """
        try:
            mtime = os.stat(self.gamepad_info_path).st_mtime
        except OSError:
            return False
        if mtime == self.gamepad_info_mtime:
            return False
        self.gamepad_info_mtime = mtime
        try:
            with open(self.gamepad_info_path) as fh:
                slots = gamepad_slots(fh.read())
        except OSError:
            return False
        pads = steam_virtual_pads()
        touched = [
            pads[slot] for slot in sorted(slots)
            if slot in pads and not device_in_use(pads[slot]) and touch_device(pads[slot])
        ]
        if touched:
            log("stream-mode: re-announced Steam gamepads {}".format(", ".join(touched)))
        return bool(touched)

    def reassert_output(self):
        """Put the output back after niri reloaded its config.

        niri drops changes made over IPC on every reload and re-applies the
        declared output: `off`, at the declared mode. A switch that touched
        config.kdl turned the output off under a running session, and with
        the monitor off that left niri with no outputs at all.
        """
        if self.streaming or self.client_id is not None:
            self.output = OUTPUT_NAME
            if self.client_id is not None:
                width, height = client_size(self.client_id, self.clients, self.max_capture)
                refresh = client_refresh(self.client_id, self.clients, self.max_fps)
                self.apply_mode(width, height, refresh)
            set_output_enabled(OUTPUT_NAME, True)
            log("stream-mode: niri reloaded its config; restored {}".format(OUTPUT_NAME))
            return True
        if other_active_outputs(OUTPUT_NAME) == set():
            set_output_enabled(OUTPUT_NAME, True)
            log("stream-mode: niri reloaded its config; kept {} on, it is the only output".format(OUTPUT_NAME))
            return True
        return False

    def readopt_running_game(self):
        """Stage a game that is still running from an earlier stream.

        Steam logs nothing new for a game that is already up, so without this
        a reconnect left it unfocused and Steam streamed the Friends List.
        """
        if self.game_pid is None or self.game_id is None or self.pending:
            return False
        if not os.path.exists("/proc/{}".format(self.game_pid)):
            self.game_pid = None
            return False
        log("stream-mode: game {} is still running; staging it again".format(self.game_id))
        return self.request(self.game_pid, self.game_id)

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
        self.capture_waiting = False
        self.nudge_return_to = None

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
        # Left on when it is the only output. With the monitor off, niri
        # would have none at all, and a Steam restarted then fails to open
        # its login window ("Failed to create fallback output window,
        # bailing"), stays logged off and is invisible to every client.
        if other_active_outputs(name) == set():
            withdraw_target()
            log("stream-mode: left {} on, it is the only output".format(name))
            return True
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

    def note_max_capture(self, width, height, fps=None):
        """The client's resolution and frame rate limit for this session.

        Applied at once: it arrives just after the stream starts, which was
        sized from the remembered limit, and unlike the client's window size
        it is not an echo of our own output.
        """
        self.max_capture = (width, height)
        self.max_fps = fps
        if not self.streaming or self.output is None or self.client_id is None:
            return False
        target = client_size(self.client_id, self.clients, self.max_capture)
        refresh = client_refresh(self.client_id, self.clients, self.max_fps)
        publish_target(self.output, target[0], target[1], refresh)
        return self.apply_mode(target[0], target[1], refresh)

    def note_client_output(self, width, height, now=None):
        """The client reported its size; act on it once it has settled.

        Followed for the whole session rather than taken once, so a client
        window resized or made fullscreen mid-stream is followed too.
        """
        if self.client_id is None or (width, height) == self.reported_output:
            return False
        self.reported_output = (width, height)
        self.settle_at = (time.monotonic() if now is None else now) + CLIENT_SIZE_SETTLE
        return True

    def settle_client_output(self, now):
        if self.settle_at is None or self.reported_output is None or now < self.settle_at:
            return False
        self.settle_at = None
        return self.learn(*self.reported_output)

    def learn(self, width, height):
        """Record the client's settled size, and use it for this session too.

        Applied immediately rather than only remembered. A client connecting
        for the first time has nothing to size the output from, so it gets the
        default; leaving the correction until the next connect would let that
        whole first session run letterboxed, which is the thing this service
        exists to prevent. Republished before the resize for the reason connect
        does the same: the resize is the display change Steam re-reads on, and
        the filter has to already be reporting the new size when it does.
        """
        if self.client_id is None:
            return False
        key = str(self.client_id)
        _, remembered_max = client_record(key, self.clients)
        refresh = client_refresh(key, self.clients, self.max_fps)
        record = {"output": [width, height], "refresh": refresh}
        max_capture = self.max_capture or remembered_max
        if max_capture is not None:
            record["max_capture"] = list(max_capture)
        changed = self.clients.get(key) != record
        if changed:
            self.clients[key] = record
            save_clients(self.clients)
            log(
                "stream-mode: learned {}x{}@{} for client {} (limit {})".format(
                    width, height, refresh, self.client_id,
                    "{}x{}".format(*self.max_capture) if self.max_capture else "unknown",
                )
            )

        target = client_size(key, self.clients, self.max_capture)
        if self.output is None:
            return changed
        current_refresh = output_refresh(self.output)
        if output_logical_size(self.output) == target and current_refresh in (None, refresh):
            return changed

        publish_target(self.output, target[0], target[1], refresh)
        set_output_mode(self.output, target[0], target[1], refresh)
        log(
            "stream-mode: set {} to {}x{}@{} for this session".format(
                self.output, target[0], target[1], refresh
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

    def is_live(self):
        """A client connected, a stream running, or a game staged."""
        return self.client_id is not None or self.streaming or self.game_pid is not None

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
        if not self.is_live():
            return False
        if steam_is_running():
            return False

        # A crash is the one way a client goes without a disconnect line.
        self.client_id = None
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

    def belongs_to_game(self, window):
        """Staged, or the running game's by app id or process ancestry.

        A game's replacement window after a splash is nobody's by name, but
        it carries the game's app id or descends from its process. Anything
        else on the streamed output is the desktop's: with the monitor off,
        niri puts every workspace there.
        """
        if window.get("id") in self.staged_windows:
            return True
        if self.game_pid is None:
            return False
        if self.game_id is not None and window.get("app_id") == "steam_app_{}".format(self.game_id):
            return True
        pid = window.get("pid")
        return bool(pid) and self.game_pid in parent_pids(pid)

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
            if not self.belongs_to_game(w):
                continue
            if is_helper_window(w):
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
            if w.get("is_floating"):
                move_window_to_tiling(window_id)
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
        # A nudge moves focus away on purpose; taking it back at once is the
        # instant return that leaves Steam's capture black.
        if self.nudge_return_to is not None:
            return False
        # A window that opened after the game asked for focus: a login box,
        # a cloud-save conflict. Steam streams the focused window, so pulling
        # focus back would hide what the player must answer. niri ids only
        # grow, so newer means a higher id. Focus falling to an older window,
        # as when a splash closes, is still taken back.
        focused_id = next((w.get("id") for w in windows if w.get("is_focused")), None)

        for w in windows:
            window_id = w.get("id")
            if window_id is None or window_id not in self.fullscreened:
                continue
            if focused_id is not None and focused_id > window_id:
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
        self.game_id = game_id
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
        # The next game in this stream gets its own nudges, and a return to
        # the window that just closed is not attempted.
        self.capture_waiting = False
        self.capture_nudges = 0
        self.nudge_return_to = None
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
        bufsize=0,
    )


def read_line(handle):
    """One line from an unbuffered reader pipe, as text.

    The pipes are unbuffered on purpose. A buffered reader's readline() takes
    a whole chunk from the pipe and keeps the lines after the first, so
    select() sees an empty pipe and those lines wait for the next write. A
    Deck stream's stop marker arrived in such a burst and was never acted on.
    Unbuffered, readline() takes one line and leaves the rest where select()
    can see them.
    """
    return handle.readline().decode("utf-8", "replace")


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
        bufsize=0,
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
            fh.seek(max(0, size - LOG_SCAN_BYTES))
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


def connected_client(path=None):
    """The client that connected most recently and has not disconnected.

    The log is followed from its end, so a restart while a client was
    connected -- every `just switch` -- forgot it. The target then stayed
    withdrawn until a stream started, and a game launched from the client
    before that went through gamescope.
    """
    path = path or CONNECTIONS_LOG
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - LOG_SCAN_BYTES))
            tail = fh.read().decode("utf-8", "replace")
    except OSError:
        return None

    connected = {}
    for line in tail.splitlines():
        match = CONNECT_RE.search(line)
        if match:
            client_id = int(match.group(1))
            connected.pop(client_id, None)
            connected[client_id] = match.group(2)
            continue
        match = DISCONNECT_RE.search(line)
        if match:
            connected.pop(int(match.group(1)), None)
    if not connected:
        return None
    client_id = list(connected)[-1]
    return client_id, connected[client_id]


def watch():
    session = Session()

    def bail(_signum, _frame):
        withdraw_target()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGINT, bail)

    session.ensure_output()
    withdraw_target()
    # Only with Steam running, for the same reason as the stream check below:
    # a Steam that crashed never logged the disconnect.
    client = connected_client() if steam_is_running() else None
    if client is not None:
        log("stream-mode: {} is still connected".format(client[1]))
        session.connect(*client)
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
            # A connected client can hand Steam a new gamepad at any moment;
            # see check_gamepad_info.
            pending_work = any((
                remove_at, session.pending, session.audits, session.settle_at,
                session.client_id is not None,
                session.streaming,
            ))
            timeout = 1.0 if pending_work else 30.0
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
                line = read_line(handle)
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
                    gone = DISCONNECT_RE.search(line)
                    if match:
                        remove_at = None
                        session.connect(int(match.group(1)), match.group(2))
                    elif gone:
                        session.disconnect(int(gone.group(1)))
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
            # is no line to react to. Polled, but only while a client or game
            # is live, and slowly -- a game outliving Steam by a few seconds
            # costs nothing, and reading every process's name is not free.
            session.run_due_audits(now)
            session.settle_client_output(now)
            session.check_gamepad_info()
            if session.is_live() and now >= next_steam_check:
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
        session.note_client_output(int(match.group(1)), int(match.group(2)))
        return remove_at

    if GAME_STREAM_RE.search(line):
        session.game_capture_requested()
        return remove_at

    if CLIENT_HEARTBEAT_RE.search(line):
        session.client_heartbeat()
        return remove_at

    if GAME_CAPTURE_RE.search(line):
        session.game_capture_started()
        return remove_at

    match = MAX_CAPTURE_RE.search(line)
    if match:
        session.note_max_capture(
            int(match.group(1)), int(match.group(2)),
            float(match.group(3)) if match.group(3) else None,
        )
        return remove_at

    match = REMOVE_PROC_RE.search(line)
    if match:
        session.unstage(int(match.group(1)))
        return remove_at

    match = START_RE.search(line)
    if match:
        log("stream-mode: stream started")
        session.begin_stream(match.group(1))
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

    if "ConfigLoaded" in event:
        # Also sent once on subscribing, which covers a watcher started while
        # niri has no outputs.
        if not (event["ConfigLoaded"] or {}).get("failed"):
            session.reassert_output()
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
        "usage: stream-mode [watch|on [W H]|off [NAME]|status]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

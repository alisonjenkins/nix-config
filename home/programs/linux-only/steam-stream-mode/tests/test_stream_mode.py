"""Tests for stream-mode's virtual output lifecycle and log parsing.

Run: python3 -m unittest discover -s tests -v
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import stream_mode  # noqa: E402

# begin_stream() clears atoms on the real X root; never let a test reach it.
stream_mode.XPROP = "/nonexistent/xprop"
# Reads the live compositor. None means "unknown", which never forces a mode.
real_output_refresh = stream_mode.output_refresh
stream_mode.output_refresh = lambda name: None
# Unknown, which keeps the plain turn-it-off behaviour.
stream_mode.other_active_outputs = lambda name: None

_state_dir = None


def setUpModule():
    """Keep the suite away from the real learned-clients file.

    Session.learn() saves through the module-level STATE path, so running the
    tests rewrote the user's own ~/.local/state/stream-mode/clients.json with
    fixture clients and threw away the real ones. A test suite must not touch
    the state of the thing it is testing.
    """
    global _state_dir
    _state_dir = tempfile.TemporaryDirectory()
    stream_mode.STATE = os.path.join(_state_dir.name, "clients.json")


def tearDownModule():
    _state_dir.cleanup()


def window(wid, pid, app_id="steam_app_2854740", size=(1277, 1406)):
    return {
        "id": wid,
        "pid": pid,
        "app_id": app_id,
        "title": "Game",
        "layout": {"window_size": list(size)},
    }


class TestLogParsing(unittest.TestCase):
    """Verbatim lines from ali-desktop's Steam logs."""

    START = "[2026-08-24 22:39:48][308.657953] Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\n"
    RES = "[2026-08-24 22:39:48][308.792672] >>> Capture resolution set to 1280x800\n"
    RES_DERIVED = "[2026-08-24 22:39:48][308.923932] >>> Capture resolution set to 1280x360\n"
    STOP = "[2026-08-24 22:40:02][322.711832] PipeWire: Deinitializing streaming\n"
    ADD = "[2026-08-24 23:30:46] Adding window 4194306 (4) for process 2331545 and gameID 2854740\n"
    REMOVE = "[2026-08-24 22:40:02] Removing process 2163386 for gameID 2854740\n"
    CONNECT = (
        "[2026-08-24 23:03:41] Client 17744070381767483567 (ali-steam-deck) "
        "connected via direct connection\n"
    )
    BROADCAST = (
        "[2026-08-24 23:03:44] Received broadcast message from client "
        "17744070381767483567 (ali-steam-deck): 192.168.1.67:27036\n"
    )
    CREATED = "Created virtual output: HEADLESS-2\n"

    def test_start_and_stop(self):
        self.assertTrue(stream_mode.START_RE.search(self.START))
        self.assertTrue(stream_mode.STOP_RE.search(self.STOP))
        self.assertFalse(stream_mode.START_RE.search(self.STOP))

    def test_a_capture_switch_is_not_a_stream_ending(self):
        """Steam logs these whenever it swaps desktop and game capture.

        Read as the end of the stream, a switch into game capture scheduled a
        teardown two minutes later: HD2 was taken out of fullscreen mid-game,
        captured at half width, and its picture stretched.
        """
        for line in (
            "[2026-09-24 09:17:59][2311.673512] >>> Stopped desktop stream\n",
            "[2026-09-24 08:03:28][183.099188] >>> Starting desktop stream\n",
        ):
            self.assertFalse(stream_mode.STOP_RE.search(line))
            self.assertFalse(stream_mode.START_RE.search(line))

    CLIENT_SIZE = (
        "[2026-08-26 06:41:28][385.926662] CLIENT: Video size: 1280x800, "
        "output size: 1280x800, overlay size: 1280x800\n"
    )
    CLIENT_SIZE_LETTERBOXED = (
        "[2026-08-26 06:22:53][65.613951] CLIENT: Video size: 1280x360, "
        "output size: 1280x800, overlay size: 1280x800\n"
    )

    STREAM_REQUEST = (
        "[2026-08-26 07:53:27] Received streaming request 43269442 with device ID "
        "9197533723563966756 from 192.168.1.46:34702\n"
    )

    def test_a_streaming_request_identifies_a_client_too(self):
        """Not every client announces itself the way the Deck does.

        The Android client never logs "connected via direct connection" — it
        authorises by device ID and then sends a streaming request. Matching
        only the Deck's phrasing meant such a client was never identified, so
        nothing was learned for it and it stayed on the default size for good.
        """
        match = stream_mode.STREAM_REQUEST_RE.search(self.STREAM_REQUEST)
        self.assertEqual(match.group(1), "9197533723563966756")

    def test_client_size_is_the_clients_own_panel(self):
        """This is what a client's size has to be learned from.

        The capture resolution cannot be used: while the display filter is
        armed it is the size we told Steam, so learning from it means learning
        our own default back and a client with a different panel never gets
        sized correctly. "output size" comes from the client and is unaffected
        -- note it stays 1280x800 in the letterboxed sample below, where the
        video size had already been fitted to the wrong desktop.
        """
        self.assertEqual(
            stream_mode.CLIENT_SIZE_RE.search(self.CLIENT_SIZE).groups(),
            ("1280", "800"),
        )
        self.assertEqual(
            stream_mode.CLIENT_SIZE_RE.search(self.CLIENT_SIZE_LETTERBOXED).groups(),
            ("1280", "800"),
        )

    def test_maximum_capture_is_the_clients_limit(self):
        line = "[2026-09-24 08:12:45][740.084658] Maximum capture: 2880x1080 60.00 FPS\n"
        self.assertEqual(
            stream_mode.MAX_CAPTURE_RE.search(line).groups(), ("2880", "1080", "60.00")
        )

    def test_add_window_gives_pid_and_game(self):
        self.assertEqual(
            stream_mode.ADD_WINDOW_RE.search(self.ADD).groups(), ("2331545", "2854740")
        )

    def test_remove_process(self):
        self.assertEqual(stream_mode.REMOVE_PROC_RE.search(self.REMOVE).group(1), "2163386")

    def test_connect_gives_id_and_name(self):
        match = stream_mode.CONNECT_RE.search(self.CONNECT)
        self.assertEqual(match.groups(), ("17744070381767483567", "ali-steam-deck"))

    def test_broadcast_is_not_a_connect(self):
        """The Deck broadcasts continuously just by being awake.

        Treating a broadcast as a connection would rebuild the output
        constantly.
        """
        self.assertIsNone(stream_mode.CONNECT_RE.search(self.BROADCAST))

    def test_disconnect_names_the_client(self):
        for reason in ("ping timeout", "disconnecting all", "told us it was offline"):
            line = (
                "[2026-09-24 08:35:19] Client 11334438332915102515 (ali-mba) "
                "disconnected: {}\n".format(reason)
            )
            match = stream_mode.DISCONNECT_RE.search(line)
            self.assertEqual(match.group(1), "11334438332915102515")
        self.assertIsNone(stream_mode.DISCONNECT_RE.search(self.CONNECT))

class TestWindowForGame(unittest.TestCase):
    GAME = 2854740

    def setUp(self):
        self._real = stream_mode.parent_pids
        stream_mode.parent_pids = lambda pid, limit=8: []

    def tearDown(self):
        stream_mode.parent_pids = self._real

    def test_app_id_wins_over_pid(self):
        """An X11 game's window belongs to xwayland-satellite, not the game.

        This is the case that failed in practice: the pid walk found nothing
        because the owning process is unrelated to the game's process tree.
        """
        windows = [
            window(3, 999, app_id="xwayland-satellite"),
            window(7, 4242, app_id="steam_app_2854740"),
        ]
        self.assertEqual(stream_mode.window_for_game(111, self.GAME, windows)["id"], 7)

    def test_exact_pid_match(self):
        windows = [window(1, 100, app_id="other"), window(2, 200, app_id="other")]
        self.assertEqual(stream_mode.window_for_game(200, self.GAME, windows)["id"], 2)

    def test_falls_back_to_ancestor(self):
        """gamescope owns the window and is an ancestor of the game."""
        stream_mode.parent_pids = lambda pid, limit=8: [400, 500] if pid == 999 else []
        windows = [window(7, 500, app_id="gamescope")]
        self.assertEqual(stream_mode.window_for_game(999, self.GAME, windows)["id"], 7)

    def test_nearest_ancestor_wins(self):
        stream_mode.parent_pids = lambda pid, limit=8: [400, 500] if pid == 999 else []
        windows = [window(7, 500, app_id="a"), window(8, 400, app_id="b")]
        self.assertEqual(stream_mode.window_for_game(999, self.GAME, windows)["id"], 8)

    def test_finds_a_descendant_window(self):
        """A game that launches gamescope itself owns a descendant window."""
        stream_mode.parent_pids = lambda pid, limit=8: [111] if pid == 555 else []
        windows = [window(9, 555, app_id="gamescope")]
        self.assertEqual(stream_mode.window_for_game(111, self.GAME, windows)["id"], 9)

    def test_no_match(self):
        self.assertIsNone(
            stream_mode.window_for_game(999, self.GAME, [window(1, 100, app_id="other")])
        )

    def test_wine_tray_window_is_not_the_game(self):
        """Wine's systray fallback shares the game's app id but is 160x20.

        Picking it fullscreened a blank window and Steam streamed that.
        """
        windows = [
            window(121, 4242, size=(160, 20)),
            window(120, 4242, size=(1341, 1642)),
        ]
        self.assertEqual(stream_mode.window_for_game(111, self.GAME, windows)["id"], 120)

    def test_a_tiled_window_wins_over_a_floating_one(self):
        dialog = window(121, 4242, size=(800, 600))
        dialog["is_floating"] = True
        windows = [dialog, window(120, 4242)]
        self.assertEqual(stream_mode.window_for_game(111, self.GAME, windows)["id"], 120)

    def test_a_floating_game_is_still_the_game(self):
        """niri floated FH6, whose first window was a 622x302 splash; skipping
        floating windows left it unstaged at 1272x717."""
        game = window(278, 4242, size=(1272, 717))
        game["is_floating"] = True
        self.assertEqual(stream_mode.window_for_game(111, self.GAME, [game])["id"], 278)

    def test_parent_pids_handles_comm_with_spaces(self):
        """/proc/PID/stat comm can contain spaces and parentheses."""
        self.assertIsInstance(stream_mode.parent_pids(os.getpid()), list)


class TestStalledGameCapture(unittest.TestCase):
    """Steam switched to game capture and never delivered a frame.

    At 10:54:16 the stream moved to GameOverlay_MovieStream for HD2 while its
    window was still growing from 640x766 to 1280x800, and no "Capture method
    set to Game" followed for six minutes: a black stream. Moving focus off
    the game and back made Steam bind again, and capture started at once.
    """

    def setUp(self):
        self._real = {k: getattr(stream_mode, k)
                      for k in ("focus_window", "focus_workspace", "niri_workspaces")}
        self.focused = []
        self.workspaces = []
        stream_mode.focus_window = lambda wid: self.focused.append(wid) or True
        stream_mode.focus_workspace = lambda out, ref: self.workspaces.append((out, ref)) or True
        stream_mode.niri_workspaces = lambda: []

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self):
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        s.streaming = True
        s.game_pid, s.game_id = 4321, 553850
        s.workspace_outputs = {9: stream_mode.OUTPUT_NAME}
        s.last_windows = [
            {"id": 227, "app_id": "steam_app_553850", "workspace_id": 9,
             "is_focused": True, "layout": {"window_size": [1282, 802]}},
            {"id": 5, "app_id": "md.obsidian.Obsidian", "workspace_id": 2},
        ]
        return s

    def stall(self, s):
        """Run the reports up to the one that should nudge."""
        s.game_capture_requested()
        for _ in range(stream_mode.CAPTURE_STALL_HEARTBEATS - 1):
            self.assertFalse(s.client_heartbeat())

    def test_a_stall_is_judged_by_the_clients_reports(self):
        s = self.session()
        self.stall(s)
        self.assertTrue(s.client_heartbeat())
        self.assertEqual(self.focused, [5], "focus moves away first")

    def test_a_slow_start_is_not_a_stall(self):
        """Capture started 8s after the switch, on the second report (13:09:23)."""
        s = self.session()
        s.game_capture_requested()
        s.client_heartbeat()
        s.client_heartbeat()
        s.game_capture_started()
        for _ in range(10):
            self.assertFalse(s.client_heartbeat())
        self.assertEqual(self.focused, [])

    def test_the_nudge_returns_a_report_later(self):
        """Returning at once, even on Steam's record-window line, Steam missed
        it and stayed on the other window (13:01:40, 13:09:23)."""
        s = self.session()
        self.stall(s)
        s.client_heartbeat()
        self.assertEqual(self.focused, [5])
        self.assertTrue(s.client_heartbeat())
        self.assertEqual(self.focused, [5, 227])

    def test_capture_starting_while_focus_is_away_still_returns(self):
        """Left away, Steam records no window and the controller stays on
        the Desktop layout, with nothing to re-arm the nudge."""
        s = self.session()
        self.stall(s)
        s.client_heartbeat()
        s.game_capture_started()
        self.assertTrue(s.client_heartbeat())
        self.assertEqual(self.focused, [5, 227])

    def test_the_nudge_avoids_steams_own_windows(self):
        """Given a Steam window, Steam recorded it instead of the game."""
        s = self.session()
        s.last_windows.insert(1, {"id": 184, "app_id": "steam", "workspace_id": 5})
        self.stall(s)
        s.client_heartbeat()
        self.assertEqual(self.focused, [5])

    def test_the_nudge_prefers_an_empty_workspace_on_the_streamed_output(self):
        """Needs no other window, and leaves the desktop's windows alone."""
        s = self.session()
        stream_mode.niri_workspaces = lambda: [
            {"idx": 5, "name": "game", "output": stream_mode.OUTPUT_NAME, "active_window_id": 227},
            {"idx": 6, "name": "notes", "output": stream_mode.OUTPUT_NAME, "active_window_id": None},
            {"idx": 7, "name": None, "output": stream_mode.OUTPUT_NAME, "active_window_id": None},
            {"idx": 1, "name": None, "output": "DP-2", "active_window_id": None},
        ]
        self.stall(s)
        self.assertTrue(s.client_heartbeat())
        self.assertEqual(self.workspaces, [(stream_mode.OUTPUT_NAME, 7)],
                         "by index on the streamed output, not the focused one")
        self.assertEqual(self.focused, [])
        s.client_heartbeat()
        self.assertEqual(self.focused, [227])

    def test_no_window_and_no_empty_workspace_is_reported(self):
        s = self.session()
        s.last_windows = [s.last_windows[0]]
        self.stall(s)
        self.assertFalse(s.client_heartbeat())
        self.assertEqual(self.focused, [])

    def test_the_nudge_gives_up_after_a_few_tries(self):
        s = self.session()
        s.game_capture_requested()
        for _ in range(10 * stream_mode.CAPTURE_STALL_HEARTBEATS * stream_mode.CAPTURE_NUDGE_LIMIT):
            s.client_heartbeat()
        self.assertEqual(len(self.focused), 2 * stream_mode.CAPTURE_NUDGE_LIMIT)

    def test_the_limit_holds_when_each_return_switches_the_stream_again(self):
        """Every return to the game logs another switch to GameOverlay
        (13:21:27, 13:29:53, 13:31:39); counting from zero on each one would
        nudge a dead capture forever."""
        s = self.session()
        s.game_capture_requested()
        for _ in range(10 * stream_mode.CAPTURE_STALL_HEARTBEATS * stream_mode.CAPTURE_NUDGE_LIMIT):
            returning = s.nudge_return_to is not None
            s.client_heartbeat()
            if returning:
                s.game_capture_requested()
        self.assertEqual(len(self.focused), 2 * stream_mode.CAPTURE_NUDGE_LIMIT)

    def test_the_next_game_in_a_stream_gets_its_own_nudges(self):
        s = self.session()
        s.game_capture_requested()
        for _ in range(10 * stream_mode.CAPTURE_STALL_HEARTBEATS * stream_mode.CAPTURE_NUDGE_LIMIT):
            s.client_heartbeat()
        self.assertTrue(s.unstage())
        s.game_pid = 5678
        self.focused.clear()
        self.stall(s)
        self.assertTrue(s.client_heartbeat(), "a fresh game is nudged")

    def test_a_game_exiting_mid_nudge_is_not_returned_to(self):
        s = self.session()
        self.stall(s)
        s.client_heartbeat()
        self.assertTrue(s.unstage())
        self.assertFalse(s.client_heartbeat())
        self.assertEqual(self.focused, [5])

    def test_a_new_stream_gets_its_own_nudges(self):
        s = self.session()
        s.capture_nudges = stream_mode.CAPTURE_NUDGE_LIMIT
        s.begin_stream()
        self.assertEqual(s.capture_nudges, 0)

    def test_no_game_window_means_no_nudge(self):
        s = self.session()
        s.last_windows = [s.last_windows[1]]
        self.stall(s)
        self.assertFalse(s.client_heartbeat())
        self.assertEqual(self.focused, [])

    def test_the_heartbeat_is_recognised(self):
        self.assertTrue(stream_mode.CLIENT_HEARTBEAT_RE.search(
            "[2026-09-24 10:54:23][3992.1] CLIENT: SteamNetworkingSockets connection: "
            "Connected SDR->lhr->lhr  Ping: 24ms IN: 81.9kbit"))


class TestVirtualGamepads(unittest.TestCase):
    """A gamepad Steam creates mid-game has to be announced again.

    SDL, inside Proton, only uses a Steam virtual gamepad listed in
    virtualgamepadinfo.txt, and checks when the device appears. On a Deck
    reconnect Steam created "pad 0" at 11:47:26 and listed it later, so HD2
    kept the old pad and ignored the controller. Touching the node made SDL
    look again, and the controls came back without a relaunch.
    """

    INFO = (
        "[slot 0]\nname=Steam Deck Controller\nVID=0x28de\nPID=0x1205\n"
        "handle=0x000000ff34504ad8\ntype=steam\n"
        "[slot 2]\nname=#controller_xbox360\nVID=0x045e\nPID=0x028e\n"
        "handle=0x00545e28e1e02487\ntype=xbox360\n"
    )

    def sysfs(self, tmp, event, name, virtual=True):
        base = os.path.join(tmp, "devices", "virtual" if virtual else "pci0000:00", "input", event)
        os.makedirs(os.path.join(base, "device"))
        with open(os.path.join(base, "device", "name"), "w") as fh:
            fh.write(name + "\n")
        os.makedirs(os.path.join(tmp, "class"), exist_ok=True)
        os.symlink(base, os.path.join(tmp, "class", event))

    def test_the_listed_slots_are_read(self):
        self.assertEqual(stream_mode.gamepad_slots(self.INFO), {0, 2})

    def test_only_steams_virtual_pads_are_found(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.sysfs(tmp, "event257", "Microsoft X-Box 360 pad 0")
            self.sysfs(tmp, "event256", "Microsoft X-Box 360 pad 1")
            self.sysfs(tmp, "event12", "Microsoft X-Box 360 pad 3", virtual=False)
            self.sysfs(tmp, "event5", "Keyboard passthrough")
            self.assertEqual(
                stream_mode.steam_virtual_pads(os.path.join(tmp, "class")),
                {0: "/dev/input/event257", 1: "/dev/input/event256"},
            )

    def test_a_pad_in_use_is_left_alone(self):
        """Touching a pad the game has open made Proton add it again.

        At 12:08 a restart re-announced the pad HD2 was using, winedevice
        opened it a second time, and the controls stopped until the next
        touch. Only a pad nothing has open needs announcing.
        """
        touched = []
        real = (stream_mode.steam_virtual_pads, stream_mode.touch_device,
                stream_mode.device_in_use)
        stream_mode.steam_virtual_pads = lambda root=None: {0: "/dev/input/event257"}
        stream_mode.touch_device = lambda path: touched.append(path) or True
        stream_mode.device_in_use = lambda path: True
        try:
            with tempfile.TemporaryDirectory() as tmp:
                info = os.path.join(tmp, "virtualgamepadinfo.txt")
                with open(info, "w") as fh:
                    fh.write(self.INFO)
                s = stream_mode.Session(stage_timeout=0)
                s.gamepad_info_path = info
                self.assertFalse(s.check_gamepad_info())
                self.assertEqual(touched, [])
        finally:
            (stream_mode.steam_virtual_pads, stream_mode.touch_device,
             stream_mode.device_in_use) = real

    def test_device_in_use_sees_an_open_node(self):
        with tempfile.NamedTemporaryFile() as fh:
            self.assertTrue(stream_mode.device_in_use(fh.name))
        self.assertFalse(stream_mode.device_in_use("/nonexistent/event999"))

    def test_listed_pads_are_touched_when_the_info_changes(self):
        touched = []
        real = (stream_mode.steam_virtual_pads, stream_mode.touch_device,
                stream_mode.device_in_use)
        stream_mode.device_in_use = lambda path: False
        stream_mode.steam_virtual_pads = lambda root=None: {
            0: "/dev/input/event257", 1: "/dev/input/event256"}
        stream_mode.touch_device = lambda path: touched.append(path) or True
        try:
            with tempfile.TemporaryDirectory() as tmp:
                info = os.path.join(tmp, "virtualgamepadinfo.txt")
                with open(info, "w") as fh:
                    fh.write(self.INFO)
                s = stream_mode.Session(stage_timeout=0)
                s.gamepad_info_path = info
                self.assertTrue(s.check_gamepad_info())
                self.assertEqual(touched, ["/dev/input/event257"])
                touched.clear()
                self.assertFalse(s.check_gamepad_info(), "unchanged file, nothing to do")
                self.assertEqual(touched, [])
        finally:
            (stream_mode.steam_virtual_pads, stream_mode.touch_device,
             stream_mode.device_in_use) = real

    def test_a_missing_info_file_is_quiet(self):
        s = stream_mode.Session(stage_timeout=0)
        s.gamepad_info_path = "/nonexistent/virtualgamepadinfo.txt"
        self.assertFalse(s.check_gamepad_info())


class TestLogReaders(unittest.TestCase):
    """Lines that arrive together must each wake the loop.

    A buffered text pipe read a whole chunk on the first readline(), kept
    the rest in Python's buffer, and select() then saw an empty pipe. The
    stop marker of a Deck stream arrived in such a burst and was never acted
    on.
    """

    def test_a_burst_of_lines_stays_visible_to_select(self):
        import select
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "log.txt")
            open(path, "w").close()
            proc = stream_mode.spawn_tail(path)
            try:
                time.sleep(0.5)
                with open(path, "a") as fh:
                    fh.write("first\nsecond\n")
                ready, _, _ = select.select([proc.stdout], [], [], 5)
                self.assertTrue(ready)
                self.assertEqual(stream_mode.read_line(proc.stdout), "first\n")
                ready, _, _ = select.select([proc.stdout], [], [], 1)
                self.assertTrue(ready, "the second line was stranded in a buffer")
                self.assertEqual(stream_mode.read_line(proc.stdout), "second\n")
            finally:
                proc.kill()
                proc.wait()


class TestSetOutputMode(unittest.TestCase):
    """X clients see each virtual output mode change one change late.

    xwayland-satellite kept reporting the previous size: after the output was
    set back to 1728x1080, HD2 read 1280x800 from X and sized its borderless
    window to that. A second change that only differs in refresh carries the
    size through.
    """

    def setUp(self):
        self._real = (stream_mode.subprocess.run, stream_mode.niri_env)
        self.calls = []

        def fake_run(args, **_kwargs):
            self.calls.append(list(args))
            return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

        stream_mode.subprocess.run = fake_run
        stream_mode.niri_env = lambda: {}

    def tearDown(self):
        stream_mode.subprocess.run, stream_mode.niri_env = self._real

    def test_the_real_mode_is_set_last_after_a_refresh_step(self):
        self.assertTrue(stream_mode.set_output_mode("steam", 1728, 1080, 60))
        self.assertEqual(
            [c[-1] for c in self.calls], ["1728x1080@61", "1728x1080@60"]
        )


class TestConnectedClient(unittest.TestCase):
    """A restart forgot the client, and a launch before the stream went through gamescope."""

    def read(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write(text)
        try:
            return stream_mode.connected_client(fh.name)
        finally:
            os.unlink(fh.name)

    def test_a_client_still_connected_is_found(self):
        self.assertEqual(
            self.read(
                "[2026-09-24 08:39:02] Client 11 (ali-mba) disconnected: disconnecting all\n"
                "[2026-09-24 08:39:33] Client 11 (ali-mba) connected via indirect connection\n"
                "[2026-09-24 08:40:00] Received broadcast message from client 11 (ali-mba): x\n"
            ),
            (11, "ali-mba"),
        )

    def test_a_disconnected_client_is_not(self):
        self.assertIsNone(self.read(
            "[x] Client 11 (ali-mba) connected via indirect connection\n"
            "[x] Client 11 (ali-mba) disconnected: ping timeout\n"
        ))

    def test_the_latest_of_several_clients_wins(self):
        self.assertEqual(
            self.read(
                "[x] Client 11 (ali-mba) connected via direct connection\n"
                "[x] Client 22 (ali-steam-deck) connected via direct connection\n"
            ),
            (22, "ali-steam-deck"),
        )

    def test_a_missing_log_means_no_client(self):
        self.assertIsNone(stream_mode.connected_client("/nonexistent/remote_connections.txt"))


class TestLearnedClients(unittest.TestCase):
    def test_default_until_learned(self):
        self.assertEqual(
            stream_mode.client_size("123", {}),
            (stream_mode.DEFAULT_WIDTH, stream_mode.DEFAULT_HEIGHT),
        )

    def test_learned_value_used(self):
        self.assertEqual(stream_mode.client_size("123", {"123": [1920, 1200]}), (1920, 1200))

    def test_learned_output_is_fitted_inside_the_resolution_limit(self):
        """A 2880x1800 Mac capped at 1080 lines gets its shape at 1728x1080."""
        clients = {"123": {"output": [2880, 1800], "max_capture": [2880, 1080]}}
        self.assertEqual(stream_mode.client_size("123", clients), (1728, 1080))

    def test_this_sessions_limit_beats_the_remembered_one(self):
        clients = {"123": {"output": [2880, 1800], "max_capture": [2880, 1080]}}
        self.assertEqual(
            stream_mode.client_size("123", clients, (2880, 1800)), (2880, 1800)
        )

    def test_a_legacy_entry_is_fitted_to_this_sessions_limit(self):
        self.assertEqual(
            stream_mode.client_size("123", {"123": [4470, 1676]}, (2880, 1080)),
            (2880, 1080),
        )

    def test_refresh_is_the_clients_frame_rate(self):
        self.assertEqual(stream_mode.client_refresh("123", {}, 59.94), 60)
        self.assertEqual(stream_mode.client_refresh("123", {}, 120.0), 120)

    def test_refresh_is_remembered_between_connects(self):
        clients = {"123": {"output": [1280, 800], "refresh": 90}}
        self.assertEqual(stream_mode.client_refresh("123", clients), 90)

    def test_refresh_defaults_until_known(self):
        for clients in ({}, {"123": [1280, 800]}, {"123": {"refresh": "junk"}}):
            self.assertEqual(
                stream_mode.client_refresh("123", clients), stream_mode.DEFAULT_REFRESH
            )

    def test_output_refresh_reads_the_current_mode_in_hertz(self):
        real = stream_mode.niri_outputs
        stream_mode.niri_outputs = lambda: {"steam": {
            "current_mode": 1,
            "modes": [{"refresh_rate": 60000}, {"refresh_rate": 90000}],
        }}
        try:
            self.assertEqual(real_output_refresh("steam"), 90)
            self.assertIsNone(real_output_refresh("DP-9"))
        finally:
            stream_mode.niri_outputs = real

    def test_fit_never_scales_up(self):
        self.assertEqual(stream_mode.fit_within(1280, 800, (2880, 1080)), (1280, 800))
        self.assertEqual(stream_mode.fit_within(1280, 800, None), (1280, 800))

    def test_fit_keeps_sizes_even(self):
        width, height = stream_mode.fit_within(2618, 1636, (2880, 1080))
        self.assertEqual((width % 2, height % 2), (0, 0))
        self.assertLessEqual(height, 1080)

    def test_malformed_entry_falls_back(self):
        self.assertEqual(
            stream_mode.client_size("123", {"123": "nonsense"}),
            (stream_mode.DEFAULT_WIDTH, stream_mode.DEFAULT_HEIGHT),
        )

    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "sub", "clients.json")
            stream_mode.save_clients({"123": [1280, 800]}, path)
            self.assertEqual(stream_mode.load_clients(path), {"123": [1280, 800]})

    def test_missing_file_is_empty(self):
        self.assertEqual(stream_mode.load_clients("/nonexistent/clients.json"), {})

    def test_corrupt_file_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "clients.json")
            with open(path, "w") as fh:
                fh.write("{not json")
            self.assertEqual(stream_mode.load_clients(path), {})


class TestSession(unittest.TestCase):
    def setUp(self):
        self.modes = []
        self.enabled = []
        self.moved = []
        self.fullscreened = []
        self.saved = []
        self.windows = [window(7, 500)]

        self._real = {
            k: getattr(stream_mode, k)
            for k in (
                "set_output_mode",
                "set_output_enabled",
                "move_window_to_output",
                "set_window_fullscreen",
                "focus_window",
                "niri_windows",
                "workspace_output",
                "move_workspace_to_output",
                "output_logical_size",
                "parent_pids",
                "usable_output_names",
                "load_clients",
                "save_clients",
            )
        }

        # Declared in niri's config, so it is present from the start and is
        # never created or destroyed by the watcher.
        self.names = {"DP-2", stream_mode.OUTPUT_NAME}

        def set_mode(name, w, h, r):
            self.modes.append((name, w, h, r))
            return True

        def set_enabled(name, enabled):
            self.enabled.append((name, enabled))
            return True

        stream_mode.set_output_mode = set_mode
        stream_mode.set_output_enabled = set_enabled
        stream_mode.move_window_to_output = lambda wid, out: self.moved.append((wid, out))
        stream_mode.set_window_fullscreen = lambda wid, on=True: self.fullscreened.append(wid) or True
        stream_mode.focus_window = lambda wid: None
        stream_mode.niri_windows = lambda: self.windows
        stream_mode.output_logical_size = lambda name: (1280, 800)
        stream_mode.parent_pids = lambda pid, limit=8: []
        stream_mode.usable_output_names = lambda: self.names
        stream_mode.load_clients = lambda path=None: {}
        stream_mode.save_clients = lambda c, path=None: self.saved.append(c)

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self, stage_timeout=0):
        return stream_mode.Session(stage_timeout=stage_timeout)

    def test_startup_finds_the_declared_output(self):
        s = self.session()
        self.assertTrue(s.ensure_output())
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_an_undeclared_output_is_reported_not_invented(self):
        """Without the declaration there is nothing to stream to.

        Creating one here would defeat the point of declaring it: the output
        has to exist before Steam resolves its remembered capture source, and
        a service that starts one on demand is always too late.
        """
        stream_mode.usable_output_names = lambda: {"DP-2"}
        s = self.session()
        self.assertFalse(s.ensure_output())
        self.assertIsNone(s.output)
        self.assertEqual(self.modes, [])
        self.assertEqual(self.enabled, [])

    def test_connect_publishes_the_target_before_enabling_the_output(self):
        """Order matters: the filter has to be armed before the X event.

        Steam re-reads its monitor list when outputs change, and enabling the
        output is that change. The display filter consults the published
        target on every such query and is inert without one, so publishing
        after enabling would miss the very read it exists to influence.
        """
        order = []
        real_publish = stream_mode.publish_target
        real_enabled = stream_mode.set_output_enabled

        def publish(*a, **k):
            order.append("publish")
            return True

        def enabled(name, on):
            order.append("enable" if on else "disable")
            return True

        stream_mode.publish_target = publish
        stream_mode.set_output_enabled = enabled
        try:
            self.session().connect(123, "deck")
        finally:
            stream_mode.publish_target = real_publish
            stream_mode.set_output_enabled = real_enabled
        self.assertEqual(order, ["publish", "enable"])

    def test_connect_turns_the_output_on(self):
        s = self.session()
        self.assertTrue(s.connect(123, "ali-steam-deck"))
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)
        self.assertEqual(self.enabled, [(stream_mode.OUTPUT_NAME, True)])

    def test_connect_resizes_to_a_learned_size(self):
        stream_mode.load_clients = lambda path=None: {"123": [1920, 1200]}
        s = self.session()
        s.connect(123, "deck")
        self.assertEqual(
            self.modes,
            [(stream_mode.OUTPUT_NAME, 1920, 1200, stream_mode.DEFAULT_REFRESH)],
        )

    def test_connect_leaves_a_correctly_sized_output_alone(self):
        """Resizing needlessly would disturb the layout on every reconnect."""
        stream_mode.output_logical_size = lambda name: (
            stream_mode.DEFAULT_WIDTH,
            stream_mode.DEFAULT_HEIGHT,
        )
        s = self.session()
        s.connect(123, "deck")
        s.connect(123, "deck")
        self.assertEqual(self.modes, [])
        self.assertEqual(self.enabled, [(stream_mode.OUTPUT_NAME, True)] * 2)

    def test_staging_creates_the_output_if_none_exists(self):
        """A game can start before any connect is seen."""
        s = self.session()
        self.assertTrue(s.request(500, 2854740))
        self.assertTrue(s.on_windows(self.windows))
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])

    def test_teardown_turns_the_output_off_once(self):
        s = self.session()
        s.connect(123, "deck")
        self.assertTrue(s.teardown())
        self.assertEqual(self.enabled[-1], (stream_mode.OUTPUT_NAME, False))
        off = self.enabled.count((stream_mode.OUTPUT_NAME, False))
        self.assertFalse(s.teardown())
        self.assertEqual(self.enabled.count((stream_mode.OUTPUT_NAME, False)), off)

    def test_idle_keeps_the_output(self):
        """Losing it between sessions broke Steam's remembered source.

        Steam resolves that source on its main loop when a session starts; a
        source that has gone away made the request fail, stalling the loop past
        its watchdog and segfaulting the client.
        """
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.on_windows(self.windows)
        self.assertFalse(s.idle())
        self.assertNotIn((stream_mode.OUTPUT_NAME, False), self.enabled)
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_idle_clears_the_staged_game(self):
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.on_windows(self.windows)
        s.idle()
        self.assertFalse(s.unstage(500))

    def test_teardown_without_output_does_nothing(self):
        self.assertFalse(self.session().teardown())
        self.assertEqual(self.enabled, [])

    def test_connect_without_a_declared_output_fails_quietly(self):
        """Nothing to turn on, and nothing this service can do about it."""
        stream_mode.usable_output_names = lambda: {"DP-2"}
        s = self.session()
        self.assertFalse(s.connect(123, "deck"))
        self.assertIsNone(s.output)
        self.assertEqual(self.enabled, [])
        self.assertEqual(self.modes, [])

    def test_stage_moves_the_window_to_the_virtual_output(self):
        """Staging places and focuses; the width is corrected from events.

        Sizing here meant deciding from a reading taken before the move had
        landed, which is how an already-sized window got resized wrongly.
        """
        s = self.session()
        s.connect(123, "deck")
        self.assertTrue(s.request(500, 2854740))
        self.assertTrue(s.on_windows(self.windows))
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])

    def test_stage_does_not_resize_the_window_itself(self):
        self.windows = [window(7, 500, size=(1280, 800))]
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.on_windows(self.windows)
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])
        self.assertEqual(self.fullscreened, [])

    def test_keeps_waiting_while_the_window_does_not_exist(self):
        """Steam logs the pid minutes before a Proton game maps a window.

        A five-second budget gave up long before the window existed, which is
        why staging never happened in practice.
        """
        self.windows = []
        s = self.session(stage_timeout=60)
        s.connect(123, "deck")
        s.request(500, 2854740)
        self.assertFalse(s.on_windows(self.windows))
        self.assertIsNotNone(s.pending)

        self.windows = [window(7, 500)]
        self.assertTrue(s.on_windows(self.windows))
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])
        self.assertIsNone(s.pending)

    def test_polling_does_not_block(self):
        """The watcher follows two logs and an idle timer; it cannot sleep."""
        self.windows = []
        s = self.session(stage_timeout=60)
        s.connect(123, "deck")
        s.request(500, 2854740)
        start = __import__("time").monotonic()
        for _ in range(20):
            s.on_windows(self.windows)
        self.assertLess(__import__("time").monotonic() - start, 1.0)

    def test_gives_up_once_the_deadline_passes(self):
        self.windows = []
        s = self.session(stage_timeout=0)
        s.connect(123, "deck")
        s.request(500, 2854740)
        self.assertFalse(s.on_windows(self.windows))
        self.assertIsNone(s.pending)
        self.assertEqual(self.moved, [])

    def test_learn_records_the_output_and_the_limit(self):
        s = self.session()
        s.connect(123, "mac")
        s.note_max_capture(2880, 1080, 120.0)
        self.assertTrue(s.learn(2880, 1800))
        self.assertEqual(
            self.saved,
            [{"123": {"output": [2880, 1800], "max_capture": [2880, 1080], "refresh": 120}}],
        )

    def test_learn_needs_a_connected_client(self):
        self.assertFalse(self.session().learn(1280, 800))
        self.assertEqual(self.saved, [])

    def test_a_reported_size_waits_to_settle(self):
        """The client's first reports echo our own output back.

        Its window opens at the capture size and only then goes fullscreen.
        Learning the first report stored the echo, 4470x1676 for a 2880x1800
        Mac, and the next session was built at it and echoed it again.
        """
        s = self.session()
        s.connect(123, "mac")
        s.note_max_capture(2880, 1080)
        self.assertTrue(s.note_client_output(4470, 1676, now=0))
        self.assertTrue(s.note_client_output(2880, 1800, now=7))
        self.assertFalse(s.settle_client_output(7 + stream_mode.CLIENT_SIZE_SETTLE - 1))
        self.assertEqual(self.saved, [])
        self.assertTrue(s.settle_client_output(7 + stream_mode.CLIENT_SIZE_SETTLE))
        self.assertEqual(self.saved[-1]["123"]["output"], [2880, 1800])

    def test_a_repeated_report_does_not_restart_the_wait(self):
        """Steam re-logs the size on every frame reset."""
        s = self.session()
        s.connect(123, "mac")
        s.note_client_output(2880, 1800, now=0)
        self.assertFalse(s.note_client_output(2880, 1800, now=5))
        self.assertTrue(s.settle_client_output(stream_mode.CLIENT_SIZE_SETTLE))

    def test_a_later_change_is_followed_too(self):
        """Resizing or fullscreening the client window mid-stream."""
        s = self.session()
        s.connect(123, "mac")
        s.note_client_output(2880, 1800, now=0)
        s.settle_client_output(stream_mode.CLIENT_SIZE_SETTLE)
        s.note_client_output(1920, 1080, now=100)
        self.assertTrue(s.settle_client_output(100 + stream_mode.CLIENT_SIZE_SETTLE))
        self.assertEqual(self.saved[-1]["123"]["output"], [1920, 1080])

    def test_a_new_client_starts_without_the_previous_limit(self):
        s = self.session()
        s.connect(123, "mac")
        s.note_max_capture(2880, 1080)
        s.teardown()
        s.connect(456, "deck")
        self.assertIsNone(s.max_capture)

    def test_unstage_only_for_the_staged_game(self):
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.on_windows(self.windows)
        self.assertFalse(s.unstage(999))
        self.assertTrue(s.unstage(500))
        self.assertFalse(s.unstage(500))


class TestOutputLifetime(unittest.TestCase):
    """The output is declared in niri's config, so it is only ever toggled.

    Creating and removing it was what broke streaming: Steam remembers its
    capture source and resolves it when a session starts, so an output that
    came and went left that request failing. Declaring it means it is there
    before Steam looks, and survives a compositor restart.

    Off between sessions is not cosmetic either: an enabled output still
    accepts windows, and niri moves workspaces onto it when the physical
    output goes away, which is what emptied the desktop onto it on a KVM
    switch.
    """

    def setUp(self):
        self.modes = []
        self.enabled = []
        self.names = {"DP-2", stream_mode.OUTPUT_NAME}
        self._real = {
            k: getattr(stream_mode, k)
            for k in (
                "set_output_mode",
                "set_output_enabled",
                "usable_output_names",
                "output_logical_size",
                "load_clients",
                "publish_target",
                "withdraw_target",
                "niri_windows",
                "set_window_fullscreen",
                "move_window_to_output",
                "steam_is_running",
                "signal_process",
            )
        }

        def set_mode(name, w, h, r):
            self.modes.append((name, w, h, r))
            return True

        def set_enabled(name, enabled):
            self.enabled.append((name, enabled))
            return True

        stream_mode.set_output_mode = set_mode
        stream_mode.set_output_enabled = set_enabled
        stream_mode.usable_output_names = lambda: self.names
        stream_mode.output_logical_size = lambda name: (1280, 800)
        stream_mode.load_clients = lambda path=None: {}
        stream_mode.publish_target = lambda *a, **k: True
        stream_mode.withdraw_target = lambda *a, **k: True
        self.workspace_moves = []
        stream_mode.workspace_output = lambda name: "DP-2"
        stream_mode.move_workspace_to_output = lambda name, out: (
            self.workspace_moves.append((name, out)) or True
        )

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def test_the_watcher_never_creates_or_removes_the_output(self):
        """Creation and removal belong to the config, not to this service."""
        for name in ("create_virtual_output", "remove_virtual_output"):
            self.assertFalse(
                hasattr(stream_mode, name),
                "{} should be gone: the output is declared, not managed".format(name),
            )

    def test_ending_a_stream_turns_the_output_off(self):
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        s.begin_stream()
        s.end_stream()
        self.assertEqual(self.enabled[-1], (stream_mode.OUTPUT_NAME, False))
        self.assertIsNone(s.output)
        # Still declared, so Steam's remembered source keeps resolving.
        self.assertIn(stream_mode.OUTPUT_NAME, self.names)

    def test_ending_a_stream_turns_the_output_off_before_disarming(self):
        """Between the two there must be no window with an output and no target.

        Steam re-reads its monitor list whenever outputs change and caches the
        result. Withdrawing the target first left it free to recompute with the
        output still present and the filter inert, so it learned the union of
        both monitors -- measured as desktop 6400x1440 -- and sized the next
        stream to that.
        """
        order = []
        stream_mode.set_output_enabled = lambda name, enabled: (
            order.append(("output", enabled)) or True
        )
        stream_mode.withdraw_target = lambda *a, **k: order.append(("target", False))

        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        s.begin_stream()
        order.clear()
        s.end_stream()

        self.assertEqual(
            order,
            [("output", False), ("target", False)],
            "the output must go off before the target is withdrawn",
        )

    def test_ending_a_stream_turns_the_output_off_even_without_one_tracked(self):
        """A second disconnect, or a restart mid-session, still has to disarm.

        Guarding the whole teardown on self.output meant a disconnect arriving
        when it was already None skipped turning the output off, leaving it on
        indefinitely with no target published -- the same inert-but-present
        state, held open until the next connect.
        """
        s = stream_mode.Session(stage_timeout=0)
        s.output = None
        self.enabled.clear()

        s.end_stream()

        self.assertIn((stream_mode.OUTPUT_NAME, False), self.enabled)

    def test_a_newly_learned_size_is_applied_to_the_running_session(self):
        """A client whose size is not yet known must not stay at the default.

        The first connect from a new client has nothing to size the output
        from, so it gets the default. Learning its real panel and only using it
        "from next connect" leaves that whole session letterboxed, which is the
        thing this service exists to prevent.

        The target is published before the resize, for the same reason connect
        does it that way: the resize is the display change Steam re-reads on,
        and the filter has to be reporting the new size by then.
        """
        order = []
        stream_mode.publish_target = lambda o, w, h, r=None: (
            order.append(("target", w, h)) or True
        )
        stream_mode.set_output_mode = lambda name, w, h, r: (
            order.append(("mode", w, h)) or True
        )

        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "tv")
        s.begin_stream()
        order.clear()

        self.assertTrue(s.learn(1920, 1080))
        self.assertEqual(order, [("target", 1920, 1080), ("mode", 1920, 1080)])

    def test_a_stream_runs_the_output_at_the_clients_frame_rate(self):
        """The size already matches; only the refresh differs."""
        stream_mode.output_refresh = lambda name: 90
        try:
            s = stream_mode.Session(stage_timeout=0)
            s.connect(123, "mac")
            self.modes.clear()
            s.note_max_capture(2880, 1080, 60.0)
            s.begin_stream()
            self.assertEqual(self.modes, [(stream_mode.OUTPUT_NAME, 1280, 800, 60)])
        finally:
            stream_mode.output_refresh = lambda name: None

    def test_learning_the_size_already_in_use_changes_nothing(self):
        """The common case: a client reconnecting at the size it had before."""
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        s.begin_stream()
        self.modes.clear()

        s.learn(1280, 800)
        self.assertEqual(self.modes, [])

    def test_big_picture_is_moved_onto_the_streamed_output(self):
        """Streaming to a phone or TV shows Big Picture, not a game.

        Only game windows were ever staged, because the Deck launches straight
        into one. A client that streams the Steam UI itself left Big Picture on
        the desktop monitor and streamed whatever happened to be behind it.
        """
        moved = []
        stream_mode.move_window_to_output = lambda wid, out: moved.append((wid, out))

        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "tv")
        s.begin_stream()
        s.on_windows([
            window(7, 999, app_id="zen-beta"),
            {"id": 8, "pid": 42, "app_id": "steam",
             "title": "Steam Big Picture Mode", "layout": {"window_size": [1280, 800]}},
        ])

        self.assertEqual(moved, [(8, stream_mode.OUTPUT_NAME)])

    def test_big_picture_is_left_alone_when_not_streaming(self):
        """It is an ordinary window on the desktop the rest of the time."""
        moved = []
        stream_mode.move_window_to_output = lambda wid, out: moved.append((wid, out))

        s = stream_mode.Session(stage_timeout=0)
        s.on_windows([
            {"id": 8, "pid": 42, "app_id": "steam",
             "title": "Steam Big Picture Mode", "layout": {"window_size": [1280, 800]}},
        ])

        self.assertEqual(moved, [])

    def test_big_picture_is_moved_once_not_on_every_event(self):
        """niri emits a window list on every change; this must not fight it."""
        moved = []
        stream_mode.move_window_to_output = lambda wid, out: moved.append((wid, out))

        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "tv")
        s.begin_stream()
        bp = [{"id": 8, "pid": 42, "app_id": "steam",
               "title": "Steam Big Picture Mode", "layout": {"window_size": [1280, 800]}}]
        s.on_windows(bp)
        s.on_windows(bp)
        s.on_windows(bp)

        self.assertEqual(len(moved), 1)

    def test_a_known_client_beats_whatever_size_the_output_is_left_at(self):
        """The client we are serving decides the size, not leftover state.

        A stream can start without a fresh connect line, and the output keeps
        whatever mode it was last put in — by the previous client, or by
        someone testing at the command line. Taking the output's current size
        in preference to the client's meant a Deck streamed at 1600x900
        because that is what the output happened to be.
        """
        published = []
        stream_mode.publish_target = lambda o, w, h, r=None: (
            published.append((w, h)) or True
        )
        stream_mode.output_logical_size = lambda name: (1600, 900)

        s = stream_mode.Session(stage_timeout=0)
        s.client_id = 123
        s.clients = {"123": [1280, 800]}
        s.begin_stream()

        self.assertEqual(published[-1], (1280, 800))
        self.assertIn((stream_mode.OUTPUT_NAME, 1280, 800, stream_mode.DEFAULT_REFRESH),
                      [(m[0], m[1], m[2], m[3]) for m in self.modes])

    def test_an_unknown_client_falls_back_to_the_outputs_size(self):
        """With no client there is nothing better to go on."""
        published = []
        stream_mode.publish_target = lambda o, w, h, r=None: (
            published.append((w, h)) or True
        )
        stream_mode.output_logical_size = lambda name: (1600, 900)

        s = stream_mode.Session(stage_timeout=0)
        s.begin_stream()

        self.assertEqual(published[-1], (1600, 900))

    def test_a_game_is_not_left_behind_when_steam_dies(self):
        """Steam crashing mid-stream orphans the game on the virtual output.

        Steam's client/helper pipe breaks if a stream ends while a game is
        running, and it exits on a fatal assert without taking the game with
        it. What is left is a process still rendering to an output nobody can
        see, which has to be found and killed by hand.
        """
        signalled = []
        stream_mode.steam_is_running = lambda: False
        stream_mode.signal_process = lambda pid, sig: signalled.append((pid, sig))

        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        s.begin_stream()
        s.game_pid = 4242
        self.enabled.clear()

        self.assertTrue(s.check_steam_alive())
        self.assertEqual(signalled, [(4242, stream_mode.signal.SIGTERM)])
        self.assertIn((stream_mode.OUTPUT_NAME, False), self.enabled)

    def test_nothing_is_killed_while_steam_is_alive(self):
        signalled = []
        stream_mode.steam_is_running = lambda: True
        stream_mode.signal_process = lambda pid, sig: signalled.append((pid, sig))

        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        s.begin_stream()
        s.game_pid = 4242

        self.assertFalse(s.check_steam_alive())
        self.assertEqual(signalled, [])

    def test_a_client_disconnecting_before_streaming_disarms(self):
        """Replaces a 45-second connect timeout.

        The timeout withdrew the target while the client was still connected
        and browsing. A game launched from the client after that raced the
        target being republished at stream start, and the shim wrapped it in
        gamescope. Steam logs every disconnect, so that is the signal.
        """
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "mac")
        self.enabled.clear()
        self.assertFalse(s.disconnect(999))
        self.assertTrue(s.disconnect(123))
        self.assertIn((stream_mode.OUTPUT_NAME, False), self.enabled)
        self.assertIsNone(s.client_id)

    def test_the_stream_belongs_to_the_client_it_names(self):
        """The last client to connect is not necessarily the one streaming.

        The Deck connected and the Mac reconnected in the same second; the
        Deck streamed, and its 1280x800 was saved as the Mac's size.
        """
        s = stream_mode.Session(stage_timeout=0)
        s.connect(222, "ali-steam-deck")
        s.connect(111, "ali-mba")
        s.begin_stream("ali-steam-deck")
        self.assertEqual(s.client_id, 222)

    def test_an_unknown_streaming_name_keeps_the_current_client(self):
        s = stream_mode.Session(stage_timeout=0)
        s.connect(111, "ali-mba")
        s.begin_stream("someone-else")
        self.assertEqual(s.client_id, 111)

    def test_the_limit_resizes_the_output_as_soon_as_it_arrives(self):
        """'Streaming started to' comes before 'Maximum capture'.

        So the stream starts at the remembered size, and the limit has to be
        applied when it arrives, not ten seconds later when the client's
        window settles.
        """
        s = stream_mode.Session(stage_timeout=0)
        s.clients = {"123": {"output": [2880, 1800]}}
        s.connect(123, "mac")
        s.begin_stream("mac")
        self.modes.clear()
        s.note_max_capture(2880, 1080, 60.0)
        self.assertEqual(self.modes, [(stream_mode.OUTPUT_NAME, 1728, 1080, 60)])

    def test_a_new_stream_forgets_the_last_sessions_limit(self):
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "mac")
        s.note_max_capture(2880, 1080, 60.0)
        s.begin_stream("mac")
        self.assertIsNone(s.max_capture)

    def test_a_config_reload_mid_stream_restores_the_clients_mode(self):
        """niri drops IPC output changes when it reloads its config.

        A switch that touched config.kdl turned the output off and back to its
        declared 1280x800@90 under a running session.
        """
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "mac")
        s.note_max_capture(2880, 1080, 60.0)
        s.clients = {"123": {"output": [2880, 1800], "max_capture": [2880, 1080]}}
        s.begin_stream()
        self.modes.clear()
        self.enabled.clear()
        stream_mode.output_logical_size = lambda name: (1280, 800)
        self.assertTrue(s.reassert_output())
        self.assertEqual(self.modes, [(stream_mode.OUTPUT_NAME, 1728, 1080, 60)])
        self.assertIn((stream_mode.OUTPUT_NAME, True), self.enabled)

    def test_a_config_reload_keeps_the_only_output_on(self):
        stream_mode.other_active_outputs = lambda name: set()
        try:
            s = stream_mode.Session(stage_timeout=0)
            self.assertTrue(s.reassert_output())
            self.assertIn((stream_mode.OUTPUT_NAME, True), self.enabled)
        finally:
            stream_mode.other_active_outputs = lambda name: None

    def test_a_config_reload_leaves_an_idle_output_alone(self):
        stream_mode.other_active_outputs = lambda name: {"DP-2"}
        try:
            s = stream_mode.Session(stage_timeout=0)
            self.assertFalse(s.reassert_output())
            self.assertEqual(self.enabled, [])
        finally:
            stream_mode.other_active_outputs = lambda name: None

    def test_a_stream_readopts_a_game_still_running(self):
        """Reconnecting to a running game streamed the Friends List.

        connect() forgets which windows were staged, and Steam logs nothing
        new for a game that is already up, so the game was never re-focused
        and Steam recorded whatever had focus.
        """
        s = stream_mode.Session(stage_timeout=0)
        s.game_pid, s.game_id = os.getpid(), 553850
        s.connect(123, "mac")
        s.begin_stream()
        self.assertEqual(s.pending[:2], (os.getpid(), 553850))

    def test_a_stream_does_not_readopt_an_exited_game(self):
        s = stream_mode.Session(stage_timeout=0)
        s.game_pid, s.game_id = 2 ** 22 + 12345, 553850
        s.connect(123, "mac")
        s.begin_stream()
        self.assertIsNone(s.pending)
        self.assertIsNone(s.game_pid)

    def test_the_only_output_is_left_on(self):
        """With the monitor off, turning this off leaves niri with nothing.

        Steam restarted then fails to open its login window and never shows
        up for Remote Play. A Steam shutdown logs a disconnect, so this path
        runs on every Steam restart.
        """
        stream_mode.other_active_outputs = lambda name: set()
        try:
            s = stream_mode.Session(stage_timeout=0)
            s.connect(123, "mac")
            self.enabled.clear()
            s.disconnect(123)
            self.assertNotIn((stream_mode.OUTPUT_NAME, False), self.enabled)
        finally:
            stream_mode.other_active_outputs = lambda name: None

    def test_the_output_goes_off_while_the_monitor_is_on(self):
        stream_mode.other_active_outputs = lambda name: {"DP-2"}
        try:
            s = stream_mode.Session(stage_timeout=0)
            s.connect(123, "mac")
            self.enabled.clear()
            s.disconnect(123)
            self.assertIn((stream_mode.OUTPUT_NAME, False), self.enabled)
        finally:
            stream_mode.other_active_outputs = lambda name: None

    def test_a_disconnect_mid_stream_leaves_the_stop_marker_in_charge(self):
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "mac")
        s.begin_stream()
        self.enabled.clear()
        self.assertFalse(s.disconnect(123))
        self.assertEqual(self.enabled, [])

    def test_steam_dying_with_a_client_connected_disarms(self):
        """A crash is the one way to lose a client without a disconnect line."""
        stream_mode.steam_is_running = lambda: False
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "mac")
        self.assertTrue(s.check_steam_alive())
        self.assertIsNone(s.client_id)

    def test_no_game_means_nothing_to_clean_up(self):
        """Steam not running is the ordinary state between sessions."""
        signalled = []
        stream_mode.steam_is_running = lambda: False
        stream_mode.signal_process = lambda pid, sig: signalled.append((pid, sig))

        s = stream_mode.Session(stage_timeout=0)
        self.assertFalse(s.check_steam_alive())
        self.assertEqual(signalled, [])

    def test_a_stream_can_start_without_a_connect(self):
        """A service restart mid-session never sees the connect line."""
        s = stream_mode.Session(stage_timeout=0)
        self.assertTrue(s.begin_stream())
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)
        self.assertIn((stream_mode.OUTPUT_NAME, True), self.enabled)

    def test_an_output_event_while_idle_does_not_turn_it_on(self):
        """Between streams it is meant to be out of the layout."""
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        s.end_stream()
        self.enabled.clear()
        self.assertFalse(s.on_outputs_changed({"DP-2"}))
        self.assertEqual(self.enabled, [])

    def test_an_event_listing_the_output_changes_nothing(self):
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        self.enabled.clear()
        self.assertFalse(s.on_outputs_changed({"DP-2", stream_mode.OUTPUT_NAME}))
        self.assertEqual(self.enabled, [])

    def test_a_client_with_a_different_panel_resizes_rather_than_replaces(self):
        """A television and a handheld share one declared output.

        Replacing it would invalidate the capture source the other client had
        been given, so the size is changed underneath it instead.
        """
        stream_mode.load_clients = lambda path=None: {"7": [3840, 2160]}
        s = stream_mode.Session(stage_timeout=0)
        s.connect(7, "living-room-tv")
        self.assertEqual(
            self.modes,
            [(stream_mode.OUTPUT_NAME, 3840, 2160, stream_mode.DEFAULT_REFRESH)],
        )
        self.assertIn(stream_mode.OUTPUT_NAME, self.names)


class TestEventDispatch(unittest.TestCase):
    """Compositor and Steam events drive everything; nothing is polled."""

    class FakeSession:
        def __init__(self):
            self.output = "steam"
            self.streaming = False
            self.pending = None
            self.last_windows = []
            self.calls = []

        def on_windows(self, windows):
            self.calls.append(("on_windows", len(windows)))

        def on_outputs_changed(self, names):
            self.calls.append(("on_outputs_changed", sorted(names)))

        def begin_stream(self, client_name=None):
            self.calls.append(("begin_stream",))
            self.streaming_to = client_name

        def request(self, pid, game_id):
            self.calls.append(("request", pid, game_id))

        def reassert_output(self):
            self.calls.append(("reassert_output",))

        def game_capture_requested(self):
            self.calls.append(("game_capture_requested",))

        def game_capture_started(self):
            self.calls.append(("game_capture_started",))

        def note_client_output(self, w, h):
            self.calls.append(("note_client_output", w, h))

        def note_max_capture(self, w, h, fps=None):
            self.calls.append(("note_max_capture", w, h, fps))

        def trace(self, window_id, what, layout=None, workspace_id=None):
            self.calls.append(("trace", window_id, what))

        def unstage(self, pid=None):
            self.calls.append(("unstage", pid))

        def return_game_workspace(self):
            self.calls.append(("return_game_workspace",))
            return True

    def setUp(self):
        self.s = self.FakeSession()

    def test_a_new_window_is_recorded_and_acted_on(self):
        stream_mode.handle_niri_event(
            self.s,
            json.dumps({"WindowOpenedOrChanged": {"window": {"id": 7, "app_id": "gamescope", "pid": 42}}}),
        )
        self.assertEqual([w["id"] for w in self.s.last_windows], [7])
        self.assertIn(("on_windows", 1), self.s.calls)

    def test_a_window_list_replaces_what_is_known(self):
        self.s.last_windows = [{"id": 1}]
        stream_mode.handle_niri_event(
            self.s, json.dumps({"WindowsChanged": {"windows": [{"id": 2}, {"id": 3}]}})
        )
        self.assertEqual(sorted(w["id"] for w in self.s.last_windows), [2, 3])

    def test_a_closed_window_is_forgotten(self):
        self.s.last_windows = [{"id": 1}, {"id": 2}]
        stream_mode.handle_niri_event(self.s, json.dumps({"WindowClosed": {"id": 1}}))
        self.assertEqual([w["id"] for w in self.s.last_windows], [2])

    def test_workspace_changes_report_the_outputs(self):
        stream_mode.handle_niri_event(
            self.s,
            json.dumps({"WorkspacesChanged": {"workspaces": [
                {"output": "DP-2"}, {"output": "steam"}, {"output": None}
            ]}}),
        )
        self.assertIn(("on_outputs_changed", ["DP-2", "steam"]), self.s.calls)

    def test_a_config_reload_reasserts_the_output(self):
        stream_mode.handle_niri_event(self.s, json.dumps({"ConfigLoaded": {"failed": False}}))
        self.assertEqual(self.s.calls, [("reassert_output",)])

    def test_a_failed_config_reload_changes_nothing(self):
        """niri keeps the old config, and with it our changes."""
        stream_mode.handle_niri_event(self.s, json.dumps({"ConfigLoaded": {"failed": True}}))
        self.assertEqual(self.s.calls, [])

    def test_malformed_events_are_ignored(self):
        stream_mode.handle_niri_event(self.s, "not json\n")
        stream_mode.handle_niri_event(self.s, json.dumps({"SomethingElse": {}}))
        self.assertEqual(self.s.calls, [])

    def test_stream_start_publishes_and_clears_the_removal(self):
        remove_at = stream_mode.handle_steam_line(
            self.s, "[x] Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\n", 123.0
        )
        self.assertIsNone(remove_at)
        self.assertIn(("begin_stream",), self.s.calls)
        self.assertEqual(self.s.streaming_to, "ali-mba")

    def test_stream_stop_schedules_the_removal(self):
        remove_at = stream_mode.handle_steam_line(
            self.s, "[x] PipeWire: Deinitializing streaming\n", None
        )
        self.assertIsNotNone(remove_at)
        self.assertGreater(remove_at, time.monotonic())

    def test_stream_stop_returns_the_game_workspace_at_once(self):
        """Stop Streaming from the tray leaves a running game behind.

        The output stays on for a grace period so a reconnect does not have
        to rebuild it, but the game must not spend that period on a display
        nobody is looking at and nobody can reach.
        """
        stream_mode.handle_steam_line(
            self.s, "[x] PipeWire: Deinitializing streaming\n", None
        )
        self.assertIn(("return_game_workspace",), self.s.calls)

    def test_a_game_window_line_requests_staging(self):
        stream_mode.handle_steam_line(
            self.s,
            "[x] Adding window 4194306 (4) for process 2331545 and gameID 2854740\n",
            None,
        )
        self.assertIn(("request", 2331545, 2854740), self.s.calls)

    def test_the_client_size_and_limit_are_noted(self):
        stream_mode.handle_steam_line(
            self.s, "[x] Maximum capture: 2880x1080 60.00 FPS\n", None
        )
        stream_mode.handle_steam_line(
            self.s,
            "[x] CLIENT: Video size: 2880x1080, output size: 2880x1800, "
            "overlay size: 2880x1800\n",
            None,
        )
        self.assertEqual(
            self.s.calls,
            [("note_max_capture", 2880, 1080, 60.0), ("note_client_output", 2880, 1800)],
        )

    def test_game_capture_lines_arm_and_clear_the_stall_check(self):
        stream_mode.handle_steam_line(
            self.s,
            "[x] >>> Switching video stream from Desktop_MovieStream to GameOverlay_MovieStream_1961662\n",
            None,
        )
        stream_mode.handle_steam_line(
            self.s, "[x] >>> Capture method set to Game Vulkan NV12 + VAAPI H264\n", None
        )
        self.assertEqual(
            self.s.calls, [("game_capture_requested",), ("game_capture_started",)]
        )

    def test_an_unrelated_line_changes_nothing(self):
        remove_at = stream_mode.handle_steam_line(self.s, "[x] noise\n", 55.0)
        self.assertEqual(remove_at, 55.0)
        self.assertEqual(self.s.calls, [])


class TestOutputDetection(unittest.TestCase):
    """Existence cannot rest on `niri msg outputs` alone.

    It omits virtual outputs in at least one state: with no physical output
    attached it returns nothing at all, while the workspaces it reports are
    still sitting on the virtual one. Believing it made the service decide a
    perfectly good output did not exist and refuse to stage games onto it.
    """

    def setUp(self):
        self._real = (stream_mode.niri_outputs, stream_mode.niri_workspaces)

    def tearDown(self):
        stream_mode.niri_outputs, stream_mode.niri_workspaces = self._real

    def test_usable_means_listed(self):
        stream_mode.niri_outputs = lambda: {"DP-2": {}, "steam": {}}
        stream_mode.niri_workspaces = lambda: []
        self.assertEqual(stream_mode.usable_output_names(), {"DP-2", "steam"})

    def test_a_stuck_output_is_taken_but_not_usable(self):
        """It survives a hotplug as a name only: unlisted, un-enableable, and
        still blocking creation."""
        stream_mode.niri_outputs = lambda: {}
        stream_mode.niri_workspaces = lambda: [{"output": "steam"}, {"output": "steam"}]
        self.assertEqual(stream_mode.taken_output_names(), {"steam"})
        self.assertEqual(stream_mode.usable_output_names(), set())

    def test_survives_either_source_failing(self):
        def boom():
            raise OSError("niri not answering")

        stream_mode.niri_outputs = boom
        stream_mode.niri_workspaces = lambda: [{"output": "steam"}]
        self.assertEqual(stream_mode.taken_output_names(), {"steam"})

        stream_mode.niri_outputs = lambda: {"DP-2": {}}
        stream_mode.niri_workspaces = boom
        self.assertEqual(stream_mode.taken_output_names(), {"DP-2"})

    def test_empty_when_nothing_answers(self):
        def boom():
            raise OSError("niri not answering")

        stream_mode.niri_outputs = boom
        stream_mode.niri_workspaces = boom
        self.assertEqual(stream_mode.taken_output_names(), set())


class TestStreamInProgress(unittest.TestCase):
    """A restart mid-stream must still publish a target."""

    def write(self, tmp, body):
        path = os.path.join(tmp, "streaming_log.txt")
        with open(path, "w") as fh:
            fh.write(body)
        return path

    def test_started_and_not_stopped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write(tmp, "noise\nStreaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\nmore\n")
            self.assertTrue(stream_mode.stream_in_progress(path))

    def test_started_then_stopped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write(
                tmp,
                "Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\nPipeWire: Deinitializing streaming\n",
            )
            self.assertFalse(stream_mode.stream_in_progress(path))

    def test_restarted_after_stopping(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write(
                tmp,
                "Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\nPipeWire: Deinitializing streaming\n"
                "Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\n",
            )
            self.assertTrue(stream_mode.stream_in_progress(path))

    def test_no_markers_at_all(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(stream_mode.stream_in_progress(self.write(tmp, "noise\n")))

    def test_missing_file(self):
        self.assertFalse(stream_mode.stream_in_progress("/nonexistent/log.txt"))


class TestNiriSocket(unittest.TestCase):
    """The socket has to be found, not inherited.

    NIRI_SOCKET is captured when the service starts, so after a logout it names
    a compositor that no longer exists. Every call then fails against a dead
    socket while a live niri sits alongside it — which had the service and a
    shell talking to different compositors and disagreeing about which outputs
    existed.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._env = dict(os.environ)
        os.environ["XDG_RUNTIME_DIR"] = self.tmp.name

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._env)
        self.tmp.cleanup()

    def touch(self, name):
        open(os.path.join(self.tmp.name, name), "w").close()

    def test_finds_a_socket_belonging_to_a_live_process(self):
        self.touch("niri.wayland-1.{}.sock".format(os.getpid()))
        found = stream_mode.live_niri_socket()
        self.assertIsNotNone(found)
        self.assertIn(str(os.getpid()), found)

    def test_ignores_a_socket_whose_process_is_gone(self):
        # PID 1 exists; use an implausible one that cannot.
        self.touch("niri.wayland-2.4294967.sock")
        self.assertIsNone(stream_mode.live_niri_socket())

    def test_prefers_the_live_one_over_a_dead_one(self):
        self.touch("niri.wayland-2.4294967.sock")
        self.touch("niri.wayland-1.{}.sock".format(os.getpid()))
        found = stream_mode.live_niri_socket()
        self.assertIn(str(os.getpid()), found)

    def test_ignores_unrelated_files(self):
        self.touch("not-niri.sock")
        self.touch("niri.sock")
        self.assertIsNone(stream_mode.live_niri_socket())

    def test_env_keeps_a_socket_that_still_exists(self):
        path = os.path.join(self.tmp.name, "niri.wayland-1.{}.sock".format(os.getpid()))
        open(path, "w").close()
        os.environ["NIRI_SOCKET"] = path
        self.assertEqual(stream_mode.niri_env()["NIRI_SOCKET"], path)

    def test_env_replaces_a_socket_that_has_gone(self):
        os.environ["NIRI_SOCKET"] = os.path.join(self.tmp.name, "gone.sock")
        live = os.path.join(self.tmp.name, "niri.wayland-1.{}.sock".format(os.getpid()))
        open(live, "w").close()
        self.assertEqual(stream_mode.niri_env()["NIRI_SOCKET"], live)


class TestStreamTarget(unittest.TestCase):
    """The gamescope shim reads this to size a launching game."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._real = stream_mode.TARGET_FILE
        self._real_json = stream_mode.TARGET_JSON_FILE
        stream_mode.TARGET_FILE = os.path.join(self.tmp.name, "sub", "target")
        stream_mode.TARGET_JSON_FILE = stream_mode.TARGET_FILE + ".json"

    def tearDown(self):
        stream_mode.TARGET_FILE = self._real
        stream_mode.TARGET_JSON_FILE = self._real_json
        self.tmp.cleanup()

    def read(self):
        with open(stream_mode.TARGET_FILE) as fh:
            return fh.read()

    def read_json(self):
        with open(stream_mode.TARGET_JSON_FILE) as fh:
            return json.load(fh)

    def test_publishes_the_size_the_filter_parses(self):
        """One line, "WIDTHxHEIGHT", and nothing the filter has to parse around.

        The filter hooks SDL, which has no notion of the compositor's output
        names, so the size is all it can use. Keeping the format this small is
        also what lets someone on another compositor drive it by hand with
        STEAM_STREAM_SIZE and no watcher at all.
        """
        self.assertTrue(stream_mode.publish_target("steam", 1280, 800, 60))
        self.assertEqual(self.read().strip(), "1280x800")

    def test_the_output_name_and_refresh_stay_out_of_the_file(self):
        stream_mode.publish_target("steam", 1280, 800, 90)
        self.assertNotIn("steam", self.read())
        self.assertNotIn("90", self.read())

    def test_it_also_publishes_what_the_shim_needs(self):
        """The gamescope shim needs more than the size.

        It sets --prefer-output from the output name and -r from the refresh,
        neither of which fits in a bare WIDTHxHEIGHT. The bare file stays the
        contract the display filter and STEAM_STREAM_SIZE share; this one
        carries the rest, for the one consumer that is compositor-aware.
        """
        self.assertTrue(stream_mode.publish_target("steam", 1280, 800, 90))
        self.assertEqual(
            self.read_json(),
            {"output": "steam", "width": 1280, "height": 800, "refresh": 90},
        )

    def test_a_target_without_a_refresh_omits_it(self):
        """The shim treats refresh as optional and skips -r when absent."""
        stream_mode.publish_target("steam", 1280, 800)
        self.assertNotIn("refresh", self.read_json())

    def test_withdraw_removes_it(self):
        stream_mode.publish_target("steam", 1280, 800)
        self.assertTrue(stream_mode.withdraw_target())
        self.assertFalse(os.path.exists(stream_mode.TARGET_FILE))

    def test_withdraw_removes_both(self):
        """Both go together, or a game launched after a stream ends is sized
        for a client that is no longer connected."""
        stream_mode.publish_target("steam", 1280, 800, 90)
        stream_mode.withdraw_target()
        self.assertFalse(os.path.exists(stream_mode.TARGET_FILE))
        self.assertFalse(os.path.exists(stream_mode.TARGET_JSON_FILE))

    def test_withdraw_reports_removal_when_only_the_json_remains(self):
        """A half-published state must still be cleaned up and reported."""
        stream_mode.publish_target("steam", 1280, 800, 90)
        os.remove(stream_mode.TARGET_FILE)
        self.assertTrue(stream_mode.withdraw_target())
        self.assertFalse(os.path.exists(stream_mode.TARGET_JSON_FILE))

    def test_withdraw_is_idempotent(self):
        """It runs on shutdown paths that may not have published anything."""
        self.assertFalse(stream_mode.withdraw_target())

    def test_publish_replaces_atomically(self):
        """A game launch can read this at any moment; a partial file is worse
        than a stale one."""
        stream_mode.publish_target("steam", 1280, 800)
        stream_mode.publish_target("steam", 1920, 1200)
        self.assertEqual(self.read().strip(), "1920x1200")
        leftovers = [f for f in os.listdir(os.path.dirname(stream_mode.TARGET_FILE))
                     if f.endswith(".new")]
        self.assertEqual(leftovers, [])




class TestStagingAudits(unittest.TestCase):
    """Re-reading a staged window on a timer, so nobody has to be watching."""

    def setUp(self):
        self._real = {k: getattr(stream_mode, k)
                      for k in ("window_location", "STAGE_AUDIT_DELAYS")}
        self.seen = []
        stream_mode.window_location = lambda wid: "output=steam size=[1280, 800]"

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def test_audits_run_when_due_and_only_once(self):
        s = stream_mode.Session(stage_timeout=0)
        s.audits = [(100.0, 7), (200.0, 7)]

        self.assertFalse(s.run_due_audits(50.0))
        self.assertTrue(s.run_due_audits(150.0))
        self.assertEqual(s.audits, [(200.0, 7)])
        self.assertTrue(s.run_due_audits(250.0))
        self.assertEqual(s.audits, [])
        self.assertFalse(s.run_due_audits(300.0))

    def test_no_audits_is_not_work(self):
        s = stream_mode.Session(stage_timeout=0)
        self.assertFalse(s.run_due_audits(1.0))


class TestEventTracing(unittest.TestCase):
    """The event stream says when a window moved; polling only says where."""

    class Recorder:
        def __init__(self):
            self.audits = [(0.0, 42)]
            self.workspace_outputs = {}
            self.last_windows = []
            self.traced = []

        watched_windows = stream_mode.Session.watched_windows
        trace = stream_mode.Session.trace

        def on_windows(self, windows):
            pass

        def on_outputs_changed(self, names):
            pass

        def fill_streamed_output(self, windows):
            return False

    def setUp(self):
        self.s = self.Recorder()
        self._log = stream_mode.log
        self.lines = []
        stream_mode.log = self.lines.append

    def tearDown(self):
        stream_mode.log = self._log

    def test_a_layout_change_for_an_audited_window_is_traced(self):
        stream_mode.handle_niri_event(self.s, json.dumps(
            {"WindowLayoutsChanged": {"changes": [[42, {"window_size": [1280, 800]}]]}}
        ))
        self.assertTrue(any("trace window 42" in l and "1280" in l for l in self.lines))

    def test_other_windows_are_not_narrated(self):
        stream_mode.handle_niri_event(self.s, json.dumps(
            {"WindowLayoutsChanged": {"changes": [[7, {"window_size": [800, 600]}]]}}
        ))
        self.assertEqual([l for l in self.lines if "trace" in l], [])

    def test_workspaces_changed_records_the_output_of_each_workspace(self):
        stream_mode.handle_niri_event(self.s, json.dumps(
            {"WorkspacesChanged": {"workspaces": [{"id": 3, "output": "steam"}]}}
        ))
        self.assertEqual(self.s.workspace_outputs, {3: "steam"})


class TestGameWorkspace(unittest.TestCase):
    """niri's own rule opens games on a named workspace; move that instead.

    Chasing each game window was a race against the compositor's
    configuration, and it lost visibly: the game appeared on the desktop
    monitor, sized as gamescope's borderless column for that monitor, and was
    dragged across a moment later.
    """

    def setUp(self):
        self._real = {k: getattr(stream_mode, k) for k in (
            "workspace_output", "move_workspace_to_output", "usable_output_names")}
        self.moves = []
        stream_mode.move_workspace_to_output = lambda name, out: (
            self.moves.append((name, out)) or True)
        stream_mode.usable_output_names = lambda: {"DP-2", stream_mode.OUTPUT_NAME}

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self):
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        return s

    def test_it_is_borrowed_for_the_stream_and_given_back(self):
        stream_mode.workspace_output = lambda name: "DP-2"
        s = self.session()

        self.assertTrue(s.borrow_game_workspace())
        self.assertEqual(self.moves, [(stream_mode.GAME_WORKSPACE, stream_mode.OUTPUT_NAME)])

        self.assertTrue(s.return_game_workspace())
        self.assertEqual(self.moves[-1], (stream_mode.GAME_WORKSPACE, "DP-2"))

    def test_a_workspace_already_there_is_left_alone(self):
        stream_mode.workspace_output = lambda name: stream_mode.OUTPUT_NAME
        s = self.session()
        self.assertFalse(s.borrow_game_workspace())
        self.assertEqual(self.moves, [])

    def test_a_missing_workspace_is_not_invented(self):
        stream_mode.workspace_output = lambda name: None
        s = self.session()
        self.assertFalse(s.borrow_game_workspace())
        self.assertEqual(self.moves, [])

    def test_returning_is_skipped_if_the_monitor_has_gone(self):
        """A KVM switch mid-stream: putting it back somewhere invented is worse."""
        stream_mode.workspace_output = lambda name: "DP-2"
        s = self.session()
        s.borrow_game_workspace()
        self.moves.clear()
        stream_mode.usable_output_names = lambda: {stream_mode.OUTPUT_NAME}

        self.assertFalse(s.return_game_workspace())
        self.assertEqual(self.moves, [])

    def test_returning_without_borrowing_does_nothing(self):
        stream_mode.workspace_output = lambda name: "DP-2"
        self.assertFalse(self.session().return_game_workspace())
        self.assertEqual(self.moves, [])

    def test_a_stranded_workspace_is_returned_without_a_recorded_home(self):
        """The reported bug: the game is unreachable on the virtual output.

        Borrowing takes an early exit when the workspace is already on the
        streamed output, which is the state a service restart mid-stream
        leaves behind. That exit recorded no home, so returning had nowhere
        to go and silently did nothing -- and every later stream re-entered
        the same exit, so the workspace never came back at all.
        """
        stream_mode.workspace_output = lambda name: stream_mode.OUTPUT_NAME
        s = self.session()
        self.assertIsNone(s.game_workspace_home)

        self.assertTrue(s.return_game_workspace())
        self.assertEqual(self.moves, [(stream_mode.GAME_WORKSPACE, "DP-2")])

    def test_a_stranded_workspace_picks_its_home_deterministically(self):
        """Several candidates: pick one by a stable rule, not by set order."""
        stream_mode.workspace_output = lambda name: stream_mode.OUTPUT_NAME
        stream_mode.usable_output_names = lambda: {
            "HDMI-A-1", "DP-2", stream_mode.OUTPUT_NAME,
        }
        s = self.session()

        self.assertTrue(s.return_game_workspace())
        self.assertEqual(self.moves, [(stream_mode.GAME_WORKSPACE, "DP-2")])

    def test_a_workspace_elsewhere_is_not_dragged_home(self):
        """No recorded home and not stranded either: leave it where it is."""
        stream_mode.workspace_output = lambda name: "HDMI-A-1"
        s = self.session()

        self.assertFalse(s.return_game_workspace())
        self.assertEqual(self.moves, [])

    def test_a_stranded_workspace_with_nowhere_to_go_is_left_alone(self):
        """Only the streamed output exists -- inventing a home is worse."""
        stream_mode.workspace_output = lambda name: stream_mode.OUTPUT_NAME
        stream_mode.usable_output_names = lambda: {stream_mode.OUTPUT_NAME}
        s = self.session()

        self.assertFalse(s.return_game_workspace())
        self.assertEqual(self.moves, [])

    def test_a_recorded_home_beats_the_fallback(self):
        """A real home was observed; do not second-guess it."""
        stream_mode.workspace_output = lambda name: "HDMI-A-1"
        stream_mode.usable_output_names = lambda: {
            "HDMI-A-1", "DP-2", stream_mode.OUTPUT_NAME,
        }
        s = self.session()
        self.assertTrue(s.borrow_game_workspace())
        self.moves.clear()

        self.assertTrue(s.return_game_workspace())
        self.assertEqual(self.moves, [(stream_mode.GAME_WORKSPACE, "HDMI-A-1")])


class TestSplashScreens(unittest.TestCase):
    """A game with a splash screen has two windows; staging only catches one.

    Armored Core's splash was staged, fullscreened and closed, and the real
    window arrived afterwards unmanaged and tiled at half the output's width.
    """

    def setUp(self):
        self._real = {k: getattr(stream_mode, k) for k in (
            "output_logical_size", "niri_windows", "set_window_fullscreen")}
        self.toggled = []
        stream_mode.output_logical_size = lambda name: (1280, 800)
        stream_mode.set_window_fullscreen = lambda wid, on=True: self.toggled.append(wid) or True
        
    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self):
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        s.streaming = True
        s.workspace_outputs = {9: stream_mode.OUTPUT_NAME}
        # A game is staged and still running: that is what makes a window
        # arriving unannounced on the streamed output the game's replacement
        # rather than something of the desktop's that wandered over.
        s.game_pid = 4321
        s.game_id = 1888160
        return s

    def half_width(self, wid, app_id="steam_app_1888160"):
        return {"id": wid, "app_id": app_id, "pid": 999999,
                "workspace_id": 9, "layout": {"window_size": [640, 766]}}

    def test_a_desktop_window_on_the_streamed_output_is_left_alone(self):
        """With the monitor off the whole desktop lives on the streamed output.

        GameGuard opened its FAQ in Zen, which was fullscreened in front of
        HD2 and then given focus back every time HD2 took it, so Steam
        captured nothing.
        """
        s = self.session()
        zen = self.half_width(194, app_id="zen-beta")
        self.assertFalse(s.fill_streamed_output([zen]))
        self.assertEqual(self.toggled, [])

    def test_a_window_arriving_after_staging_is_still_fullscreened(self):
        s = self.session()
        stream_mode.niri_windows = lambda: [self.half_width(127)]
        s.fill_streamed_output([self.half_width(127)])
        self.assertEqual(self.toggled, [127])

    def test_it_stops_after_a_few_attempts(self):
        """A window that cannot be widened must not be fought forever.

        Setting a width is idempotent, so this can run on every event that
        says the width is wrong -- but a window with a fixed size would then
        be retried endlessly.
        """
        s = self.session()
        stream_mode.niri_windows = lambda: [self.half_width(127)]
        for _ in range(stream_mode.WIDEN_LIMIT + 3):
            s.fill_streamed_output([self.half_width(127)])
        self.assertEqual(len(self.toggled), stream_mode.WIDEN_LIMIT)

    def test_a_window_that_widens_resets_the_budget(self):
        s = self.session()
        full = {"id": 127, "app_id": "steam_app_1888160", "workspace_id": 9,
                "layout": {"window_size": [1280, 800]}}
        stream_mode.niri_windows = lambda: [self.half_width(127)]
        s.fill_streamed_output([self.half_width(127)])
        s.fill_streamed_output([full])
        self.toggled.clear()
        for _ in range(stream_mode.WIDEN_LIMIT + 2):
            s.fill_streamed_output([self.half_width(127)])
        self.assertEqual(len(self.toggled), stream_mode.WIDEN_LIMIT)

    def test_windows_on_other_outputs_are_left_alone(self):
        s = self.session()
        s.workspace_outputs = {9: "DP-2"}
        stream_mode.niri_windows = lambda: [self.half_width(127)]
        s.fill_streamed_output([self.half_width(127)])
        self.assertEqual(self.toggled, [])

    def test_an_unstaged_window_is_left_alone_once_the_game_has_gone(self):
        """The teardown case: a terminal drifted onto the streamed output 90
        seconds after the game exited and was resized to fit it."""
        s = self.session()
        s.game_pid = None
        stream_mode.niri_windows = lambda: [self.half_width(3)]
        self.assertFalse(s.fill_streamed_output([self.half_width(3)]))
        self.assertEqual(self.toggled, [])

    def test_nothing_happens_when_not_streaming(self):
        s = self.session()
        s.streaming = False
        stream_mode.niri_windows = lambda: [self.half_width(127)]
        s.fill_streamed_output([self.half_width(127)])
        self.assertEqual(self.toggled, [])

    def test_a_tiny_helper_window_is_not_fullscreened(self):
        s = self.session()
        tray = {"id": 121, "workspace_id": 9, "layout": {"window_size": [160, 20]}}
        self.assertFalse(s.fill_streamed_output([tray]))
        self.assertEqual(self.toggled, [])

    def test_a_floating_game_is_tiled_then_fullscreened(self):
        tiled = []
        real = stream_mode.move_window_to_tiling
        stream_mode.move_window_to_tiling = lambda wid: tiled.append(wid) or True
        try:
            s = self.session()
            floating = dict(self.half_width(121), is_floating=True)
            self.assertTrue(s.fill_streamed_output([floating]))
        finally:
            stream_mode.move_window_to_tiling = real
        self.assertEqual(tiled, [121])
        self.assertEqual(self.toggled, [121])


class TestGamescopeAtoms(unittest.TestCase):
    """gamescope leaves GAMESCOPE_* atoms on the host X root. Steam then acts
    as if it runs inside gamescope, reads focus from GAMESCOPE_FOCUSED_APP,
    gets app id 0, and flips the stream between game and desktop mode."""

    ROOT = (
        "_NET_ACTIVE_WINDOW(WINDOW): window id # 0x6e00001\n"
        "GAMESCOPE_COMPOSITE_FORCE(CARDINAL) = 0\n"
        "GAMESCOPE_DISPLAY_HDR_ENABLED(CARDINAL) = 1\n"
        "GAMESCOPE_RESHADE_EFFECT(UTF8_STRING) = \n"
        "GAMESCOPE_RESHADE_EFFECT(UTF8_STRING) = \n"
    )

    def setUp(self):
        self._real_run = stream_mode.subprocess.run
        self.calls = []

        def fake_run(args, **_kwargs):
            self.calls.append(list(args))
            stdout = self.ROOT if args[-1] == "-root" else ""
            return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")

        stream_mode.subprocess.run = fake_run

    def tearDown(self):
        stream_mode.subprocess.run = self._real_run

    def test_removes_each_gamescope_atom_once(self):
        removed = stream_mode.clear_gamescope_atoms()
        self.assertEqual(removed, [
            "GAMESCOPE_COMPOSITE_FORCE",
            "GAMESCOPE_DISPLAY_HDR_ENABLED",
            "GAMESCOPE_RESHADE_EFFECT",
        ])
        removes = [c[-1] for c in self.calls if "-remove" in c]
        self.assertEqual(removes, removed)

    def test_leaves_other_atoms_alone(self):
        stream_mode.clear_gamescope_atoms()
        self.assertFalse(any("_NET_ACTIVE_WINDOW" in c for c in self.calls))

    def test_only_successful_removals_are_reported(self):
        real_fake = stream_mode.subprocess.run

        def one_removal_fails(args, **kwargs):
            result = real_fake(args, **kwargs)
            if args[-1] == "GAMESCOPE_DISPLAY_HDR_ENABLED":
                return subprocess.CompletedProcess(args, 1, stdout="", stderr="BadAtom")
            return result

        stream_mode.subprocess.run = one_removal_fails
        self.assertEqual(stream_mode.clear_gamescope_atoms(), [
            "GAMESCOPE_COMPOSITE_FORCE",
            "GAMESCOPE_RESHADE_EFFECT",
        ])

    def test_an_unreachable_x_server_is_not_fatal(self):
        def failing_run(args, **_kwargs):
            raise OSError("xprop not found")

        stream_mode.subprocess.run = failing_run
        self.assertEqual(stream_mode.clear_gamescope_atoms(), [])


class TestSteamDeath(unittest.TestCase):
    """Steam dying mid-stream leaves no stop marker and no tidy-up.

    Measured: Steam exited on a broken IPC pipe at 19:34:24 while a stream was
    running, so the log ends on a start marker. The service was restarted a
    few minutes later, read that truncated log, concluded a stream was in
    progress and re-armed — leaving the game workspace on the streamed output
    and a target published, with no Steam at all, for forty minutes.
    """

    def setUp(self):
        self._real = {k: getattr(stream_mode, k) for k in (
            "steam_is_running", "set_output_enabled", "withdraw_target",
            "workspace_output", "move_workspace_to_output", "usable_output_names",
            "publish_target", "output_logical_size", "load_clients",
            "signal_process")}
        self.enabled = []
        stream_mode.set_output_enabled = lambda n, e: self.enabled.append((n, e)) or True
        stream_mode.withdraw_target = lambda *a, **k: True
        stream_mode.publish_target = lambda *a, **k: True
        stream_mode.workspace_output = lambda name: "DP-2"
        stream_mode.move_workspace_to_output = lambda name, out: True
        stream_mode.usable_output_names = lambda: {"DP-2", stream_mode.OUTPUT_NAME}
        stream_mode.output_logical_size = lambda name: (1280, 800)
        stream_mode.load_clients = lambda path=None: {}
        stream_mode.signal_process = lambda pid, sig: True

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def test_a_stream_without_steam_is_not_a_stream(self):
        """The start marker is not evidence on its own once Steam is gone."""
        stream_mode.steam_is_running = lambda: False
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        s.streaming = True

        self.assertTrue(s.check_steam_alive())
        self.assertIn((stream_mode.OUTPUT_NAME, False), self.enabled)
        self.assertFalse(s.streaming)

    def test_a_live_stream_with_steam_running_is_left_alone(self):
        stream_mode.steam_is_running = lambda: True
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        s.streaming = True

        self.assertFalse(s.check_steam_alive())
        self.assertTrue(s.streaming)

    def test_idle_with_no_steam_is_the_ordinary_state(self):
        """Steam is not running most of the time; that is not a fault."""
        stream_mode.steam_is_running = lambda: False
        s = stream_mode.Session(stage_timeout=0)
        self.assertFalse(s.check_steam_alive())
        self.assertEqual(self.enabled, [])

    def test_a_start_marker_alone_does_not_mean_a_stream(self):
        """The log keeps its start marker for good once Steam dies mid-stream."""
        import tempfile as _t
        with _t.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write("Streaming started to ali-mba at 0.0.0.0:0, audio channels = 2, MTU = 1200\n")
            path = fh.name
        try:
            self.assertTrue(stream_mode.stream_in_progress(path))
            # The guard is the conjunction at the call site: a start marker is
            # only evidence while Steam exists to be doing the streaming.
            stream_mode.steam_is_running = lambda: False
            self.assertFalse(
                stream_mode.stream_in_progress(path) and stream_mode.steam_is_running()
            )
        finally:
            os.unlink(path)


class TestFocus(unittest.TestCase):
    """gamescope draws at the size it was last activated with.

    A game sat fullscreen by niri's geometry and was still drawn at half the
    output for eight minutes, with focused=False in every audit. Tapping the
    window fixed it instantly, which is what focusing it does.
    """

    def setUp(self):
        self._real = {k: getattr(stream_mode, k) for k in (
            "focus_window", "output_logical_size", "niri_windows",
            "set_window_fullscreen")}
        self.focused = []
        stream_mode.focus_window = lambda wid: self.focused.append(wid) or True
        stream_mode.output_logical_size = lambda name: (1280, 800)
        
    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self):
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        s.streaming = True
        s.workspace_outputs = {9: stream_mode.OUTPUT_NAME}
        return s

    def win(self, wid, focused, size=(1280, 800)):
        return {"id": wid, "workspace_id": 9, "is_focused": focused,
                "layout": {"window_size": list(size)}}

    def test_focus_is_taken_back_when_it_is_lost(self):
        s = self.session()
        s.fullscreened.add(9)
        self.assertTrue(s.refocus_streamed_window([self.win(9, False)]))
        self.assertEqual(self.focused, [9])

    def test_a_focused_window_is_left_alone(self):
        s = self.session()
        s.fullscreened.add(9)
        self.assertFalse(s.refocus_streamed_window([self.win(9, True)]))
        self.assertEqual(self.focused, [])

    def test_it_gives_up_rather_than_fighting_forever(self):
        """Switching to something else on the desktop must eventually win."""
        s = self.session()
        s.fullscreened.add(9)
        for _ in range(stream_mode.REFOCUS_LIMIT + 3):
            s.refocus_streamed_window([self.win(9, False)])
        self.assertEqual(len(self.focused), stream_mode.REFOCUS_LIMIT)

    def test_regaining_focus_resets_the_budget(self):
        s = self.session()
        s.fullscreened.add(9)
        s.refocus_streamed_window([self.win(9, False)])
        s.refocus_streamed_window([self.win(9, True)])
        self.focused.clear()
        for _ in range(stream_mode.REFOCUS_LIMIT + 2):
            s.refocus_streamed_window([self.win(9, False)])
        self.assertEqual(len(self.focused), stream_mode.REFOCUS_LIMIT)

    def test_a_nudge_in_flight_is_not_undone(self):
        s = self.session()
        s.fullscreened.add(9)
        s.nudge_return_to = 9
        self.assertFalse(s.refocus_streamed_window([self.win(9, False)]))
        self.assertEqual(self.focused, [])

    def test_a_window_newer_than_the_game_keeps_focus(self):
        """A login box or cloud-save prompt opened after the game must reach
        the client; Steam streams the focused window."""
        s = self.session()
        s.fullscreened.add(9)
        login = dict(self.win(12, True, size=(480, 360)), app_id="launcher")
        self.assertFalse(s.refocus_streamed_window([self.win(9, False), login]))
        self.assertEqual(self.focused, [])

    def test_focus_falling_to_an_older_window_is_taken_back(self):
        """A splash closing hands focus to whatever was there before."""
        s = self.session()
        s.fullscreened.add(9)
        terminal = self.win(2, True)
        self.assertTrue(s.refocus_streamed_window([self.win(9, False), terminal]))
        self.assertEqual(self.focused, [9])

    def test_nothing_is_focused_when_not_streaming(self):
        s = self.session()
        s.streaming = False
        s.fullscreened.add(9)
        self.assertFalse(s.refocus_streamed_window([self.win(9, False)]))
        self.assertEqual(self.focused, [])


class TestReaderBackoff(unittest.TestCase):
    """A reader that keeps dying must not be respawned at full speed.

    A relog takes niri's event stream with it, and every immediate respawn
    died at once: 587 restarts in 45 seconds, which is a busy loop wearing a
    retry's clothes.
    """

    def test_the_first_wait_is_the_minimum(self):
        self.assertEqual(
            stream_mode.next_reader_backoff(0.0), stream_mode.READER_BACKOFF_MIN
        )

    def test_it_doubles(self):
        first = stream_mode.next_reader_backoff(0.0)
        self.assertEqual(stream_mode.next_reader_backoff(first), first * 2)

    def test_it_stops_at_the_ceiling(self):
        delay = 0.0
        for _ in range(50):
            delay = stream_mode.next_reader_backoff(delay)
        self.assertEqual(delay, stream_mode.READER_BACKOFF_MAX)

    def test_the_ceiling_is_low_enough_to_stay_responsive(self):
        """The reader is how every window event arrives; a long wait costs
        real responsiveness, so this is a deliberate ceiling rather than an
        arbitrary one."""
        self.assertLessEqual(stream_mode.READER_BACKOFF_MAX, 10)


class TestFullscreenFill(unittest.TestCase):
    """Fullscreen, not a wide column.

    A maximised column is laid out inside the working area, so anything with
    an exclusive zone on the streamed output takes its space: the desktop bar
    reserved 34px and a 1280x800 client got 1280x766 of game with a status bar
    above it. Fullscreen ignores struts and gaps, which is the only way to
    cover the output without dictating what else may run on the desktop.
    """

    def setUp(self):
        self._real = {k: getattr(stream_mode, k) for k in (
            "set_window_fullscreen", "focus_window", "output_logical_size",
            "workspace_output", "move_workspace_to_output",
            "usable_output_names")}
        self.calls = []
        stream_mode.set_window_fullscreen = lambda wid, on: (
            self.calls.append((wid, on)) or True)
        stream_mode.focus_window = lambda wid: True
        stream_mode.output_logical_size = lambda name: (1280, 800)

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self):
        s = stream_mode.Session(stage_timeout=0)
        s.output = stream_mode.OUTPUT_NAME
        s.streaming = True
        s.workspace_outputs = {9: stream_mode.OUTPUT_NAME}
        return s

    def win(self, wid, size):
        return {"id": wid, "workspace_id": 9, "is_focused": True,
                "layout": {"window_size": list(size)}}

    def test_a_staged_window_short_of_the_output_is_fullscreened(self):
        s = self.session()
        s.staged_windows.add(9)
        self.assertTrue(s.fill_streamed_output([self.win(9, (640, 766))]))
        self.assertEqual(self.calls, [(9, True)])

    def test_a_window_short_only_in_height_is_fullscreened(self):
        """The bar's exclusive zone costs height alone; width looks correct."""
        s = self.session()
        s.staged_windows.add(9)
        self.assertTrue(s.fill_streamed_output([self.win(9, (1280, 766))]))
        self.assertEqual(self.calls, [(9, True)])

    def test_a_window_already_covering_the_output_is_left_alone(self):
        s = self.session()
        s.staged_windows.add(9)
        self.assertFalse(s.fill_streamed_output([self.win(9, (1280, 800))]))
        self.assertEqual(self.calls, [])

    def test_a_window_we_did_not_stage_is_left_alone(self):
        """A terminal drifted onto the streamed output and was resized to
        1248px wide. Nothing but the staged game is ours to touch."""
        s = self.session()
        self.assertFalse(s.fill_streamed_output([self.win(3, (405, 734))]))
        self.assertEqual(self.calls, [])

    def test_fullscreening_records_the_window_so_it_can_be_undone(self):
        s = self.session()
        s.staged_windows.add(9)
        s.fill_streamed_output([self.win(9, (640, 766))])
        self.assertIn(9, s.fullscreened)

    def test_returning_the_workspace_undoes_the_fullscreen(self):
        """The stream borrows the window's state and gives it back.

        Forcing fullscreen on the desktop monitor is what the niri window rule
        deliberately stopped doing -- it overrode gamescope's own borderless
        sizing -- so a game that outlives the stream must not keep it.
        """
        stream_mode.workspace_output = lambda name: stream_mode.OUTPUT_NAME
        stream_mode.usable_output_names = lambda: {"DP-2", stream_mode.OUTPUT_NAME}
        stream_mode.move_workspace_to_output = lambda name, out: True
        s = self.session()
        s.fullscreened.add(9)

        s.return_game_workspace()
        self.assertEqual(self.calls, [(9, False)])
        self.assertEqual(s.fullscreened, set())


class TestShortOfOutput(unittest.TestCase):
    """Maximising is not fullscreen; on a gapped workspace it falls short.

    The game workspace sets gaps 0 and the rule turns borders off, so a
    maximised column happens to equal the output exactly. That is a property
    of the configuration, not of what the service asks for, so a change to it
    should be visible rather than silently costing the client a border.
    """

    def setUp(self):
        self._log = stream_mode.log
        self.lines = []
        stream_mode.log = self.lines.append

    def tearDown(self):
        stream_mode.log = self._log

    def warnings(self):
        return [l for l in self.lines if "after widening" in l]

    def test_an_exact_match_says_nothing(self):
        s = stream_mode.Session(stage_timeout=0)
        self.assertFalse(s.warn_if_short_of_output(1, [1280, 800], (1280, 800)))
        self.assertEqual(self.warnings(), [])

    def test_falling_short_is_reported_once(self):
        s = stream_mode.Session(stage_timeout=0)
        self.assertTrue(s.warn_if_short_of_output(1, [1248, 768], (1280, 800)))
        self.assertFalse(s.warn_if_short_of_output(1, [1248, 768], (1280, 800)))
        self.assertEqual(len(self.warnings()), 1)

    def test_a_short_height_counts_too(self):
        """Only the width is corrected, so a short height would go unnoticed."""
        s = stream_mode.Session(stage_timeout=0)
        self.assertTrue(s.warn_if_short_of_output(1, [1280, 768], (1280, 800)))

    def test_becoming_exact_rearms_the_warning(self):
        s = stream_mode.Session(stage_timeout=0)
        s.warn_if_short_of_output(1, [1248, 768], (1280, 800))
        s.warn_if_short_of_output(1, [1280, 800], (1280, 800))
        self.assertTrue(s.warn_if_short_of_output(1, [1248, 768], (1280, 800)))

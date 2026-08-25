"""Tests for stream-mode's virtual output lifecycle and log parsing.

Run: python3 -m unittest discover -s tests -v
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import stream_mode  # noqa: E402


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

    START = "[2026-08-24 22:39:48][308.657953] >>> Starting desktop stream\n"
    RES = "[2026-08-24 22:39:48][308.792672] >>> Capture resolution set to 1280x800\n"
    RES_DERIVED = "[2026-08-24 22:39:48][308.923932] >>> Capture resolution set to 1280x360\n"
    STOP = "[2026-08-24 22:40:02][322.711832] >>> Stopped desktop stream\n"
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

    def test_capture_resolution(self):
        self.assertEqual(stream_mode.RES_RE.search(self.RES).groups(), ("1280", "800"))

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

    def test_created_output_name(self):
        self.assertEqual(stream_mode.CREATED_RE.search(self.CREATED).group(1), "HEADLESS-2")


class TestIsFullscreen(unittest.TestCase):
    """niri offers only a toggle, so a wrong answer un-fullscreens the game."""

    def test_window_filling_the_output(self):
        self.assertTrue(
            stream_mode.is_fullscreen(window(1, 2, size=(1280, 800)), (1280, 800))
        )

    def test_tiled_window(self):
        self.assertFalse(stream_mode.is_fullscreen(window(1, 2), (1280, 800)))

    def test_unknown_output_size(self):
        self.assertFalse(stream_mode.is_fullscreen(window(1, 2), None))

    def test_missing_layout(self):
        self.assertFalse(stream_mode.is_fullscreen({"id": 1}, (1280, 800)))


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

    def test_parent_pids_handles_comm_with_spaces(self):
        """/proc/PID/stat comm can contain spaces and parentheses."""
        self.assertIsInstance(stream_mode.parent_pids(os.getpid()), list)


class TestLearnedClients(unittest.TestCase):
    def test_default_until_learned(self):
        self.assertEqual(
            stream_mode.client_size("123", {}),
            (stream_mode.DEFAULT_WIDTH, stream_mode.DEFAULT_HEIGHT),
        )

    def test_learned_value_used(self):
        self.assertEqual(stream_mode.client_size("123", {"123": [1920, 1200]}), (1920, 1200))

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
        self.created = []
        self.removed = []
        self.moved = []
        self.fullscreened = []
        self.saved = []
        self.windows = [window(7, 500)]
        self.next_name = stream_mode.OUTPUT_NAME

        self._real = {
            k: getattr(stream_mode, k)
            for k in (
                "create_virtual_output",
                "remove_virtual_output",
                "move_window_to_output",
                "fullscreen_window",
                "focus_window",
                "niri_windows",
                "output_logical_size",
                "parent_pids",
                "existing_output_names",
                "enable_output",
                "load_clients",
                "save_clients",
            )
        }

        def create(w, h, r, name=None):
            self.created.append((w, h, r))
            return name or self.next_name

        stream_mode.create_virtual_output = create
        stream_mode.remove_virtual_output = lambda n: self.removed.append(n)
        stream_mode.move_window_to_output = lambda wid, out: self.moved.append((wid, out))
        stream_mode.fullscreen_window = lambda wid: self.fullscreened.append(wid)
        stream_mode.focus_window = lambda wid: None
        stream_mode.niri_windows = lambda: self.windows
        stream_mode.output_logical_size = lambda name: (1280, 800)
        stream_mode.parent_pids = lambda pid, limit=8: []
        stream_mode.existing_output_names = lambda: set()
        self.enabled = []
        stream_mode.enable_output = lambda n: self.enabled.append(n)
        stream_mode.load_clients = lambda path=None: {}
        stream_mode.save_clients = lambda c, path=None: self.saved.append(c)

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def session(self, stage_timeout=0):
        return stream_mode.Session(stage_timeout=stage_timeout)

    def test_startup_creates_the_output_before_any_connect(self):
        """A client that connected while this was not running never re-triggers."""
        s = self.session()
        self.assertTrue(s.ensure_output())
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_startup_adopts_an_existing_output(self):
        """It survives a service restart, so it is usually already there."""
        stream_mode.existing_output_names = lambda: {stream_mode.OUTPUT_NAME}
        s = self.session()
        self.assertFalse(s.ensure_output())
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)
        self.assertEqual(self.created, [])
        self.assertEqual(self.removed, [])

    def test_connect_creates_an_output_at_the_default_size(self):
        s = self.session()
        self.assertTrue(s.connect(123, "ali-steam-deck"))
        self.assertEqual(
            self.created,
            [(stream_mode.DEFAULT_WIDTH, stream_mode.DEFAULT_HEIGHT, stream_mode.DEFAULT_REFRESH)],
        )
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_connect_uses_a_learned_size(self):
        stream_mode.load_clients = lambda path=None: {"123": [1920, 1200]}
        s = self.session()
        s.connect(123, "deck")
        self.assertEqual(self.created, [(1920, 1200, stream_mode.DEFAULT_REFRESH)])

    def test_reconnect_reuses_the_output(self):
        """Recreating it would invalidate the source Steam has remembered."""
        s = self.session()
        s.connect(123, "deck")
        self.assertFalse(s.connect(123, "deck"))
        self.assertEqual(len(self.created), 1)
        self.assertEqual(self.removed, [])

    def test_connect_rebuilds_only_when_the_size_is_wrong(self):
        stream_mode.load_clients = lambda path=None: {"123": [1920, 1200]}
        stream_mode.output_logical_size = lambda name: (1280, 800)
        s = self.session()
        s.connect(123, "deck")
        s.connect(123, "deck")
        self.assertEqual(self.removed, [stream_mode.OUTPUT_NAME])
        self.assertEqual(self.created[-1], (1920, 1200, stream_mode.DEFAULT_REFRESH))

    def test_staging_creates_the_output_if_none_exists(self):
        """A game can start before any connect is seen."""
        s = self.session()
        self.assertTrue(s.request(500, 2854740))
        self.assertTrue(s.poll())
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])

    def test_teardown_removes_the_output_once(self):
        s = self.session()
        s.connect(123, "deck")
        self.assertTrue(s.teardown())
        self.assertEqual(self.removed, [stream_mode.OUTPUT_NAME])
        self.assertFalse(s.teardown())
        self.assertEqual(self.removed, [stream_mode.OUTPUT_NAME])

    def test_idle_keeps_the_output(self):
        """Removing it between sessions broke Steam's remembered source.

        Steam resolves that source on its main loop when a session starts; a
        source that has gone away made the request fail, stalling the loop past
        its watchdog and segfaulting the client.
        """
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.poll()
        self.assertFalse(s.idle())
        self.assertEqual(self.removed, [])
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_idle_clears_the_staged_game(self):
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.poll()
        s.idle()
        self.assertFalse(s.unstage(500))

    def test_teardown_without_output_does_nothing(self):
        self.assertFalse(self.session().teardown())
        self.assertEqual(self.removed, [])

    def test_an_existing_output_of_the_right_size_is_adopted(self):
        """Replacing it is what kept invalidating Steam's remembered source."""
        stream_mode.existing_output_names = lambda: {stream_mode.OUTPUT_NAME}
        s = self.session()
        self.assertFalse(s.connect(123, "deck"))
        self.assertEqual(self.removed, [])
        self.assertEqual(self.created, [])
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_missing_name_is_not_treated_as_success(self):
        self.next_name = None
        s = self.session()
        self.assertFalse(s.connect(123, "deck"))
        self.assertIsNone(s.output)

    def test_stage_moves_and_fullscreens_on_the_virtual_output(self):
        s = self.session()
        s.connect(123, "deck")
        self.assertTrue(s.request(500, 2854740))
        self.assertTrue(s.poll())
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])
        self.assertEqual(self.fullscreened, [7])

    def test_stage_does_not_toggle_an_already_fullscreen_game(self):
        self.windows = [window(7, 500, size=(1280, 800))]
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.poll()
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
        self.assertFalse(s.poll())
        self.assertIsNotNone(s.pending)

        self.windows = [window(7, 500)]
        self.assertTrue(s.poll())
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
            s.poll()
        self.assertLess(__import__("time").monotonic() - start, 1.0)

    def test_gives_up_once_the_deadline_passes(self):
        self.windows = []
        s = self.session(stage_timeout=0)
        s.connect(123, "deck")
        s.request(500, 2854740)
        self.assertFalse(s.poll())
        self.assertIsNone(s.pending)
        self.assertEqual(self.moved, [])

    def test_learn_records_the_first_resolution_only(self):
        """Steam re-logs a derived resolution after negotiating."""
        s = self.session()
        s.connect(123, "deck")
        self.assertTrue(s.learn(1280, 800))
        self.assertFalse(s.learn(1280, 360))
        self.assertEqual(self.saved, [{"123": [1280, 800]}])

    def test_learn_needs_a_connected_client(self):
        self.assertFalse(self.session().learn(1280, 800))
        self.assertEqual(self.saved, [])

    def test_learning_resets_between_sessions(self):
        s = self.session()
        s.connect(123, "deck")
        s.learn(1280, 800)
        s.teardown()
        s.connect(123, "deck")
        self.assertTrue(s.learn(1920, 1200))

    def test_unstage_only_for_the_staged_game(self):
        s = self.session()
        s.connect(123, "deck")
        s.request(500, 2854740)
        s.poll()
        self.assertFalse(s.unstage(999))
        self.assertTrue(s.unstage(500))
        self.assertFalse(s.unstage(500))


class TestOutputLifetime(unittest.TestCase):
    """The output is created once and never disabled.

    Disabling one does not merely take it out of the layout: niri reports it as
    not connected, it vanishes from `niri msg outputs`, the portal stops
    offering it, and `on` cannot bring it back — while the name stays taken, so
    it cannot be recreated either. Workspaces are kept off it by giving them a
    home output instead.
    """

    def setUp(self):
        self.enabled = []
        self.created = []
        self.names = set()
        self._real = {
            k: getattr(stream_mode, k)
            for k in (
                "create_virtual_output",
                "enable_output",
                "existing_output_names",
                "output_logical_size",
                "load_clients",
                "publish_target",
                "withdraw_target",
            )
        }
        stream_mode.create_virtual_output = lambda w, h, r, name=None: (
            self.created.append((w, h)) or stream_mode.OUTPUT_NAME
        )
        stream_mode.enable_output = lambda n: self.enabled.append(n)
        stream_mode.existing_output_names = lambda: self.names
        stream_mode.output_logical_size = lambda name: (1280, 800)
        stream_mode.load_clients = lambda path=None: {}
        stream_mode.publish_target = lambda *a, **k: True
        stream_mode.withdraw_target = lambda: True

    def tearDown(self):
        for k, v in self._real.items():
            setattr(stream_mode, k, v)

    def test_enabled_on_creation(self):
        s = stream_mode.Session(stage_timeout=0)
        s.ensure_output()
        self.assertEqual(self.enabled, [stream_mode.OUTPUT_NAME])

    def test_enabled_on_connect(self):
        """Steam picks its capture source before any stream is logged."""
        s = stream_mode.Session(stage_timeout=0)
        s.connect(123, "deck")
        self.assertIn(stream_mode.OUTPUT_NAME, self.enabled)

    def test_ending_a_stream_removes_the_output(self):
        """Removed, not disabled: niri cannot re-enable a disabled virtual
        output, and leaving an idle one in the layout is what let a KVM switch
        empty the desktop onto it."""
        removed = []
        real = stream_mode.remove_virtual_output
        stream_mode.remove_virtual_output = lambda n: removed.append(n)
        try:
            s = stream_mode.Session(stage_timeout=0)
            s.ensure_output()
            s.begin_stream()
            s.end_stream()
        finally:
            stream_mode.remove_virtual_output = real
        self.assertEqual(removed, [stream_mode.OUTPUT_NAME])
        self.assertIsNone(s.output)

    def test_the_watchdog_leaves_it_absent_while_idle(self):
        """It is meant to be gone between streams."""
        removed = []
        real = stream_mode.remove_virtual_output
        stream_mode.remove_virtual_output = lambda n: removed.append(n)
        try:
            s = stream_mode.Session(stage_timeout=0)
            s.ensure_output()
            s.end_stream()
            self.created.clear()
            s.last_check = 0.0
            self.assertFalse(s.watchdog(interval=0))
        finally:
            stream_mode.remove_virtual_output = real
        self.assertEqual(self.created, [])

    def test_adopts_a_healthy_output_that_already_exists(self):
        def collide(w, h, r, name=None):
            raise stream_mode.OutputExists(stream_mode.OUTPUT_NAME)

        stream_mode.create_virtual_output = collide
        self.names = {stream_mode.OUTPUT_NAME}
        s = stream_mode.Session(stage_timeout=0)
        self.assertFalse(s.ensure_output())
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)
        self.assertIn(stream_mode.OUTPUT_NAME, self.enabled)

    def test_replaces_an_output_that_holds_its_name_but_is_unusable(self):
        """An output an earlier revision disabled cannot be re-enabled.

        It stays absent from `niri msg outputs` while blocking the name, so
        adopting it looped forever: create collides, enable fails, the watchdog
        sees nothing and tries again.
        """
        removed = []
        calls = {"n": 0}

        def create(w, h, r, name=None):
            calls["n"] += 1
            if calls["n"] == 1:
                raise stream_mode.OutputExists(stream_mode.OUTPUT_NAME)
            self.created.append((w, h))
            return stream_mode.OUTPUT_NAME

        stream_mode.create_virtual_output = create
        real_remove = stream_mode.remove_virtual_output
        stream_mode.remove_virtual_output = lambda n: removed.append(n)
        try:
            self.names = set()  # niri does not list it
            s = stream_mode.Session(stage_timeout=0)
            self.assertTrue(s.ensure_output())
        finally:
            stream_mode.remove_virtual_output = real_remove

        self.assertEqual(removed, [stream_mode.OUTPUT_NAME])
        self.assertEqual(len(self.created), 1)
        self.assertEqual(s.output, stream_mode.OUTPUT_NAME)

    def test_watchdog_rebuilds_a_vanished_output(self):
        s = stream_mode.Session(stage_timeout=0)
        self.names = set()
        s.ensure_output()
        self.assertEqual(len(self.created), 1)
        s.last_check = 0.0
        self.assertTrue(s.watchdog(interval=0))
        self.assertEqual(len(self.created), 2)

    def test_watchdog_leaves_a_healthy_output_alone(self):
        s = stream_mode.Session(stage_timeout=0)
        s.ensure_output()
        self.names = {stream_mode.OUTPUT_NAME}
        self.assertFalse(s.watchdog(interval=0))
        self.assertEqual(len(self.created), 1)

    def test_watchdog_is_rate_limited(self):
        s = stream_mode.Session(stage_timeout=0)
        s.ensure_output()
        self.names = set()
        s.last_check = 0.0
        s.watchdog(interval=0)
        before = len(self.created)
        for _ in range(10):
            s.watchdog(interval=3600)
        self.assertEqual(len(self.created), before)


class TestStreamTarget(unittest.TestCase):
    """The gamescope shim reads this to size a launching game."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._real = stream_mode.TARGET_FILE
        stream_mode.TARGET_FILE = os.path.join(self.tmp.name, "sub", "target.json")

    def tearDown(self):
        stream_mode.TARGET_FILE = self._real
        self.tmp.cleanup()

    def read(self):
        with open(stream_mode.TARGET_FILE) as fh:
            return json.load(fh)

    def test_publishes_what_the_shim_needs(self):
        self.assertTrue(stream_mode.publish_target("steam", 1280, 800, 60))
        self.assertEqual(
            self.read(), {"output": "steam", "width": 1280, "height": 800, "refresh": 60}
        )

    def test_refresh_is_optional(self):
        stream_mode.publish_target("steam", 1280, 800)
        self.assertNotIn("refresh", self.read())

    def test_withdraw_removes_it(self):
        stream_mode.publish_target("steam", 1280, 800)
        self.assertTrue(stream_mode.withdraw_target())
        self.assertFalse(os.path.exists(stream_mode.TARGET_FILE))

    def test_withdraw_is_idempotent(self):
        """It runs on shutdown paths that may not have published anything."""
        self.assertFalse(stream_mode.withdraw_target())

    def test_publish_replaces_atomically(self):
        """A game launch can read this at any moment; a partial file is worse
        than a stale one."""
        stream_mode.publish_target("steam", 1280, 800)
        stream_mode.publish_target("steam", 1920, 1200)
        self.assertEqual(self.read()["width"], 1920)
        leftovers = [f for f in os.listdir(os.path.dirname(stream_mode.TARGET_FILE))
                     if f.endswith(".new")]
        self.assertEqual(leftovers, [])


class TestFollow(unittest.TestCase):
    def test_partial_line_is_withheld_until_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "log.txt")
            with open(path, "w") as fh:
                fh.write(">>> Starting")
            lines = stream_mode.follow(path, seek_to_end=False)
            with open(path, "a") as fh:
                fh.write(" desktop stream\n")
            self.assertEqual(next(lines), ">>> Starting desktop stream\n")

    def test_reads_appended_lines_and_survives_truncation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "log.txt")
            with open(path, "w") as fh:
                fh.write("preexisting\n")

            # seek_to_end=False so the generator has a deterministic start: it
            # is lazy, so with the default the seek would not happen until the
            # first next(), by which time the appended line is already there.
            lines = stream_mode.follow(path, seek_to_end=False)
            self.assertEqual(next(lines), "preexisting\n")

            with open(path, "a") as fh:
                fh.write("first\n")
            self.assertEqual(next(lines), "first\n")

            with open(path, "w") as fh:
                fh.write("after truncation\n")
            self.assertEqual(next(lines), "after truncation\n")

    def test_missing_file_yields_none_rather_than_blocking(self):
        """The watcher follows two logs; a missing one must not stall the other."""
        with tempfile.TemporaryDirectory() as tmp:
            lines = stream_mode.follow(
                os.path.join(tmp, "absent.txt"), seek_to_end=False, idle_yield=True
            )
            self.assertIsNone(next(lines))


if __name__ == "__main__":
    unittest.main()

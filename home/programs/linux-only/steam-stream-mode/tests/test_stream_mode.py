"""Tests for stream-mode's virtual output lifecycle and log parsing.

Run: python3 -m unittest discover -s tests -v
"""

import json
import os
import sys
import tempfile
import time
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
                "fullscreen_window",
                "focus_window",
                "niri_windows",
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
        stream_mode.fullscreen_window = lambda wid: self.fullscreened.append(wid)
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

    def test_stage_moves_and_fullscreens_on_the_virtual_output(self):
        s = self.session()
        s.connect(123, "deck")
        self.assertTrue(s.request(500, 2854740))
        self.assertTrue(s.on_windows(self.windows))
        self.assertEqual(self.moved, [(7, stream_mode.OUTPUT_NAME)])
        self.assertEqual(self.fullscreened, [7])

    def test_stage_does_not_toggle_an_already_fullscreen_game(self):
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

        def begin_stream(self):
            self.calls.append(("begin_stream",))

        def request(self, pid, game_id):
            self.calls.append(("request", pid, game_id))

        def learn(self, w, h):
            self.calls.append(("learn", w, h))

        def unstage(self, pid=None):
            self.calls.append(("unstage", pid))

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

    def test_malformed_events_are_ignored(self):
        stream_mode.handle_niri_event(self.s, "not json\n")
        stream_mode.handle_niri_event(self.s, json.dumps({"SomethingElse": {}}))
        self.assertEqual(self.s.calls, [])

    def test_stream_start_publishes_and_clears_the_removal(self):
        remove_at = stream_mode.handle_steam_line(
            self.s, "[x] >>> Starting desktop stream\n", 123.0
        )
        self.assertIsNone(remove_at)
        self.assertIn(("begin_stream",), self.s.calls)

    def test_stream_stop_schedules_the_removal(self):
        remove_at = stream_mode.handle_steam_line(
            self.s, "[x] >>> Stopped desktop stream\n", None
        )
        self.assertIsNotNone(remove_at)
        self.assertGreater(remove_at, time.monotonic())

    def test_a_game_window_line_requests_staging(self):
        stream_mode.handle_steam_line(
            self.s,
            "[x] Adding window 4194306 (4) for process 2331545 and gameID 2854740\n",
            None,
        )
        self.assertIn(("request", 2331545, 2854740), self.s.calls)

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
            path = self.write(tmp, "noise\n>>> Starting desktop stream\nmore\n")
            self.assertTrue(stream_mode.stream_in_progress(path))

    def test_started_then_stopped(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write(
                tmp,
                ">>> Starting desktop stream\n>>> Stopped desktop stream\n",
            )
            self.assertFalse(stream_mode.stream_in_progress(path))

    def test_restarted_after_stopping(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write(
                tmp,
                ">>> Starting desktop stream\n>>> Stopped desktop stream\n"
                ">>> Starting desktop stream\n",
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
        stream_mode.TARGET_FILE = os.path.join(self.tmp.name, "sub", "target")

    def tearDown(self):
        stream_mode.TARGET_FILE = self._real
        self.tmp.cleanup()

    def read(self):
        with open(stream_mode.TARGET_FILE) as fh:
            return fh.read()

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
        self.assertEqual(self.read().strip(), "1920x1200")
        leftovers = [f for f in os.listdir(os.path.dirname(stream_mode.TARGET_FILE))
                     if f.endswith(".new")]
        self.assertEqual(leftovers, [])



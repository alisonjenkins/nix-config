"""Tests for stream-mode's mode selection and log parsing.

Run: python3 -m unittest discover -s tests -v
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import stream_mode  # noqa: E402


def mode(width, height, refresh_mhz, preferred=False):
    return {
        "width": width,
        "height": height,
        "refresh_rate": refresh_mhz,
        "is_preferred": preferred,
    }


# The real DP-2 mode list on ali-desktop, trimmed to the interesting entries.
DP2 = [
    mode(5120, 1440, 119999, preferred=True),
    mode(3840, 1080, 119974, preferred=True),
    mode(2560, 1440, 119998),
    mode(2560, 1440, 59951),
    mode(1920, 1080, 120000),
    mode(1920, 1080, 59940),
    mode(1280, 800, 59810),
]


class TestPickMode(unittest.TestCase):
    def test_exact_match_wins(self):
        """A Steam Deck asks for 1280x800 and DP-2 advertises exactly that."""
        chosen = stream_mode.pick_mode(DP2, 1280, 800)
        self.assertEqual((chosen["width"], chosen["height"]), (1280, 800))

    def test_exact_match_prefers_higher_refresh(self):
        chosen = stream_mode.pick_mode(DP2, 2560, 1440)
        self.assertEqual(chosen["refresh_rate"], 119998)

    def test_unmatched_resolution_picks_closest_aspect(self):
        """A 1920x1200 (16:10) client has no exact mode here.

        16:10 is closer to 1280x800 than to any 16:9 mode, so letterboxing is
        minimised by picking it even though it is far smaller.
        """
        chosen = stream_mode.pick_mode(DP2, 1920, 1200)
        self.assertEqual((chosen["width"], chosen["height"]), (1280, 800))

    def test_sixteen_by_nine_client_gets_largest_sixteen_by_nine(self):
        chosen = stream_mode.pick_mode(DP2, 1600, 900)
        self.assertEqual((chosen["width"], chosen["height"]), (1920, 1080))

    def test_never_picks_the_ultrawide_for_a_normal_client(self):
        """The whole point: 5120x1440 is what produces the letterboxing."""
        for width, height in [(1280, 800), (1920, 1080), (1600, 900), (2560, 1440)]:
            chosen = stream_mode.pick_mode(DP2, width, height)
            self.assertNotEqual(
                (chosen["width"], chosen["height"]),
                (5120, 1440),
                "picked the ultrawide for a {}x{} client".format(width, height),
            )

    def test_empty_mode_list(self):
        self.assertIsNone(stream_mode.pick_mode([], 1280, 800))


class TestModeString(unittest.TestCase):
    def test_matches_niri_format(self):
        """niri msg fails on a near miss, so the format has to be exact."""
        self.assertEqual(stream_mode.mode_string(mode(1280, 800, 59810)), "1280x800@59.810")
        self.assertEqual(
            stream_mode.mode_string(mode(5120, 1440, 119999)), "5120x1440@119.999"
        )


class TestLogParsing(unittest.TestCase):
    """Verbatim lines from ali-desktop's streaming_log.txt."""

    START = "[2026-08-24 22:39:48][308.657953] >>> Starting desktop stream\n"
    RES = "[2026-08-24 22:39:48][308.792672] >>> Capture resolution set to 1280x800\n"
    RES_DERIVED = "[2026-08-24 22:39:48][308.923932] >>> Capture resolution set to 1280x360\n"
    STOP = "[2026-08-24 22:40:02][322.711832] >>> Stopped desktop stream\n"
    NOISE = "[2026-08-24 22:39:49][309.831738] Setting target bitrate to 10000 Kbit/s\n"

    def test_start_and_stop_detected(self):
        self.assertTrue(stream_mode.START_RE.search(self.START))
        self.assertTrue(stream_mode.STOP_RE.search(self.STOP))
        self.assertFalse(stream_mode.START_RE.search(self.STOP))

    def test_resolution_extracted(self):
        match = stream_mode.RES_RE.search(self.RES)
        self.assertEqual(match.groups(), ("1280", "800"))

    def test_noise_ignored(self):
        for pattern in (stream_mode.START_RE, stream_mode.STOP_RE, stream_mode.RES_RE):
            self.assertFalse(pattern.search(self.NOISE))


class TestSession(unittest.TestCase):
    """Session applies at most one change and undoes exactly that one."""

    def setUp(self):
        self.applied = []
        self._real_apply = stream_mode.apply_mode
        self._real_state = stream_mode.output_state
        stream_mode.apply_mode = lambda m, name=None: self.applied.append(
            (m["width"], m["height"])
        )
        stream_mode.output_state = lambda name=None: (DP2, DP2[0])

    def tearDown(self):
        stream_mode.apply_mode = self._real_apply
        stream_mode.output_state = self._real_state

    def test_applies_once_then_restores(self):
        session = stream_mode.Session()
        session.start(1280, 800)
        self.assertEqual(self.applied, [(1280, 800)])
        session.restore()
        self.assertEqual(self.applied, [(1280, 800), (5120, 1440)])

    def test_derived_resolution_does_not_chase_its_own_tail(self):
        """Steam re-logs the capture resolution after the output changes."""
        session = stream_mode.Session()
        session.start(1280, 800)
        session.start(1280, 360)
        self.assertEqual(self.applied, [(1280, 800)])

    def test_restore_is_idempotent(self):
        session = stream_mode.Session()
        session.start(1280, 800)
        session.restore()
        session.restore()
        self.assertEqual(self.applied, [(1280, 800), (5120, 1440)])

    def test_restore_without_start_does_nothing(self):
        stream_mode.Session().restore()
        self.assertEqual(self.applied, [])

    def test_no_change_when_already_correct(self):
        stream_mode.output_state = lambda name=None: (DP2, DP2[-1])
        session = stream_mode.Session()
        session.start(1280, 800)
        self.assertEqual(self.applied, [])
        session.restore()
        self.assertEqual(self.applied, [])


class TestFollow(unittest.TestCase):
    def test_partial_line_is_withheld_until_complete(self):
        """Steam writes a line in more than one syscall often enough to matter."""
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "streaming_log.txt")
            with open(path, "w") as fh:
                fh.write(">>> Starting")
            lines = stream_mode.follow(path, seek_to_end=False)
            with open(path, "a") as fh:
                fh.write(" desktop stream\n")
            self.assertEqual(next(lines), ">>> Starting desktop stream\n")

    def test_reads_appended_lines_and_survives_truncation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "streaming_log.txt")
            with open(path, "w") as fh:
                fh.write("preexisting\n")

            # seek_to_end=False so the generator has a deterministic start.
            # It is lazy, so with the default the seek would not happen until
            # the first next() — by which time the appended line is already
            # there and would be skipped.
            lines = stream_mode.follow(path, seek_to_end=False)
            self.assertEqual(next(lines), "preexisting\n")

            with open(path, "a") as fh:
                fh.write("first\n")
            self.assertEqual(next(lines), "first\n")

            # Steam truncates this log when the client restarts.
            with open(path, "w") as fh:
                fh.write("after truncation\n")
            self.assertEqual(next(lines), "after truncation\n")


if __name__ == "__main__":
    unittest.main()

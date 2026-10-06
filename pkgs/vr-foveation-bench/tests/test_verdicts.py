"""Tests for the verdicts record: parse, render, upsert, row from a report."""

import unittest

from vr_foveation_bench import verdicts

HEADER = "| game | date | driver | verdict | gpuTimeChange | powerChange | noise | artefacts |"


def row(game="Fallout 4 VR", driver="mesa 26.0", **over):
    base = {"game": game, "date": "2026-10-06T12:00:00Z", "driver": driver, "verdict": "go",
            "gpuTimeChange": "-7.3%", "powerChange": "n/a",
            "noise": "GPU ±0.42 ms; power n/a", "artefacts": "none seen"}
    base.update(over)
    return base


def report(**over):
    verdict = {"game": "Fallout 4 VR", "date": "2026-10-06T12:00:00Z", "driver": "mesa 26.0",
               "verdict": "go", "gpuTimeChange": -0.0734, "powerChange": -0.12,
               "noise": {"medianGpuMs": {"off": 0.42, "on": 0.1},
                         "meanPowerW": {"off": 0.5, "on": 1.14}},
               "artefacts": "tolerable", "reason": "x"}
    verdict.update(over)
    return {"reports": [{}, {}], "verdict": verdict}


class RowFromReport(unittest.TestCase):
    def test_renders_all_columns(self):
        got = verdicts.row_from_report(report(), "edges shimmer")
        self.assertEqual(list(got), list(verdicts.COLUMNS))
        self.assertEqual(got, {
            "game": "Fallout 4 VR", "date": "2026-10-06T12:00:00Z", "driver": "mesa 26.0",
            "verdict": "go", "gpuTimeChange": "-7.3%", "powerChange": "-12.0%",
            "noise": "GPU ±0.42 ms; power ±1.1 W", "artefacts": "edges shimmer"})

    def test_positive_change_has_plus_sign(self):
        got = verdicts.row_from_report(report(gpuTimeChange=0.021), "")
        self.assertEqual(got["gpuTimeChange"], "+2.1%")

    def test_none_renders_na(self):
        got = verdicts.row_from_report(
            report(powerChange=None, noise={"medianGpuMs": None, "meanPowerW": None}), "")
        self.assertEqual(got["powerChange"], "n/a")
        self.assertEqual(got["noise"], "GPU n/a; power n/a")

    def test_invalid_verdict_names_the_value(self):
        with self.assertRaisesRegex(ValueError, "maybe"):
            verdicts.row_from_report(report(verdict="maybe"), "")

    def test_newline_in_notes_collapses(self):
        got = verdicts.row_from_report(report(), "a\nb\r\nc")
        self.assertEqual(got["artefacts"], "a b c")

    def test_missing_key_is_a_value_error(self):
        bad = report()
        del bad["verdict"]["driver"]
        with self.assertRaisesRegex(ValueError, "driver"):
            verdicts.row_from_report(bad, "")


class Table(unittest.TestCase):
    def test_round_trip(self):
        rows = [row(), row(game="Skyrim VR", artefacts="a | b \\ c", verdict="no-go")]
        self.assertEqual(verdicts.parse_table(verdicts.render_table(rows)), rows)

    def test_pipe_is_escaped_in_output(self):
        text = verdicts.render_table([row(artefacts="a|b")])
        self.assertIn("a\\|b", text)
        self.assertEqual(len(verdicts.parse_table(text)), 1)

    def test_newline_never_breaks_the_table(self):
        text = verdicts.render_table([row(artefacts="a\nb")])
        self.assertEqual(len([ln for ln in text.splitlines() if ln.strip()]), 3)

    def test_render_rejects_invalid_verdict(self):
        with self.assertRaisesRegex(ValueError, "yes"):
            verdicts.render_table([row(verdict="yes")])

    def test_parse_rejects_invalid_verdict(self):
        text = verdicts.render_table([row()]).replace("| go |", "| yes |")
        with self.assertRaisesRegex(ValueError, "yes"):
            verdicts.parse_table(text)

    def test_parse_no_table_is_empty(self):
        self.assertEqual(verdicts.parse_table("just prose\n"), [])

    def test_header_is_exact(self):
        self.assertEqual(verdicts.render_table([]).splitlines()[0], HEADER)


class Upsert(unittest.TestCase):
    def test_creates_table_in_empty_text(self):
        out = verdicts.upsert("", row())
        self.assertEqual(verdicts.parse_table(out), [row()])
        self.assertTrue(out.endswith("\n"))

    def test_creates_table_after_prose(self):
        out = verdicts.upsert("# Verdicts\n\nSome prose.\n", row())
        self.assertTrue(out.startswith("# Verdicts\n\nSome prose.\n\n" + HEADER))
        self.assertEqual(verdicts.parse_table(out), [row()])

    def test_same_game_different_driver_adds(self):
        out = verdicts.upsert(verdicts.upsert("", row()), row(driver="mesa 26.1"))
        self.assertEqual([r["driver"] for r in verdicts.parse_table(out)],
                         ["mesa 26.0", "mesa 26.1"])

    def test_same_game_and_driver_replaces_in_place(self):
        text = verdicts.upsert(verdicts.upsert("", row()), row(game="Skyrim VR"))
        out = verdicts.upsert(text, row(verdict="no-go", gpuTimeChange="+1.0%"))
        rows = verdicts.parse_table(out)
        self.assertEqual([r["game"] for r in rows], ["Fallout 4 VR", "Skyrim VR"])
        self.assertEqual(rows[0]["verdict"], "no-go")

    def test_prose_before_and_after_is_kept(self):
        base = "intro\n\n" + verdicts.render_table([row(), row(game="Skyrim VR")]) + "\nafter text\n"
        out = verdicts.upsert(base, row(verdict="inconclusive"))
        self.assertTrue(out.startswith("intro\n\n" + HEADER))
        self.assertTrue(out.endswith("\nafter text\n"))
        self.assertEqual(verdicts.parse_table(out)[0]["verdict"], "inconclusive")
        self.assertEqual(verdicts.parse_table(out)[1], row(game="Skyrim VR"))

    def test_idempotent(self):
        once = verdicts.upsert("intro\n", row())
        self.assertEqual(verdicts.upsert(once, row()), once)
        with_tail = once + "\ntail\n"
        self.assertEqual(verdicts.upsert(with_tail, row()), with_tail)


if __name__ == "__main__":
    unittest.main()

"""Tests for scripts/adr-sources.py.

Run: python3 -m unittest discover -s scripts/tests -p 'test_adr_sources.py'
"""

from __future__ import annotations

import contextlib
import datetime as dt
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from email.message import Message
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parent.parent / "adr-sources.py"
spec = importlib.util.spec_from_file_location("adr_sources", SCRIPT)
assert spec and spec.loader
adr = importlib.util.module_from_spec(spec)
sys.modules["adr_sources"] = adr
spec.loader.exec_module(adr)

TODAY = dt.date(2026, 10, 30)
PINNED = "https://raw.githubusercontent.com/torvalds/linux/v6.18/doc.rst"
FLOATING = "https://docs.example.test/stable/page"


def entry(*urls, **over):
    base = {"urls": list(urls) or [PINNED], "reviewed": "2026-10-30"}
    base.update(over)
    return base


def manifest(**sources):
    return {"sources": sources,
            "max_review_days": {"pinned": 365, "floating": 90}}


class Normalise(unittest.TestCase):
    def test_folds_whitespace_curly_quotes_and_backticks(self):
        self.assertEqual(adr.normalise("a\n  “b”\t`c`"), 'a "b" c')

    def test_strips_markup_and_entities(self):
        page = "<p>no <code>greater</code> than&nbsp;x &amp; y</p><script>z</script>"
        self.assertEqual(adr.normalise(page, markup=True), "no greater than x & y")

    def test_inline_tags_do_not_split_words_block_tags_do(self):
        page = "<p>offloads<a href='x'>.</a></p><p>next</p><pre>a<span>b</span></pre>"
        self.assertEqual(adr.normalise(page, markup=True), "offloads. next ab")

    def test_quote_wrapped_across_comment_leaders(self):
        page = "/*\n * they do not meet\n * the 'Prague' bar\n */"
        self.assertIn("they do not meet the 'Prague' bar", adr.normalise(page))


class Quotes(unittest.TestCase):
    def test_double_quoted_and_backticked(self):
        cell = '"first one"; `code()` and "second"'
        self.assertEqual(adr.quotes(cell), ["first one", "code()", "second"])

    def test_quote_containing_backticks_is_taken_whole(self):
        self.assertEqual(adr.quotes('"trumps `all` here"'), ["trumps `all` here"])

    def test_snippet_containing_double_quotes_is_taken_whole(self):
        self.assertEqual(adr.quotes('`.name = "bbr",` (patch)'), ['.name = "bbr",'])


    def test_unterminated_delimiter_is_an_error_not_a_dropped_tail(self):
        with self.assertRaisesRegex(ValueError, "unterminated"):
            adr.quotes('"first" 5" pipe and "second"')


class AdrRows(unittest.TestCase):
    def test_error_names_the_row(self):
        with self.assertRaisesRegex(ValueError, "^Q4: unterminated"):
            adr.adr_rows('| Q4 | f | "never closed | s |\n')

    def test_duplicate_id_is_an_error(self):
        table = '| R1 | a | "one one one" | u |\n| R1 | b | "two two two" | u |\n'
        with self.assertRaisesRegex(ValueError, "R1.*more than once"):
            adr.adr_rows(table)

    TABLE = (
        "| ID | Finding | Quote | Source |\n|---|---|---|---|\n"
        '| R1 | a | "said so" | `u` |\n'
        "| Q10 | b | n/a | none |\n"
        "| Q2 | c | `x \\| y;` and `p|q` | u |\n"
        "prose | S3 |\n")

    def test_ids_quotes_and_na(self):
        rows = adr.adr_rows(self.TABLE)
        self.assertEqual(set(rows), {"R1", "Q10", "Q2"})
        self.assertEqual(rows["R1"], ["said so"])
        self.assertEqual(rows["Q10"], [])

    def test_escaped_pipe_is_a_literal_pipe_and_code_pipes_do_not_split(self):
        self.assertEqual(adr.adr_rows(self.TABLE)["Q2"], ["x | y;", "p|q"])


class Lint(unittest.TestCase):
    ROWS = {"Q1": ["alpha beta"], "Q7": []}

    def good(self):
        return manifest(Q1=entry(), Q7={"none": "absence claim",
                                        "reviewed": "2026-10-30"})

    def test_clean(self):
        self.assertEqual(adr.lint(self.good(), self.ROWS, TODAY), [])

    def test_id_missing_from_manifest_and_orphan(self):
        got = adr.lint(manifest(Q1=entry(), Z9=entry()), {"Q1": ["a"], "Q2": ["b"]},
                       TODAY)
        self.assertIn("Q2: in the ADR, not in the manifest", got)
        self.assertIn("Z9: in the manifest, not in the ADR", got)

    def test_none_needs_a_reason_and_no_quotes_in_the_row(self):
        got = adr.lint(manifest(Q1={"none": " ", "reviewed": "2026-10-30"}),
                       {"Q1": ["alpha"]}, TODAY)
        self.assertIn("Q1: none needs a reason", got)
        self.assertIn("Q1: marked none but the ADR row quotes strings", got)

    def test_row_without_quotes_must_say_why(self):
        got = adr.lint(manifest(Q1=entry()), {"Q1": []}, TODAY)
        self.assertIn("Q1: the ADR row has no quotes; give a none reason", got)

    def test_quoted_row_needs_somewhere_to_look(self):
        got = adr.lint(manifest(Q1={"reviewed": "2026-10-30"}), {"Q1": ["a"]}, TODAY)
        self.assertIn("Q1: give urls or a file to read", got)

    def test_missing_or_malformed_reviewed_is_a_finding_not_a_crash(self):
        got = adr.lint(manifest(Q1={"urls": [PINNED]}), {"Q1": ["alpha beta"]}, TODAY)
        self.assertIn("Q1: missing reviewed", got)
        got = adr.lint(manifest(Q1=entry(reviewed="last week")),
                       {"Q1": ["alpha beta"]}, TODAY)
        self.assertIn("Q1: reviewed 'last week' is not an ISO date", got)

    def test_none_entries_are_review_aged_too(self):
        stale = {"none": "absence", "reviewed": "2025-01-01"}
        got = adr.lint(manifest(Q7=stale), {"Q7": []}, TODAY)
        self.assertTrue(any("365-day limit for pinned" in p for p in got), got)
        probe = {"url": FLOATING, "absent": ["x"]}
        floating = dict(stale, reviewed="2026-06-01", probes=[probe])
        got = adr.lint(manifest(Q7=floating), {"Q7": []}, TODAY)
        self.assertTrue(any("90-day limit for floating" in p for p in got), got)

    def test_probe_urls_count_toward_the_kind(self):
        probe = {"url": FLOATING, "absent": ["x"]}
        got = adr.lint(manifest(Q1=entry(reviewed="2026-06-01", probes=[probe])),
                       {"Q1": ["alpha beta"]}, TODAY)
        self.assertTrue(any("90-day limit for floating" in p for p in got), got)

    def test_overdue_review_by_kind(self):
        got = adr.lint(manifest(Q1=entry(reviewed="2025-01-01")), {"Q1": ["a"]}, TODAY)
        self.assertTrue(any("365-day limit for pinned" in p for p in got))
        got = adr.lint(manifest(Q1=entry(FLOATING, reviewed="2026-06-01")),
                       {"Q1": ["a"]}, TODAY)
        self.assertTrue(any("90-day limit for floating" in p for p in got))


class LintQuotesAndAnchors(unittest.TestCase):
    def lint(self, rows, **over):
        return adr.lint(manifest(Q1=entry(**over)), {"Q1": rows}, TODAY)

    def test_short_or_empty_quotes_prove_nothing(self):
        got = self.lint(["Default: 2", "short", "`` ", "long enough quote"])
        self.assertIn("Q1: quote 'short' is too short to prove anything", got)
        self.assertIn("Q1: quote '`` ' is too short to prove anything", got)
        self.assertFalse(any("long enough" in p for p in got))

    def test_eight_normalised_characters_is_enough(self):
        self.assertEqual(self.lint(["abcd efg"]), [])
        self.assertEqual(self.lint(["abcd   efg"]), [])
        self.assertTrue(self.lint(["abcd  ef"]))
        self.assertTrue(self.lint(["`ab`   `c`"]))

    def test_anchor_keys_and_values_are_checked(self):
        rows = ["long enough quote"]
        self.assertIn("Q1: anchor key 'x' is not a quote index",
                      self.lint(rows, anchor={"x": "near"}))
        self.assertIn("Q1: anchor for quote index 3 is out of range",
                      self.lint(rows, anchor={"3": "near"}))
        self.assertIn("Q1: anchor for quote index 0 needs a non-empty string",
                      self.lint(rows, anchor={"0": " "}))
        self.assertEqual(self.lint(rows, anchor={"0": "near"}), [])


class LintUrlQuotes(unittest.TestCase):
    def lint(self, *urls, rows=("alpha beta", "gamma delta")):
        return adr.lint(manifest(Q1=entry(*urls)), {"Q1": list(rows)}, TODAY)

    def test_out_of_range_index(self):
        got = self.lint({"url": PINNED, "quotes": [2]}, FLOATING)
        self.assertIn(f"Q1: {PINNED}: quote index 2 is out of range", got)

    def test_object_without_url_or_with_bad_indexes(self):
        got = self.lint({"quotes": [0]}, {"url": PINNED, "quotes": ["a"]}, FLOATING)
        self.assertIn("Q1: urls item without a url", got)
        self.assertIn(f"Q1: {PINNED}: quotes must be a list of row quote indexes", got)

    def test_quote_with_no_place_to_look(self):
        got = self.lint({"url": PINNED, "quotes": [0]})
        self.assertIn("Q1: quote index 1 is assigned to no url and no string url or file "
                      "is listed", got)

    def test_clean(self):
        self.assertEqual(self.lint({"url": PINNED, "quotes": [0, 1]}), [])
        self.assertEqual(self.lint({"url": PINNED, "quotes": [0]}, FLOATING), [])


class Floating(unittest.TestCase):
    def test_tag_and_commit_urls_are_pinned_branches_are_not(self):
        pinned = ("https://raw.githubusercontent.com/o/r/v1.20.4/x",
                  "https://github.com/o/r/blob/70e33da/x",
                  "https://git.kernel.org/pub/scm/x.git/patch/?id=218af599fa63")
        floating = ("https://raw.githubusercontent.com/o/r/master/x",
                    "https://docs.example.test/stable/p")
        for url in pinned:
            self.assertFalse(adr.is_floating({}, url), url)
        for url in floating:
            self.assertTrue(adr.is_floating({}, url), url)

    def test_a_branch_named_like_a_version_is_floating(self):
        for url in ("https://raw.githubusercontent.com/google/bbr/v3/x",
                    "https://raw.githubusercontent.com/o/r/v2/x",
                    "https://raw.githubusercontent.com/o/r/1/x",
                    "https://raw.githubusercontent.com/o/r/release/x"):
            self.assertTrue(adr.is_floating({}, url), url)
        for url in ("https://raw.githubusercontent.com/o/r/v1.2/x",
                    "https://raw.githubusercontent.com/o/r/7.1/x",
                    "https://raw.githubusercontent.com/o/r/v1.34.0/x"):
            self.assertFalse(adr.is_floating({}, url), url)

    def test_entry_can_override(self):
        self.assertTrue(adr.is_floating({"floating": True}, PINNED))


class Check(unittest.TestCase):
    ROWS = {"Q1": ["alpha beta"]}

    def run_check(self, entry_, fetcher, rows=None):
        return adr.check(manifest(Q1=entry_), rows or self.ROWS, fetcher)

    def test_present_after_whitespace_folding(self):
        self.assertEqual(self.run_check(entry(), lambda w: "x alpha\n beta y"), [])

    def test_pinned_miss_is_wrong_floating_miss_is_drifted(self):
        pinned = self.run_check(entry(), lambda w: "nothing")
        self.assertEqual(len(pinned), 1)
        self.assertIn("Q1: wrong:", pinned[0])
        floating = self.run_check(entry(FLOATING), lambda w: "nothing")
        self.assertIn("Q1: drifted:", floating[0])

    def test_any_source_of_the_row_may_hold_the_quote(self):
        pages = {PINNED: "nothing", FLOATING: "has alpha beta"}
        self.assertEqual(self.run_check(entry(PINNED, FLOATING), pages.get), [])

    def test_assigned_quote_must_be_in_its_own_url(self):
        pages = {PINNED: "has alpha beta", FLOATING: "nothing"}
        pair = entry({"url": PINNED, "quotes": [0]}, {"url": FLOATING, "quotes": [0]})
        got = self.run_check(pair, pages.get)
        self.assertEqual(len(got), 1)
        self.assertIn(FLOATING, got[0])
        self.assertIn("drifted", got[0])

    def test_assigned_quote_holds_when_every_url_has_it(self):
        pair = entry({"url": PINNED, "quotes": [0]}, {"url": FLOATING, "quotes": [0]})
        self.assertEqual(self.run_check(pair, lambda w: "alpha beta"), [])

    def test_unassigned_quote_may_be_in_any_string_url(self):
        pages = {PINNED: "alpha", FLOATING: "beta"}
        rows = {"Q1": ["alpha", "beta"]}
        mixed = entry({"url": PINNED, "quotes": [0]}, FLOATING)
        self.assertEqual(self.run_check(mixed, pages.get, rows), [])

    def test_an_assignment_is_not_satisfied_by_another_url(self):
        pages = {PINNED: "nothing", FLOATING: "alpha"}
        mixed = entry({"url": PINNED, "quotes": [0]}, FLOATING)
        got = self.run_check(mixed, pages.get, {"Q1": ["alpha"]})
        self.assertEqual(len(got), 1)
        self.assertIn("wrong", got[0])

    def test_anchor_must_precede_the_quote_closely(self):
        rows = {"Q1": ["Default: 2"]}
        page = "Other: x. " + "filler " * 80 + "tcp_ecn Default: 2 end"
        near = self.run_check(entry(anchor={"0": "tcp_ecn"}), lambda w: page, rows)
        self.assertEqual(near, [])
        far = self.run_check(entry(anchor={"0": "Other:"}), lambda w: page, rows)
        self.assertEqual(len(far), 1)
        self.assertIn("anchor 'Other:'", far[0])

    def test_anchor_holds_when_any_occurrence_is_close_enough(self):
        rows = {"Q1": ["Default: 2"]}
        page = "x Default: 2 " + "filler " * 80 + "tcp_ecn Default: 2"
        self.assertEqual(
            self.run_check(entry(anchor={"0": "tcp_ecn"}), lambda w: page, rows), [])

    def test_unreachable_is_reported_not_raised(self):
        def boom(_):
            raise OSError("503")
        self.assertEqual(self.run_check(entry(), boom), ["unreachable: 503"])

    LOCAL = {"file": "/proc/config.gz", "host": "box", "reviewed": "2026-10-30"}

    def run_local(self, local, fetcher):
        unchecked = []
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            got = adr.check(manifest(Q1=local), self.ROWS, fetcher,
                            unchecked=unchecked, hostname="box")
        return got, unchecked, out.getvalue()

    def test_missing_local_file_is_skipped_visibly_and_counted(self):
        def absent(_):
            raise FileNotFoundError("/proc/config.gz")
        got, unchecked, out = self.run_local(self.LOCAL, absent)
        self.assertEqual(got, [])
        self.assertEqual(len(unchecked), 1)
        self.assertIn("skipped /proc/config.gz", out)

    def test_local_file_is_compared_only_on_its_host(self):
        got, unchecked, _ = self.run_local(self.LOCAL, lambda w: "nothing")
        self.assertIn("Q1: drifted:", got[0])
        self.assertEqual(unchecked, [])

    def test_file_without_a_host_or_for_another_host_is_unchecked(self):
        def never(_):
            raise AssertionError("fetched")
        for local in ({"file": "/proc/config.gz", "reviewed": "2026-10-30"},
                      dict(self.LOCAL, host="other")):
            got, unchecked, out = self.run_local(local, never)
            self.assertEqual(got, [])
            self.assertEqual(len(unchecked), 1)
            self.assertIn("file source is host-specific", out)

    def test_each_location_fetched_once(self):
        calls = []

        def counting(where):
            calls.append(where)
            return "alpha beta"
        adr.check(manifest(Q1=entry(), Q2=entry()),
                  {"Q1": ["alpha beta"], "Q2": ["alpha"]}, counting)
        self.assertEqual(calls, [PINNED])

    def test_none_and_quoteless_rows_are_not_fetched(self):
        def never(_):
            raise AssertionError("fetched")
        self.assertEqual(
            adr.check(manifest(Q7={"none": "absence", "reviewed": "2026-10-30"}),
                      {"Q7": []}, never), [])


class FakeResponse:
    headers = {"Content-Type": "text/plain"}

    def __init__(self, body=b"ok"):
        self.body = body

    def read(self):
        return self.body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeOpener:
    def __init__(self, *outcomes):
        self.outcomes = list(outcomes)
        self.calls = 0

    def open(self, req, timeout):
        self.calls += 1
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def http_error(code, headers=None):
    msg = Message()
    for name, value in (headers or {}).items():
        msg[name] = value
    return urllib.error.HTTPError("https://x.test", code, "msg", msg, None)


class Fetch(unittest.TestCase):
    def setUp(self):
        sleeper = mock.patch.object(adr.time, "sleep")
        self.sleep = sleeper.start()
        self.addCleanup(sleeper.stop)

    def test_not_found_is_not_retried(self):
        opener = FakeOpener(http_error(404))
        with self.assertRaisesRegex(OSError, "404"):
            adr.fetch("https://x.test/a", opener)
        self.assertEqual(opener.calls, 1)
        self.sleep.assert_not_called()

    def test_server_error_is_retried_then_succeeds(self):
        opener = FakeOpener(http_error(503), OSError("reset"), FakeResponse(b"body"))
        self.assertEqual(adr.fetch("https://x.test/a", opener), "body")
        self.assertEqual(opener.calls, 3)

    def test_gives_up_after_the_last_attempt(self):
        opener = FakeOpener(*[http_error(503)] * adr.FETCH_TRIES)
        with self.assertRaises(OSError):
            adr.fetch("https://x.test/a", opener)
        self.assertEqual(opener.calls, adr.FETCH_TRIES)

    def test_github_rate_limit_is_its_own_error_and_not_retried(self):
        opener = FakeOpener(http_error(403, {"X-RateLimit-Remaining": "0"}))
        with self.assertRaises(adr.RateLimited):
            adr.fetch("https://api.github.com/a", opener)
        self.assertEqual(opener.calls, 1)
        self.sleep.assert_not_called()

    def test_other_403_is_a_plain_error(self):
        opener = FakeOpener(http_error(403, {"X-RateLimit-Remaining": "12"}))
        with self.assertRaises(OSError) as ctx:
            adr.fetch("https://api.github.com/a", opener)
        self.assertNotIsInstance(ctx.exception, adr.RateLimited)

    def test_check_reports_rate_limit_apart_from_unreachable(self):
        def limited(where):
            raise adr.RateLimited(f"{where}: HTTP Error 403")
        got = adr.check(manifest(Q1=entry()), {"Q1": ["alpha beta"]}, limited)
        self.assertEqual(got, [f"rate limited: {PINNED}"])

    def test_transient_classification(self):
        self.assertTrue(adr.transient(http_error(429)))
        self.assertTrue(adr.transient(OSError("timed out")))
        self.assertFalse(adr.transient(http_error(403)))


class RedirectKeepsTokenOnItsHost(unittest.TestCase):
    def redirect(self, target):
        req = urllib.request.Request("https://api.github.com/a",
                                     headers={"Authorization": "Bearer t"})
        handler = adr._DropAuthOnRedirect()
        return handler.redirect_request(req, None, 301, "moved", {}, target)

    def test_same_host_keeps_the_header(self):
        new = self.redirect("https://api.github.com/b")
        self.assertEqual(new.get_header("Authorization"), "Bearer t")

    def test_other_host_drops_it(self):
        new = self.redirect("https://elsewhere.test/b")
        self.assertFalse(new.has_header("Authorization"))


class Probes(unittest.TestCase):
    def run_probe(self, probe, text):
        entry_ = {"none": "absence", "reviewed": "2026-10-30", "probes": [probe]}
        return adr.probe_findings("Q7", entry_, lambda url: adr.normalise(text))

    def test_absent_holds(self):
        probe = {"url": PINNED, "absent": ["tcp_prague"]}
        self.assertEqual(self.run_probe(probe, "tcp_bbr.c tcp_dctcp.c"), [])

    def test_broken_absence_is_wrong_when_pinned_and_revisit_when_floating(self):
        pinned = self.run_probe({"url": PINNED, "absent": ["tcp_prague"]},
                                "tcp_prague.c")
        self.assertIn("Q7: wrong:", pinned[0])
        floating = self.run_probe({"url": FLOATING, "absent": ["tcp_prague"]},
                                  "tcp_prague.c")
        self.assertIn("Q7: revisit:", floating[0])

    def test_present_missing_is_wrong_or_drifted(self):
        self.assertIn("wrong:", self.run_probe({"url": PINNED, "present": ["x"]}, "y")[0])
        self.assertIn("drifted:", self.run_probe({"url": FLOATING, "present": ["x"]}, "y")[0])

    def test_between_limits_the_text(self):
        text = "a = { ONE }; b = { LOG_MARTIANS };"
        probe = {"url": PINNED, "between": ["a = {", "};"],
                 "present": ["ONE"], "absent": ["LOG_MARTIANS"]}
        self.assertEqual(self.run_probe(probe, text), [])

    def test_missing_span_is_a_finding_not_a_silent_pass(self):
        probe = {"url": PINNED, "between": ["moved = {", "};"], "absent": ["x"]}
        got = self.run_probe(probe, "nothing here")
        self.assertIn("span", got[0])

    def test_lint_rejects_an_empty_probe(self):
        got = adr.probe_problems("Q7", [{"url": PINNED}])
        self.assertTrue(any("present or absent" in p for p in got))


class Decisions(unittest.TestCase):
    ROWS = {"Q1": ["a"], "Q2": ["b"], "R1": ["c"]}
    ADR = ("## Evidence\n| Q1 | x | y | z |\n## Decision\n\nIntro Q1 here.\n\n"
           "1. **One.** Rests on Q1 and\n   Q2.\n2. **Two.** Rests on R1.\n"
           "## Other\nprose\n")

    def test_clean(self):
        self.assertEqual(adr.decision_problems(self.ADR, self.ROWS), [])

    def test_items_include_continuation_lines(self):
        items = adr.decision_items(self.ADR)
        self.assertEqual(len(items), 2)
        self.assertIn("Q2", items[0])

    def test_renamed_heading_is_a_finding_not_a_silent_pass(self):
        renamed = self.ADR.replace("## Decision\n", "## Decisions\n")
        got = adr.decision_problems(renamed, self.ROWS)
        self.assertTrue(any("no numbered items under '## Decision'" in p for p in got))

    def test_decision_without_citation_or_with_unknown_id(self):
        adr_text = self.ADR.replace("Rests on R1.", "Rests on nothing and Z9.")
        got = adr.decision_problems(adr_text, self.ROWS)
        self.assertIn("decision 2: cites Z9, which is not in the ADR", got)
        bare = self.ADR.replace("Rests on R1.", "No evidence.")
        self.assertIn("decision 2: cites no evidence ID",
                      adr.decision_problems(bare, self.ROWS))

    def test_uncited_evidence_needs_a_background_reason(self):
        rows = dict(self.ROWS, Q9=["d"])
        self.assertIn("Q9: evidence no decision or finding cites",
                      adr.decision_problems(self.ADR, rows))
        self.assertEqual(adr.decision_problems(self.ADR, rows, {"Q9": "reference"}), [])

    def test_stale_or_empty_background_entries(self):
        got = adr.decision_problems(self.ADR, self.ROWS, {"Q1": "x", "Z1": " "})
        self.assertIn("Q1: background entry is now cited; remove it", got)
        self.assertIn("Z1: background entry is not in the ADR", got)
        self.assertIn("Z1: background needs a reason", got)


class RepoClaims(unittest.TestCase):
    CLAIM = {"claim": "desktop forces cake", "host": "h", "option": "o",
             "key": "net.core.default_qdisc", "equals": "cake"}

    def test_match(self):
        got = adr.repo_findings([self.CLAIM], lambda h, o: {"net.core.default_qdisc": "cake"})
        self.assertEqual(got, [])

    def test_changed_value_names_both_sides(self):
        got = adr.repo_findings([self.CLAIM], lambda h, o: {"net.core.default_qdisc": "fq"})
        self.assertIn("is 'fq', the ADR says 'cake'", got[0])

    def test_unset_key_equals_null(self):
        claim = dict(self.CLAIM, equals=None)
        self.assertEqual(adr.repo_findings([claim], lambda h, o: {}), [])
        self.assertEqual(len(adr.repo_findings([self.CLAIM], lambda h, o: {})), 1)

    def test_one_evaluation_per_host_and_option(self):
        calls = []

        def evaluator(host, option):
            calls.append((host, option))
            return {"a": 1, "b": 2}
        claims = [dict(self.CLAIM, key="a", equals=1), dict(self.CLAIM, key="b", equals=2)]
        self.assertEqual(adr.repo_findings(claims, evaluator), [])
        self.assertEqual(len(calls), 1)

    def test_evaluation_failure_is_reported(self):
        def boom(host, option):
            raise OSError("no such host")
        got = adr.repo_findings([self.CLAIM], boom)
        self.assertEqual(got, ["repo: unevaluable: no such host"])

    def test_missing_fields_are_lint_problems(self):
        self.assertEqual(adr.repo_problems([{"host": "h"}]),
                         ["repo claim 1: missing claim", "repo claim 1: missing option",
                          "repo claim 1: missing equals"])


class Main(unittest.TestCase):
    """The command line end to end over a throwaway ADR and manifest."""

    ADR = ("# ADR\n\n## Evidence\n\n| ID | Finding | Quote | Source |\n|---|---|---|---|\n"
           '| Q1 | f | "alpha beta" | u |\n\n## Decision\n\n1. **Do it.** Rests on Q1.\n')
    MANIFEST = {
        "adr": "adr.md",
        "max_review_days": {"pinned": 365, "floating": 90},
        "sources": {"Q1": {"urls": [PINNED], "reviewed": "2026-10-30"}},
        "repo_claims": [{"claim": "c", "host": "h", "option": "o",
                         "key": "k", "equals": 1}],
    }

    def test_check_reports_how_many_sources_it_could_not_check(self):
        local = dict(self.MANIFEST, sources={"Q1": {"file": "/nonexistent/cfg.gz",
                                                    "host": "no-such-host",
                                                    "reviewed": "2026-10-30"}})
        code, out = self.run_main("check", manifest_=local)
        self.assertEqual(code, 0, out)
        self.assertIn("1 sources unchecked", out)
        code, out = self.run_main("check")
        self.assertNotIn("unchecked", out)

    def run_main(self, command, adr_text=None, page="alpha beta", value=1,
                 manifest_=None):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "adr.md").write_text(adr_text or self.ADR)
            manifest = Path(tmp, "sources.json")
            manifest.write_text(json.dumps(manifest_ or self.MANIFEST))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = adr.main([command, str(manifest), "--today", "2026-10-30"],
                                fetcher=lambda where: page,
                                evaluator=lambda host, option: {"k": value})
        return code, out.getvalue()

    def test_clean_run_exits_zero_for_every_command(self):
        for command in ("lint", "check", "repo"):
            code, out = self.run_main(command)
            self.assertEqual((command, code), (command, 0), out)
            self.assertIn("1 evidence rows, 1 repo claims current", out)

    def test_check_exits_one_on_a_misquote(self):
        code, out = self.run_main("check", page="something else")
        self.assertEqual(code, 1)
        self.assertIn("Q1: wrong:", out)

    def test_repo_exits_one_on_a_changed_value(self):
        code, out = self.run_main("repo", value=2)
        self.assertEqual(code, 1)
        self.assertIn("is 2, the ADR says 1", out)

    def test_lint_exits_one_on_a_malformed_quote_cell(self):
        code, out = self.run_main("lint", adr_text=self.ADR.replace('"alpha beta"', '"alpha'))
        self.assertEqual(code, 1)
        self.assertIn("unterminated", out)

    def test_lint_only_never_fetches(self):
        def never(_):
            raise AssertionError("fetched")
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "adr.md").write_text(self.ADR)
            manifest = Path(tmp, "sources.json")
            manifest.write_text(json.dumps(self.MANIFEST))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(adr.main(["lint", str(manifest)], fetcher=never), 0)


if __name__ == "__main__":
    unittest.main()

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "lib"))

import graderlib  # noqa: E402

TASK = "explain"
CONTRADICTION_PENALTY = 0.15

REQUIRED_FACTS = {
    "begin_first": r"begin[^.\n]{0,80}\bfirst\b|\bfirst\b[^.\n]{0,80}begin",
    "reverse_registration_order": r"revers",
    "done_last": r"done[^.\n]{0,100}\blast\b|\blast\b[^.\n]{0,100}done|final[^.\n]{0,60}done",
    "done_position_independent": (
        r"done[^.\n]{0,200}(not registered|unregistered|isn'?t registered|never registered|without|"
        r"even if|regardless|no matter|wherever|where it was registered|position|even when)"
    ),
    "compact_halves": r"compact[^.\n]{0,80}(half|//\s*2|/\s*2|floor)",
    "wide_doubles": r"wide[^.\n]{0,80}(doubl|\*\s*2|x\s*2|twice|2x)",
    "scale_multiplies": r"scale",
    "rounds_to_multiple_of_8": (
        r"multiple of (8|eight)|nearest (multiple of )?(8|eight)|8\s*\*\s*round|round[^.\n]{0,60}\b(8|eight)\b"
    ),
    "bankers_rounding": (
        r"banker|half[- ]to[- ]even|ties? (go|to|round)[^.\n]{0,10}even|round half|"
        r"python'?s? (built-?in )?round|round-half"
    ),
    "minimum_16": (
        r"(minimum|\bmin\b|at least|floor|clamp|never (less|below|smaller))[^.\n]{0,50}\b16\b|"
        r"\b16\b[^.\n]{0,50}(minimum|at least|floor|clamp|lower bound)"
    ),
}

CONTRADICTIONS = {
    "done_first": r"\bdone\b[^.\n]{0,40}\bfirst\b",
    "compact_doubles": r"compact[^.\n]{0,40}(doubl|twice|\*\s*2)",
    "wide_halves": r"wide[^.\n]{0,40}\bhalf\b",
    "truncation_or_ceiling": r"\btruncat|\bceil\b|always round(s|ed|ing)? up|round(s|ed|ing)? up always",
    "registration_order": r"(?<!not )\b(in|same as) (the )?(same|registration|registered|insertion) order\b",
}


def grade(workdir, reply, here):
    changed = graderlib.changed_paths(here / "input", workdir)
    if any(p for p in changed if (here / "input" / p).exists()):
        return graderlib.result(TASK, False, 0.0, "a read-only task modified files: " + ", ".join(changed))
    text = reply.lower()
    if not text.strip():
        return graderlib.result(TASK, False, 0.0, "empty reply")
    present = [name for name, rx in REQUIRED_FACTS.items() if re.search(rx, text)]
    absent = [name for name in REQUIRED_FACTS if name not in present]
    contradictions = [name for name, rx in CONTRADICTIONS.items() if re.search(rx, text)]
    score = len(present) / len(REQUIRED_FACTS) - CONTRADICTION_PENALTY * len(contradictions)
    details = {"facts_present": present, "facts_absent": absent, "contradictions": contradictions}
    if absent or contradictions:
        reason = []
        if absent:
            reason.append("missing facts: " + ", ".join(absent))
        if contradictions:
            reason.append("contradiction patterns: " + ", ".join(contradictions))
        return graderlib.result(TASK, False, score, "; ".join(reason), needs_review=False, **details)
    return graderlib.result(
        TASK, True, score, "all required facts present by regex; a human must confirm the prose is right",
        needs_review=True, **details,
    )


if __name__ == "__main__":
    sys.exit(graderlib.run_grader(TASK, grade, HERE))

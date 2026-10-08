import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

SUBPROCESS_TIMEOUT_SECONDS = 60
MAX_REASON_CHARS = 400


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("workdir", type=Path)
    parser.add_argument("--reply-file", type=Path, default=None)
    args = parser.parse_args(argv)
    reply = ""
    if args.reply_file is not None and args.reply_file.exists():
        reply = args.reply_file.read_text(encoding="utf-8", errors="replace")
    return args.workdir.resolve(), reply


def result(task, passed, score, reason, needs_review=False, **details):
    out = {
        "task": task,
        "pass": bool(passed),
        "score": round(max(0.0, min(1.0, score)), 4),
        "reason": " ".join(reason.split())[:MAX_REASON_CHARS],
        "needs_review": bool(needs_review),
    }
    if details:
        out["details"] = details
    return out


def run_grader(task, grade_fn, here, argv=None):
    workdir, reply = parse_args(argv)
    try:
        out = grade_fn(workdir, reply, here)
    except Exception as exc:
        out = result(task, False, 0.0, f"grader error: {type(exc).__name__}: {exc}")
    print(json.dumps(out, sort_keys=True))
    return 0


def tree_digest(root):
    root = Path(root)
    digest = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            digest[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return digest


def changed_paths(before_root, after_root):
    before = tree_digest(before_root)
    after = tree_digest(after_root)
    return sorted(p for p in set(before) | set(after) if before.get(p) != after.get(p))


def run_python(args, cwd, timeout=SUBPROCESS_TIMEOUT_SECONDS):
    try:
        proc = subprocess.run(
            [sys.executable, *args],
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
        )
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s"
    return proc.returncode, proc.stdout + proc.stderr


def run_unittest(cwd, module):
    code, output = run_python(["-m", "unittest", module], cwd)
    return code == 0, output

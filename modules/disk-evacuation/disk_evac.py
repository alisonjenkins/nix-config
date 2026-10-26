import argparse
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
import errno
import glob
import hashlib
import json
import logging
import os
from pathlib import Path
import stat
import sys
import time
from typing import NewType

RelPath = NewType("RelPath", Path)
AbsPath = NewType("AbsPath", Path)

logger = logging.getLogger("disk_evac")
if not logger.handlers:
    _h = logging.StreamHandler(sys.stderr)
    _h.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
    logger.addHandler(_h)


class PlanError(Exception):
    pass


@dataclass(frozen=True)
class Entry:
    rel: RelPath
    size: int
    mtime_ns: int
    mode: int
    uid: int
    gid: int
    dest: AbsPath | None
    action: str


@dataclass(frozen=True)
class Plan:
    source: Path
    created: str
    entries: tuple[Entry, ...]
    # Directories and files the source would not list or stat; their
    # contents are missing from the plan and need a human.
    unreadable: tuple[str, ...] = ()


@dataclass(frozen=True)
class RunResult:
    verified: int
    failed: int
    skipped: int
    bytes_copied: int
    stopped: str
    # Entries left pending because the destination branch was too full.
    deferred: int = 0


def _open_source(path: Path) -> int:
    return os.open(path, os.O_RDONLY)


def _sleep(seconds: float) -> None:
    time.sleep(seconds)


def free_bytes(path: Path) -> int:
    st = os.statvfs(path)
    return int(st.f_bavail * st.f_frsize)


def list_branches(pool_glob: str, skip: Sequence[Path]) -> list[Path]:
    skip_resolved = {s.resolve() for s in skip}
    seen: set[Path] = set()
    results: list[Path] = []
    for p in sorted(glob.glob(pool_glob)):
        path = Path(p)
        if path.is_dir():
            resolved = path.resolve()
            if resolved not in skip_resolved and resolved not in seen:
                seen.add(resolved)
                results.append(path)
    return results


def _sort_key(
    item: tuple[RelPath, int, int, int, int, int],
    priority: Sequence[str],
) -> tuple[int, str]:
    rel_str = str(item[0])
    for idx, pfx in enumerate(priority):
        if rel_str.startswith(pfx):
            return (idx, rel_str)
    return (len(priority), rel_str)


def make_plan(
    source: Path,
    pool_glob: str,
    skip: Sequence[Path],
    reserve_bytes: int,
    priority: Sequence[str],
) -> Plan:
    dest_branches = [
        b for b in list_branches(pool_glob, skip)
        if b.resolve() != source.resolve()
    ]

    presence_branches: list[Path] = []
    presence_seen: set[Path] = {source.resolve()}
    for p in sorted(glob.glob(pool_glob)):
        path = Path(p)
        if path.is_dir():
            res = path.resolve()
            if res not in presence_seen:
                presence_seen.add(res)
                presence_branches.append(path)
    for s in skip:
        if s.is_dir():
            res = s.resolve()
            if res not in presence_seen:
                presence_seen.add(res)
                presence_branches.append(s)

    raw_files: list[tuple[RelPath, int, int, int, int, int]] = []
    unreadable: list[str] = []

    def _note_unreadable(path: str, exc: OSError) -> None:
        reason = _errno_name(exc, "io_error")
        logger.warning("unreadable path=%s error=%s", path, reason)
        unreadable.append(f"{path}: {reason}")

    def _walk(curr: Path) -> None:
        try:
            with os.scandir(curr) as it:
                for item in it:
                    if item.name == "lost+found":
                        continue
                    try:
                        st = item.stat(follow_symlinks=False)
                    except OSError as exc:
                        _note_unreadable(item.path, exc)
                        continue
                    if stat.S_ISDIR(st.st_mode):
                        _walk(Path(item.path))
                    elif stat.S_ISREG(st.st_mode):
                        rel = RelPath(Path(item.path).relative_to(source))
                        raw_files.append(
                            (
                                rel,
                                st.st_size,
                                st.st_mtime_ns,
                                st.st_mode & 0o7777,
                                st.st_uid,
                                st.st_gid,
                            )
                        )
        except OSError as exc:
            _note_unreadable(str(curr), exc)

    _walk(source)
    raw_files.sort(key=lambda x: _sort_key(x, priority))

    planned_bytes: dict[Path, int] = {b: 0 for b in dest_branches}
    entries: list[Entry] = []

    for rel, size, mtime_ns, mode, uid, gid in raw_files:
        found_same = False
        found_diff = False
        for b in presence_branches:
            target = b / rel
            try:
                st_t = os.lstat(target)
            except OSError:
                continue
            if not stat.S_ISREG(st_t.st_mode):
                # A symlink or other object in the way is never "present".
                found_diff = True
            elif st_t.st_size == size and st_t.st_mtime_ns == mtime_ns:
                # Copies made by this tool keep mtime, so equal size alone
                # is not enough to call a different file a copy.
                found_same = True
            else:
                found_diff = True

        if found_diff:
            action = "conflict"
            dest = None
        elif found_same:
            action = "already_present"
            dest = None
        else:
            best_branch: Path | None = None
            best_free = -1
            for b in dest_branches:
                try:
                    cur_free = free_bytes(b) - planned_bytes[b]
                except OSError:
                    continue
                if cur_free - size >= reserve_bytes:
                    if cur_free > best_free:
                        best_free = cur_free
                        best_branch = b

            if best_branch is not None:
                action = "copy"
                dest = AbsPath(best_branch / rel)
                planned_bytes[best_branch] += size
            else:
                action = "no_space"
                dest = None

        entries.append(
            Entry(
                rel=rel,
                size=size,
                mtime_ns=mtime_ns,
                mode=mode,
                uid=uid,
                gid=gid,
                dest=dest,
                action=action,
            )
        )

    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return Plan(
        source=source,
        created=created,
        entries=tuple(entries),
        unreadable=tuple(unreadable),
    )


def write_plan(plan: Plan, out: Path) -> None:
    data = {
        "version": 1,
        "source": str(plan.source),
        "created": plan.created,
        "unreadable": list(plan.unreadable),
        "entries": [
            {
                "rel": str(e.rel),
                "size": e.size,
                "mtime_ns": e.mtime_ns,
                "mode": e.mode,
                "uid": e.uid,
                "gid": e.gid,
                "dest": str(e.dest) if e.dest is not None else None,
                "action": e.action,
            }
            for e in plan.entries
        ],
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2), encoding="utf-8")


def load_plan(path: Path, pool_glob: str, skip: Sequence[Path]) -> Plan:
    try:
        content = path.read_text(encoding="utf-8")
        data = json.loads(content)
    except Exception as exc:
        raise PlanError(f"failed_read_plan path={path} error={exc}") from exc

    if data.get("version") != 1:
        raise PlanError(f"unknown_version version={data.get('version')}")

    source = Path(data["source"])
    created = str(data["created"])
    branches = list_branches(pool_glob, skip)

    entries: list[Entry] = []
    for item in data.get("entries", []):
        rel_str = item.get("rel")
        if not isinstance(rel_str, str) or not rel_str:
            raise PlanError(f"invalid_rel entry={item}")
        rel_path = Path(rel_str)
        if rel_path.is_absolute() or ".." in rel_path.parts:
            raise PlanError(f"unsafe_rel entry={item}")

        action = str(item.get("action", ""))
        dest_str = item.get("dest")
        dest: AbsPath | None = None

        if action == "copy":
            if not isinstance(dest_str, str):
                raise PlanError(f"missing_dest entry={item}")
            dest_path = Path(dest_str)
            matched = any(dest_path == b / rel_path for b in branches)
            if not matched:
                raise PlanError(f"dest_outside_pool entry={item}")
            dest = AbsPath(dest_path)
        else:
            dest = None

        entries.append(
            Entry(
                rel=RelPath(rel_path),
                size=int(item["size"]),
                mtime_ns=int(item["mtime_ns"]),
                mode=int(item["mode"]),
                uid=int(item["uid"]),
                gid=int(item["gid"]),
                dest=dest,
                action=action,
            )
        )

    return Plan(
        source=source,
        created=created,
        entries=tuple(entries),
        unreadable=tuple(str(u) for u in data.get("unreadable", [])),
    )


CHUNK = 1024 * 1024
MAX_DEFER_LOGS = 5


@dataclass(frozen=True)
class _Outcome:
    status: str  # "verified", "failed" or "deferred"
    sha256: str | None
    error: str | None


def _errno_name(exc: OSError, default: str) -> str:
    if exc.errno:
        return errno.errorcode.get(exc.errno, f"errno_{exc.errno}")
    return default


def _append_manifest(
    manifest_path: Path,
    rel: str,
    dest: str,
    size: int,
    sha256: str | None,
    status_str: str,
    error: str | None,
) -> None:
    rec = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rel": rel,
        "dest": dest,
        "size": size,
        "sha256": sha256,
        "status": status_str,
        "error": error,
    }
    with open(manifest_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def _sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def _make_parents(parent: Path, gid: int) -> None:
    to_create: list[Path] = []
    curr = parent
    while not curr.exists():
        to_create.append(curr)
        curr = curr.parent
    for p in reversed(to_create):
        p.mkdir(mode=0o2775, exist_ok=True)
        try:
            p.chmod(0o2775)
            if os.geteuid() == 0:
                os.chown(p, -1, gid)
        except OSError as exc:
            logger.warning("dir_metadata_failed dir=%s error=%s", p, exc)


def _apply_metadata(dest: Path, entry: Entry) -> None:
    # The bytes are verified at this point; a metadata failure must not
    # leave a good file out of the manifest.
    try:
        os.chmod(dest, entry.mode)
        os.utime(dest, ns=(entry.mtime_ns, entry.mtime_ns))
        if os.geteuid() == 0:
            os.chown(dest, entry.uid, entry.gid)
    except OSError as exc:
        logger.warning("metadata_failed dest=%s error=%s", dest, exc)


def _copy_entry(
    entry: Entry,
    dest: AbsPath,
    source: Path,
    reserve_bytes: int,
    throttle: Callable[[int], None],
) -> _Outcome:
    """Copy one file; every failure becomes an _Outcome, none escapes.

    Source errors keep the bare errno name (EIO); destination errors are
    prefixed with dest_ so the manifest says which disk misbehaved.
    """
    branch = Path(*dest.parts[: len(dest.parts) - len(entry.rel.parts)])
    try:
        # The plan can be days old; the pool may have filled since.
        if free_bytes(branch) - entry.size < reserve_bytes:
            return _Outcome("deferred", None, "no_space")
    except OSError as exc:
        return _Outcome("failed", None, "dest_" + _errno_name(exc, "statvfs"))

    partial = dest.parent / (dest.name + ".evac-partial")
    try:
        _make_parents(dest.parent, entry.gid)
        partial.unlink(missing_ok=True)
    except OSError as exc:
        return _Outcome("failed", None, "dest_" + _errno_name(exc, "prepare"))

    try:
        src_fd = _open_source(source / entry.rel)
    except OSError as exc:
        return _Outcome("failed", None, _errno_name(exc, "open_error"))

    phase = "dest"
    committed = False
    try:
        hasher = hashlib.sha256()
        with open(partial, "xb") as dst:
            while True:
                phase = "source"
                chunk = os.read(src_fd, CHUNK)
                phase = "dest"
                if not chunk:
                    break
                hasher.update(chunk)
                dst.write(chunk)
                throttle(len(chunk))
            dst.flush()
            os.fsync(dst.fileno())
            try:
                # Drop the cached pages so the verify read hits the disk.
                os.posix_fadvise(dst.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
            except OSError as exc:
                # Only a hint; failing the rescue over it would be worse.
                logger.warning("fadvise_failed dest=%s error=%s", dest, exc)
        src_sha = hasher.hexdigest()
        partial_sha = _sha256_of(partial)
        if partial_sha != src_sha:
            return _Outcome("failed", partial_sha, "verify_mismatch")
        if os.path.lexists(dest):
            return _Outcome("failed", src_sha, "dest_exists")
        os.replace(partial, dest)
        committed = True
        _apply_metadata(dest, entry)
        return _Outcome("verified", src_sha, None)
    except OSError as exc:
        name = _errno_name(exc, "io_error")
        return _Outcome(
            "failed", None, name if phase == "source" else "dest_" + name
        )
    finally:
        try:
            os.close(src_fd)
        except OSError:
            pass
        if not committed:
            try:
                partial.unlink(missing_ok=True)
            except OSError as exc:
                logger.warning("partial_left dest=%s error=%s", partial, exc)


def _load_manifest(manifest_path: Path) -> tuple[set[str], set[str]]:
    verified: set[str] = set()
    failed: set[str] = set()
    if not manifest_path.exists():
        return verified, failed
    with open(manifest_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            rel = rec.get("rel")
            st = rec.get("status")
            if not isinstance(rel, str):
                continue
            if st == "verified":
                verified.add(rel)
                failed.discard(rel)
            elif st == "failed" and rel not in verified:
                failed.add(rel)
    return verified, failed


def run_plan(
    plan: Plan,
    state_dir: Path,
    budget_bytes: int,
    max_consecutive_errors: int,
    rate_bytes_per_s: int,
    retry_failed: bool = False,
    reserve_bytes: int = 0,
) -> RunResult:
    state_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = state_dir / "manifest.jsonl"
    verified_rels, failed_rels = _load_manifest(manifest_path)

    verified_count = 0
    failed_count = 0
    skipped_count = 0
    deferred_count = 0
    bytes_copied = 0
    bytes_read = 0
    consecutive_errors = 0
    stopped = "done"
    start_time = time.monotonic()

    def throttle(n: int) -> None:
        nonlocal bytes_read
        bytes_read += n
        if rate_bytes_per_s > 0:
            expected = bytes_read / rate_bytes_per_s
            elapsed = time.monotonic() - start_time
            if expected > elapsed:
                _sleep(expected - elapsed)

    for entry in plan.entries:
        if entry.action != "copy" or entry.dest is None:
            continue
        rel_str = str(entry.rel)
        if rel_str in verified_rels:
            skipped_count += 1
            continue
        if rel_str in failed_rels and not retry_failed:
            skipped_count += 1
            continue

        if bytes_copied + entry.size > budget_bytes:
            stopped = "budget_reached"
            break

        outcome = _copy_entry(
            entry, entry.dest, plan.source, reserve_bytes, throttle
        )
        if outcome.status == "deferred":
            # Still pending, so nothing to persist; a full branch would
            # otherwise add a manifest line and a log line per entry.
            deferred_count += 1
            if deferred_count <= MAX_DEFER_LOGS:
                logger.warning(
                    "deferred rel=%s reason=%s", rel_str, outcome.error
                )
            continue
        _append_manifest(
            manifest_path,
            rel=rel_str,
            dest=str(entry.dest),
            size=entry.size,
            sha256=outcome.sha256,
            status_str=outcome.status,
            error=outcome.error,
        )
        if outcome.status == "verified":
            consecutive_errors = 0
            bytes_copied += entry.size
            verified_count += 1
            verified_rels.add(rel_str)
            failed_rels.discard(rel_str)
        else:
            logger.warning(
                "copy_failed rel=%s error=%s", rel_str, outcome.error
            )
            consecutive_errors += 1
            failed_count += 1
            failed_rels.add(rel_str)
            if consecutive_errors >= max_consecutive_errors:
                stopped = "too_many_errors"
                break

    return RunResult(
        verified=verified_count,
        failed=failed_count,
        skipped=skipped_count,
        bytes_copied=bytes_copied,
        stopped=stopped,
        deferred=deferred_count,
    )


def status(plan: Plan, state_dir: Path) -> dict[str, int]:
    manifest_path = state_dir / "manifest.jsonl"
    verified_set: set[str] = set()
    failed_set: set[str] = set()

    if manifest_path.exists():
        with open(manifest_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                r = rec.get("rel")
                st = rec.get("status")
                if isinstance(r, str):
                    if st == "verified":
                        verified_set.add(r)
                        failed_set.discard(r)
                    elif st == "failed" and r not in verified_set:
                        failed_set.add(r)

    total_copy = 0
    already_present = 0
    conflict = 0
    no_space = 0
    verified = 0
    failed = 0
    pending = 0
    bytes_verified = 0

    for entry in plan.entries:
        if entry.action == "copy":
            total_copy += 1
            rel_str = str(entry.rel)
            if rel_str in verified_set:
                verified += 1
                bytes_verified += entry.size
            elif rel_str in failed_set:
                failed += 1
            else:
                pending += 1
        elif entry.action == "already_present":
            already_present += 1
        elif entry.action == "conflict":
            conflict += 1
        elif entry.action == "no_space":
            no_space += 1

    return {
        "total_copy": total_copy,
        "verified": verified,
        "failed": failed,
        "pending": pending,
        "already_present": already_present,
        "conflict": conflict,
        "no_space": no_space,
        "bytes_verified": bytes_verified,
    }


def main(argv: Sequence[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    parser = argparse.ArgumentParser(description="mergerfs disk evacuator")
    subparsers = parser.add_subparsers(dest="cmd")

    plan_parser = subparsers.add_parser("plan")
    plan_parser.add_argument("--source", type=Path, required=True)
    plan_parser.add_argument("--pool-glob", type=str, required=True)
    plan_parser.add_argument(
        "--skip", type=Path, action="append", default=[]
    )
    plan_parser.add_argument("--reserve-gib", type=float, default=50.0)
    plan_parser.add_argument(
        "--priority", type=str, action="append", default=[]
    )
    plan_parser.add_argument("--out", type=Path, required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--plan", type=Path, required=True)
    run_parser.add_argument("--pool-glob", type=str, required=True)
    run_parser.add_argument(
        "--skip", type=Path, action="append", default=[]
    )
    run_parser.add_argument("--state", type=Path, required=True)
    run_parser.add_argument("--budget-gib", type=float, default=100.0)
    run_parser.add_argument(
        "--max-consecutive-errors", type=int, default=5
    )
    run_parser.add_argument("--rate-mib-s", type=float, default=40.0)
    run_parser.add_argument("--reserve-gib", type=float, default=50.0)
    run_parser.add_argument("--retry-failed", action="store_true")

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("--plan", type=Path, required=True)
    status_parser.add_argument("--pool-glob", type=str, required=True)
    status_parser.add_argument(
        "--skip", type=Path, action="append", default=[]
    )
    status_parser.add_argument("--state", type=Path, required=True)

    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return int(exc.code) if isinstance(exc.code, int) else 2

    if args.cmd == "plan":
        try:
            reserve_bytes = int(args.reserve_gib * (1024**3))
            p = make_plan(
                source=args.source,
                pool_glob=args.pool_glob,
                skip=args.skip,
                reserve_bytes=reserve_bytes,
                priority=args.priority,
            )
            write_plan(p, args.out)
            summary: dict[str, int] = {
                "copy": 0,
                "already_present": 0,
                "conflict": 0,
                "no_space": 0,
                "bytes_to_copy": 0,
                "unreadable": len(p.unreadable),
            }
            for e in p.entries:
                if e.action in summary:
                    summary[e.action] += 1
                if e.action == "copy":
                    summary["bytes_to_copy"] += e.size
            print(json.dumps(summary))
            return 0
        except Exception as exc:  # noqa: BLE001
            # Top-level CLI guard: any failure becomes exit 1 plus a
            # traceback in the journal, never a half-printed result.
            logger.error("plan_failed error=%s", exc, exc_info=True)
            return 1

    if args.cmd == "run":
        try:
            p = load_plan(args.plan, args.pool_glob, args.skip)
        except PlanError as pe:
            logger.error("load_plan_failed error=%s", pe)
            return 1
        except Exception as exc:  # noqa: BLE001
            logger.error("fatal_plan_load error=%s", exc, exc_info=True)
            return 1

        try:
            budget_bytes = int(args.budget_gib * (1024**3))
            rate_bytes = int(args.rate_mib_s * (1024 * 1024))
            res = run_plan(
                plan=p,
                state_dir=args.state,
                budget_bytes=budget_bytes,
                max_consecutive_errors=args.max_consecutive_errors,
                rate_bytes_per_s=rate_bytes,
                retry_failed=args.retry_failed,
                reserve_bytes=int(args.reserve_gib * (1024**3)),
            )
            res_dict = {
                "verified": res.verified,
                "failed": res.failed,
                "skipped": res.skipped,
                "deferred": res.deferred,
                "bytes_copied": res.bytes_copied,
                "stopped": res.stopped,
            }
            print(json.dumps(res_dict))
            if res.stopped == "too_many_errors":
                return 2
            return 0
        except Exception as exc:  # noqa: BLE001
            logger.error("run_failed error=%s", exc, exc_info=True)
            return 1

    if args.cmd == "status":
        try:
            p = load_plan(args.plan, args.pool_glob, args.skip)
            st = status(p, args.state)
            print(json.dumps(st))
            return 0
        except Exception as exc:  # noqa: BLE001
            logger.error("status_failed error=%s", exc, exc_info=True)
            return 1

    parser.print_usage(sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

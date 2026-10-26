"""Failure paths found in review: destination errors, stale plans, cache."""

import errno
import json
import logging
import os
from pathlib import Path

import pytest

import disk_evac


def _env(
    tmp_path: Path, files: dict[str, bytes]
) -> tuple[Path, Path, str]:
    source = tmp_path / "source"
    source.mkdir()
    for name, data in files.items():
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    branch = tmp_path / "branches" / "disk1"
    branch.mkdir(parents=True)
    return source, branch, str(tmp_path / "branches" / "*")


def _plan(source: Path, pool_glob: str) -> disk_evac.Plan:
    return disk_evac.make_plan(source, pool_glob, [], 0, [])


def _run(
    plan: disk_evac.Plan, tmp_path: Path, **kwargs: int | bool
) -> disk_evac.RunResult:
    return disk_evac.run_plan(
        plan=plan,
        state_dir=tmp_path / "state",
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
        **kwargs,  # type: ignore[arg-type]
    )


def _manifest(tmp_path: Path) -> list[dict[str, object]]:
    lines = (tmp_path / "state" / "manifest.jsonl").read_text().splitlines()
    return [json.loads(line) for line in lines]


def test_destination_write_error_is_recorded_not_raised(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan = _plan(source, pool_glob)

    def full(fd: int) -> None:
        raise OSError(errno.ENOSPC, "No space left on device")

    monkeypatch.setattr(os, "fsync", full)

    res = _run(plan, tmp_path)

    assert (res.verified, res.failed) == (0, 1)
    rec = _manifest(tmp_path)[0]
    assert rec["status"] == "failed"
    assert rec["error"] == "dest_ENOSPC"
    assert list(branch.rglob("*.evac-partial")) == []
    assert not (branch / "a.bin").exists()


def test_unwritable_destination_is_recorded_not_raised(
    tmp_path: Path,
) -> None:
    if os.geteuid() == 0:
        pytest.skip("root ignores directory permissions")
    source, branch, pool_glob = _env(tmp_path, {"d/a.bin": b"payload"})
    plan = _plan(source, pool_glob)
    branch.chmod(0o500)
    try:
        res = _run(plan, tmp_path)
    finally:
        branch.chmod(0o700)

    assert (res.verified, res.failed) == (0, 1)
    error = _manifest(tmp_path)[0]["error"]
    assert isinstance(error, str) and error.startswith("dest_")


def test_destination_error_after_failure_does_not_stop_next_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, branch, pool_glob = _env(
        tmp_path, {"01.bin": b"first", "02.bin": b"second"}
    )
    plan = _plan(source, pool_glob)
    real_fsync = os.fsync
    calls: list[int] = []

    def flaky(fd: int) -> None:
        calls.append(fd)
        if len(calls) == 1:
            raise OSError(errno.EIO, "write error")
        real_fsync(fd)

    monkeypatch.setattr(os, "fsync", flaky)

    res = _run(plan, tmp_path)

    assert (res.verified, res.failed) == (1, 1)
    assert not (branch / "01.bin").exists()
    assert (branch / "02.bin").read_bytes() == b"second"


def test_full_destination_defers_without_reading_source(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan = _plan(source, pool_glob)
    real_free = disk_evac.free_bytes
    real_open = disk_evac._open_source

    def never_open(path: Path) -> int:
        raise AssertionError("source must not be read for a full branch")

    monkeypatch.setattr(disk_evac, "free_bytes", lambda p: 5)
    monkeypatch.setattr(disk_evac, "_open_source", never_open)

    res = _run(plan, tmp_path, reserve_bytes=1)

    assert (res.verified, res.failed, res.deferred) == (0, 0, 1)
    assert not (tmp_path / "state" / "manifest.jsonl").exists()
    assert not (branch / "a.bin").exists()

    # Space frees up: a deferred entry is retried without --retry-failed.
    monkeypatch.setattr(disk_evac, "free_bytes", real_free)
    monkeypatch.setattr(disk_evac, "_open_source", real_open)
    res = _run(plan, tmp_path, reserve_bytes=1)

    assert (res.verified, res.deferred) == (1, 0)
    assert (branch / "a.bin").read_bytes() == b"payload"


def test_reserve_is_enforced_at_run_time_not_only_plan_time(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"x" * 100})
    plan = _plan(source, pool_glob)
    # 150 free, 100 file, 60 reserve: 150 - 100 < 60.
    monkeypatch.setattr(disk_evac, "free_bytes", lambda p: 150)

    res = _run(plan, tmp_path, reserve_bytes=60)

    assert res.deferred == 1
    assert not (branch / "a.bin").exists()


def test_mid_read_error_names_source_errno_and_cleans_partial(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan = _plan(source, pool_glob)
    real_read = os.read
    seen: list[int] = []

    def bad_second_read(fd: int, n: int) -> bytes:
        seen.append(n)
        if len(seen) == 2:
            raise OSError(errno.EIO, "Input/output error")
        return real_read(fd, n)

    monkeypatch.setattr(os, "read", bad_second_read)

    res = _run(plan, tmp_path)

    assert res.failed == 1
    assert _manifest(tmp_path)[0]["error"] == "EIO"
    assert list(branch.rglob("*.evac-partial")) == []


def test_verify_reads_after_cache_drop(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, _branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan = _plan(source, pool_glob)
    events: list[object] = []
    real_fsync = os.fsync
    real_fadvise = os.posix_fadvise
    real_sha = disk_evac._sha256_of

    def fsync(fd: int) -> None:
        events.append("fsync")
        real_fsync(fd)

    def fadvise(fd: int, offset: int, length: int, advice: int) -> None:
        events.append(("fadvise", advice))
        real_fadvise(fd, offset, length, advice)

    def sha(path: Path) -> str:
        events.append("verify")
        return real_sha(path)

    monkeypatch.setattr(os, "fsync", fsync)
    monkeypatch.setattr(os, "posix_fadvise", fadvise)
    monkeypatch.setattr(disk_evac, "_sha256_of", sha)

    res = _run(plan, tmp_path)

    assert res.verified == 1
    assert events == [
        "fsync",
        ("fadvise", os.POSIX_FADV_DONTNEED),
        "verify",
    ]


def test_same_size_different_mtime_is_a_conflict_not_present(
    tmp_path: Path,
) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"AAAA"})
    other = branch / "a.bin"
    other.write_bytes(b"BBBB")
    src_ns = (source / "a.bin").stat().st_mtime_ns
    os.utime(other, ns=(src_ns + 10**9, src_ns + 10**9))

    plan = _plan(source, pool_glob)

    assert [e.action for e in plan.entries] == ["conflict"]


def test_symlink_in_the_way_is_a_conflict(tmp_path: Path) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"AAAA"})
    # lstat reports a symlink's size as its target length: 4, like the file.
    (branch / "a.bin").symlink_to("abcd")

    plan = _plan(source, pool_glob)

    assert [e.action for e in plan.entries] == ["conflict"]


def test_unreadable_directory_is_reported_not_dropped(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    source, _branch, pool_glob = _env(
        tmp_path, {"ok.txt": b"fine", "bad/lost.txt": b"hidden"}
    )
    real_scandir = os.scandir

    def scandir(path: str | os.PathLike[str]) -> object:
        if str(path).endswith("bad"):
            raise OSError(errno.EIO, "Input/output error")
        return real_scandir(path)

    monkeypatch.setattr(os, "scandir", scandir)

    plan = _plan(source, pool_glob)

    assert [str(e.rel) for e in plan.entries] == ["ok.txt"]
    assert len(plan.unreadable) == 1
    assert plan.unreadable[0].endswith("bad: EIO")

    plan_file = tmp_path / "plan.json"
    disk_evac.write_plan(plan, plan_file)
    loaded = disk_evac.load_plan(plan_file, pool_glob, [])
    assert loaded.unreadable == plan.unreadable

    code = disk_evac.main(
        [
            "plan", "--source", str(source), "--pool-glob", pool_glob,
            "--reserve-gib", "0", "--out", str(plan_file),
        ]
    )
    assert code == 0
    assert json.loads(capsys.readouterr().out)["unreadable"] == 1


def test_cli_failure_logs_traceback(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    source, _branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan_file = tmp_path / "plan.json"
    disk_evac.write_plan(_plan(source, pool_glob), plan_file)

    def boom(**kwargs: object) -> object:
        raise RuntimeError("boom")

    monkeypatch.setattr(disk_evac, "run_plan", boom)
    caplog.set_level(logging.ERROR, logger="disk_evac")

    code = disk_evac.main(
        [
            "run", "--plan", str(plan_file), "--pool-glob", pool_glob,
            "--state", str(tmp_path / "state"),
        ]
    )

    assert code == 1
    record = next(r for r in caplog.records if "run_failed" in r.getMessage())
    assert record.exc_info is not None


def test_cli_run_exits_3_when_everything_is_deferred(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    source, _branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan_file = tmp_path / "plan.json"
    disk_evac.write_plan(_plan(source, pool_glob), plan_file)
    monkeypatch.setattr(disk_evac, "free_bytes", lambda p: 1024**3)

    code = disk_evac.main(
        [
            "run", "--plan", str(plan_file), "--pool-glob", pool_glob,
            "--state", str(tmp_path / "state"), "--reserve-gib", "1",
        ]
    )

    assert code == 3
    out = json.loads(capsys.readouterr().out)
    assert out["deferred"] == 1 and out["verified"] == 0


def test_fadvise_failure_does_not_fail_the_copy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source, branch, pool_glob = _env(tmp_path, {"a.bin": b"payload"})
    plan = _plan(source, pool_glob)

    def unsupported(fd: int, offset: int, length: int, advice: int) -> None:
        raise OSError(errno.EINVAL, "Invalid argument")

    monkeypatch.setattr(os, "posix_fadvise", unsupported)

    res = _run(plan, tmp_path)

    assert (res.verified, res.failed) == (1, 0)
    assert (branch / "a.bin").read_bytes() == b"payload"


def test_deferred_logging_is_capped(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    names = {f"f{i}.bin": b"x" for i in range(8)}
    source, _branch, pool_glob = _env(tmp_path, names)
    plan = _plan(source, pool_glob)
    monkeypatch.setattr(disk_evac, "free_bytes", lambda p: 0)
    caplog.set_level(logging.WARNING, logger="disk_evac")

    res = _run(plan, tmp_path, reserve_bytes=1)

    assert res.deferred == 8
    logged = [r for r in caplog.records if "deferred rel=" in r.getMessage()]
    assert len(logged) == disk_evac.MAX_DEFER_LOGS

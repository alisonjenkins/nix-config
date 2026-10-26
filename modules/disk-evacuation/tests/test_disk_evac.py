import errno
import json
import os
from pathlib import Path

import pytest

import disk_evac


def test_plan_chooses_branch_with_most_free_space(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    f1 = source / "file1.txt"
    f1.write_bytes(b"hello world")

    b1 = tmp_path / "branches" / "disk1"
    b2 = tmp_path / "branches" / "disk2"
    b1.mkdir(parents=True)
    b2.mkdir(parents=True)

    def fake_free(path: Path) -> int:
        if "disk1" in str(path):
            return 100 * (1024**3)
        if "disk2" in str(path):
            return 500 * (1024**3)
        return 0

    monkeypatch.setattr(disk_evac, "free_bytes", fake_free)

    pool_glob = str(tmp_path / "branches" / "*")
    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=10 * (1024**3),
        priority=[],
    )

    assert len(plan.entries) == 1
    entry = plan.entries[0]
    assert entry.action == "copy"
    assert entry.dest is not None
    assert entry.dest == b2 / "file1.txt"


def test_plan_never_uses_skip_branch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    f1 = source / "file1.txt"
    f1.write_bytes(b"data")

    b1 = tmp_path / "branches" / "disk1"
    b2 = tmp_path / "branches" / "disk2"
    b1.mkdir(parents=True)
    b2.mkdir(parents=True)

    def fake_free(path: Path) -> int:
        if "disk2" in str(path):
            return 1000 * (1024**3)
        return 50 * (1024**3)

    monkeypatch.setattr(disk_evac, "free_bytes", fake_free)

    pool_glob = str(tmp_path / "branches" / "*")
    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[b2],
        reserve_bytes=10 * (1024**3),
        priority=[],
    )

    assert len(plan.entries) == 1
    entry = plan.entries[0]
    assert entry.action == "copy"
    assert entry.dest == b1 / "file1.txt"


def test_already_present_and_conflict_detection(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    f_same = source / "same.txt"
    f_same.write_bytes(b"exact content")
    f_diff = source / "diff.txt"
    f_diff.write_bytes(b"source version")
    f_new = source / "new.txt"
    f_new.write_bytes(b"fresh")

    b1 = tmp_path / "branches" / "disk1"
    b2 = tmp_path / "branches" / "disk2"
    b1.mkdir(parents=True)
    b2.mkdir(parents=True)

    (b1 / "same.txt").write_bytes(b"exact content")
    mtime_ns = f_same.stat().st_mtime_ns
    os.utime(b1 / "same.txt", ns=(mtime_ns, mtime_ns))
    (b2 / "diff.txt").write_bytes(b"different")

    pool_glob = str(tmp_path / "branches" / "*")
    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=1024,
        priority=[],
    )

    actions = {str(e.rel): e.action for e in plan.entries}
    assert actions["same.txt"] == "already_present"
    assert actions["diff.txt"] == "conflict"
    assert actions["new.txt"] == "copy"

    for e in plan.entries:
        if e.action != "copy":
            assert e.dest is None


def test_no_space_when_reserve_cannot_be_met(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    f = source / "big.bin"
    f.write_bytes(b"x" * 2000)

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)

    monkeypatch.setattr(disk_evac, "free_bytes", lambda p: 5000)

    pool_glob = str(tmp_path / "branches" / "*")
    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=4000,
        priority=[],
    )

    assert len(plan.entries) == 1
    assert plan.entries[0].action == "no_space"
    assert plan.entries[0].dest is None


def test_priority_ordering(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "z_file.txt").write_bytes(b"1")
    (source / "a_file.txt").write_bytes(b"2")
    (source / "media_movie.mkv").write_bytes(b"3")
    (source / "photos_vacation.jpg").write_bytes(b"4")
    (source / "media_trailer.mp4").write_bytes(b"5")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)

    pool_glob = str(tmp_path / "branches" / "*")
    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=["photos_", "media_"],
    )

    rels = [str(e.rel) for e in plan.entries]
    assert rels == [
        "photos_vacation.jpg",
        "media_movie.mkv",
        "media_trailer.mp4",
        "a_file.txt",
        "z_file.txt",
    ]


def test_plan_does_not_open_source_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "secret.txt").write_bytes(b"confidential")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)

    def forbidden_open(*args: object, **kwargs: object) -> int:
        raise AssertionError("_open_source must never be called during plan")

    monkeypatch.setattr(disk_evac, "_open_source", forbidden_open)

    pool_glob = str(tmp_path / "branches" / "*")
    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    assert len(plan.entries) == 1
    assert plan.entries[0].action == "copy"


def test_load_plan_validation(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "doc.txt").write_bytes(b"content")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    plan_file = tmp_path / "plan.json"
    disk_evac.write_plan(plan, plan_file)

    loaded = disk_evac.load_plan(plan_file, pool_glob, [])
    assert len(loaded.entries) == 1

    plan_v2 = tmp_path / "v2.json"
    content = json.loads(plan_file.read_text(encoding="utf-8"))
    content["version"] = 2
    plan_v2.write_text(json.dumps(content), encoding="utf-8")
    with pytest.raises(disk_evac.PlanError, match="unknown_version"):
        disk_evac.load_plan(plan_v2, pool_glob, [])

    plan_dot = tmp_path / "dot.json"
    content = json.loads(plan_file.read_text(encoding="utf-8"))
    content["entries"][0]["rel"] = "../outside.txt"
    plan_dot.write_text(json.dumps(content), encoding="utf-8")
    with pytest.raises(disk_evac.PlanError, match="unsafe_rel"):
        disk_evac.load_plan(plan_dot, pool_glob, [])

    plan_out = tmp_path / "out.json"
    content = json.loads(plan_file.read_text(encoding="utf-8"))
    content["entries"][0]["dest"] = str(tmp_path / "rogue" / "doc.txt")
    plan_out.write_text(json.dumps(content), encoding="utf-8")
    with pytest.raises(disk_evac.PlanError, match="dest_outside_pool"):
        disk_evac.load_plan(plan_out, pool_glob, [])


def test_run_plan_copies_verifies_preserves_mode_and_mtime_and_no_partials(
    tmp_path: Path,
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    f = source / "test.txt"
    f.write_bytes(b"sample data content 12345")
    os.chmod(f, 0o644)
    target_mtime_ns = 1700000000000000000
    os.utime(f, ns=(target_mtime_ns, target_mtime_ns))

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    state_dir = tmp_path / "state"
    result = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=3,
        rate_bytes_per_s=0,
    )

    assert result.verified == 1
    assert result.failed == 0
    assert result.skipped == 0
    assert result.bytes_copied == len(b"sample data content 12345")
    assert result.stopped == "done"

    dest_file = b1 / "test.txt"
    assert dest_file.exists()
    assert dest_file.read_bytes() == b"sample data content 12345"
    st = dest_file.stat()
    assert (st.st_mode & 0o777) == 0o644
    assert st.st_mtime_ns == target_mtime_ns

    partials = list(b1.rglob("*.evac-partial"))
    assert partials == []


def test_read_error_records_failed_removes_partial_and_next_copies(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "01_bad.txt").write_bytes(b"bad file")
    (source / "02_good.txt").write_bytes(b"good file")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )

    orig_open = disk_evac._open_source

    def faulty_open(path: Path) -> int:
        if "01_bad" in str(path):
            raise OSError(errno.EIO, "disk read error")
        return orig_open(path)

    monkeypatch.setattr(disk_evac, "_open_source", faulty_open)

    state_dir = tmp_path / "state"
    res = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )

    assert res.verified == 1
    assert res.failed == 1
    assert res.stopped == "done"
    assert (b1 / "02_good.txt").exists()
    assert not (b1 / "01_bad.txt").exists()
    assert list(b1.rglob("*.evac-partial")) == []


def test_max_consecutive_errors_stops_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    for i in range(5):
        (source / f"f{i}.txt").write_bytes(b"x")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )

    def always_fail(path: Path) -> int:
        raise OSError(errno.EIO, "failing disk")

    monkeypatch.setattr(disk_evac, "_open_source", always_fail)

    state_dir = tmp_path / "state"
    res = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=2,
        rate_bytes_per_s=0,
    )

    assert res.stopped == "too_many_errors"
    assert res.failed == 2
    assert res.verified == 0


def test_budget_stops_run_before_entry_that_does_not_fit(
    tmp_path: Path,
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "01_fit.txt").write_bytes(b"x" * 60)
    (source / "02_nofit.txt").write_bytes(b"x" * 60)

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=10,
        priority=[],
    )

    state_dir = tmp_path / "state"
    res = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=100,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )

    assert res.stopped == "budget_reached"
    assert res.verified == 1
    assert res.bytes_copied == 60
    assert (b1 / "01_fit.txt").exists()
    assert not (b1 / "02_nofit.txt").exists()


def test_second_run_is_idempotent_no_open_source_for_verified(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "file.txt").write_bytes(b"contents")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    state_dir = tmp_path / "state"

    res1 = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )
    assert res1.verified == 1

    def forbidden(path: Path) -> int:
        raise AssertionError("must not open source on verified file")

    monkeypatch.setattr(disk_evac, "_open_source", forbidden)

    res2 = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )
    assert res2.skipped == 1
    assert res2.verified == 0
    assert res2.stopped == "done"


def test_failed_entry_retry_policy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "flaky.txt").write_bytes(b"payload")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    state_dir = tmp_path / "state"

    orig_open = disk_evac._open_source
    fail = True

    def mock_open(path: Path) -> int:
        if fail:
            raise OSError(errno.EIO, "temporary failure")
        return orig_open(path)

    monkeypatch.setattr(disk_evac, "_open_source", mock_open)

    res1 = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
        retry_failed=False,
    )
    assert res1.failed == 1

    fail = False
    res2 = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
        retry_failed=False,
    )
    assert res2.skipped == 1
    assert res2.verified == 0

    res3 = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
        retry_failed=True,
    )
    assert res3.verified == 1
    assert res3.skipped == 0


def test_source_tree_unchanged_after_run(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    sub = source / "subdir"
    sub.mkdir()
    f1 = source / "f1.txt"
    f2 = sub / "f2.txt"
    f1.write_bytes(b"content 1")
    f2.write_bytes(b"content 2")

    st1_before = f1.stat()
    st2_before = f2.stat()
    data1_before = f1.read_bytes()
    data2_before = f2.read_bytes()

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    state_dir = tmp_path / "state"
    disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )

    assert f1.read_bytes() == data1_before
    assert f2.read_bytes() == data2_before
    st1_after = f1.stat()
    st2_after = f2.stat()
    assert st1_after.st_mtime_ns == st1_before.st_mtime_ns
    assert st2_after.st_mtime_ns == st2_before.st_mtime_ns
    assert st1_after.st_mode == st1_before.st_mode
    assert st2_after.st_mode == st2_before.st_mode


def test_dest_exists_yields_failed_with_dest_exists(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "existing.txt").write_bytes(b"source data")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )

    dest = b1 / "existing.txt"
    dest.write_bytes(b"conflicting prior destination")

    state_dir = tmp_path / "state"
    res = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )

    assert res.failed == 1
    assert res.verified == 0
    assert list(b1.rglob("*.evac-partial")) == []

    manifest = (state_dir / "manifest.jsonl").read_text(encoding="utf-8")
    rec = json.loads(manifest.strip())
    assert rec["status"] == "failed"
    assert rec["error"] == "dest_exists"


def test_cli_plan_run_status_round_trip(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "f1.txt").write_bytes(b"cli test file")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")
    plan_file = tmp_path / "plan.json"
    state_dir = tmp_path / "state"

    code_plan = disk_evac.main([
        "plan", "--reserve-gib", "0",
        "--source",
        str(source),
        "--pool-glob",
        pool_glob,
        "--out",
        str(plan_file),
    ])
    out_plan, _ = capsys.readouterr()
    assert code_plan == 0
    plan_summary = json.loads(out_plan.strip())
    assert plan_summary["copy"] == 1
    assert plan_summary["bytes_to_copy"] == len(b"cli test file")

    code_run = disk_evac.main([
        "run", "--reserve-gib", "0",
        "--plan",
        str(plan_file),
        "--pool-glob",
        pool_glob,
        "--state",
        str(state_dir),
        "--rate-mib-s",
        "0",
    ])
    out_run, _ = capsys.readouterr()
    assert code_run == 0
    run_res = json.loads(out_run.strip())
    assert run_res["verified"] == 1
    assert run_res["stopped"] == "done"

    code_status = disk_evac.main([
        "status",
        "--plan",
        str(plan_file),
        "--pool-glob",
        pool_glob,
        "--state",
        str(state_dir),
    ])
    out_status, _ = capsys.readouterr()
    assert code_status == 0
    stat_res = json.loads(out_status.strip())
    assert stat_res["total_copy"] == 1
    assert stat_res["verified"] == 1
    assert stat_res["pending"] == 0
    assert stat_res["bytes_verified"] == len(b"cli test file")


def test_status_unit(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "f1.txt").write_bytes(b"data1")
    (source / "f2.txt").write_bytes(b"data2")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    state_dir = tmp_path / "state"

    st_before = disk_evac.status(plan, state_dir)
    assert st_before["total_copy"] == 2
    assert st_before["verified"] == 0
    assert st_before["pending"] == 2
    assert st_before["failed"] == 0
    assert st_before["bytes_verified"] == 0

    disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=5,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )

    st_after = disk_evac.status(plan, state_dir)
    assert st_after["total_copy"] == 2
    assert st_after["verified"] == 1
    assert st_after["pending"] == 1
    assert st_after["bytes_verified"] == 5


def test_cli_exit_codes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "bad.txt").write_bytes(b"content")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")
    plan_file = tmp_path / "plan.json"
    state_dir = tmp_path / "state"

    disk_evac.main([
        "plan", "--reserve-gib", "0",
        "--source",
        str(source),
        "--pool-glob",
        pool_glob,
        "--out",
        str(plan_file),
    ])

    def broken_open(path: Path) -> int:
        raise OSError(errno.EIO, "error")

    monkeypatch.setattr(disk_evac, "_open_source", broken_open)

    code_too_many = disk_evac.main([
        "run", "--reserve-gib", "0",
        "--plan",
        str(plan_file),
        "--pool-glob",
        pool_glob,
        "--state",
        str(state_dir),
        "--max-consecutive-errors",
        "1",
    ])
    assert code_too_many == 2

    code_fatal = disk_evac.main([
        "run", "--reserve-gib", "0",
        "--plan",
        str(tmp_path / "nonexistent.json"),
        "--pool-glob",
        pool_glob,
        "--state",
        str(state_dir),
    ])
    assert code_fatal == 1


def test_verify_mismatch_fails_and_deletes_partial(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "corrupt.txt").write_bytes(b"some content")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )

    orig_fsync = os.fsync

    def corrupt_fsync(fd: int) -> None:
        orig_fsync(fd)
        partials = list(b1.rglob("*.evac-partial"))
        for p in partials:
            with open(p, "ab") as f:
                f.write(b"corrupt")

    monkeypatch.setattr(os, "fsync", corrupt_fsync)

    state_dir = tmp_path / "state"
    res = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=0,
    )
    assert res.failed == 1
    assert res.verified == 0
    assert list(b1.rglob("*.evac-partial")) == []


def test_throttling_calls_sleep(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "data.txt").write_bytes(b"x" * 2000)

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )

    slept_total = 0.0

    def fake_sleep(secs: float) -> None:
        nonlocal slept_total
        slept_total += secs

    monkeypatch.setattr(disk_evac, "_sleep", fake_sleep)

    state_dir = tmp_path / "state"
    # rate 100 bytes per second for 2000 bytes => throttled
    res = disk_evac.run_plan(
        plan=plan,
        state_dir=state_dir,
        budget_bytes=10**9,
        max_consecutive_errors=5,
        rate_bytes_per_s=100,
    )
    assert res.verified == 1
    assert slept_total > 0.0


def test_lost_and_found_and_symlinks_skipped(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "regular.txt").write_bytes(b"regular")

    # lost+found dir
    lf = source / "lost+found"
    lf.mkdir()
    (lf / "lost.txt").write_bytes(b"lost")

    # symlink to regular
    (source / "link.txt").symlink_to(source / "regular.txt")

    b1 = tmp_path / "branches" / "disk1"
    b1.mkdir(parents=True)
    pool_glob = str(tmp_path / "branches" / "*")

    plan = disk_evac.make_plan(
        source=source,
        pool_glob=pool_glob,
        skip=[],
        reserve_bytes=100,
        priority=[],
    )
    rels = [str(e.rel) for e in plan.entries]
    assert rels == ["regular.txt"]

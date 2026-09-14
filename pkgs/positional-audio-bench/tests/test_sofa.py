from pathlib import Path

import h5py
import numpy as np
import pytest
from positional_audio_bench.sofa import SofaFormatError, load_sofa

FS = 48000.0
TAPS = 32


def _write_fixture(path: Path, positions: list[tuple[float, float, float]]) -> None:
    n = len(positions)
    with h5py.File(path, "w") as f:
        ir = np.zeros((n, 2, TAPS), dtype=np.float64)
        for i in range(n):
            # Distinct, recoverable left/right IR per position: an impulse at
            # a position-dependent tap index, so nearest-neighbour lookup can
            # be verified by checking which impulse comes back.
            ir[i, 0, i % TAPS] = 1.0
            ir[i, 1, (i + 1) % TAPS] = 1.0
        f.create_dataset("Data.IR", data=ir)
        f.create_dataset("Data.SamplingRate", data=np.array([FS]))
        pos_ds = f.create_dataset("SourcePosition", data=np.array(positions, dtype=np.float64))
        pos_ds.attrs["Units"] = b"degree, degree, metre"


def test_load_sofa_reads_positions_and_irs(tmp_path: Path):
    path = tmp_path / "fixture.sofa"
    _write_fixture(path, [(0.0, 0.0, 1.0), (90.0, 0.0, 1.0), (180.0, 0.0, 1.0)])

    hrir = load_sofa(path)

    assert hrir.sample_rate == FS
    assert hrir.positions.shape == (3, 3)
    assert hrir.ir_left.shape == (3, TAPS)
    np.testing.assert_array_equal(hrir.positions[1], [90.0, 0.0, 1.0])


def test_nearest_picks_exact_match(tmp_path: Path):
    path = tmp_path / "fixture.sofa"
    _write_fixture(path, [(0.0, 0.0, 1.0), (90.0, 0.0, 1.0), (180.0, 0.0, 1.0), (270.0, 0.0, 1.0)])
    hrir = load_sofa(path)

    left, right = hrir.nearest(90.0, 0.0)
    assert np.argmax(left) == 1 % TAPS
    assert np.argmax(right) == 2 % TAPS


def test_nearest_picks_closest_when_not_exact(tmp_path: Path):
    path = tmp_path / "fixture.sofa"
    _write_fixture(path, [(0.0, 0.0, 1.0), (30.0, 0.0, 1.0), (60.0, 0.0, 1.0)])
    hrir = load_sofa(path)

    left, _ = hrir.nearest(25.0, 0.0)
    assert np.argmax(left) == 1  # closer to the 30-degree measurement than to 0 or 60


def test_load_sofa_rejects_mismatched_receiver_count(tmp_path: Path):
    path = tmp_path / "bad.sofa"
    with h5py.File(path, "w") as f:
        f.create_dataset("Data.IR", data=np.zeros((2, 3, TAPS)))
        f.create_dataset("Data.SamplingRate", data=np.array([FS]))
        pos_ds = f.create_dataset("SourcePosition", data=np.zeros((2, 3)))
        pos_ds.attrs["Units"] = b"degree, degree, metre"

    with pytest.raises(SofaFormatError):
        load_sofa(path)


def test_load_sofa_rejects_missing_datasets(tmp_path: Path):
    path = tmp_path / "empty.sofa"
    with h5py.File(path, "w") as f:
        f.create_dataset("SomeOtherThing", data=np.zeros(1))

    with pytest.raises(SofaFormatError):
        load_sofa(path)

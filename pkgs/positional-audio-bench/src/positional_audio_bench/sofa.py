"""Minimal reader for SimpleFreeFieldHRIR-convention SOFA files.

SOFA is HDF5 (netCDF4-classic) underneath. Full SOFA supports many
conventions (moving sources, SOS filters, arbitrary receiver counts); every
HRTF set this tool targets (MIT KEMAR, CIPIC, SADIE II, ARI, HUTUBS) uses the
one convention handled here: two receivers (left/right ear), FIR data, source
positions in spherical (azimuth, elevation, radius).
"""

from __future__ import annotations

import dataclasses
from pathlib import Path

import h5py
import numpy as np


class SofaFormatError(ValueError):
    pass


@dataclasses.dataclass(frozen=True)
class HRIRSet:
    """HRIR measurements for one HRTF dataset.

    `positions` holds (azimuth_deg, elevation_deg, radius_m) rows, azimuth
    measured counter-clockwise from straight ahead (matches
    `modules.desktop.pipewire.binauralSurround.angles`'s convention: 0 =
    front, 90 = hard left).
    """

    positions: np.ndarray  # (N, 3)
    ir_left: np.ndarray  # (N, taps)
    ir_right: np.ndarray  # (N, taps)
    sample_rate: float

    def nearest(self, azimuth_deg: float, elevation_deg: float) -> tuple[np.ndarray, np.ndarray]:
        """Left/right HRIR for the measured position closest to the given angle.

        Nearest-neighbour, not interpolated: dense enough on every dataset
        this tool targets (native grids are a few degrees at worst) that the
        interpolation error is well under what the localization-error scores
        care about, and it keeps the lookup simple to reason about and test.
        """
        az = np.radians(self.positions[:, 0])
        el = np.radians(self.positions[:, 1])
        target_az = np.radians(azimuth_deg)
        target_el = np.radians(elevation_deg)
        # Angular (great-circle) distance on the unit sphere, not Euclidean
        # distance in (az, el) — azimuth wraps at 360 and its metric distance
        # shrinks toward the poles, so a naive coordinate-space nearest-match
        # picks the wrong point near the seams.
        cos_dist = np.sin(el) * np.sin(target_el) + np.cos(el) * np.cos(target_el) * np.cos(
            az - target_az
        )
        idx = int(np.argmax(cos_dist))
        return self.ir_left[idx], self.ir_right[idx]


def load_sofa(path: Path) -> HRIRSet:
    with h5py.File(path, "r") as f:
        if "Data.IR" not in f or "SourcePosition" not in f:
            raise SofaFormatError(f"{path}: missing Data.IR/SourcePosition — not a SimpleFreeFieldHRIR file")

        ir = np.asarray(f["Data.IR"], dtype=np.float64)  # (M, R, N)
        if ir.ndim != 3 or ir.shape[1] != 2:
            raise SofaFormatError(f"{path}: Data.IR shape {ir.shape}, expected (M, 2, N) two-receiver HRIR")

        positions = np.asarray(f["SourcePosition"], dtype=np.float64)  # (M, 3)
        if positions.shape[0] != ir.shape[0]:
            raise SofaFormatError(
                f"{path}: SourcePosition has {positions.shape[0]} rows, Data.IR has {ir.shape[0]}"
            )

        units = f["SourcePosition"].attrs.get("Units", b"degree, degree, metre")
        units = units.decode() if isinstance(units, bytes) else str(units)
        if "degree" not in units.split(",")[0]:
            raise SofaFormatError(f"{path}: SourcePosition units {units!r}, expected degrees for azimuth")

        sample_rate = float(np.asarray(f["Data.SamplingRate"]).reshape(-1)[0])

    return HRIRSet(
        positions=positions,
        ir_left=ir[:, 0, :],
        ir_right=ir[:, 1, :],
        sample_rate=sample_rate,
    )

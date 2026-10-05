"""Sample the discrete GPU's power, clock, load and temperature from sysfs.

The card is found by PCI device id, never by hwmon index: hwmon numbers follow
probe order and the integrated GPU can take either slot (research.md D7).
Nothing here writes to sysfs.
"""

import logging
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Optional, TextIO

DEFAULT_SYSFS_ROOT = "/sys"
DEFAULT_PCI_DEVICE = 0x7550
# 20 Hz: the power sensor updates in under 100 ms (research.md D7).
DEFAULT_INTERVAL_S = 0.05
CSV_HEADER = "time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s"

log = logging.getLogger("vr_foveation_bench.sampler")

_CARD_RE = re.compile(r"^card\d+$")
_ACTIVE_CLOCK_RE = re.compile(r"(\d+(?:\.\d+)?)\s*mhz\s*\*", re.IGNORECASE)


class SensorError(RuntimeError):
    """A sysfs file is missing or unparsable; the message names the path."""


class GpuNotFound(RuntimeError):
    """No (or more than one) card matches the PCI device id."""


@dataclass(frozen=True)
class GpuPaths:
    card: str
    hwmon: Path
    power: Path
    sclk: Path
    busy: Path
    temp: Path


@dataclass(frozen=True)
class Reading:
    power_w: float
    core_mhz: float
    gpu_busy_percent: float
    temp_c: Optional[float]


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SensorError(f"cannot read {path}: {exc}") from exc


def _read_number(path: Path) -> float:
    raw = _read(path).strip()
    try:
        return float(raw)
    except ValueError:
        raise SensorError(f"{path}: not a number: {raw!r}") from None


def _cards(root: Path) -> List[Path]:
    drm = root / "class" / "drm"
    if not drm.is_dir():
        raise GpuNotFound(f"{drm} is not a directory (sysfs root {root})")
    return sorted(p for p in drm.iterdir() if _CARD_RE.match(p.name))


def _device_id(card: Path) -> int:
    path = card / "device" / "device"
    raw = _read(path).strip()
    try:
        return int(raw, 16)
    except ValueError:
        raise SensorError(f"{path}: not a hexadecimal PCI device id: {raw!r}") from None


def _hwmon_with_power(card: Path) -> Path:
    hwmon_root = card / "device" / "hwmon"
    candidates = sorted(hwmon_root.glob("hwmon*")) if hwmon_root.is_dir() else []
    for candidate in candidates:
        if (candidate / "power1_average").exists():
            return candidate
    raise SensorError(
        f"no hwmon with power1_average under {hwmon_root} "
        f"(found: {', '.join(c.name for c in candidates) or 'none'})")


def find_gpu(sysfs_root: str = DEFAULT_SYSFS_ROOT, pci_device: int = DEFAULT_PCI_DEVICE) -> GpuPaths:
    root = Path(sysfs_root)
    found = {}
    for card in _cards(root):
        if not (card / "device" / "device").exists():
            log.warning("event=card_skipped card=%s reason=no_pci_device_file", card.name)
            continue
        found[card] = _device_id(card)
    matches = [card for card, dev in found.items() if dev == pci_device]
    if not matches:
        seen = ", ".join(f"{c.name}=0x{d:04x}" for c, d in found.items()) or "no cards"
        raise GpuNotFound(f"no card with PCI device 0x{pci_device:04x} under {root} (saw: {seen})")
    if len(matches) > 1:
        raise GpuNotFound(
            f"PCI device 0x{pci_device:04x} matches several cards: "
            f"{', '.join(c.name for c in matches)}")
    card = matches[0]
    hwmon = _hwmon_with_power(card)
    paths = GpuPaths(
        card=card.name,
        hwmon=hwmon,
        power=hwmon / "power1_average",
        sclk=card / "device" / "pp_dpm_sclk",
        busy=card / "device" / "gpu_busy_percent",
        temp=hwmon / "temp1_input",
    )
    log.info("event=gpu_selected card=%s pci_device=0x%04x hwmon=%s", paths.card, pci_device, hwmon.name)
    return paths


def _active_core_mhz(path: Path) -> float:
    for line in _read(path).splitlines():
        match = _ACTIVE_CLOCK_RE.search(line)
        if match:
            return float(match.group(1))
    raise SensorError(f"{path}: no line marked with '*' (active clock)")


def read_sample(paths: GpuPaths) -> Reading:
    temp = _read_number(paths.temp) / 1000.0 if paths.temp.exists() else None
    return Reading(
        power_w=_read_number(paths.power) / 1_000_000.0,
        core_mhz=_active_core_mhz(paths.sclk),
        gpu_busy_percent=_read_number(paths.busy),
        temp_c=temp,
    )


def _row(t: float, unix_s: float, r: Reading) -> str:
    temp = "" if r.temp_c is None else f"{r.temp_c:.1f}"
    return (f"{t:.3f},{r.power_w:.3f},{r.core_mhz:g},{r.gpu_busy_percent:g},{temp},"
            f"{unix_s:.3f}")


def run(paths: GpuPaths, out: TextIO, interval: float, duration: Optional[float],
        clock: Callable[[], float], wall: Callable[[], float],
        sleep: Callable[[float], None],
        should_stop: Optional[Callable[[], bool]] = None) -> int:
    """Write CSV rows until `duration` s elapse or `should_stop()` is true.

    `clock` is monotonic and times the loop; `wall` is the Unix wall clock
    written as `unix_s` so the rows line up with the frame log. Returns the
    number of rows written. The deadline of each sample is fixed from the
    start so slow reads do not stretch the sampling period.
    """
    if interval <= 0:
        raise ValueError(f"interval must be positive, got {interval!r}")
    if duration is not None and duration < 0:
        raise ValueError(f"duration must not be negative, got {duration!r}")
    out.write(CSV_HEADER + "\n")
    start = clock()
    count = 0
    while True:
        t = clock() - start
        if count > 0 and duration is not None and t > duration:
            break
        out.write(_row(t, wall(), read_sample(paths)) + "\n")
        out.flush()
        count += 1
        if should_stop is not None and should_stop():
            break
        if duration is not None and t + interval > duration:
            break
        sleep(max(0.0, start + count * interval - clock()))
    log.info("event=sampling_done rows=%d interval_s=%s", count, interval)
    return count


def sample_to_file(paths: GpuPaths, out_path: str, interval: float, duration: Optional[float],
                   clock: Callable[[], float], wall: Callable[[], float],
                   sleep: Callable[[float], None],
                   should_stop: Optional[Callable[[], bool]] = None) -> int:
    with open(out_path, "w", encoding="utf-8", newline="") as handle:
        return run(paths, handle, interval, duration, clock, wall, sleep, should_stop)

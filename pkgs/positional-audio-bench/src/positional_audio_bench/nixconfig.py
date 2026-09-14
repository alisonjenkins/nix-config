"""Load `angles`/`compensationEq` from JSON, or straight out of a host's
evaluated Nix config, so the benchmark never hand-copies coefficients that
live in `modules.desktop.pipewire.binauralSurround`.
"""

from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path

from .biquad import BiquadStage

logger = logging.getLogger(__name__)


def stages_from_json(raw: list[dict]) -> list[BiquadStage]:
    return [BiquadStage(type=s["type"], freq=float(s["freq"]), q=float(s.get("q", 1.0)), gain=float(s["gain"])) for s in raw]


def load_binaural_config(path: Path) -> tuple[dict[str, float], list[BiquadStage]]:
    """Load `{"angles": {...}, "compensationEq": [...]}` from a JSON file."""
    data = json.loads(path.read_text())
    angles = {k: float(v) for k, v in data["angles"].items()}
    eq = stages_from_json(data.get("compensationEq", []))
    return angles, eq


def load_binaural_config_from_host(host: str, flake_ref: str = ".") -> tuple[dict[str, float], list[BiquadStage]]:
    """Evaluate a host's actual deployed `binauralSurround` config via `nix eval`.

    For interactive tuning only — the flake-check regression gate uses the
    pure `binaural-surround-defaults.nix` values instead, so it never depends
    on evaluating a full host (secrets, hardware-specific inputs, etc.).
    """
    attr = f"{flake_ref}#nixosConfigurations.{host}.config.modules.desktop.pipewire.binauralSurround"
    logger.info("evaluating %s", attr)
    result = subprocess.run(
        ["nix", "eval", attr, "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
    angles = {k: float(v) for k, v in data["angles"].items()}
    eq = stages_from_json(data.get("compensationEq", []))
    return angles, eq

"""The verdicts record: a Markdown table with one row per game and driver."""

from typing import Any, Dict, List, Mapping, Optional, Tuple

COLUMNS = ("game", "date", "driver", "verdict", "gpuTimeChange", "powerChange", "noise", "artefacts")
VERDICTS = ("go", "no-go", "inconclusive")
KEY = ("game", "driver")

Row = Dict[str, str]

_HEADER = "| " + " | ".join(COLUMNS) + " |"
_SEPARATOR = "| " + " | ".join("---" for _ in COLUMNS) + " |"


def _check_verdict(value: str) -> None:
    if value not in VERDICTS:
        raise ValueError(f"verdict {value!r} is not one of {', '.join(VERDICTS)}")


def _check_row(row: Mapping[str, str]) -> None:
    missing = [c for c in COLUMNS if c not in row]
    if missing:
        raise ValueError(f"row is missing columns: {', '.join(missing)}")
    _check_verdict(row["verdict"])


def _escape(cell: str) -> str:
    one_line = " ".join(cell.splitlines())
    return one_line.replace("\\", "\\\\").replace("|", "\\|")


def _split_line(line: str) -> List[str]:
    cells, current, chars = [], [], iter(line.strip())
    next(chars, None)
    for ch in chars:
        if ch == "\\":
            current.append(next(chars, ""))
        elif ch == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    if "".join(current).strip():
        cells.append("".join(current).strip())
    return cells


def _table_span(lines: List[str]) -> Optional[Tuple[int, int]]:
    for i, line in enumerate(lines):
        if line.lstrip().startswith("|") and _split_line(line) == list(COLUMNS):
            end = i + 1
            while end < len(lines) and lines[end].lstrip().startswith("|"):
                end += 1
            return i, end
    return None


def parse_table(text: str) -> List[Row]:
    lines = text.splitlines()
    span = _table_span(lines)
    if span is None:
        return []
    rows = []
    for number, line in enumerate(lines[span[0] + 2:span[1]], start=span[0] + 3):
        cells = _split_line(line)
        if len(cells) != len(COLUMNS):
            raise ValueError(f"line {number}: expected {len(COLUMNS)} columns, got {len(cells)}")
        row = dict(zip(COLUMNS, cells))
        _check_row(row)
        rows.append(row)
    return rows


def _table_lines(rows: List[Row]) -> List[str]:
    lines = [_HEADER, _SEPARATOR]
    for row in rows:
        _check_row(row)
        lines.append("| " + " | ".join(_escape(row[c]) for c in COLUMNS) + " |")
    return lines


def render_table(rows: List[Row]) -> str:
    return "\n".join(_table_lines(rows)) + "\n"


def upsert(text: str, row: Row) -> str:
    _check_row(row)
    lines = text.splitlines()
    span = _table_span(lines)
    if span is None:
        prefix = text.rstrip("\n")
        return (prefix + "\n\n" if prefix else "") + render_table([row])
    rows = parse_table(text)
    key = tuple(row[c] for c in KEY)
    for i, existing in enumerate(rows):
        if tuple(existing[c] for c in KEY) == key:
            rows[i] = dict(row)
            break
    else:
        rows.append(dict(row))
    merged = lines[:span[0]] + _table_lines(rows) + lines[span[1]:]
    return "\n".join(merged) + "\n"


def _percent(value: Optional[float]) -> str:
    return "n/a" if value is None else f"{value * 100:+.1f}%"


def _noise_cell(noise: Optional[Mapping[str, float]], fmt: str) -> str:
    return "n/a" if noise is None else "±" + fmt.format(max(noise["off"], noise["on"]))


def row_from_report(report_json: Mapping[str, Any], artefact_notes: str) -> Row:
    try:
        verdict = report_json["verdict"]
        noise = verdict["noise"]
        row = {
            "game": str(verdict["game"]),
            "date": str(verdict["date"]),
            "driver": str(verdict["driver"]),
            "verdict": verdict["verdict"],
            "gpuTimeChange": _percent(verdict["gpuTimeChange"]),
            "powerChange": _percent(verdict["powerChange"]),
            "noise": (f"GPU {_noise_cell(noise['medianGpuMs'], '{:.2f}')}"
                      f"{'' if noise['medianGpuMs'] is None else ' ms'}; "
                      f"power {_noise_cell(noise['meanPowerW'], '{:.1f}')}"
                      f"{'' if noise['meanPowerW'] is None else ' W'}"),
            "artefacts": " ".join(artefact_notes.splitlines()),
        }
    except (KeyError, TypeError) as exc:
        raise ValueError(f"report has no usable verdict section: missing or malformed {exc}") from exc
    _check_verdict(row["verdict"])
    return row

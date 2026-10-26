"""HTTP control surface for disk-evacuation.service.

Lets an orchestrator (n8n) start the evacuation, pause it and read its
progress. Every request needs the bearer token; the only mutations are
starting the one fixed unit and toggling a pause flag.
"""

from __future__ import annotations

import argparse
import hmac
import json
import logging
import subprocess
import sys
from collections.abc import Callable, Sequence
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

logger = logging.getLogger("evac_api")

SHOW_PROPS = ("ActiveState", "SubState", "Result", "ExecMainStatus")
BUSY_STATES = ("active", "activating", "deactivating", "reloading")
COMMAND_TIMEOUT_S = 30

Runner = Callable[[Sequence[str]], "subprocess.CompletedProcess[str]"]
Route = Callable[[], tuple[int, dict[str, Any]]]


def _run(cmd: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(cmd), capture_output=True, text=True, timeout=COMMAND_TIMEOUT_S, check=False
    )


class Controller:
    def __init__(
        self,
        unit: str,
        state_dir: Path,
        status_cmd: Sequence[str],
        pressure_file: Path = Path("/proc/pressure/io"),
        run: Runner = _run,
    ) -> None:
        self.unit = unit
        self.pause_flag = state_dir / "PAUSED"
        self.status_cmd = list(status_cmd)
        self.pressure_file = pressure_file
        self.run = run

    def unit_state(self) -> dict[str, str]:
        cmd = ["systemctl", "show", self.unit]
        for prop in SHOW_PROPS:
            cmd += ["-p", prop]
        out: dict[str, str] = {}
        for line in self.run(cmd).stdout.splitlines():
            key, _, value = line.partition("=")
            out[key] = value
        return out

    def sources(self) -> dict[str, Any]:
        proc = self.run(self.status_cmd)
        if proc.returncode != 0:
            return {"error": proc.stderr.strip()[-300:] or f"exit {proc.returncode}"}
        parsed: dict[str, Any] = json.loads(proc.stdout)
        return parsed

    def io_pressure_avg300(self) -> float | None:
        try:
            for line in self.pressure_file.read_text().splitlines():
                if line.startswith("some"):
                    for field in line.split():
                        if field.startswith("avg300="):
                            return float(field.removeprefix("avg300="))
        except (OSError, ValueError):
            logger.warning("pressure_unreadable file=%s", self.pressure_file, exc_info=True)
        return None

    def status(self) -> dict[str, Any]:
        sources = self.sources()
        plans = [v for v in sources.values() if isinstance(v, dict)]
        finished = "error" not in sources and bool(plans) and all(
            p.get("pending") == 0 for p in plans
        )
        return {
            "unit": self.unit_state(),
            "paused": self.pause_flag.exists(),
            "finished": finished,
            "io_pressure_avg300": self.io_pressure_avg300(),
            "sources": sources,
        }

    def start(self) -> tuple[int, dict[str, Any]]:
        if self.pause_flag.exists():
            return 409, {"error": "paused"}
        state = self.unit_state().get("ActiveState", "")
        if state in BUSY_STATES:
            return 409, {"error": "running", "active_state": state}
        if state == "failed":
            return 409, {"error": "failed", "hint": "POST /resume to clear it"}
        proc = self.run(["systemctl", "start", "--no-block", self.unit])
        if proc.returncode != 0:
            logger.error("start_failed stderr=%s", proc.stderr.strip())
            return 500, {"error": "start_failed", "detail": proc.stderr.strip()[-300:]}
        return 202, {"started": True}

    def pause(self) -> tuple[int, dict[str, Any]]:
        self.pause_flag.touch()
        return 200, {"paused": True}

    def resume(self) -> tuple[int, dict[str, Any]]:
        self.pause_flag.unlink(missing_ok=True)
        self.run(["systemctl", "reset-failed", self.unit])
        return 200, {"paused": False}


def make_handler(controller: Controller, token: str) -> type[BaseHTTPRequestHandler]:
    expected = f"Bearer {token}".encode()

    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: dict[str, Any]) -> None:
            payload = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _dispatch(self, routes: dict[str, Route]) -> None:
            given = self.headers.get("Authorization", "").encode()
            if not hmac.compare_digest(given, expected):
                self._send(401, {"error": "unauthorised"})
                return
            route = routes.get(self.path)
            if route is None:
                self._send(404, {"error": "not_found"})
                return
            try:
                code, body = route()
            except Exception:  # noqa: BLE001 - a failed probe must not kill the server
                logger.error("handler_failed path=%s", self.path, exc_info=True)
                self._send(500, {"error": "internal"})
                return
            self._send(code, body)

        def do_GET(self) -> None:  # noqa: N802
            self._dispatch({"/status": lambda: (200, controller.status())})

        def do_POST(self) -> None:  # noqa: N802
            self._dispatch(
                {
                    "/start": controller.start,
                    "/pause": controller.pause,
                    "/resume": controller.resume,
                }
            )

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
            logger.info("request client=%s %s", self.client_address[0], format % args)

    return Handler


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen", default="0.0.0.0")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token-file", type=Path, required=True)
    parser.add_argument("--unit", required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument(
        "--status-cmd", required=True, help="program that prints the per-source status JSON"
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    token = args.token_file.read_text().strip()
    if not token:
        logger.error("empty_token file=%s", args.token_file)
        return 1
    controller = Controller(args.unit, args.state_dir, [args.status_cmd])
    server = ThreadingHTTPServer((args.listen, args.port), make_handler(controller, token))
    logger.info("listening addr=%s port=%d", args.listen, args.port)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())

from __future__ import annotations

import json
import subprocess
import threading
import urllib.error
import urllib.request
from collections.abc import Iterator, Sequence
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any

import pytest

import evac_api

TOKEN = "s3cret-token"


class FakeSystemd:
    """Stands in for systemctl and the status script."""

    def __init__(self) -> None:
        self.active_state = "inactive"
        self.calls: list[list[str]] = []
        self.status_json = json.dumps(
            {"sdg": {"pending": 4, "verified": 1, "failed": 0, "total_copy": 5}}
        )
        self.status_rc = 0

    def __call__(self, cmd: Sequence[str]) -> subprocess.CompletedProcess[str]:
        argv = list(cmd)
        self.calls.append(argv)
        if argv[:2] == ["systemctl", "show"]:
            out = f"ActiveState={self.active_state}\nSubState=dead\nResult=success\nExecMainStatus=0\n"
            return subprocess.CompletedProcess(argv, 0, out, "")
        if argv[0] == "systemctl":
            return subprocess.CompletedProcess(argv, 0, "", "")
        return subprocess.CompletedProcess(
            argv, self.status_rc, self.status_json, "boom" if self.status_rc else ""
        )


@pytest.fixture
def systemd() -> FakeSystemd:
    return FakeSystemd()


@pytest.fixture
def server(tmp_path: Path, systemd: FakeSystemd) -> Iterator[str]:
    pressure = tmp_path / "pressure"
    pressure.write_text("some avg10=1.00 avg60=2.00 avg300=3.50 total=1\nfull avg10=0 avg60=0 avg300=0 total=0\n")
    controller = evac_api.Controller(
        "disk-evacuation.service", tmp_path, ["status-script"], pressure, systemd
    )
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), evac_api.make_handler(controller, TOKEN))
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{httpd.server_address[1]}"
    httpd.shutdown()
    httpd.server_close()


def call(base: str, method: str, path: str, token: str | None = TOKEN) -> tuple[int, dict[str, Any]]:
    req = urllib.request.Request(base + path, method=method, data=b"" if method == "POST" else None)
    if token is not None:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read())


@pytest.mark.parametrize("token", [None, "wrong", ""])
def test_every_route_rejects_a_missing_or_wrong_token(server: str, systemd: FakeSystemd, token: str | None) -> None:
    assert call(server, "GET", "/status", token)[0] == 401
    assert call(server, "POST", "/start", token)[0] == 401
    assert not any(c[:2] == ["systemctl", "start"] for c in systemd.calls)


def test_unknown_path_is_404(server: str) -> None:
    assert call(server, "GET", "/nope")[0] == 404


def test_status_reports_unit_pressure_and_sources(server: str) -> None:
    code, body = call(server, "GET", "/status")

    assert code == 200
    assert body["unit"]["ActiveState"] == "inactive"
    assert body["io_pressure_avg300"] == 3.5
    assert body["paused"] is False
    assert body["finished"] is False
    assert body["sources"]["sdg"]["pending"] == 4


def test_finished_only_when_every_plan_has_nothing_pending(server: str, systemd: FakeSystemd) -> None:
    systemd.status_json = json.dumps({"sdg": {"pending": 0}, "sdk": {"pending": 0}})
    assert call(server, "GET", "/status")[1]["finished"] is True

    systemd.status_json = json.dumps({"sdg": {"pending": 0}, "sdk": {"pending": 2}})
    assert call(server, "GET", "/status")[1]["finished"] is False

    systemd.status_json = "{}"
    assert call(server, "GET", "/status")[1]["finished"] is False


def test_status_script_failure_is_reported_not_finished(server: str, systemd: FakeSystemd) -> None:
    systemd.status_rc = 1

    body = call(server, "GET", "/status")[1]

    assert body["finished"] is False
    assert body["sources"] == {"error": "boom"}


def test_start_runs_the_unit_when_idle(server: str, systemd: FakeSystemd) -> None:
    code, body = call(server, "POST", "/start")

    assert (code, body) == (202, {"started": True})
    assert ["systemctl", "start", "--no-block", "disk-evacuation.service"] in systemd.calls


@pytest.mark.parametrize("state", ["active", "activating"])
def test_start_refuses_while_running(server: str, systemd: FakeSystemd, state: str) -> None:
    systemd.active_state = state

    code, body = call(server, "POST", "/start")

    assert code == 409 and body["error"] == "running"
    assert not any(c[:2] == ["systemctl", "start"] for c in systemd.calls)


def test_start_refuses_after_failure_until_resumed(server: str, systemd: FakeSystemd) -> None:
    systemd.active_state = "failed"
    assert call(server, "POST", "/start")[1]["error"] == "failed"

    assert call(server, "POST", "/resume")[0] == 200
    assert ["systemctl", "reset-failed", "disk-evacuation.service"] in systemd.calls

    systemd.active_state = "inactive"
    assert call(server, "POST", "/start")[0] == 202


def test_pause_blocks_start_and_resume_lifts_it(server: str) -> None:
    assert call(server, "POST", "/pause")[1] == {"paused": True}
    assert call(server, "GET", "/status")[1]["paused"] is True

    assert call(server, "POST", "/start") == (409, {"error": "paused"})

    call(server, "POST", "/resume")
    assert call(server, "POST", "/start")[0] == 202


def test_main_refuses_an_empty_token(tmp_path: Path) -> None:
    token_file = tmp_path / "token"
    token_file.write_text("\n")

    code = evac_api.main(
        [
            "--port", "0", "--token-file", str(token_file), "--unit", "u",
            "--state-dir", str(tmp_path), "--status-cmd", "true",
        ]
    )

    assert code == 1

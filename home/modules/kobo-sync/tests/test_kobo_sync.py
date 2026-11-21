"""Branch tests for kobo-sync.sh.

A fake ssh runs the remote command locally against a fake /mnt/onboard,
or fails the way real ssh does (exit 255 plus its stderr). A fake
kollate-cli records its calls. tar, rsync and sqlite3 are real.
"""

import os
import sqlite3
import stat
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "kobo-sync.sh"

FAKE_SSH = r"""#!/usr/bin/env bash
case ${FAKE_SSH_MODE:-ok} in
  down) echo "ssh: Could not resolve hostname kobo: Name or service not known" >&2; exit 255 ;;
  hostkey) echo "Host key verification failed." >&2; exit 255 ;;
  auth) echo "root@kobo: Permission denied (publickey)." >&2; exit 255 ;;
esac
cmd=${!#}
cmd=${cmd//\/mnt\/onboard/$FAKE_ONBOARD}
if [[ -n ${FAKE_SSH_DROP_COPY:-} && $cmd == *"tar -cf"* ]]; then
  sh -c "$cmd" | head -c 512
  echo "Connection to kobo closed by remote host." >&2
  exit 255
fi
exec sh -c "$cmd"
"""

FAKE_KOLLATE = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_KOLLATE_LOG"
library=$2
mkdir -p "$(dirname "$library")"
case $3 in
  import) sqlite3 "$library" 'CREATE TABLE IF NOT EXISTS setting (key TEXT PRIMARY KEY, value TEXT)' ;;
  transcribe) [[ -z ${FAKE_TRANSCRIBE_FAIL:-} ]] || exit 1 ;;
esac
"""


def write_exe(path: Path, text: str) -> None:
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class Kobo:
    def __init__(self, root: Path):
        self.root = root
        self.onboard = root / "onboard"
        self.state = root / "state"
        self.data = root / "data"
        self.vault = root / "vault"
        self.log = root / "kollate.log"
        bin_dir = root / "bin"
        bin_dir.mkdir()
        write_exe(bin_dir / "ssh", FAKE_SSH)
        write_exe(bin_dir / "kollate-cli", FAKE_KOLLATE)
        self.path = f"{bin_dir}:{os.environ['PATH']}"

        (self.onboard / ".kobo" / "markups").mkdir(parents=True)
        (self.onboard / ".kobo" / "markups" / "page.svg").write_text("<svg/>")
        (self.onboard / "My Notebooks").mkdir()
        (self.onboard / "My Notebooks" / "Ideas.nebo").write_text("nebo")
        db = sqlite3.connect(self.onboard / ".kobo" / "KoboReader.sqlite")
        db.execute("CREATE TABLE Bookmark (BookmarkID TEXT, Text TEXT)")
        db.execute("INSERT INTO Bookmark VALUES ('b1', 'a highlight')")
        db.commit()
        db.close()

    def run(self, transcribe="gpu", **env):
        prelude = "\n".join(
            [
                "set -o errexit -o nounset -o pipefail",
                "host=kobo",
                f"ssh_key={self.root}/key",
                f"vault={self.vault}",
                "stamp_paths=\".kobo/KoboReader.sqlite .kobo/markups 'My Notebooks'\"",
                "sync_paths=\".kobo/KoboReader.sqlite .kobo/markups .kobo-images 'My Notebooks'\"",
                f"transcribe={transcribe}",
            ]
        )
        result = subprocess.run(
            ["bash", "-c", prelude + "\n" + SCRIPT.read_text()],
            env={
                "PATH": self.path,
                "HOME": str(self.root),
                "XDG_STATE_HOME": str(self.state),
                "XDG_DATA_HOME": str(self.data),
                "FAKE_ONBOARD": str(self.onboard),
                "FAKE_KOLLATE_LOG": str(self.log),
                **env,
            },
            capture_output=True,
            text=True,
            timeout=60,
        )
        return result

    def kollate_calls(self):
        if not self.log.exists():
            return []
        return [line.split()[2] for line in self.log.read_text().splitlines()]


@pytest.fixture
def kobo(tmp_path):
    return Kobo(tmp_path)


def test_sync_imports_transcribes_and_exports(kobo):
    r = kobo.run()
    assert r.returncode == 0, r.stderr
    assert "event=synced" in r.stderr
    assert kobo.kollate_calls() == ["import", "transcribe", "export"]
    assert (kobo.state / "kobo-sync" / "mirror" / ".kobo" / "KoboReader.sqlite").is_file()
    assert (kobo.state / "kobo-sync" / "mirror" / "My Notebooks" / "Ideas.nebo").is_file()
    lib = sqlite3.connect(kobo.data / "kollate" / "library.db")
    assert lib.execute("SELECT value FROM setting WHERE key = 'on_device_delete'").fetchone() == ("trash",)


def test_unchanged_listing_skips_kollate(kobo):
    assert kobo.run().returncode == 0
    r = kobo.run()
    assert r.returncode == 0, r.stderr
    assert "event=unchanged" in r.stderr
    assert kobo.kollate_calls() == ["import", "transcribe", "export"]


def test_force_resyncs_unchanged_listing(kobo):
    assert kobo.run().returncode == 0
    r = kobo.run(KOBO_SYNC_FORCE="1")
    assert "event=synced" in r.stderr
    assert kobo.kollate_calls().count("import") == 2


def test_unreachable_kobo_exits_quietly(kobo):
    r = kobo.run(FAKE_SSH_MODE="down")
    assert r.returncode == 0, r.stderr
    assert "event=kobo_unreachable" in r.stderr
    assert kobo.kollate_calls() == []


def test_changed_host_key_fails_with_fix(kobo):
    r = kobo.run(FAKE_SSH_MODE="hostkey")
    assert r.returncode == 1
    assert "event=host_key_changed" in r.stderr
    assert "known_hosts" in r.stderr


def test_rejected_key_fails_with_fix(kobo):
    r = kobo.run(FAKE_SSH_MODE="auth")
    assert r.returncode == 1
    assert "event=auth_failed" in r.stderr


def test_connection_lost_mid_copy_exits_quietly(kobo):
    r = kobo.run(FAKE_SSH_DROP_COPY="1")
    assert r.returncode == 0, r.stderr
    assert "event=kobo_lost_mid_copy" in r.stderr
    assert kobo.kollate_calls() == []
    assert not (kobo.state / "kobo-sync" / "last-stamp").exists()


def test_corrupt_database_is_rejected(kobo):
    (kobo.onboard / ".kobo" / "KoboReader.sqlite").write_bytes(b"not a database" * 100)
    r = kobo.run()
    assert r.returncode == 1
    assert "event=integrity_failed" in r.stderr
    assert kobo.kollate_calls() == []


def test_transcribe_failure_still_exports(kobo):
    r = kobo.run(FAKE_TRANSCRIBE_FAIL="1")
    assert r.returncode == 0, r.stderr
    assert "event=transcribe_failed" in r.stderr
    assert kobo.kollate_calls() == ["import", "transcribe", "export"]


def test_transcribe_off_skips_it(kobo):
    r = kobo.run(transcribe="off")
    assert r.returncode == 0, r.stderr
    assert kobo.kollate_calls() == ["import", "export"]


def test_cpu_transcribe_passes_flag(kobo):
    assert kobo.run(transcribe="cpu").returncode == 0
    assert "transcribe --cpu" in kobo.log.read_text()

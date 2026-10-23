import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import endpoint  # noqa: E402


class DefaultUrl(unittest.TestCase):
    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)
        env = mock.patch.dict(os.environ, {"LOCAL_LLM_STATE_DIR": self.state.name})
        env.start()
        self.addCleanup(env.stop)
        for name in ("PROBE_URL", "LOCAL_LLM_URL"):
            os.environ.pop(name, None)

    def write_active(self, text):
        (Path(self.state.name) / "active-profile.json").write_text(text)

    def test_falls_back_to_the_llama_server_port(self):
        self.assertEqual(endpoint.default_url(), "http://127.0.0.1:8080")

    def test_follows_the_active_profile_port(self):
        self.write_active(json.dumps({"profile": "p", "url": "http://127.0.0.1:8081"}))
        self.assertEqual(endpoint.default_url(), "http://127.0.0.1:8081")

    def test_unreadable_active_profile_is_ignored(self):
        self.write_active("not json")
        self.assertEqual(endpoint.default_url(), "http://127.0.0.1:8080")

    def test_local_llm_url_beats_the_active_profile(self):
        self.write_active(json.dumps({"url": "http://127.0.0.1:8081"}))
        os.environ["LOCAL_LLM_URL"] = "http://llm.example:9000"
        self.assertEqual(endpoint.default_url(), "http://llm.example:9000")

    def test_probe_url_beats_everything(self):
        os.environ["LOCAL_LLM_URL"] = "http://llm.example:9000"
        os.environ["PROBE_URL"] = "http://probe.example:1"
        self.assertEqual(endpoint.default_url(), "http://probe.example:1")


if __name__ == "__main__":
    unittest.main()

"""Default server URL for the probes, so they follow whatever is serving.

Order: PROBE_URL, LOCAL_LLM_URL, the url of the active delegation profile,
then llama-server's own default.
"""
import json
import os
from pathlib import Path

FALLBACK_URL = "http://127.0.0.1:8080"


def state_dir():
    if os.environ.get("LOCAL_LLM_STATE_DIR"):
        return Path(os.environ["LOCAL_LLM_STATE_DIR"])
    cache = os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
    return Path(cache) / "delegate-to-local"


def active_profile_url():
    try:
        return json.loads((state_dir() / "active-profile.json").read_text()).get("url") or None
    except (OSError, ValueError, AttributeError):
        return None


def default_url():
    return os.environ.get("PROBE_URL") or os.environ.get("LOCAL_LLM_URL") or active_profile_url() or FALLBACK_URL

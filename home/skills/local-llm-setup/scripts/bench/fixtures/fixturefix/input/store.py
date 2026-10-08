import json
import os

CONFIG_DIR = "conf"
SETTINGS_FILE = "settings.json"


def settings_path(root):
    return os.path.join(root, CONFIG_DIR, SETTINGS_FILE)


def load_settings(root):
    with open(settings_path(root)) as handle:
        return json.load(handle)


def retries(root):
    return load_settings(root).get("retries", 0)

import json
import os
import tempfile
import unittest

import store


class LoadTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = tmp.name
        path = os.path.join(self.root, "settings.json")   
        with open(path, "w") as handle:
            json.dump({"retries": 3}, handle)

    def test_load_settings(self):
        self.assertEqual(store.load_settings(self.root), {"retries": 3})

    def test_retries(self):
        self.assertEqual(store.retries(self.root), 3)

    def test_settings_path_is_under_conf(self):
        self.assertTrue(store.settings_path(self.root).endswith("conf/settings.json"))


if __name__ == "__main__":
    unittest.main()

import os
import tempfile
import unittest

from device_scan import scan


class ScanTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = tmp.name

    def write(self, relative_path):
        full = os.path.join(self.root, relative_path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w"):
            pass

    def test_finds_nested_files(self):
        for name in ["a.dev", "sub/b.dev", "sub/deep/c.dev", "sub/skip.txt"]:
            self.write(name)
        self.assertEqual(scan(self.root), ["a.dev", "sub/b.dev", "sub/deep/c.dev"])

    def test_skips_hidden_directories(self):
        for name in ["a.dev", ".git/x.dev", "sub/.cache/y.dev"]:
            self.write(name)
        self.assertEqual(scan(self.root), ["a.dev"])

    def test_custom_suffix(self):
        self.write("a.dev")
        self.write("b.cfg")
        self.assertEqual(scan(self.root, ".cfg"), ["b.cfg"])

    def test_missing_root_raises(self):
        with self.assertRaises(FileNotFoundError):
            scan(os.path.join(self.root, "missing"))


if __name__ == "__main__":
    unittest.main()

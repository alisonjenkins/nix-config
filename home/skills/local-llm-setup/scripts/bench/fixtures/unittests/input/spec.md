# test_device_scan.py specification

Write `test_device_scan.py` in this directory using only `unittest`,
`os`, `tempfile` and `device_scan` (the module under test, already correct;
do not change it).

Imports at the top: `import os`, `import tempfile`, `import unittest`,
`from device_scan import scan`.

One class, `ScanTests(unittest.TestCase)`, with a `setUp` and exactly four
tests, in this order.

`setUp`: create a `tempfile.TemporaryDirectory()`, register its `cleanup`
with `self.addCleanup`, and store its path as `self.root`. Add a helper
method `write(self, relative_path)` that creates any missing parent
directories under `self.root` and writes an empty file at that path.

1. `test_finds_nested_files`: call `self.write` for `a.dev`, `sub/b.dev`,
   `sub/deep/c.dev` and `sub/skip.txt`. Assert with `assertEqual` that
   `scan(self.root)` equals `["a.dev", "sub/b.dev", "sub/deep/c.dev"]`.
2. `test_skips_hidden_directories`: write `a.dev`, `.git/x.dev` and
   `sub/.cache/y.dev`. Assert that `scan(self.root)` equals `["a.dev"]`.
3. `test_custom_suffix`: write `a.dev` and `b.cfg`. Assert that
   `scan(self.root, ".cfg")` equals `["b.cfg"]`.
4. `test_missing_root_raises`: assert with `assertRaises(FileNotFoundError)`
   that `scan(os.path.join(self.root, "missing"))` raises.

Style rule for blank lines: no blank line inside any method body; exactly
one blank line between two methods of the class; exactly two blank lines
between the last import and `class`. End the file with
`if __name__ == "__main__": unittest.main()` written on two lines
(the `if` line, then the indented call), after two blank lines.

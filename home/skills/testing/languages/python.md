# Testing Python

## Practice
- `pytest`, run from the devshell. Test files mirror the module tree.
- Fixtures for setup, `tmp_path` for filesystem work — never write into the
  repo or `/tmp` by hand.
- `pytest.mark.parametrize` instead of loops inside a test; each case reports
  its own pass/fail.
- `pytest.raises(SpecificError, match="...")` — assert the message too, or the
  test passes on an unrelated failure of the same type.
- `monkeypatch` for env vars and clocks. Avoid patching your own functions;
  that tests the mock.

## Traps
- Import-time side effects make tests order-dependent. Keep module import
  free of I/O.
- `assert` on floats needs `pytest.approx`.

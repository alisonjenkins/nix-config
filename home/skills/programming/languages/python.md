# Python

## Toolchain
- Interpreter and deps come from Nix (`python3.withPackages`) or a flake
  devshell. Do not `pip install` into the user profile.
- Format with `ruff format`, lint with `ruff check`. Type-check with `mypy`
  where the project already has annotations.

## Idioms
- Type-annotate every public function. Annotations are the documentation.
- `pathlib.Path`, not string paths. `subprocess.run([...], check=True)`, never
  `shell=True` with interpolated values.
- Dataclasses (or pydantic, if the project already uses it) instead of dicts
  for structured data that crosses a function boundary.
- Catch the specific exception. A bare `except Exception` needs a comment
  saying why the broad catch is correct and must re-raise or log with
  `exc_info=True`.
- f-strings for formatting; `logging` for output, never `print`, except in a
  CLI whose output *is* the product.

## Scripts
- A utility script resolves its own tools — a `nix-shell` shebang or a devshell
  — and never assumes anything beyond coreutils is on `PATH`. Anything needing
  pandas, numpy, scipy or similar ships as a directory with a `flake.nix`
  devshell beside the script, invoked via `nix develop`.
- Scripts that touch external systems take a `--dry-run` and are safe to re-run.

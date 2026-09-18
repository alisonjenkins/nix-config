# Python

## Toolchain
- Interpreter and deps come from Nix (`python3.withPackages`) or a flake
  devshell. Do not `pip install` into the user profile.
- Format with `ruff format`, lint with `ruff check`. Type-check with `mypy`
  where the project already has annotations.
- Profiling/benchmarking/vectorization/zero-copy tools: see
  `../performance.md`'s tool table first.
- Guard rail: on a new project (or a module you can annotate fully), run
  `mypy --strict` rather than the default permissive mode. Python's type
  system only catches what you've told it to check; an unannotated function
  is invisible to it. `pydantic`/`dataclass` at the boundary (see Idioms) is
  what makes an invalid input a validation error at parse time instead of an
  `AttributeError` deep in the call stack.

## Idioms
- Type-annotate every public function. Annotations are the documentation.
- `pathlib.Path`, not string paths. `subprocess.run([...], check=True)`, never
  `shell=True` with interpolated values.
- Dataclasses (or pydantic, if the project already uses it) instead of dicts
  for structured data that crosses a function boundary.
- `CustomerId = NewType("CustomerId", str)`, not a bare `str` — mandatory per
  `defensive.md`'s "distinct domain concepts" rule; only caught under `mypy
  --strict` (see Toolchain above), erased at runtime.
- Catch the specific exception. A bare `except Exception` needs a comment
  saying why the broad catch is correct and must re-raise or log with
  `exc_info=True`.
- f-strings for formatting; `logging` for output, never `print`, except in a
  CLI whose output *is* the product.
- Structured logging: `structlog` where the project already has it:
  `logger.info("order_failed", order_id=order_id, reason=reason)` kwargs.
  Stdlib `logging` does not accept arbitrary kwargs as fields (they raise
  `TypeError`); pass `extra={"order_id": order_id, "reason": reason}`
  instead, with a JSON formatter that reads them off the record.
  `contextvars` for request/job-scoped correlation IDs so they appear on
  every line without threading a parameter through every call. See
  `../observability.md` for what belongs in a log line and at what level.

## Scripts
- A utility script resolves its own tools (a `nix-shell` shebang or a
  devshell) and never assumes anything beyond coreutils is on `PATH`.
  Anything needing pandas, numpy, scipy or similar ships as a directory with
  a `flake.nix` devshell beside the script, invoked via `nix develop`.
- Scripts that touch external systems take a `--dry-run` and are safe to re-run.

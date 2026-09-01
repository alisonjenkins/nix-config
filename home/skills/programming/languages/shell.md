# Shell

## Baseline
- `#!/usr/bin/env bash` plus `set -euo pipefail` in every script. Without it,
  a failing command in the middle silently continues.
- Quote every expansion: `"$var"`, `"${arr[@]}"`. Unquoted expansion is the
  single most common shell bug.
- `shellcheck` clean. In Nix, `writeShellApplication` runs it for you — prefer
  it over `writeShellScriptBin`.

## Portability
- These scripts run on several machines. Do not assume a tool exists or sits
  at a fixed path: probe with `command -v` and fall back.
  - `rg` → `grep -r`; `fd` → `find` (and note Debian packages it as `fdfind`).
- For anything beyond coreutils, resolve the tool through a `nix-shell`
  shebang or a devshell rather than trusting `PATH`. This machine has no global
  package pool, so an assumed tool fails with "command not found" or silently
  runs a mismatched version.
- A diagnostic or one-shot utility is a **directory, not a loose file**: a
  `flake.nix` whose `devShells.default` provides the dependencies, plus the
  script, which invokes its analysis through `nix develop`. Applies to anything
  needing tracing tools, or Python with numeric or data libraries.
- No GNU-only flags when the script may run on macOS (`sed -i` differs; use a
  temp file or `perl -pi -e`).

## Safety
- Destructive operations name their target explicitly; no `rm -rf "$dir"/`
  where `$dir` could be empty. Guard with `[[ -n "$dir" ]]`.
- Anything touching an external system is idempotent and safe to re-run.
- Timestamps in output are ISO8601 UTC.

## Observability
- Log to stderr (`>&2`), not stdout, so a script's actual output stays
  pipeable and its diagnostics stay visible either way.
- A systemd unit's stdout/stderr already land in the journal with unit,
  timestamp and PID attached — do not hand-roll a log file and a rotation
  scheme on top of that. Structure a line so it filters well:
  `echo "event=disk_check status=fail path=$path" >&2` beats a free-text
  sentence for the same reason it does in any other language — see
  `../observability.md`.
- On failure, echo the failing command and the value that made it fail before
  exiting non-zero — `set -e` stops the script but tells no one why.

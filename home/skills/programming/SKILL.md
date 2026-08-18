---
name: programming
description: General code-writing conventions that apply in every language — naming, comments, error handling, altitude, and matching the surrounding code — plus a routing table to per-language guidance for Rust, Python, Nix, TypeScript/JavaScript, and shell. Use when writing or refactoring code, reviewing your own diff before handing it over, or when unsure of the idiom for a language in this repo.
---

# Programming

General rules first. Then read the per-language file for whatever you are
actually editing — it carries the toolchain, idioms, and traps for that
language.

## General rules

- **Match the surrounding code.** Comment density, naming style, error
  handling, and file layout come from the neighbours, not from your defaults.
  A diff that reads like the rest of the file is worth more than one that is
  independently prettier.
- **Comment why, not what.** The code says what. A comment earns its place by
  recording a decision, a constraint, or a trap that the next reader would
  otherwise re-derive.
- **Errors carry context.** Never discard an error to satisfy a type. Either
  handle it, or propagate it with enough context that the log line alone
  identifies the failing operation and its inputs.
- **No speculative generality.** Write the concrete thing. Extract the
  abstraction on the second or third use, when its shape is known.
- **Right altitude.** Solve the problem asked. Do not widen scope, do not
  silently narrow it, and do not refactor unrelated code in the same change.
- **Reuse before writing.** Search for an existing helper before adding one.
  Duplicated logic is the default failure mode of agent-written code.
- **Idempotence at the boundaries.** Anything that touches an external system
  checks current state before mutating, and is safe to re-run.
- **No unexplained magic values.** A literal that encodes a policy (timeout,
  retry count, buffer size) gets a name and a one-line justification.

## Per-language routing

Read the file matching what you are editing. If several apply, read each.

| Working in | Read |
|---|---|
| `*.rs`, `Cargo.toml` | [languages/rust.md](languages/rust.md) |
| `*.py`, `pyproject.toml` | [languages/python.md](languages/python.md) |
| `*.nix`, `flake.nix` | [languages/nix.md](languages/nix.md) |
| `*.ts`, `*.tsx`, `*.js`, `package.json` | [languages/typescript.md](languages/typescript.md) |
| `*.sh`, `*.bash`, shell in a hook or CI step | [languages/shell.md](languages/shell.md) |

## Related

- Tests for the code you are writing: the `testing` skill.
- Committing the result: the `git` skill.
- Reviewing a finished diff: the `review` skill.

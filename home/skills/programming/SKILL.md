---
name: programming
description: Use when writing, changing, fixing, debugging or refactoring code in any language — including a one-line fix, a config value, or a shell snippet embedded in another file. Covers .nix, .rs, .py, .ts, .tsx, .js, .sh and their config files. Carries the conventions that apply everywhere (naming, comments, error handling, scope, matching the surrounding code) and routes to per-language guidance for Rust, Python, Nix, TypeScript/JavaScript and shell, plus assertions and crash-early behaviour, thread-safety and shared state, and input validation and secrets.
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
- **Don't program by coincidence.** If you cannot say *why* it works, it does
  not work yet — it happens to pass. Code that was arrived at by permuting
  until the test went green is the most expensive kind to own, because the
  next person, including you, will assume it was reasoned. Understand the
  mechanism, or say plainly that you have not.
- **Name well; rename when needed.** A name that no longer describes what the
  thing does is a defect, not cosmetics — it actively misleads every reader
  after you. Renaming the thing you are already changing is part of the change,
  not scope creep; renaming things you are not otherwise touching is.
- **Don't live with broken windows.** A known-wrong thing left in place
  licenses the next one, and the decay compounds faster than anyone expects.
  Fix it if it is in reach, and if it is genuinely out of scope, record it
  where it will be found — never step over it silently.
- **Treat reluctance as a signal.** When you find yourself circling a change
  without starting it, the usual cause is that the requirement is unclear or
  the design is wrong, not that the work is unpleasant. Stop and re-read the
  requirement before pushing through.

## By-concern routing

Independent of language. Read the one that matches what the change involves.

| The change involves | Read |
|---|---|
| Input that could be wrong, an impossible state, an assertion, a resource to release, an error path | [defensive.md](defensive.md) |
| Threads, async tasks, workers, locks, shared or cached state, an intermittent failure | [concurrency.md](concurrency.md) |
| Untrusted input, a query or command built from data, permissions, tokens or secrets, a dependency bump | [security.md](security.md) |

## Per-language routing

Read the file matching what you are editing. If several apply, read each.

| Working in | Read |
|---|---|
| `*.rs`, `Cargo.toml` | [languages/rust.md](languages/rust.md) |
| `*.py`, `pyproject.toml` | [languages/python.md](languages/python.md) |
| `*.nix`, `flake.nix` | [languages/nix.md](languages/nix.md) |
| `*.ts`, `*.tsx`, `*.js`, `package.json` | [languages/typescript.md](languages/typescript.md) |
| `*.sh`, `*.bash`, or a shell snippet embedded anywhere else — a hook, a CI step, a Nix string, a systemd unit | [languages/shell.md](languages/shell.md) |

## Related

- Deciding what shape the change should be — where a responsibility belongs,
  whether to split a module, why a small change is touching many files: the
  `design` skill. Reach for it before writing when the structure is in
  question, not after.
- Finding out *why* something is broken, before writing the fix: the
  `debugging` skill. This one covers writing the change; that one covers
  locating the fault and deciding which evidence to trust. Both apply to a bug
  fix, in that order.
- Tests for the code you are writing: the `testing` skill.
- Committing the result: the `git` skill.
- Reviewing a finished diff: the `review` skill.

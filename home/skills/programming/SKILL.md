---
name: programming
description: Use when writing, changing, fixing, debugging or refactoring code in any language, including a one-line fix, a config value, or a shell snippet embedded in another file. Covers .nix, .rs, .py, .ts, .tsx, .js, .sh, .go, .cs and their config files, including .NET Framework and .NET Core/5+. Carries the conventions that apply everywhere (naming, comments, error handling, scope, matching the surrounding code) and routes to per-language guidance for Rust, Python, Nix, TypeScript/JavaScript, shell, Go and C#/.NET, plus assertions and crash-early behaviour, thread-safety and shared state, input validation and secrets, observability (logging, tracing, structured log fields, correlation IDs, instrumenting new code so behaviour can be read from its output instead of guessed at), and performance work — profiling, benchmarking, and SIMD/vectorization.
---

# Programming

General rules first. Then read the per-language file for whatever you are
actually editing: it carries the toolchain, idioms, and traps for that
language.

## General rules

- **Match the surrounding code — except comment density.** Naming style,
  error handling, and file layout come from the neighbours, not from your
  defaults. A diff that reads like the rest of the file is worth more than
  one that is independently prettier. Comment density is the one exception:
  a file full of comment noise is not a convention to match, it is the thing
  the next rule fixes. Do not add comments just because the file already has
  many.
- **Default to no comments.** This overrides "match the surrounding code"
  above — an over-commented neighbour is never a reason to add more. Well-
  named identifiers already say what the code does; a comment restating that
  is noise. Write one only when the *why* is non-obvious — a hidden
  constraint, a subtle invariant, a workaround for a specific bug, behaviour
  that would surprise a reader — and drop it if removing it would not
  confuse a future reader. Never comment what the code does, reference the
  current task, fix, caller, or issue number (`used by X`, `added for the Y
  flow`, `handles the case from issue #123`), or leave a `// removed` marker
  for deleted code. Describing *why* a workaround exists is fine and
  expected; citing the ticket that prompted it is not.
- **Comments earn their place, then get out of the way.** One short line,
  plain words, the constraint stated directly — no multi-line blocks, no
  restating in a second sentence what the first already said. Same bar as the
  `writing` skill's dyslexia/ADHD baseline: short sentences, no dense wall of
  text to parse before the point lands.
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
  not work yet, it only happens to pass. Code that was arrived at by permuting
  until the test went green is the most expensive kind to own, because the
  next person, including you, will assume it was reasoned. Understand the
  mechanism, or say plainly that you have not.
- **Name well; rename when needed.** A name that no longer describes what the
  thing does is a defect, not cosmetics: it actively misleads every reader
  after you. Renaming the thing you are already changing is part of the change,
  not scope creep; renaming things you are not otherwise touching is.
- **Don't live with broken windows.** A known-wrong thing left in place
  licenses the next one, and the decay compounds faster than anyone expects.
  Fix it if it is in reach, and if it is genuinely out of scope, record it
  where it will be found; never step over it silently.
- **Treat reluctance as a signal.** When you find yourself circling a change
  without starting it, the usual cause is that the requirement is unclear or
  the design is wrong, not that the work is unpleasant. Stop and re-read the
  requirement before pushing through.
- **Delegating code work to a sub-agent means naming this skill in its
  prompt.** A freshly spawned sub-agent gets no skill listing at all — it
  cannot discover `programming` on its own, and skips every rule here
  silently if not told. State it by exact name (`invoke the programming
  skill, then read its languages/rust.md` for Rust work, and so on for
  whichever per-language file applies) in the prompt you hand it. Once
  invoked, disclosure inside the sub-agent works exactly as it does here:
  the sub-agent reads this body, then follows the routing table to whichever
  child file the work needs — nothing about running as a sub-agent changes
  that mechanism.

## By-concern routing

Independent of language. Read the one that matches what the change involves.

| The change involves | Read |
|---|---|
| Input that could be wrong, an impossible state, an assertion, a resource to release, an error path | [defensive.md](defensive.md) |
| Threads, async tasks, workers, locks, shared or cached state, an intermittent failure | [concurrency.md](concurrency.md) |
| Untrusted input, a query or command built from data, permissions, tokens or secrets, a dependency bump | [security.md](security.md) |
| Any new code path, log line, error, retry, or state transition — anything that should be answerable from output later instead of re-derived by guessing | [observability.md](observability.md) |
| Making something faster, profiling, benchmarking, or a SIMD/vectorization change | [performance.md](performance.md) |

## Per-language routing

Read the file matching what you are editing. If several apply, read each.

| Working in | Read |
|---|---|
| `*.rs`, `Cargo.toml` | [languages/rust.md](languages/rust.md) |
| `*.py`, `pyproject.toml` | [languages/python.md](languages/python.md) |
| `*.nix`, `flake.nix` | [languages/nix.md](languages/nix.md) |
| `*.ts`, `*.tsx`, `*.js`, `package.json` | [languages/typescript.md](languages/typescript.md) |
| `*.sh`, `*.bash`, or a shell snippet embedded anywhere else, such as a hook, a CI step, a Nix string, a systemd unit | [languages/shell.md](languages/shell.md) |
| `*.go`, `go.mod` | [languages/go.md](languages/go.md) |
| `*.cs`, `*.csproj`, `*.sln`, .NET Framework or .NET Core/5+ | [languages/csharp.md](languages/csharp.md) |

## Related

- The ask itself being unclear: it named a solution rather than a problem, or
  you are about to guess which of two readings was meant: the `requirements`
  skill, before any of this.
- Deciding what shape the change should be: where a responsibility belongs,
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

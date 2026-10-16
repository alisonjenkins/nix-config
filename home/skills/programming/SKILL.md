---
name: programming
description: >-
  Use when writing, changing, fixing, debugging or refactoring code in any language, including a one-line fix, a config value, or a shell snippet embedded in another file. Covers .nix, .rs, .py, .ts, .tsx, .js, .sh, .go, .cs. Routes to per-language guidance (Rust, Python, Nix, TypeScript/JavaScript, shell, Go, C#/.NET), plus assertions, thread-safety, input validation/secrets, observability, performance/profiling, and navigating code with the LSP tool (definitions, references, callers, rename).
metadata:
  summary: "Use when writing, changing, fixing or debugging code in any language: Rust, Python, Nix, TypeScript, shell, Go, C#; secrets, concurrency, performance; LSP navigation (definitions, references)."
---

# Programming

General rules first. Then read the per-language file for what you are
editing: toolchain, idioms, and traps.

## General rules

- **Match the surrounding code — except comment density.** Naming style,
  error handling, and file layout come from the neighbours, not your
  defaults. Comment density is the exception: do not add comments because the
  file already has many.
- **Default to no comments.** Write one only when the *why* is non-obvious (a
  hidden constraint, a subtle invariant, a workaround), in one short line of
  plain words. Never comment what the code does, reference the current task,
  caller or issue number, or leave a `// removed` marker. Full wording and
  examples: [general-rules-detail.md](general-rules-detail.md), read it before
  adding or editing any comment.
- **Errors carry context.** Never discard an error to satisfy a type. Either
  handle it, or propagate it with enough context that the log line alone
  identifies the failing operation and its inputs.
- **No speculative generality.** Write the concrete thing. Extract the
  abstraction on the second or third use, when its shape is known.
- **Right altitude.** Solve the problem asked. Do not widen scope, do not
  silently narrow it, and do not refactor unrelated code in the same change.
- **Reuse before writing.** Search for an existing helper before adding one.
  Duplicated logic is the default failure mode of agent-written code.
- **Ask the language server, not grep, about meaning.** Use the `LSP` tool
  when available; list references before changing a signature or renaming.
  An empty answer is not "none" — see [lsp.md](lsp.md).
- **Idempotence at the boundaries.** Anything that touches an external system
  checks current state before mutating, and is safe to re-run.
- **No unexplained magic values.** A literal that encodes a policy (timeout,
  retry count, buffer size) gets a name and a one-line justification.
- **Don't program by coincidence.** If you cannot say *why* it works, it only
  happens to pass. Understand the mechanism, or say plainly that you have not.
- **Name well; rename when needed.** A stale name is a defect. Rename what you
  are already changing; renaming untouched things is scope creep.
- **Don't live with broken windows.** Fix a known-wrong thing if in reach; if
  out of scope, record it where it will be found. Never step over it silently.
- **Treat reluctance as a signal.** Circling a change without starting it
  means the requirement is unclear or the design is wrong; re-read the
  requirement. (Reasoning for these four:
  [general-rules-detail.md](general-rules-detail.md).)
- **Delegating code work to a sub-agent means naming this skill in its
  prompt** — see the `delegation` skill for why and how.

## By-concern routing

Independent of language. Read the one that matches what the change involves.

| The change involves | Read |
|---|---|
| Input that could be wrong, an impossible state, an assertion, a resource to release, an error path | [defensive.md](defensive.md) |
| Threads, async tasks, workers, locks, shared or cached state, an intermittent failure | [concurrency.md](concurrency.md) |
| Untrusted input, a query or command built from data, permissions, tokens or secrets, a dependency bump | [security.md](security.md) |
| Any new code path, log line, error, retry, or state transition — anything that should be answerable from output later instead of re-derived by guessing | [observability.md](observability.md) |
| Making something faster, profiling, benchmarking, or a SIMD/vectorization change | [performance.md](performance.md) |
| Finding a definition, callers or references, a type, a rename or signature change; an LSP answer that came back empty | [lsp.md](lsp.md) |
| Adding or editing a comment; the full reasoning behind the general rules | [general-rules-detail.md](general-rules-detail.md) |

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

- The ask is unclear (named a solution not a problem, or you would guess):
  `requirements`, before any of this.
- Deciding the shape of the change (where code belongs, splitting a module):
  `design`, before writing, not after.
- Why something is broken: `debugging` locates the fault first; this skill
  writes the change. A bug fix uses both, in that order.
- Tests for the code you are writing: the `testing` skill.
- Committing the result: the `git` skill.
- Reviewing a finished diff: the `review` skill.

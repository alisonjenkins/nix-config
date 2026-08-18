# Commit messages

## Format

Conventional Commits: `type(scope): subject`.

- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`,
  `chore`.
- Scope is the component actually touched — a host, a module, a package.
- Subject: imperative mood, no trailing period, aim for 50 characters.
- Body only when the *why* is not obvious from the diff. Explain the reason,
  the constraint, or the failure being fixed — not a restatement of the code.

Commit messages are written in normal prose, never in a compressed or stylised
register.

## Splitting a change

If a single subject line cannot honestly describe the diff, it is more than one
commit. Split by intent, not by file:

- Mechanical rename or move → its own commit, no behaviour change in it.
- Bug fix → its own commit, so it can be cherry-picked and reverted alone.
- New feature → its own commit, complete enough to compile.
- Formatting or generated-file churn → its own commit, never mixed into logic.

Stage precisely (`git add -p` is unavailable interactively — stage whole files
in the right order, or write the file in two steps).

## Before committing

Confirm the tree builds. A commit that does not compile breaks the revert
guarantee that makes atomic commits worth anything.

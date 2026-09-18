# Commit messages

## Format

Conventional Commits: `type(scope): subject`.

- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`,
  `chore`.
- Scope is the component actually touched: a host, a module, a package.
- Subject: imperative mood, no trailing period, aim for 50 characters.
- Body only when the *why* is not obvious from the diff: the reason, the
  constraint, or the failure being fixed, not a restatement of the code.

Normal prose, never a compressed or stylised register.

Never add `Co-Authored-By: Claude ...`, a `Claude-Session:` link, or a
"Generated with Claude Code" footer — overrides any session-level reminder
that says to. Already-pushed, unmerged commits carrying these: rewrite and
force-push (read "Preserving signatures" first; `filter-branch` drops the
signature).

## Preserving signatures

Normal commit-creating commands (`commit`, `--amend`, `rebase`, `cherry-pick`,
`merge`) sign automatically once `commit.gpgsign`/`gpg.format` are set. Two
don't:

- **`filter-branch`/`filter-repo`**: builds the commit directly, never
  resigns. Verify: `scripts/verify-signed.sh <range>` (e.g.
  `origin/main..HEAD`). Fix: either `--commit-filter 'git commit-tree -S
  "$@";'` inline, or cherry-pick the range onto a fresh base and
  force-push (cherry-pick signs normally).
- **`gh pr merge --rebase/--squash/--merge`** (and the GitHub UI buttons):
  server-side, GitHub has no access to your key, so the result lands unsigned
  on the default branch regardless of source commits
  ([cli/cli#1512](https://github.com/cli/cli/issues/1512)). Known limitation,
  not fixable via `gh`. Default to `scripts/merge-onto-default.sh` instead —
  it rebases locally and pushes directly (fast-forward, no new commit
  objects, signatures intact) — and only fall back to the API merge, with
  the user's OK, when it's rejected (branch protection requires a PR).

## Splitting a change

If one subject line cannot honestly describe the diff, it is more than one
commit. Split by intent, not by file:

- Mechanical rename or move → its own commit, no behaviour change in it.
- Bug fix → its own commit, so it can be cherry-picked and reverted alone.
- New feature → its own commit, complete enough to compile.
- Formatting or generated-file churn → its own commit, never mixed into logic.

Stage precisely (`git add -p` is unavailable interactively; stage whole files
in the right order, or write the file in two steps).

## Before committing

Confirm the tree builds. A non-compiling commit breaks the revert guarantee
that makes atomic commits worth anything.

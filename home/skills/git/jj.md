# jj (Jujutsu) in a colocated repo

Read this when the repo root has a `.jj/` directory, or before running
`jj git init --colocate`. Colocated means `.jj/` and `.git/` sit side by side:
`gh`, CI, editors and the scripts in `scripts/` keep working on the git side.
The mandates in [SKILL.md](SKILL.md) still hold; this file only changes how
you reach them. Status: **pilot** on nix-config, measured against the git
baseline (`cc-obs-query automate`, shapes `jj …` against `git …`).

## Check before the first jj command

```
test -d "$(git rev-parse --show-toplevel)/.jj" && jj --version
```

- No `.jj/`: use git. Do not colocate a repo unless the user asked.
- **Inside a git worktree, use git.** jj looks for `.jj/` by walking up, so in
  `.claude/worktrees/<name>/` it finds the *main* checkout's repo and rewrites
  that working copy, not the worktree. For isolated work in a jj repo use
  `jj workspace add ../<repo>-<feature>` instead; it has no `.git`, so run
  `gh` there with `-R owner/repo` and `--head <bookmark>`.

## The model in four lines

- `@` is the working-copy commit. Every jj command first snapshots the files
  on disk into it. There is no staging area and nothing to `add`.
- `@-` is its parent: usually the last finished change. Push `@-`, not `@`,
  unless `@` holds the work.
- A **change id** (letters `k`-`z`, e.g. `qpvuntsm`) survives rewrites; a
  commit id (hex) does not. Refer to changes by change id.
- A **bookmark** is a git branch. It does **not** move when you make new
  commits; you move it (`jj bookmark set`).

## Cheat sheet

| Want | jj | Not |
|---|---|---|
| State | `jj st` | `git status` |
| Recent history | `jj log -n 10 --no-graph -T builtin_log_oneline` | bare `jj log` (graph, all heads) |
| This branch only | `jj log --no-graph -T builtin_log_oneline -r 'trunk()..@'` | |
| What changed | `jj diff --stat`, then `jj diff --git <path>` (`--git` is the default here) | full `jj diff` first |
| Finish a change and start the next | `jj commit -m "<msg>"` | `git add && git commit` |
| Reword | `jj describe -r <rev> -m "<msg>"` | `git commit --amend` |
| Start from main | `jj git fetch && jj new 'trunk()'` | `git switch -c` |
| Fold the working copy into its parent | `jj squash` | `git commit --amend` |
| Fold some files into a given change | `jj squash --into <rev> <paths>` | `fixup!` + autosquash |
| Send each hunk to the change that last touched those lines | `jj absorb` | |
| Split by paths | `jj split -r <rev> -m "<msg for first part>" <paths>` | `rebase -i` + `edit` |
| Move one change | `jj rebase -r <rev> -d <dest>` | `rebase -i` reorder |
| Rebase the branch on main | `jj git fetch && jj rebase -b @ -d 'trunk()'` | `git pull --rebase` |
| Drop a change | `jj abandon <rev>` | `git reset --hard` |
| Name it for a PR | `jj bookmark create <name> -r @-` | |
| Move the name after more work | `jj bookmark set <name> -r @-` | |
| Push | `jj git push -b <name>` | `git push -u` |
| Push without naming | `jj git push -c @-` (creates `push-<changeid>`) | |
| Undo the last jj command | `jj undo` | reflog archaeology |
| See or restore earlier states | `jj op log -n 5`, `jj op restore <op>` | |

`jj split`, `jj squash -i`, `jj describe` with no `-m`, and `jj resolve` open
an editor or a TUI. Always pass `-m` and paths so nothing is interactive.

## Gotchas

- **Branch names are fixed by the harness.** When the session names a branch
  (`claude/...`), use it: `jj bookmark create <that name> -r @-` and
  `jj git push -b <that name>`. `-c` invents its own name and pushes to the
  wrong branch.
- **New bookmarks:** older jj refuses to push one it has not seen on the
  remote; add `--allow-new` if the error says so.
- **Everything on disk is committed.** A scratch file, a build output, a
  secret left in the tree lands in `@` on the next command. `.gitignore` is
  honoured; for a file already snapshotted, add it to `.gitignore` and run
  `jj file untrack <path>`. Keep scratch work outside the repo.
- **No git hooks run.** jj never calls `pre-commit` or `commit-msg`. Run them
  yourself before pushing. prek takes git refs, not revsets, so pass commit
  ids: `prek run --from-ref "$(jj log -r 'trunk()' --no-graph -T commit_id)" --to-ref "$(jj log -r @- --no-graph -T commit_id)"`.
- **Signing** happens on push (`git.sign-on-push`), so local commits are
  unsigned until then. Never turn it off; `scripts/verify-signed.sh` checks
  the pushed range as it does for git.
- **Conflicts do not stop the command.** A rebase that conflicts succeeds and
  marks changes with `×` in the log. Check `jj st` after every rebase; fix by
  `jj new <conflicted>`, editing the files, then `jj squash`. Never push a
  conflicted change.
- **`git` in a colocated repo** sees a detached `HEAD`. Read-only git is safe
  (`git log`, `git diff`, `gh`); jj imports anything git writes. Do not mix
  `git rebase` or `git commit` into a jj flow mid-change; pick one.
- **Rewriting a pushed change** is still rewriting published history: the
  confirm-first rule in [SKILL.md](SKILL.md) applies to `jj squash`,
  `jj rebase` and `jj describe` on anything a bookmark has pushed. jj marks
  such changes immutable once they are in `trunk()`; `--ignore-immutable` is
  never the answer.
- **Fixups while a PR is open:** make the fix a separate change described
  `fixup! <target subject>` so reviewers see it. Before merge, fold it with
  `jj squash --from <fixup> --into <target>`, then `jj git push -b <name>`.
  `scripts/check-no-fixups.sh` still gates the merge.

## Compact output

- Always `--no-graph` and a template when reading history; `-n` caps it.
- `jj diff --stat` or `--summary` before any full diff; then one path at a
  time with `--git`.
- `jj st` is already short; do not follow it with `jj log` to "confirm".
- Do not run `jj log` after `jj commit`, `jj squash` or `jj rebase` to check
  the result: each prints the new working-copy line itself.
- Ids: `jj log -r @- --no-graph -T 'change_id.short()'` returns just the id.

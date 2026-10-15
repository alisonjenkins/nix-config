# Carrying a patch to a project you don't own

For a fix you want now but have not sent upstream, or may never send. The fork's
pull request is the record and the reminder to upstream it.

## Steps

1. Fork under the user's account (`gh repo fork <owner>/<repo> --clone=false
   --default-branch-only`). Do this only when the user asked for it.
2. Push the branch to the fork and open the PR **against the fork**:
   `gh pr create --repo <you>/<repo> --base <default> --head <branch>`. Never
   rely on the default target. Check the returned URL names the fork. Start the
   body with one line saying it is a fork-only PR, kept as a reminder to
   upstream, not submitted there.
3. Consume it in the build by commit, not by PR number. A PR's `.patch` URL
   changes when the PR is updated, which breaks the hash; a commit URL does not
   (`https://github.com/<you>/<repo>/commit/<sha>.patch`).
4. Exclude files the pinned source may not match: tests, docs, the changelog
   (`excludes = [ ... ]` on `fetchpatch2`). They conflict with an older pin and
   the build does not need them.
5. Get the hash from a build with a fake hash and copy the `got:` value.
6. Override only the dependency that needs it (`pkg.override { dep = patched; }`),
   never the global attribute: replacing a widely used package rebuilds
   everything that depends on it.
7. To change the patch, push a new commit to the fork branch, then bump the
   revision and hash. Record where the patches live in the repo's `CLAUDE.md`.

## Before it goes upstream

- Read the project's contributing guide and its AI policy first. Some ask for a
  generic trailer on AI-assisted commits, some require a human-written
  description plus a disclosure, some forbid AI contributions. Follow that
  project's rule, not your own default. Where AI contributions are forbidden,
  stop at the fork: do not draft the upstream issue, description or patch.
- Tests are usually required, and a changelog entry often is too. A performance
  change with no deterministic observable can only pin behaviour; say so rather
  than claiming the test proves the speedup.
- A token without the `workflow` scope cannot push commits that add or change
  CI workflow files relative to the fork. A branch based on an old tag whose
  workflows differ from the fork's default branch is refused for that reason.
  Do not widen the token; base the branch on the fork's default branch.

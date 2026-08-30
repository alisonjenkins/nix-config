# The automation GitHub App

`update.yaml` opens its nightly `flake.lock` PR as a GitHub App rather than as
`github-actions[bot]`. This file records why, and how to set the App up.

## Why an App

A PR opened with the built-in `GITHUB_TOKEN` does not start `pull_request`
workflows. That is a deliberate GitHub rule against recursion, and it means
`pr-check.yaml` never produced the `flake-check` status that branch protection
on `main` requires. The nightly then sat until someone approved and ran the
check by hand, and the job's own 30 minute wait expired long before that.

An App installation token is a different actor, so the PR it opens starts
`pull_request` workflows normally.

What this deliberately does **not** do:

- It does not relax `fork-pr-contributor-approval`, which stays at
  `all_external_contributors`. Real outside contributors still need approval
  before anything of theirs reaches the self-hosted runner.
- It does not add any bypass to branch protection. The nightly PR still has to
  go green on `flake-check` like every other PR.

## Creating it

One App covers every repo that needs this. Install it on each one; each
workflow run mints its own token, scoped to the repo it runs in and valid for
about an hour.

1. Create the App at
   <https://github.com/settings/apps/new>, or under the org if these repos move
   to one. Name it something recognisable in a PR author field, for example
   `alisonjenkins-automation`.
2. Homepage URL can be the repo. Uncheck **Active** under Webhook; this App
   never receives events.
3. Repository permissions, and nothing beyond these:
   - **Contents**: Read and write, to push the update branch.
   - **Pull requests**: Read and write, to open the PR and arm auto-merge.
4. Under **Where can this GitHub App be installed?**, choose **Only on this
   account**.
5. Create it, then **Install App** and select the repositories it should act
   on. Add repos here as more of them need automated PRs.
6. Generate a private key. The `.pem` downloads once.

## Wiring it to a repo

Two secrets per repo, or one organisation secret shared across them:

| Secret | Value |
|---|---|
| `AUTOMATION_APP_ID` | The numeric App ID from the App's settings page |
| `AUTOMATION_APP_PRIVATE_KEY` | The full contents of the `.pem`, including the BEGIN and END lines |

```bash
gh secret set AUTOMATION_APP_ID --repo <owner>/<repo> --body '<app id>'
gh secret set AUTOMATION_APP_PRIVATE_KEY --repo <owner>/<repo> < path/to/key.pem
```

Secrets are not exposed to workflows triggered by fork PRs, so this credential
cannot be read by an outside contributor's branch.

## Rotating the key

Generate a new private key in the App settings, update
`AUTOMATION_APP_PRIVATE_KEY` in every repo, then delete the old key. The App ID
does not change. Nothing else needs touching, since the tokens themselves are
minted per run and expire on their own.

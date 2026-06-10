# `modules.githubActionsRunner` — on-demand, scale-to-zero GitHub Actions runner

A nix-darwin module that runs the **official** `actions/runner` on a Mac, but only
when there is a job to do. A small launchd poller (`StartInterval`, default 60s) checks
the GitHub API for queued jobs and spawns a single **ephemeral** runner on demand; after
the job the runner de-registers and exits, so idle RAM is ~0MB (no persistent `.NET`
listener).

- Engine: official `actions/runner` (nixpkgs `github-runner`) — full action compatibility.
- Idle: ~0MB (poller exits between ticks). Tradeoff: ~30–60s job pickup latency.
- Concurrency: one runner at a time (atomic `mkdir` lock).
- Scope: per-repo (`repos`) and/or org-wide (`orgs`).

## Quick start (per host)

```nix
inputs.sops-nix.darwinModules.sops
self.darwinModules.github-actions-runner
({ config, ... }: {
  sops.secrets.github-runner-token = {
    sopsFile = self + "/secrets/github-runner-token.enc.yaml";
    key = "github_runner_token";
    owner = "ali";            # must match the daemon's UserName (cfg.user)
  };
  modules.githubActionsRunner = {
    enable = true;
    tokenFile = config.sops.secrets.github-runner-token.path;
    repos = [ "alisonjenkins/some-project" ];
    orgs = [ ];               # org names; keep small (polling cost scales with repo count)
  };
})
```

Then in each project's workflow:

```yaml
jobs:
  build:
    runs-on: [self-hosted, macos, aarch64, nix]   # must include self-hosted + your labels
    steps:
      - uses: actions/checkout@v4
      - run: nix build .#packages.aarch64-darwin.default
```

`nix`, `git`, `coreutils`, etc. are already on the job PATH — no `install-nix-action` needed.

## Creating the fine-grained PAT

The poller needs a GitHub **fine-grained personal access token** to (a) list queued jobs
and (b) mint short-lived runner registration tokens.

1. GitHub → **Settings → Developer settings → Fine-grained personal access tokens →
   Generate new token**.
2. **Resource owner:** your user (for `repos`) and/or the organization (for `orgs`).
3. **Repository access:** *Only select repositories* → pick every repo in `repos` (and the
   org repos you want buildable). For an org runner you can choose *All repositories*.
4. **Permissions** — set exactly:

   | Target | Permission | Access |
   | ------ | ---------- | ------ |
   | Repository | **Administration** | Read and write *(mint runner registration tokens)* |
   | Repository | **Actions** | Read *(list queued runs and their jobs)* |
   | Repository | **Metadata** | Read *(implicit / required)* |
   | Organization *(only if using `orgs`)* | **Self-hosted runners** | Read and write |
   | Organization *(only if using `orgs`)* | **Administration** | Read *(enumerate org repos)* |

5. **Expiry:** set a calendar reminder to rotate. The runner re-registers from the PAT on
   every job, so an expired PAT silently stops new runs.

## Storing the PAT in sops

The value must contain the token with **no trailing newline** (the scripts also strip
newlines defensively).

```bash
# in the repo root
sops secrets/github-runner-token.enc.yaml
```

Add a single key:

```yaml
github_runner_token: github_pat_xxxxxxxxxxxxxxxxxxxxxxxx
```

Ensure `.sops.yaml` has a `creation_rule` for
`^secrets/github-runner-token\.enc\.yaml$` listing the recipients (admin + the host key),
placed **before** any generic `^secrets/...` rule. Then `git add` the encrypted file.

### Rotation

Regenerate the PAT in GitHub, re-run `sops secrets/github-runner-token.enc.yaml`, replace
the value, and `darwin-rebuild switch` (or `just switch`). No runner re-registration is
needed — runners are ephemeral and re-minted per job.

## How it works

- **No copy of the runner package.** `github-runner`'s wrapped `config.sh`/`run.sh` honor
  `RUNNER_ROOT`; the module points it at a writable `runnerDir` (default
  `/var/lib/github-actions-runner`) for `.runner`/`.credentials`/`_work`/`_diag`, while the
  immutable assets stay in the nix store.
- **Detection:** per tick the poller GETs `…/actions/runs?status=queued` for each repo,
  then inspects each queued run's jobs and matches one whose `labels` include `self-hosted`
  (or intersect `extraLabels`). Org targets enumerate `…/orgs/{org}/repos` (cached
  `repoListCacheMinutes`) and poll each.
- **Spawn:** mint a registration token from the PAT, `config.sh --ephemeral …`, then
  `run.sh` under a `timeout` watchdog (`spawnTimeoutMinutes`). `--ephemeral` exits after one
  job; the watchdog kills + de-registers a runner that never picked one up.

## Options (`modules.githubActionsRunner.*`)

| Option | Default | Notes |
| ------ | ------- | ----- |
| `enable` | `false` | |
| `tokenFile` | — | Path to the PAT file (from sops). |
| `repos` | `[]` | `owner/repo` targets. |
| `orgs` | `[]` | Org names; runner registers org-wide. Keep small. |
| `pollInterval` | `60` | launchd `StartInterval` (s). 30–60 recommended. |
| `repoListCacheMinutes` | `10` | Org repo-list cache TTL. |
| `runnerNamePrefix` | hostname | Runner name prefix (unique suffix appended). |
| `extraLabels` | `[ "macos" "aarch64" "nix" ]` | Advertised labels. |
| `extraPackages` | `[]` | Extra packages on the job PATH. |
| `user` | `system.primaryUser` | Owns `runnerDir`; poller + jobs run as this user. |
| `runnerDir` | `/var/lib/github-actions-runner` | `RUNNER_ROOT`. |
| `spawnTimeoutMinutes` | `20` | Watchdog for false-positive detection. |
| `package` | `pkgs.github-runner` | The official runner package. |

## Troubleshooting

- Logs: `tail -f <runnerDir>/poller.log` (default `/var/lib/github-actions-runner/poller.log`).
- Daemon: `launchctl print system/org.nixos.github-actions-runner-poller`.
- Idle proof: log shows `tick: no queued jobs` and `pgrep -f Runner.Listener` is empty.
- `mint-token` perms check: run `github-runner-mint-token repo owner/repo` — prints a token
  if the PAT is scoped correctly.
- Org polling is API-heavy for large orgs (fine-grained PAT = 5000 req/hr). Prefer listing
  the build-relevant repos in `repos`, or raise `repoListCacheMinutes`.

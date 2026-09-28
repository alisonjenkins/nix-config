# Configuring credential profiles

`sift` resolves LGTM (Loki/Prometheus) and Datadog credentials via
[secretspec](https://secretspec.dev), never via a raw token typed into a
CLI flag. See `pkgs/sift/docs/adr/0006-secretspec-credential-resolution.md`
for why, `pkgs/sift/docs/adr/0007-credential-caching-and-memory-hygiene.md` for
how repeated `sift` calls avoid repeated 1Password prompts, and
`pkgs/sift/docs/adr/0008-datadog-direct-api.md` for why Datadog is queried
directly rather than through `pup`.

1Password is the primary/recommended source.

## The short version

1. `pkgs/sift/secretspec.toml` declares what secrets exist —
   `LGTM_BEARER_TOKEN`, `LGTM_BASIC_AUTH_USER`,
   `LGTM_BASIC_AUTH_PASSWORD` for `sift lgtm ...`, and `DD_API_KEY`,
   `DD_APP_KEY` for `sift datadog ...` (all declared `required = false`
   in secretspec itself — see the note below on what that does and
   doesn't mean for Datadog) — and, per profile, which provider
   resolves them.
2. You put real values into that provider (1Password, AWS SSM/Secrets
   Manager, Azure Key Vault, or a plain env var) yourself, outside of
   sift and outside of anything an LLM session touches.
3. You invoke `sift ... --auth-profile <name>`. Only the profile *name*
   crosses the command line — the resolved value goes straight from the
   provider into the outbound request's `Authorization` header (LGTM)
   or `DD-API-KEY`/`DD-APPLICATION-KEY` headers (Datadog) inside sift's
   own process.

## Datadog: `--auth-profile` is optional, the credential is not

LGTM's `--auth-profile` genuinely means "query unauthenticated" when
omitted — fine for a local, unsecured Loki/Prometheus. Datadog's API
has no unauthenticated mode, so `sift datadog ...` behaves differently:
omitting `--auth-profile` still resolves via secretspec's `default`
profile (bound to the `env` provider), so a plain `DD_API_KEY`/
`DD_APP_KEY` exported in the shell works with no profile flag at all —
this is what `DD_SITE=us3.datadoghq.com` + env-var keys looks like on
the work laptop. `required = false` in `secretspec.toml` only means
secretspec itself won't hard-fail profile resolution when a key is
unset; `sift`'s own `DatadogAuth::from_secretspec_profile` is what
turns a still-missing key into a clear, named error
(`AuthError::MissingDatadogKey`) before any request goes out — naming
`DD_API_KEY` or `DD_APP_KEY` specifically, not a generic auth failure.

```bash
sift datadog logs 'service:checkout status:error' --site us3.datadoghq.com --auth-profile work
```

Put real values into the `work`/`personal` profile's 1Password vault the
same way as the LGTM secrets below: items titled `DD_API_KEY` and
`DD_APP_KEY`.

## 1Password (recommended): the `personal` profile

`secretspec.toml` ships `--auth-profile personal`, bound to a
1Password vault (`onepassword://Personal` by default — rename it in
`secretspec.toml`'s `[providers]` table to match your own vault).

**One-time setup:**

```bash
op signin
op item create --category=password --vault=Personal \
  --title=LGTM_BEARER_TOKEN password=<the-real-token>
```

secretspec's 1Password provider reads by item title matching the
secret name exactly (`LGTM_BEARER_TOKEN`), from the vault named in the
provider URI. Repeat for `LGTM_BASIC_AUTH_USER`/`LGTM_BASIC_AUTH_PASSWORD`
if the target uses Basic Auth instead of a bearer token.

**Then:**

```bash
sift lgtm logs '{app="checkout"}' --url https://loki.example.com --auth-profile personal
```

The first call prompts 1Password's normal device-approval flow
(desktop app or `op signin`); ADR 0007's caching means that's at most
once per 30-minute window, not once per `sift` call.

### CI / headless / no human to approve a prompt

Use a [1Password service account](https://developer.1password.com/docs/service-accounts/)
instead of your own interactive session — it authenticates
non-interactively, with no device-approval prompt at all, scoped to
read-only access on just the vault(s) you grant it:

```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_..."
sift lgtm logs '{app="checkout"}' --url https://loki.example.com --auth-profile personal
```

secretspec's 1Password provider picks up `OP_SERVICE_ACCOUNT_TOKEN`
from the environment automatically — no `secretspec.toml` change
needed. This is the right setup for a CI pipeline or any unattended
`sift` invocation.

## Work 1Password account: the `work` profile

`--auth-profile work` reads from the work 1Password account through a
`work_1password` provider alias that `secretspec.toml` deliberately
leaves undefined: its URI names the work account, which stays out of
this public repo. On work machines (`workIdentity = true`),
`home/programs/sift` renders the alias into the per-user
`~/.config/secretspec/config.toml` from sops, with the same 30-minute
keyring cache as `personal`. secretspec checks project aliases before
user ones, so never define `work_1password` in `secretspec.toml` too; it
would shadow the real value.

**One-time setup** (on the work machine):

```bash
op account list                     # note the work account's USER ID
op item create --category=password --account <USER ID> --vault=<vault> \
  --title=DD_API_KEY password=<api-key>
op item create --category=password --account <USER ID> --vault=<vault> \
  --title=DD_APP_KEY password=<application-key>
sops secrets/ali-work-laptop-macos/work-identity.enc.yaml
# add:  secretspec_work_1password_uri: onepassword://<USER ID>@<vault>
```

Then `just switch`. Add the key to the sops file **before** switching.
home-manager's sops-nix decrypts in a background agent (launchd on macOS,
a systemd user service on Linux), not in the switch itself, and it stops
at the first missing key. So the switch can look successful while none
of `work-identity.enc.yaml`'s secrets get written, including the work git
email and the work SSH public keys, not only this alias. Elsewhere,
`--auth-profile work` fails with "Provider alias 'work_1password' is not
defined".

The `work` profile's `LGTM_*` secrets come from the same 1Password vault
now, not SSM. They are optional, so one that only exists in SSM is
silently absent and `sift lgtm ... --auth-profile work` queries without
credentials. Create them in the vault too if you use that combination.

A cached alias like this one is a complete route and can't sit in a
fallback chain, so the profile names only `work_1password`. To back a
profile with AWS SSM Parameter Store instead, define an alias such as
`{ uri = "awsps://us-east-1", cache = { provider = "local_cache", max_age = "30m" } }`;
the `awsps` provider reads `/secretspec/{project}/{profile}/{key}`.

## Adding your own profile (e.g. Azure Key Vault)

Add a new `[profiles.<name>]` section to `secretspec.toml`, declaring
the same three (optional) secrets, plus a `[profiles.<name>.defaults]`
block naming which provider alias to use:

```toml
[providers]
azure_kv = { uri = "akv://my-vault-name", cache = { provider = "local_cache", max_age = "30m" } }

[profiles.staging]
LGTM_BEARER_TOKEN = { required = false, description = "..." }
LGTM_BASIC_AUTH_USER = { required = false, description = "..." }
LGTM_BASIC_AUTH_PASSWORD = { required = false, description = "..." }

[profiles.staging.defaults]
providers = ["azure_kv"]
```

Then `sift ... --auth-profile staging` resolves from that Azure Key
Vault. The `cache = { provider = "local_cache", max_age = "30m" }`
wrapper is optional but recommended for any provider that can prompt a
human (1Password's device approval is the main one) — it reuses the
existing `local_cache` alias (backed by the OS keyring, not a file; see
ADR 0007) so repeated `sift` calls within the window don't re-prompt.
Real per-secret provider overrides are also possible (put `providers =
[...]` directly on one secret instead of the whole profile's
`defaults`) — see secretspec's own docs for the full schema.

## If a cached value goes stale before its TTL expires

Delete the cache entry directly from the OS keyring (secretspec's cache
key format is `secretspec/cache/{project}/{profile}/{key}`, e.g.
`secretspec/cache/sift/personal/LGTM_BEARER_TOKEN`), or just wait out the
`max_age` window — the next resolution re-fetches from the
authoritative provider automatically once the cached entry expires.

## Verifying a profile without querying anything

```bash
cd pkgs/sift && cargo test auth::
```

`secretspec_toml_parses_and_validates` catches a typo'd provider alias
or malformed TOML. It does not verify that a *real* value exists in
your provider — for that, use secretspec's own CLI (`secretspec check
--profile <name>`) once it's installed, or just run a real `sift` query
against that profile.

## Where the audit trail goes

secretspec logs every resolution attempt (who, when, which secret, why
— never the value) to `~/.local/state/secretspec/audit.log` by default.
Disable with `[audit] enabled = false` in `~/.config/secretspec/config.toml`
if you don't want this.

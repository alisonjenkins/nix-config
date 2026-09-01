# Configuring credential profiles

`sift` resolves LGTM (Loki/Prometheus) credentials via
[secretspec](https://secretspec.dev), never via a raw token typed into a
CLI flag. See `docs/adr/0006-secretspec-credential-resolution.md` for why.

## The short version

1. `pkgs/sift/secretspec.toml` declares what secrets exist
   (`LGTM_BEARER_TOKEN`, `LGTM_BASIC_AUTH_USER`,
   `LGTM_BASIC_AUTH_PASSWORD` — all optional) and, per profile, which
   provider resolves them.
2. You put real values into that provider (1Password, AWS SSM/Secrets
   Manager, Azure Key Vault, or a plain env var) yourself, outside of
   sift and outside of anything an LLM session touches.
3. You invoke `sift ... --auth-profile <name>`. Only the profile *name*
   crosses the command line — the resolved value goes straight from the
   provider into the outbound request's `Authorization` header inside
   sift's own process.

## Using an existing profile

Two examples ship in `secretspec.toml`: `personal` (1Password) and
`work` (AWS SSM Parameter Store). To use one, put the actual value into
that backend under the exact secret name:

**1Password (`personal` profile):**

```bash
op signin
op item create --category=password --vault=Personal \
  --title=LGTM_BEARER_TOKEN password=<your-real-token>
```

secretspec's 1Password provider reads by item title matching the secret
name (`LGTM_BEARER_TOKEN`), from the vault named in
`secretspec.toml`'s `[providers]` table (`Personal` by default — change
it to match your own vault).

**AWS SSM (`work` profile):**

```bash
AWS_PROFILE=<your-profile> aws ssm put-parameter \
  --name /secretspec/sift/work/LGTM_BEARER_TOKEN --type SecureString \
  --value <your-real-token>
```

`secretspec/sift/work/` is the `awsps` provider's default parameter
path template — `/secretspec/{project}/{profile}/{key}`, where
`project` comes from `secretspec.toml`'s `[project] name` and `profile`
from `--auth-profile`. Adjust the region in `secretspec.toml`'s
`work_awsps` provider entry (`awsps://us-east-1`) to match where the
parameter actually lives; add `?prefix=/myteam` to that URI instead if
you want a different path prefix than the default template.

Then:

```bash
sift lgtm logs '{app="checkout"}' --url https://loki.example.com --auth-profile work
```

## Adding your own profile

Add a new `[profiles.<name>]` section to `secretspec.toml`, declaring
the same three (optional) secrets, plus a `[profiles.<name>.defaults]`
block naming which provider alias to use:

```toml
[providers]
azure_kv = "akv://my-vault-name"

[profiles.staging]
LGTM_BEARER_TOKEN = { required = false, description = "..." }
LGTM_BASIC_AUTH_USER = { required = false, description = "..." }
LGTM_BASIC_AUTH_PASSWORD = { required = false, description = "..." }

[profiles.staging.defaults]
providers = ["azure_kv"]
```

Then `sift ... --auth-profile staging` resolves from that Azure Key
Vault. Real per-secret provider overrides are also possible (put
`providers = [...]` directly on one secret instead of the whole
profile's `defaults`) — see secretspec's own docs for the full schema.

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

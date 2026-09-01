# ADR 0006: Resolve LGTM credentials via secretspec, never as a raw CLI value

## Status

Accepted

## Context

`sift` is designed to be invoked by Claude (or another LLM-driven agent)
during an investigation, not only by a human at a terminal — that's the
whole premise of the `observability` skill this tool supports. Any
credential passed as a CLI argument or a value visibly set in an env var
sift reads directly is something Claude's own tool-call transcript would
contain: an `Authorization` bearer token typed into a `--bearer-token`
flag is exactly as visible to the LLM as the command itself.

The requirement, stated directly: secrets must never leak, and the LLM
must never see them — it should only ever know a *profile name*
identifying where a credential lives, never the credential's value.
Separately, the credentials in question need to come from real
enterprise secret stores already in use: 1Password, AWS Secrets Manager,
AWS SSM Parameter Store, and Azure Key Vault.

Two options were considered:

1. **Raw CLI flags / env vars** (`--bearer-token`, `SIFT_LGTM_TOKEN`,
   ...). Simple, but fails the core requirement outright: whoever/
   whatever invokes `sift` has to already hold the plaintext value and
   hand it over on the command line.
2. **`secretspec`** (`cachix/secretspec`, `docs.rs/secretspec`): a
   Rust library that separates *declaring* what a project needs
   (`secretspec.toml`, committed, no real values) from *resolving*
   where the value actually comes from (a named profile bound to a
   provider). The caller passes a profile name; the library returns the
   resolved plaintext to the caller's own process, never printing or
   persisting it.

secretspec was evaluated once already, and initially rejected: it adds
roughly 50 dependencies (including `tokio` and the AWS/Azure SDKs, both
async under the hood), commits the project to a `secretspec.toml`
schema file, and its multi-backend/multi-profile design looked
disproportionate for what looked at the time like "one optional
bearer token." That rejection was reversed once the actual requirement
was stated: multi-backend (1Password + AWS SSM/Secrets
Manager + Azure Key Vault), profile-scoped, LLM-opaque credential
resolution is precisely the problem secretspec's declare/resolve split
solves — it stopped being "a heavyweight tool for one flag" and became
the tool built for exactly this shape of requirement.

The dependency-cost concern (Consequences below) is real and unchanged;
it's outweighed by matching the actual requirement instead of a
simplified version of it.

## Decision

- `pkgs/sift/secretspec.toml` declares three optional secrets
  (`LGTM_BEARER_TOKEN`, `LGTM_BASIC_AUTH_USER`,
  `LGTM_BASIC_AUTH_PASSWORD`) and one or more named profiles, each
  bound to a provider (1Password via the `op` CLI, AWS SSM/Secrets
  Manager, Azure Key Vault, or a plain env var as a zero-config
  fallback). This file contains no real secret material — provider
  URIs (a vault name, an AWS region) are not secrets — so it is
  committed. See `pkgs/sift/docs/credential-profiles.md` for how to
  add or configure a profile.
- `QueryArgs` (`src/cli.rs`) carries `--auth-profile <name>` /
  `SIFT_LGTM_AUTH_PROFILE`, a profile *name* only. Omitting it means an
  unauthenticated query (the default for a local, unsecured
  Loki/Prometheus) — there is no raw-token flag to fall back to.
- `src/auth.rs`'s `Auth::from_secretspec_profile(profile: &str)` is the
  only place a resolved credential exists as a `String`. It calls
  `secretspec::Secrets::load()`, `set_profile(profile)`, and
  `resolve_named()` for each of the three secret names, then applies
  whichever resolved to `reqwest`'s `bearer_auth`/`basic_auth` directly
  on the outbound request builder. The value is never logged (`tracing`
  calls in `main.rs` log the query and URL, never `Auth`'s contents),
  never written to disk, and never round-trips through anything
  process-argument-visible.
- `Cargo.toml` pins `secretspec` with `default-features = false,
  features = ["awssm", "awsps", "akv"]` — the three cloud backends
  actually needed. 1Password support needs no feature flag: its
  provider (`secretspec/src/provider/onepassword.rs`) shells out to the
  `op` CLI via `std::process::Command` rather than linking an SDK, so it
  compiles in unconditionally.

## Consequences

- Claude's own invocations of `sift` only ever contain
  `--auth-profile work` or similar — never a value it could echo back,
  log, or leak. This is the property the whole decision exists for.
- `sift`'s dependency tree and binary size grow substantially: `tokio`,
  `aws-config`/`aws-sdk-secretsmanager`/`aws-sdk-ssm`, and
  `azure_core`/`azure_identity`/`azure_security_keyvault_secrets` all
  come in transitively through `secretspec`, even though `sift` itself
  stays fully synchronous (see the `query_window`/`fetch` call chain in
  `main.rs` — no `async fn` anywhere in `sift`'s own code; the tokio
  runtime lives entirely inside secretspec's black box, invoked through
  its synchronous `Secrets::load()`/`resolve_named()` API).
- secretspec logs every resolution attempt (profile, secret name, a
  caller-supplied reason, never the value) to a local audit log by
  default — a genuine bonus for the stated goal, not something `sift`
  had to build itself.
- Adding a new provider (Datadog's own secret needs, once ADR 0002's
  Fast-follow lands) is a `secretspec.toml` profile change, not a code
  change — `auth::Auth` is already platform-agnostic.
- Real API surface differs from secretspec's own published docs in
  places (its docs site describes a `SecretSpec::builder()` type that
  does not exist in the actual crate; the real entry point is
  `Secrets::load()` with `&mut self` setters and `resolve_named()`
  returning a `NamedResolution` enum) — this ADR's Decision section
  reflects the verified source (`cachix/secretspec` on GitHub,
  `secretspec` crate version 0.20.0), not the docs site, and any future
  secretspec upgrade should re-verify against source rather than
  trusting secretspec.dev at face value.

# ADR 0007: TTL'd local caching for resolved credentials, zeroized in memory

## Status

Accepted

## Context

ADR 0006 established profile-based credential resolution via
secretspec so an LLM-driven `sift` invocation only ever passes a
profile name, never a secret value. Two gaps surfaced once that was
working:

1. **Repeated resolution during one investigation.** Claude typically
   calls `sift` many times while investigating a single incident (one
   query per hypothesis). Each call resolves the profile's credential
   from scratch — for the 1Password provider (`onepassword.rs` shells
   out to `op item get`), that means a fresh `op` invocation every
   time, and 1Password's own device-approval flow can prompt the human
   for each one. An investigation that makes ten queries would produce
   ten approval prompts for what is, from the human's perspective, one
   ongoing task.
2. **In-memory hygiene.** `Auth` (src/auth.rs) held resolved
   credentials as plain `String`s. A plain `String`'s `Drop` just frees
   the allocation — it does not overwrite the bytes first — so a
   resolved bearer token or password could persist in freed heap memory
   for an unbounded time after `sift` no longer needed it, readable by
   a memory dump, a swapped page, or a debugger attached to the
   process.

## Decision

**Caching.** `secretspec.toml`'s `[providers]` table wraps each
authoritative provider (`personal_1password`, `work_awsps`) with
secretspec's built-in `cache` config, backed by a `local_cache` alias
pointing at `keyring://` (the OS's own credential store — Secret
Service/gnome-keyring/kwallet on Linux, Keychain on macOS, Credential
Manager on Windows):

```toml
personal_1password = { uri = "onepassword://Personal", cache = { provider = "local_cache", max_age = "30m" } }
local_cache = "keyring://secretspec/cache/{project}/{profile}/{key}"
```

The first `sift` call in a 30-minute window resolves from the
authoritative provider (and may prompt); every subsequent call within
that window reads the cached value from the OS keyring instead — no
prompt, no repeated `op`/AWS API call. secretspec's cache envelope
(`secretspec/src/cache.rs`) carries its own expiry and a
`route_fingerprint` that invalidates the entry if the provider
configuration changes, so a stale entry can't silently outlive a
`secretspec.toml` edit. The OS keyring itself is unlocked once per
login session (not per `sift` call), so caching there doesn't
reintroduce the same per-call friction it's meant to remove.

30 minutes was chosen as a reasonable single-investigation window —
long enough to cover a multi-query investigation, short enough that a
credential rotated mid-day doesn't stay cached for the rest of it.
Adjust `max_age` per profile if that tradeoff doesn't fit; see
`docs/credential-profiles.md`.

**Memory hygiene.** `Auth`'s secret-bearing fields are wrapped in
`secrecy::SecretString` rather than plain `String`:

```rust
pub struct Auth {
    pub bearer_token: Option<SecretString>,
    pub basic_auth: Option<(String, SecretString)>, // user is an identifier, not secret material
}
```

`SecretString` zeroizes its backing memory on drop and redacts itself
from `Debug` output, so an accidental `{:?}` (a `tracing` field, a
panic message) can't leak the value. `Auth::apply()` calls
`.expose_secret()` only inline, at the point of attaching the header to
the `reqwest::blocking::RequestBuilder` — the plaintext exists
unwrapped for the shortest span the API allows, not for `Auth`'s whole
lifetime.

## Consequences

- An investigation making N `sift` calls against the same
  `--auth-profile` within 30 minutes produces at most one 1Password
  approval prompt, not N.
- The cache is genuinely at the OS credential-store layer (ADR 0006's
  "no plaintext on disk" property holds for the cache too — see
  `docs/credential-profiles.md`'s note on `keyring://`), not a file
  `sift` or secretspec writes itself.
- `secrecy::SecretString` cannot cover secretspec's own internal
  resolution path (its `ResolvedSecret.value` is a plain
  `Option<String>` — that's secretspec's API, not ours to change), nor
  what `reqwest` itself does with the header value once
  `.expose_secret()` hands it over. The zeroize/redact guarantee
  applies to the span `Auth` actually owns the value: from
  `from_secretspec_profile`'s construction to `apply()`'s single-use
  exposure. This is a real, bounded improvement, not an end-to-end
  guarantee across every crate in the call chain.
- `secrecy` was already a transitive dependency (pulled in by
  `secretspec` itself), so depending on it directly adds no new crate
  to the tree — only makes an existing one part of `sift`'s own public
  surface.

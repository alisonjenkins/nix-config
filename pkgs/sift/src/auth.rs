use secrecy::{ExposeSecret, SecretString};
use secretspec::{NamedResolution, Secrets};
use std::path::{Path, PathBuf};
use thiserror::Error;

const BEARER_TOKEN_SECRET: &str = "LGTM_BEARER_TOKEN";
const BASIC_AUTH_USER_SECRET: &str = "LGTM_BASIC_AUTH_USER";
const BASIC_AUTH_PASSWORD_SECRET: &str = "LGTM_BASIC_AUTH_PASSWORD";

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("loading secretspec.toml: {0}")]
    LoadSpec(Box<secretspec::SecretSpecError>),
    #[error("resolving secret {name:?} from secretspec profile {profile:?}: {source}")]
    Resolve {
        name: &'static str,
        profile: String,
        source: Box<secretspec::SecretSpecError>,
    },
}

/// Credentials for an outbound LGTM query request, resolved once per
/// invocation via a named secretspec profile. Never persisted to disk —
/// built fresh from whichever provider (1Password, AWS SSM/Secrets
/// Manager, Azure Key Vault, ...) the profile's `secretspec.toml`
/// binding points at, and applied directly to a `reqwest` request
/// builder. The caller (main.rs, driven by `--auth-profile`) only ever
/// passes a profile *name* on the command line — the resolved plaintext
/// value never appears in a CLI argument, so it never reaches anything
/// an LLM-driven invocation of `sift` could observe. See
/// pkgs/sift/docs/adr/0006-secretspec-credential-resolution.md.
#[derive(Default)]
pub struct Auth {
    /// Wrapped in `SecretString` (zeroized on drop, `Debug`-redacted) —
    /// the actual bearer credential, not just an identifier.
    pub bearer_token: Option<SecretString>,
    /// `user` is an identifier (e.g. a Grafana Cloud instance ID), not
    /// secret material — only `password` is wrapped.
    pub basic_auth: Option<(String, SecretString)>,
}

impl Auth {
    pub fn none() -> Self {
        Self::default()
    }

    pub fn from_secretspec_profile(profile: &str) -> Result<Self, AuthError> {
        let mut secrets = resolve_secrets()?;
        secrets.set_profile(profile);
        let secrets = secrets.with_reason("sift LGTM query");

        let bearer_token =
            resolve_optional(&secrets, profile, BEARER_TOKEN_SECRET)?.map(SecretString::from);
        let basic_auth_user = resolve_optional(&secrets, profile, BASIC_AUTH_USER_SECRET)?;
        let basic_auth_password = resolve_optional(&secrets, profile, BASIC_AUTH_PASSWORD_SECRET)?
            .map(SecretString::from);

        let basic_auth = match (basic_auth_user, basic_auth_password) {
            (Some(user), Some(password)) => Some((user, password)),
            _ => None,
        };

        Ok(Self {
            bearer_token,
            basic_auth,
        })
    }

    /// Exposes the wrapped plaintext only for the span of this call —
    /// building the request's auth headers — rather than holding an
    /// unwrapped copy anywhere in `Auth` itself.
    pub fn apply(
        &self,
        builder: reqwest::blocking::RequestBuilder,
    ) -> reqwest::blocking::RequestBuilder {
        let builder = match &self.bearer_token {
            Some(token) => builder.bearer_auth(token.expose_secret()),
            None => builder,
        };
        match &self.basic_auth {
            Some((user, password)) => builder.basic_auth(user, Some(password.expose_secret())),
            None => builder,
        }
    }
}

/// Locates `secretspec.toml`, in priority order: an explicit
/// `SIFT_SECRETSPEC_TOML` override, then the Nix-installed copy next to
/// the running binary, then cwd-based discovery (walking up from the
/// working directory, same as `Secrets::load()`'s default).
///
/// The installed-copy step exists because a packaged `sift` binary's
/// cwd has no reason to contain `secretspec.toml` — cwd discovery alone
/// only works when running from a checkout of this repo (which is what
/// this module's own tests rely on). See default.nix's `postInstall`,
/// which places the file at `$out/share/sift/secretspec.toml`.
fn resolve_secrets() -> Result<Secrets, AuthError> {
    if let Ok(path) = std::env::var("SIFT_SECRETSPEC_TOML") {
        return Secrets::load_from(Path::new(&path)).map_err(|e| AuthError::LoadSpec(Box::new(e)));
    }
    if let Some(installed) = installed_secretspec_toml_path() {
        if installed.is_file() {
            return Secrets::load_from(&installed).map_err(|e| AuthError::LoadSpec(Box::new(e)));
        }
    }
    Secrets::load().map_err(|e| AuthError::LoadSpec(Box::new(e)))
}

/// `None` if the running binary's own path can't be determined —
/// callers fall through to cwd-based discovery in that case rather
/// than treating it as fatal.
fn installed_secretspec_toml_path() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let bin_dir = exe.parent()?;
    let install_root = bin_dir.parent()?;
    Some(install_root.join("share").join("sift").join("secretspec.toml"))
}

fn resolve_optional(
    secrets: &Secrets,
    profile: &str,
    name: &'static str,
) -> Result<Option<String>, AuthError> {
    let resolution = secrets
        .resolve_named(name)
        .map_err(|source| AuthError::Resolve {
            name,
            profile: profile.to_string(),
            source: Box::new(source),
        })?;

    match resolution {
        NamedResolution::Resolved(secret) => Ok(secret.value),
        NamedResolution::Missing { .. } | NamedResolution::Undeclared => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    // Regression tests for secretspec.toml itself — a typo'd provider
    // alias, secret name, or TOML syntax error would fail here without
    // needing a real 1Password/AWS/Azure credential available. Relies
    // on cargo test's cwd being the crate root (pkgs/sift), where
    // secretspec.toml lives.

    #[test]
    fn secretspec_toml_parses_and_validates() {
        // Exercises resolve_secrets()'s full priority chain, not
        // Secrets::load() directly — during `cargo test` there's no
        // installed $out/share/sift/secretspec.toml next to the test
        // binary, so this still falls through to cwd-based discovery,
        // but it's the real code path rather than a bypass of it.
        resolve_secrets().expect("pkgs/sift/secretspec.toml should load and validate");
    }

    #[test]
    fn installed_secretspec_toml_path_is_relative_to_the_running_binary() {
        // A loose sanity check: whatever current_exe() resolves to
        // during `cargo test`, the computed path should end with
        // share/sift/secretspec.toml, matching default.nix's
        // postInstall layout — not asserting the path exists (it
        // won't, in a dev/test build).
        let path = installed_secretspec_toml_path()
            .expect("current_exe() should resolve during cargo test");
        assert!(path.ends_with("share/sift/secretspec.toml"));
    }

    #[test]
    fn default_profile_resolves_to_nothing_when_the_env_var_is_unset() {
        // Regression test for a real behavior found while writing this
        // file: an optional secret with NO provider bound at all
        // errors as NoProviderConfigured rather than resolving to
        // Missing — "no value" and "misconfigured" must stay
        // distinguishable. secretspec.toml binds the default profile
        // to the `env` provider specifically so this stays resolvable.
        let mut secrets = resolve_secrets().expect("secretspec.toml should load");
        secrets.set_profile("default");
        let secrets = secrets.with_reason("auth.rs unit test");

        let resolution = secrets
            .resolve_named(BEARER_TOKEN_SECRET)
            .expect("resolving an optional secret via the env provider should not error");

        assert!(matches!(
            resolution,
            NamedResolution::Missing { required: false } | NamedResolution::Undeclared
        ));
    }
}

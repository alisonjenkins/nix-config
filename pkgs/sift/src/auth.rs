use secretspec::{NamedResolution, Secrets};
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
/// docs/adr/0006-secretspec-credential-resolution.md.
#[derive(Default)]
pub struct Auth {
    pub bearer_token: Option<String>,
    pub basic_auth: Option<(String, String)>,
}

impl Auth {
    pub fn none() -> Self {
        Self::default()
    }

    pub fn from_secretspec_profile(profile: &str) -> Result<Self, AuthError> {
        let mut secrets = Secrets::load().map_err(|e| AuthError::LoadSpec(Box::new(e)))?;
        secrets.set_profile(profile);
        let secrets = secrets.with_reason("sift LGTM query");

        let bearer_token = resolve_optional(&secrets, profile, BEARER_TOKEN_SECRET)?;
        let basic_auth_user = resolve_optional(&secrets, profile, BASIC_AUTH_USER_SECRET)?;
        let basic_auth_password = resolve_optional(&secrets, profile, BASIC_AUTH_PASSWORD_SECRET)?;

        let basic_auth = match (basic_auth_user, basic_auth_password) {
            (Some(user), Some(password)) => Some((user, password)),
            _ => None,
        };

        Ok(Self {
            bearer_token,
            basic_auth,
        })
    }

    pub fn apply(
        &self,
        builder: reqwest::blocking::RequestBuilder,
    ) -> reqwest::blocking::RequestBuilder {
        let builder = match &self.bearer_token {
            Some(token) => builder.bearer_auth(token),
            None => builder,
        };
        match &self.basic_auth {
            Some((user, password)) => builder.basic_auth(user, Some(password)),
            None => builder,
        }
    }
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
        Secrets::load().expect("pkgs/sift/secretspec.toml should load and validate");
    }

    #[test]
    fn default_profile_resolves_to_nothing_when_the_env_var_is_unset() {
        // Regression test for a real behavior found while writing this
        // file: an optional secret with NO provider bound at all
        // errors as NoProviderConfigured rather than resolving to
        // Missing — "no value" and "misconfigured" must stay
        // distinguishable. secretspec.toml binds the default profile
        // to the `env` provider specifically so this stays resolvable.
        let mut secrets = Secrets::load().expect("secretspec.toml should load");
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

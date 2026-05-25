// CurseForge (cfwidget) + Modrinth API wrappers. Listings cached on disk
// for 1h; jars cached indefinitely (by file/version id). All HTTP goes
// through the retry/backoff wrapper in `http`.
use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::PathBuf;
use std::time::Duration;

use crate::cache::{cache_dir, cache_fresh};
use crate::http::http_get;
use crate::state::{Source, StateEntry};

const LISTING_TTL_SECS: u64 = 3600;
const _LISTING_TTL: Duration = Duration::from_secs(LISTING_TTL_SECS);

#[derive(Debug, Clone, Deserialize)]
pub struct CfFile {
    pub id: u64,
    pub name: String,
    #[serde(default)]
    pub versions: Vec<String>,
    #[serde(default, rename = "type")]
    pub ftype: String,
}

#[derive(Debug, Deserialize)]
struct CfProject {
    #[serde(default)]
    files: Vec<CfFile>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MrFile {
    pub url: String,
    pub filename: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MrVersion {
    pub id: String,
    #[serde(default)]
    pub version_number: Option<String>,
    #[serde(default)]
    pub files: Vec<MrFile>,
    #[serde(default)]
    pub date_published: String,
}

/// One bump candidate uniform across both backends. `fetch_to` downloads
/// the underlying jar into the cache and returns its local path.
#[derive(Clone)]
pub struct Candidate {
    pub source: &'static str,
    pub id: String,
    pub name: String,
    pub version_hint: Option<String>,
    pub fetch: std::sync::Arc<dyn Fn() -> Result<PathBuf> + Send + Sync>,
}

impl std::fmt::Debug for Candidate {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Candidate")
            .field("source", &self.source)
            .field("id", &self.id)
            .field("name", &self.name)
            .field("version_hint", &self.version_hint)
            .finish()
    }
}

/// Returns the "current id" (source-appropriate identifier) used to
/// short-circuit when the candidate list's newest entry matches what
/// we already ship.
pub fn current_id_of(entry: &StateEntry) -> String {
    match &entry.source {
        Source::Curseforge { file_id, .. } => file_id.to_string(),
        Source::Modrinth { version_id, .. } => version_id.clone(),
    }
}

pub fn cfwidget_files(project_id: u64) -> Result<Vec<CfFile>> {
    let cache = cache_dir().join(format!("cfwidget-{}.json", project_id));
    let d: CfProject = if cache_fresh(&cache, LISTING_TTL_SECS) {
        serde_json::from_slice(&std::fs::read(&cache)?)
            .with_context(|| format!("decode cached {}", cache.display()))?
    } else {
        let raw = http_get(&format!("https://api.cfwidget.com/{}", project_id))?;
        let _ = std::fs::write(&cache, &raw);
        serde_json::from_slice(&raw).with_context(|| format!("decode cfwidget {}", project_id))?
    };
    let mut files: Vec<CfFile> = d
        .files
        .into_iter()
        .filter(|f| {
            f.versions.iter().any(|v| v == "1.21.1")
                && f.versions.iter().any(|v| v == "NeoForge")
                && (f.ftype == "release" || f.ftype == "beta")
        })
        .collect();
    // Newest first by upload id.
    files.sort_by(|a, b| b.id.cmp(&a.id));
    Ok(files)
}

fn url_encode_array_param(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

pub fn modrinth_versions(project_id: &str) -> Result<Vec<MrVersion>> {
    let cache = cache_dir().join(format!("modrinth-{}.json", project_id));
    let mut d: Vec<MrVersion> = if cache_fresh(&cache, LISTING_TTL_SECS) {
        serde_json::from_slice(&std::fs::read(&cache)?)
            .with_context(|| format!("decode cached {}", cache.display()))?
    } else {
        let gv = url_encode_array_param("[\"1.21.1\"]");
        let ld = url_encode_array_param("[\"neoforge\"]");
        let url = format!(
            "https://api.modrinth.com/v2/project/{}/version?game_versions={}&loaders={}",
            project_id, gv, ld
        );
        let raw = http_get(&url)?;
        let _ = std::fs::write(&cache, &raw);
        serde_json::from_slice(&raw)
            .with_context(|| format!("decode modrinth versions {}", project_id))?
    };
    d.sort_by(|a, b| b.date_published.cmp(&a.date_published));
    Ok(d)
}

pub fn fetch_jar_curseforge(file_id: u64, name: &str) -> Result<PathBuf> {
    let out = cache_dir().join(format!("cf-{}-{}", file_id, name));
    if let Ok(meta) = std::fs::metadata(&out) {
        if meta.len() > 0 {
            return Ok(out);
        }
    }
    let pre = file_id / 1000;
    let suf = file_id % 1000;
    let url = format!(
        "https://mediafilez.forgecdn.net/files/{}/{}/{}",
        pre, suf, name
    );
    let bytes = http_get(&url)?;
    std::fs::write(&out, &bytes)?;
    Ok(out)
}

pub fn fetch_jar_modrinth(version_id: &str, file_url: &str, name: &str) -> Result<PathBuf> {
    let out = cache_dir().join(format!("mr-{}-{}", version_id, name));
    if let Ok(meta) = std::fs::metadata(&out) {
        if meta.len() > 0 {
            return Ok(out);
        }
    }
    let bytes = http_get(file_url)?;
    std::fs::write(&out, &bytes)?;
    Ok(out)
}

pub fn enumerate_candidates(entry: &StateEntry) -> Result<Vec<Candidate>> {
    match &entry.source {
        Source::Curseforge { project_id, .. } => {
            let files = cfwidget_files(*project_id)?;
            Ok(files
                .into_iter()
                .map(|f| {
                    let fid = f.id;
                    let name = f.name.clone();
                    Candidate {
                        source: "curseforge",
                        id: fid.to_string(),
                        name: name.clone(),
                        version_hint: None,
                        fetch: std::sync::Arc::new(move || {
                            fetch_jar_curseforge(fid, &name)
                        }),
                    }
                })
                .collect())
        }
        Source::Modrinth { project_id, .. } => {
            let versions = modrinth_versions(project_id)?;
            Ok(versions
                .into_iter()
                .filter_map(|v| {
                    let f0 = v.files.first()?.clone();
                    let vid = v.id.clone();
                    let url = f0.url.clone();
                    let name = f0.filename.clone();
                    Some(Candidate {
                        source: "modrinth",
                        id: vid.clone(),
                        name: name.clone(),
                        version_hint: v.version_number,
                        fetch: std::sync::Arc::new(move || {
                            fetch_jar_modrinth(&vid, &url, &name)
                        }),
                    })
                })
                .collect())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_brackets_and_quotes() {
        assert_eq!(
            url_encode_array_param("[\"1.21.1\"]"),
            "%5B%221.21.1%22%5D"
        );
        assert_eq!(
            url_encode_array_param("[\"neoforge\"]"),
            "%5B%22neoforge%22%5D"
        );
        assert_eq!(url_encode_array_param("abc-1.2_3.~"), "abc-1.2_3.~");
    }

    #[test]
    fn current_id_dispatch() {
        let cf = StateEntry {
            source: Source::Curseforge {
                project_id: 1,
                file_id: 42,
            },
            dest_file: crate::state::DestFile::Extras,
        };
        assert_eq!(current_id_of(&cf), "42");

        let mr = StateEntry {
            source: Source::Modrinth {
                project_id: "abc".into(),
                version_id: "xyz".into(),
            },
            dest_file: crate::state::DestFile::Overlays,
        };
        assert_eq!(current_id_of(&mr), "xyz");
    }
}

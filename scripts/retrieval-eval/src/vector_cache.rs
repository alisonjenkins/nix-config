use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CacheError {
    #[error("read cache {path}: {source}")]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("parse cache {path}: {source}")]
    Parse {
        path: PathBuf,
        source: serde_json::Error,
    },
    #[error("write cache {path}: {source}")]
    Write {
        path: PathBuf,
        source: std::io::Error,
    },
}

#[derive(Debug, Serialize, Deserialize)]
struct Entry {
    hash: u64,
    vector: Vec<f32>,
}

/// Document vectors keyed by chunk id, valid only for one embedder identity
/// and only while the chunk's text hash is unchanged.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct VectorCache {
    identity: String,
    entries: HashMap<String, Entry>,
}

/// FNV-1a, 64-bit: stable across Rust versions, unlike `DefaultHasher`.
pub fn fnv1a(text: &str) -> u64 {
    const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
    const PRIME: u64 = 0x0000_0100_0000_01b3;
    text.bytes().fold(OFFSET_BASIS, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(PRIME)
    })
}

impl VectorCache {
    pub fn new(identity: &str) -> Self {
        Self {
            identity: identity.to_owned(),
            entries: HashMap::new(),
        }
    }

    /// A missing file, or one written for a different identity, is an empty cache.
    pub fn load(path: &Path, identity: &str) -> Result<Self, CacheError> {
        let raw = match fs::read_to_string(path) {
            Ok(raw) => raw,
            Err(source) if source.kind() == ErrorKind::NotFound => return Ok(Self::new(identity)),
            Err(source) => {
                return Err(CacheError::Read {
                    path: path.to_owned(),
                    source,
                })
            }
        };
        let cache: Self = serde_json::from_str(&raw).map_err(|source| CacheError::Parse {
            path: path.to_owned(),
            source,
        })?;
        Ok(if cache.identity == identity {
            cache
        } else {
            Self::new(identity)
        })
    }

    /// Writes a sibling temp file then renames it, so a hook reading the cache
    /// never sees a half-written one.
    pub fn save(&self, path: &Path) -> Result<(), CacheError> {
        let write_err = |source| CacheError::Write {
            path: path.to_owned(),
            source,
        };
        let json = serde_json::to_string(self).map_err(|e| write_err(e.into()))?;
        let tmp = path.with_extension("tmp");
        fs::write(&tmp, json).map_err(write_err)?;
        fs::rename(&tmp, path).map_err(write_err)
    }

    pub fn get(&self, id: &str, hash: u64) -> Option<&[f32]> {
        self.entries
            .get(id)
            .filter(|entry| entry.hash == hash)
            .map(|entry| entry.vector.as_slice())
    }

    pub fn put(&mut self, id: String, hash: u64, vector: Vec<f32>) {
        self.entries.insert(id, Entry { hash, vector });
    }

    /// Drop entries whose chunk no longer exists.
    pub fn retain_ids(&mut self, ids: &HashSet<&str>) {
        self.entries.retain(|id, _| ids.contains(id.as_str()));
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    #[test]
    fn fnv1a_matches_reference_vectors() {
        assert_eq!(fnv1a(""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a("a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(fnv1a("foobar"), 0x8594_4171_f739_67e8);
    }

    #[test]
    fn get_returns_vector_only_for_matching_hash() {
        let mut cache = VectorCache::new("m");
        cache.put("a.md".to_owned(), 7, vec![1.0, 2.0]);
        assert_eq!(cache.get("a.md", 7), Some([1.0, 2.0].as_slice()));
        assert_eq!(cache.get("a.md", 8), None);
        assert_eq!(cache.get("b.md", 7), None);
    }

    #[test]
    fn put_replaces_a_stale_entry() {
        let mut cache = VectorCache::new("m");
        cache.put("a.md".to_owned(), 1, vec![1.0]);
        cache.put("a.md".to_owned(), 2, vec![9.0]);
        assert_eq!(cache.len(), 1);
        assert_eq!(cache.get("a.md", 2), Some([9.0].as_slice()));
    }

    #[test]
    fn save_then_load_round_trips() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.json");
        let mut cache = VectorCache::new("m");
        cache.put("a.md".to_owned(), u64::MAX, vec![0.5, -0.5]);
        cache.save(&path).unwrap();
        let loaded = VectorCache::load(&path, "m").unwrap();
        assert_eq!(loaded.get("a.md", u64::MAX), Some([0.5, -0.5].as_slice()));
    }

    #[test]
    fn save_leaves_no_temp_file_behind() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.json");
        VectorCache::new("m").save(&path).unwrap();
        let names: Vec<String> = std::fs::read_dir(dir.path())
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names, ["cache.json"]);
    }

    #[test]
    fn missing_file_loads_as_empty() {
        let dir = tempfile::tempdir().unwrap();
        let cache = VectorCache::load(&dir.path().join("nope.json"), "m").unwrap();
        assert!(cache.is_empty());
    }

    #[test]
    fn identity_mismatch_discards_the_old_vectors() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.json");
        let mut cache = VectorCache::new("model-a");
        cache.put("a.md".to_owned(), 1, vec![1.0]);
        cache.save(&path).unwrap();
        assert!(VectorCache::load(&path, "model-b").unwrap().is_empty());
    }

    #[test]
    fn corrupt_file_error_names_the_path() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.json");
        std::fs::write(&path, "{broken").unwrap();
        let err = VectorCache::load(&path, "m").unwrap_err();
        assert!(err.to_string().contains("cache.json"));
    }

    #[test]
    fn retain_ids_drops_deleted_chunks() {
        let mut cache = VectorCache::new("m");
        cache.put("keep.md".to_owned(), 1, vec![1.0]);
        cache.put("gone.md".to_owned(), 1, vec![1.0]);
        cache.retain_ids(&HashSet::from(["keep.md"]));
        assert_eq!(cache.len(), 1);
        assert!(cache.get("keep.md", 1).is_some());
    }
}

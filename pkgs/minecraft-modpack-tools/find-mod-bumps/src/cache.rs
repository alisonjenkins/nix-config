// On-disk HTTP/jar cache. Honours $FIND_BUMPS_CACHE so CI runs can pin a
// scratch dir; defaults to /tmp/find-mod-bumps-cache for parity with the
// retired python script.
use std::path::PathBuf;
use std::sync::OnceLock;

pub fn cache_dir() -> &'static PathBuf {
    static C: OnceLock<PathBuf> = OnceLock::new();
    C.get_or_init(|| {
        let p = std::env::var("FIND_BUMPS_CACHE")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/tmp/find-mod-bumps-cache"));
        let _ = std::fs::create_dir_all(&p);
        p
    })
}

/// Return true if a cache file is younger than `max_age_secs`.
pub fn cache_fresh(path: &std::path::Path, max_age_secs: u64) -> bool {
    let Ok(meta) = std::fs::metadata(path) else {
        return false;
    };
    let Ok(modified) = meta.modified() else {
        return false;
    };
    modified
        .elapsed()
        .map(|d| d.as_secs() < max_age_secs)
        .unwrap_or(false)
}

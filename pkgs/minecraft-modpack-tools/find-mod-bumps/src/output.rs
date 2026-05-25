// Formatters for the three replacement-entry shapes. Sha256 is left as a
// `$(nix hash file ...)` shell substitution so the user pastes the
// emitted block into a here-doc that materializes the literal hash. The
// rust binary deliberately does not shell out itself.
use crate::cache::cache_dir;

#[derive(Debug, Clone)]
pub struct BumpRecord {
    pub mod_id: String,
    pub name: String,
    pub version: String,
    pub current_version: String,
    pub source: String,  // "curseforge" | "modrinth"
    pub dest_file: String, // "extras.nix" | "overlays.nix"
    pub project_id_num: u64,    // CF project id (0 for modrinth)
    pub project_id_str: String, // Modrinth project id (empty for CF)
    pub file_id: u64,           // CF only
    pub current_file_id: u64,   // CF only
    pub version_id: String,     // Modrinth only
    pub current_version_id: String, // Modrinth only
}

pub fn format_extras_replacement(b: &BumpRecord) -> String {
    let cached = cache_dir().join(format!("cf-{}-{}", b.file_id, b.name));
    let pre = b.file_id / 1000;
    let suf = b.file_id % 1000;
    format!(
        "    {{\n\
         \x20     origProjectID = {pid};\n\
         \x20     origFileID    = {ofid};\n\
         \x20     projectID     = {pid};\n\
         \x20     fileID        = {fid};\n\
         \x20     required      = true;\n\
         \x20     filename      = \"{name}\";\n\
         \x20     jar = fetchurl {{\n\
         \x20       url    = \"https://mediafilez.forgecdn.net/files/{pre}/{suf}/{name}\";\n\
         \x20       name   = \"{name}\";\n\
         \x20       sha256 = \"$(nix hash file --base32 --type sha256 {cached})\";\n\
         \x20     }};\n\
         \x20   }}",
        pid = b.project_id_num,
        ofid = b.current_file_id,
        fid = b.file_id,
        name = b.name,
        pre = pre,
        suf = suf,
        cached = cached.display(),
    )
}

pub fn format_overlays_curseforge(b: &BumpRecord) -> String {
    let cached = cache_dir().join(format!("cf-{}-{}", b.file_id, b.name));
    format!(
        "  # In overlays.nix, replace the matching curseforge entry with:\n\
        \x20 {{\n\
        \x20   filename       = \"{name}\";\n\
        \x20   dropAsOverride = false;\n\
        \x20   projectID      = {pid};\n\
        \x20   fileID         = {fid};\n\
        \x20   jar = curseforge {fid} \"{name}\"\n\
        \x20     \"$(nix hash file --base32 --type sha256 {cached})\";\n\
        \x20 }}",
        name = b.name,
        pid = b.project_id_num,
        fid = b.file_id,
        cached = cached.display(),
    )
}

pub fn format_overlays_modrinth(b: &BumpRecord) -> String {
    let cached = cache_dir().join(format!("mr-{}-{}", b.version_id, b.name));
    format!(
        "  # In overlays.nix, replace the matching modrinth entry with:\n\
        \x20 {{\n\
        \x20   filename       = \"{name}\";\n\
        \x20   dropAsOverride = true;\n\
        \x20   jar = modrinth \"{pid}\" \"{vid}\"\n\
        \x20     \"{name}\"\n\
        \x20     \"$(nix hash file --base32 --type sha256 {cached})\";\n\
        \x20 }}",
        name = b.name,
        pid = b.project_id_str,
        vid = b.version_id,
        cached = cached.display(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cf_bump() -> BumpRecord {
        BumpRecord {
            mod_id: "foo".into(),
            name: "foo-2.0.jar".into(),
            version: "2.0".into(),
            current_version: "1.0".into(),
            source: "curseforge".into(),
            dest_file: "extras.nix".into(),
            project_id_num: 12345,
            project_id_str: String::new(),
            file_id: 99001,
            current_file_id: 88001,
            version_id: String::new(),
            current_version_id: String::new(),
        }
    }

    fn mr_bump() -> BumpRecord {
        BumpRecord {
            mod_id: "iris".into(),
            name: "iris-1.9.0.jar".into(),
            version: "1.9.0".into(),
            current_version: "1.8.0".into(),
            source: "modrinth".into(),
            dest_file: "overlays.nix".into(),
            project_id_num: 0,
            project_id_str: "YL57xq9U".into(),
            file_id: 0,
            current_file_id: 0,
            version_id: "ZZZZ".into(),
            current_version_id: "ABCD".into(),
        }
    }

    #[test]
    fn extras_replacement_contains_pinned_fields() {
        let s = format_extras_replacement(&cf_bump());
        assert!(s.contains("origProjectID = 12345"));
        assert!(s.contains("origFileID    = 88001"));
        assert!(s.contains("projectID     = 12345"));
        assert!(s.contains("fileID        = 99001"));
        assert!(s.contains("filename      = \"foo-2.0.jar\""));
        // forgecdn split path: 99001 -> 99/1
        assert!(s.contains("/files/99/1/foo-2.0.jar"));
        assert!(s.contains("$(nix hash file --base32 --type sha256"));
    }

    #[test]
    fn overlays_modrinth_contains_modrinth_helper() {
        let s = format_overlays_modrinth(&mr_bump());
        assert!(s.contains("modrinth \"YL57xq9U\" \"ZZZZ\""));
        assert!(s.contains("filename       = \"iris-1.9.0.jar\""));
    }

    #[test]
    fn overlays_curseforge_contains_curseforge_helper() {
        let s = format_overlays_curseforge(&cf_bump());
        assert!(s.contains("curseforge 99001 \"foo-2.0.jar\""));
    }
}

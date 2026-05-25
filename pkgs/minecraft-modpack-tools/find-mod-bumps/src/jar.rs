// Read `META-INF/neoforge.mods.toml` (or the older `META-INF/mods.toml`)
// from a jar and parse the `[[mods]]` + `[dependencies.<modId>]` tables
// into a per-modId info struct.
use regex::Regex;
use std::collections::HashMap;
use std::io::Read;
use std::path::Path;
use std::sync::OnceLock;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Dep {
    pub mod_id: String,
    pub version_range: String,
    pub dep_type: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ModInfo {
    pub version: String,
    pub deps: Vec<Dep>,
}

fn re_strip_desc() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    // Triple-single-quoted descriptions often contain control chars that
    // break the toml crate. Strip them before parsing — we don't read
    // descriptions anyway.
    R.get_or_init(|| Regex::new(r"(?s)description\s*=\s*'''.*?'''").unwrap())
}

pub fn parse_modstoml_bytes(raw: &[u8]) -> Option<HashMap<String, ModInfo>> {
    let text = String::from_utf8_lossy(raw);
    let text = re_strip_desc().replace_all(&text, "description=''");
    let parsed: toml::Value = match toml::from_str(&text) {
        Ok(v) => v,
        Err(_) => return None,
    };
    let mods_arr = parsed.get("mods")?.as_array()?;
    let deps_table = parsed.get("dependencies").and_then(|v| v.as_table());

    let mut out: HashMap<String, ModInfo> = HashMap::new();
    for m in mods_arr {
        let Some(mid) = m.get("modId").and_then(|v| v.as_str()) else {
            continue;
        };
        let version = m
            .get("version")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let mut deps: Vec<Dep> = Vec::new();
        if let Some(t) = deps_table {
            if let Some(raw_deps) = t.get(mid) {
                let entries: Vec<&toml::Value> = match raw_deps {
                    toml::Value::Array(a) => a.iter().collect(),
                    toml::Value::Table(_) => vec![raw_deps],
                    _ => vec![],
                };
                for d in entries {
                    deps.push(Dep {
                        mod_id: d
                            .get("modId")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        version_range: d
                            .get("versionRange")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        dep_type: d
                            .get("type")
                            .and_then(|v| v.as_str())
                            .unwrap_or("required")
                            .to_string(),
                    });
                }
            }
        }
        out.insert(mid.to_string(), ModInfo { version, deps });
    }
    Some(out)
}

pub fn parse_jar_mods(jar_path: &Path) -> HashMap<String, ModInfo> {
    if !jar_path.exists() {
        return HashMap::new();
    }
    let Ok(file) = std::fs::File::open(jar_path) else {
        return HashMap::new();
    };
    let Ok(mut zf) = zip::ZipArchive::new(file) else {
        return HashMap::new();
    };
    for name in ["META-INF/neoforge.mods.toml", "META-INF/mods.toml"] {
        if let Ok(mut entry) = zf.by_name(name) {
            let mut raw = Vec::new();
            if entry.read_to_end(&mut raw).is_ok() {
                if let Some(out) = parse_modstoml_bytes(&raw) {
                    return out;
                }
            }
            break;
        }
    }
    HashMap::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_toml() -> &'static [u8] {
        // Two mods in one file, one with a list-of-tables dep, one with
        // a single inline dep. The triple-quoted description deliberately
        // includes content that would trip strict TOML parsers.
        br#"
modLoader = "javafml"
loaderVersion = "[4,)"
license = "MIT"

[[mods]]
modId = "foo"
version = "1.2.3"
description = '''
Multi-line
desc with 'quotes' that some parsers choke on.
'''

[[mods]]
modId = "bar"
version = "9.9.9"

[[dependencies.foo]]
modId = "neoforge"
versionRange = "[21.1.0,)"
type = "required"

[[dependencies.foo]]
modId = "shared_lib"
versionRange = "[6.0.0,7.0.0)"
type = "required"

[[dependencies.bar]]
modId = "foo"
versionRange = "[1.0.0,2.0.0)"
type = "optional"
"#
    }

    #[test]
    fn parses_mods_and_deps() {
        let parsed = parse_modstoml_bytes(sample_toml()).expect("parse ok");
        assert_eq!(parsed.len(), 2);

        let foo = parsed.get("foo").unwrap();
        assert_eq!(foo.version, "1.2.3");
        assert_eq!(foo.deps.len(), 2);
        assert_eq!(foo.deps[1].mod_id, "shared_lib");
        assert_eq!(foo.deps[1].version_range, "[6.0.0,7.0.0)");
        assert_eq!(foo.deps[1].dep_type, "required");

        let bar = parsed.get("bar").unwrap();
        assert_eq!(bar.version, "9.9.9");
        assert_eq!(bar.deps.len(), 1);
        assert_eq!(bar.deps[0].dep_type, "optional");
    }

    #[test]
    fn returns_none_on_broken_toml() {
        let parsed = parse_modstoml_bytes(b"this = is = not = toml");
        assert!(parsed.is_none());
    }

    #[test]
    fn empty_when_no_mods_array() {
        // Missing [[mods]] block yields None (matches python's behaviour
        // of returning a (None, None) tuple).
        let parsed = parse_modstoml_bytes(b"foo = 1\n");
        assert!(parsed.is_none());
    }
}

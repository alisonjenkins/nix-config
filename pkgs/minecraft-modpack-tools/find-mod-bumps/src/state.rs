// Parse the merged pack-state from the three source files
// (arkana-mods.nix, arkana-mods-extras.nix, overlays.nix). Same regex
// shapes as the python predecessor; resolution order matches too.
use regex::Regex;
use std::collections::HashMap;
use std::path::Path;
use std::sync::OnceLock;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Source {
    Curseforge { project_id: u64, file_id: u64 },
    Modrinth { project_id: String, version_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DestFile {
    Extras,
    Overlays,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StateEntry {
    pub source: Source,
    pub dest_file: DestFile,
    /// `noBump = true` on the extras replacement — a hand-pin the tool must
    /// never advance. Set for mods where a newer upstream file is a known-bad
    /// ABI break (e.g. lionfishapi 2.6: 2.7-fix-fix drops IAnimatedEntity and
    /// changes BasicEntityModel, crashing L_Ender's Cataclysm). Without this,
    /// every fixpoint round re-suggests the bump and clobbers the manual pin.
    pub no_bump: bool,
}

impl StateEntry {
    pub fn source_kind(&self) -> &'static str {
        match self.source {
            Source::Curseforge { .. } => "curseforge",
            Source::Modrinth { .. } => "modrinth",
        }
    }
}

fn re_entry() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(
            r#"(?s)projectID\s*=\s*(\d+)\s*;\s*fileID\s*=\s*(\d+)\s*;\s*required\s*=\s*\w+\s*;\s*filename\s*=\s*"([^"]+)""#,
        )
        .unwrap()
    })
}
fn re_replace() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        // Optional `noBump = true;` immediately precedes origProjectID when a
        // replacement is a hand-pin (group 1). Groups then shift: 2=origPID,
        // 3=origFID, 4=newPID, 5=newFID, 6=filename.
        Regex::new(
            r#"(?s)(?:noBump\s*=\s*(true|false)\s*;\s*)?origProjectID\s*=\s*(\d+)\s*;\s*origFileID\s*=\s*(\d+)\s*;\s*projectID\s*=\s*(\d+)\s*;\s*fileID\s*=\s*(\d+)\s*;\s*required\s*=\s*\w+\s*;\s*filename\s*=\s*"([^"]+)""#,
        )
        .unwrap()
    })
}
fn re_skipdis() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"projectID\s*=\s*(\d+)\s*;\s*fileID\s*=\s*(?:(\d+)|null)").unwrap())
}
fn re_overlay_modrinth() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    // Tolerate up to ~400 chars between `filename = "..."` and the
    // `modrinth "PROJ" "VER"` helper invocation.
    R.get_or_init(|| {
        Regex::new(
            r#"(?s)filename\s*=\s*"([^"]+)"\s*;[\s\S]{0,400}?modrinth\s+"([A-Za-z0-9]+)"\s+"([A-Za-z0-9]+)""#,
        )
        .unwrap()
    })
}
fn re_overlay_curseforge() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(
            r#"(?s)filename\s*=\s*"([^"]+)"[\s\S]{0,300}?projectID\s*=\s*(\d+)\s*;\s*fileID\s*=\s*(\d+)\s*;\s*jar\s*=\s*curseforge"#,
        )
        .unwrap()
    })
}

fn slice_section<'a>(text: &'a str, marker: &str) -> Option<&'a str> {
    let s = text.find(marker)?;
    let after = &text[s..];
    let e = after.find("];")?;
    Some(&after[..e])
}

/// Build the merged effective mod-source map (filename -> StateEntry).
/// Resolution order: arkana base -> extras replacements override by
/// (origProjectID, origFileID) -> extras skipped/disabled remove ->
/// overlays additive.
pub fn load_pack_state(
    mods_nix: &Path,
    extras_nix: Option<&Path>,
    overlays_nix: Option<&Path>,
) -> std::io::Result<HashMap<String, StateEntry>> {
    let mods_text = std::fs::read_to_string(mods_nix)?;
    let extras_text = match extras_nix {
        Some(p) if p.exists() => std::fs::read_to_string(p)?,
        _ => String::new(),
    };
    let overlays_text = match overlays_nix {
        Some(p) if p.exists() => std::fs::read_to_string(p)?,
        _ => String::new(),
    };
    Ok(load_pack_state_from_strings(
        &mods_text,
        &extras_text,
        &overlays_text,
    ))
}

/// Pure-string version of `load_pack_state` so tests don't need fs setup.
pub fn load_pack_state_from_strings(
    mods_text: &str,
    extras_text: &str,
    overlays_text: &str,
) -> HashMap<String, StateEntry> {
    let mut by_orig: HashMap<(u64, u64), String> = HashMap::new();
    // (projectID, fileID) pairs carrying `noBump = true` — never advance.
    let mut no_bump_keys: std::collections::HashSet<(u64, u64)> = std::collections::HashSet::new();
    for c in re_entry().captures_iter(mods_text) {
        let pid: u64 = c[1].parse().unwrap_or(0);
        let fid: u64 = c[2].parse().unwrap_or(0);
        by_orig.insert((pid, fid), c[3].to_string());
    }

    if !extras_text.is_empty() {
        if let Some(section) = slice_section(extras_text, "replacements = [") {
            for c in re_replace().captures_iter(section) {
                let no_bump = c.get(1).is_some_and(|m| m.as_str() == "true");
                let opid: u64 = c[2].parse().unwrap_or(0);
                let ofid: u64 = c[3].parse().unwrap_or(0);
                let npid: u64 = c[4].parse().unwrap_or(0);
                let nfid: u64 = c[5].parse().unwrap_or(0);
                by_orig.remove(&(opid, ofid));
                by_orig.insert((npid, nfid), c[6].to_string());
                if no_bump {
                    no_bump_keys.insert((npid, nfid));
                }
            }
        }
        for marker in ["skipped = [", "disabled = ["] {
            let Some(section) = slice_section(extras_text, marker) else {
                continue;
            };
            for c in re_skipdis().captures_iter(section) {
                let pid: u64 = c[1].parse().unwrap_or(0);
                let fid: Option<u64> = c.get(2).and_then(|m| m.as_str().parse().ok());
                match fid {
                    None => by_orig.retain(|k, _| k.0 != pid),
                    Some(fid) => {
                        by_orig.remove(&(pid, fid));
                    }
                }
            }
        }
    }

    let mut state: HashMap<String, StateEntry> = HashMap::new();
    for ((pid, fid), fname) in by_orig.into_iter() {
        let no_bump = no_bump_keys.contains(&(pid, fid));
        state.insert(
            fname,
            StateEntry {
                source: Source::Curseforge {
                    project_id: pid,
                    file_id: fid,
                },
                dest_file: DestFile::Extras,
                no_bump,
            },
        );
    }

    if !overlays_text.is_empty() {
        for c in re_overlay_modrinth().captures_iter(overlays_text) {
            let fname = c[1].to_string();
            state.insert(
                fname,
                StateEntry {
                    source: Source::Modrinth {
                        project_id: c[2].to_string(),
                        version_id: c[3].to_string(),
                    },
                    dest_file: DestFile::Overlays,
                    no_bump: false,
                },
            );
        }
        for c in re_overlay_curseforge().captures_iter(overlays_text) {
            let fname = c[1].to_string();
            // Defensive: don't clobber a Modrinth match for the same name.
            state.entry(fname).or_insert(StateEntry {
                source: Source::Curseforge {
                    project_id: c[2].parse().unwrap_or(0),
                    file_id: c[3].parse().unwrap_or(0),
                },
                dest_file: DestFile::Overlays,
                no_bump: false,
            });
        }
    }

    state
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arkana_base_entries() {
        let mods = r#"
        [
          {
            projectID = 12345;
            fileID    = 678;
            required  = true;
            filename  = "alpha-1.0.jar";
          }
          {
            projectID = 99;
            fileID    = 100;
            required  = true;
            filename  = "beta-2.0.jar";
          }
        ]
        "#;
        let s = load_pack_state_from_strings(mods, "", "");
        assert_eq!(s.len(), 2);
        let alpha = s.get("alpha-1.0.jar").unwrap();
        assert_eq!(alpha.dest_file, DestFile::Extras);
        assert_eq!(
            alpha.source,
            Source::Curseforge {
                project_id: 12345,
                file_id: 678
            }
        );
    }

    #[test]
    fn extras_replacements_override_by_orig_key() {
        let mods = r#"{ projectID = 1; fileID = 10; required = true; filename = "old.jar"; }"#;
        let extras = r#"
        replacements = [
          {
            origProjectID = 1;
            origFileID    = 10;
            projectID     = 1;
            fileID        = 20;
            required      = true;
            filename      = "new.jar";
          }
        ];
        "#;
        let s = load_pack_state_from_strings(mods, extras, "");
        assert_eq!(s.len(), 1);
        assert!(!s.contains_key("old.jar"));
        let new = s.get("new.jar").unwrap();
        assert_eq!(
            new.source,
            Source::Curseforge {
                project_id: 1,
                file_id: 20
            }
        );
    }

    #[test]
    fn extras_replacement_nobump_flag_parsed() {
        let mods = r#"
          { projectID = 1; fileID = 10; required = true; filename = "pinned-old.jar"; }
          { projectID = 2; fileID = 20; required = true; filename = "free-old.jar"; }
        "#;
        // First replacement is a hand-pin (noBump = true); second is a normal
        // bump with no flag. Only the first entry must carry no_bump.
        let extras = r#"
        replacements = [
          {
            noBump        = true;
            origProjectID = 1;
            origFileID    = 10;
            projectID     = 1;
            fileID        = 11;
            required      = true;
            filename      = "pinned-new.jar";
          }
          {
            origProjectID = 2;
            origFileID    = 20;
            projectID     = 2;
            fileID        = 21;
            required      = true;
            filename      = "free-new.jar";
          }
        ];
        "#;
        let s = load_pack_state_from_strings(mods, extras, "");
        assert!(s.get("pinned-new.jar").unwrap().no_bump, "pin must set no_bump");
        assert!(!s.get("free-new.jar").unwrap().no_bump, "unflagged stays bumpable");
    }

    #[test]
    fn extras_skipped_removes_entries() {
        let mods = r#"
          { projectID = 1; fileID = 10; required = true; filename = "a.jar"; }
          { projectID = 2; fileID = 20; required = true; filename = "b.jar"; }
        "#;
        // Wildcard skip (fileID = null) drops ALL files for that project.
        let extras = r#"
        skipped = [
          { projectID = 1; fileID = null; }
        ];
        "#;
        let s = load_pack_state_from_strings(mods, extras, "");
        assert!(!s.contains_key("a.jar"));
        assert!(s.contains_key("b.jar"));
    }

    #[test]
    fn extras_disabled_removes_specific_file() {
        let mods = r#"{ projectID = 5; fileID = 50; required = true; filename = "c.jar"; }"#;
        let extras = r#"
        disabled = [
          { projectID = 5; fileID = 50; reason = "boot-fail"; }
        ];
        "#;
        let s = load_pack_state_from_strings(mods, extras, "");
        assert!(!s.contains_key("c.jar"));
    }

    #[test]
    fn overlay_modrinth_entry() {
        let overlays = r#"
          {
            filename       = "iris-1.8.0.jar";
            dropAsOverride = true;
            jar = modrinth "YL57xq9U" "ABCD1234"
              "iris-1.8.0.jar"
              "sha256-...";
          }
        "#;
        let s = load_pack_state_from_strings("", "", overlays);
        let iris = s.get("iris-1.8.0.jar").expect("iris present");
        assert_eq!(
            iris.source,
            Source::Modrinth {
                project_id: "YL57xq9U".to_string(),
                version_id: "ABCD1234".to_string()
            }
        );
        assert_eq!(iris.dest_file, DestFile::Overlays);
    }

    #[test]
    fn overlay_curseforge_entry() {
        let overlays = r#"
          {
            filename       = "create-6.0.10.jar";
            dropAsOverride = false;
            projectID      = 328085;
            fileID         = 9999999;
            jar = curseforge 9999999 "create-6.0.10.jar"
              "sha256-...";
          }
        "#;
        let s = load_pack_state_from_strings("", "", overlays);
        let c = s.get("create-6.0.10.jar").unwrap();
        assert_eq!(
            c.source,
            Source::Curseforge {
                project_id: 328085,
                file_id: 9999999
            }
        );
        assert_eq!(c.dest_file, DestFile::Overlays);
    }
}

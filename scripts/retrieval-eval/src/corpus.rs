use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use thiserror::Error;
use walkdir::WalkDir;

pub const INTRO: &str = "(intro)";
const MEMORY_INDEX: &str = "MEMORY.md";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Chunk {
    pub id: String,
    pub title: String,
    pub text: String,
}

impl Chunk {
    /// Text fed to every retriever, so each one sees the same document.
    pub fn document(&self) -> String {
        format!("{}\n\n{}", self.title, self.text)
    }
}

#[derive(Debug, Error)]
pub enum CorpusError {
    #[error("read {path}: {source}")]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("walk {path}: {source}")]
    Walk {
        path: PathBuf,
        source: walkdir::Error,
    },
    #[error("skill dir not found: {0}")]
    SkillDirMissing(PathBuf),
}

pub fn strip_frontmatter(md: &str) -> (HashMap<String, String>, &str) {
    let Some(rest) = md.strip_prefix("---\n") else {
        return (HashMap::new(), md);
    };
    let Some(end) = rest.find("\n---\n") else {
        return (HashMap::new(), md);
    };
    let (header, tail) = rest.split_at(end);
    let body = tail.strip_prefix("\n---\n").unwrap_or(tail);
    let meta = header
        .lines()
        .filter(|line| !line.starts_with(char::is_whitespace))
        .filter_map(|line| line.split_once(':'))
        .map(|(key, value)| (key.trim().to_owned(), value.trim().to_owned()))
        .collect();
    (meta, body)
}

/// Split on `## ` headings outside code fences; `###` stays in its parent.
pub fn split_sections(md: &str) -> Vec<(String, String)> {
    let mut sections: Vec<(String, Vec<&str>)> = vec![(INTRO.to_owned(), Vec::new())];
    let mut in_fence = false;
    for line in md.lines() {
        if line.starts_with("```") {
            in_fence = !in_fence;
        }
        match line.strip_prefix("## ") {
            Some(heading) if !in_fence => sections.push((heading.trim().to_owned(), Vec::new())),
            _ => {
                if let Some((_, lines)) = sections.last_mut() {
                    lines.push(line);
                }
            }
        }
    }
    sections
        .into_iter()
        .map(|(heading, lines)| (heading, lines.join("\n").trim().to_owned()))
        .filter(|(_, body)| !body.is_empty())
        .collect()
}

fn read(path: &Path) -> Result<String, CorpusError> {
    fs::read_to_string(path).map_err(|source| CorpusError::Read {
        path: path.to_owned(),
        source,
    })
}

fn markdown_files(dir: &Path, max_depth: usize) -> Result<Vec<PathBuf>, CorpusError> {
    let mut files = Vec::new();
    for entry in WalkDir::new(dir).max_depth(max_depth).sort_by_file_name() {
        let entry = entry.map_err(|source| CorpusError::Walk {
            path: dir.to_owned(),
            source,
        })?;
        let is_md = entry.path().extension().is_some_and(|ext| ext == "md");
        if entry.file_type().is_file() && is_md {
            files.push(entry.into_path());
        }
    }
    Ok(files)
}

/// One chunk per memory file; the file name is the chunk id.
pub fn load_memories(memory_dir: &Path) -> Result<Vec<Chunk>, CorpusError> {
    let mut chunks = Vec::new();
    for path in markdown_files(memory_dir, 1)? {
        let Some(file_name) = path.file_name().map(|n| n.to_string_lossy().into_owned()) else {
            continue;
        };
        if file_name == MEMORY_INDEX {
            continue;
        }
        let raw = read(&path)?;
        let (meta, body) = strip_frontmatter(&raw);
        let stem = file_name.trim_end_matches(".md").to_owned();
        let title = meta.get("name").cloned().unwrap_or(stem);
        let description = meta.get("description").map_or("", String::as_str);
        let text = [description, body.trim()]
            .iter()
            .filter(|part| !part.is_empty())
            .copied()
            .collect::<Vec<_>>()
            .join("\n");
        chunks.push(Chunk {
            id: file_name,
            title,
            text,
        });
    }
    Ok(chunks)
}

/// One chunk per `##` section of every markdown file under each skill dir;
/// the id is `<skill>/<relative path>#<heading>`.
pub fn load_skill_sections(
    skills_root: &Path,
    skills: &[String],
) -> Result<Vec<Chunk>, CorpusError> {
    let mut chunks = Vec::new();
    for skill in skills {
        let skill_dir = skills_root.join(skill);
        if !skill_dir.is_dir() {
            return Err(CorpusError::SkillDirMissing(skill_dir));
        }
        for path in markdown_files(&skill_dir, usize::MAX)? {
            let rel = path
                .strip_prefix(skills_root)
                .unwrap_or(&path)
                .to_string_lossy()
                .into_owned();
            let raw = read(&path)?;
            let (_, body) = strip_frontmatter(&raw);
            for (heading, text) in split_sections(body) {
                chunks.push(Chunk {
                    id: format!("{rel}#{heading}"),
                    title: format!("{rel} - {heading}"),
                    text,
                });
            }
        }
    }
    Ok(chunks)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    #[test]
    fn frontmatter_is_split_off_and_top_level_keys_kept() {
        let md = "---\nname: foo\ndescription: bar baz\nmetadata:\n  type: x\n---\nbody\n";
        let (meta, body) = strip_frontmatter(md);
        assert_eq!(meta.get("name").map(String::as_str), Some("foo"));
        assert_eq!(meta.get("description").map(String::as_str), Some("bar baz"));
        assert!(!meta.contains_key("type"));
        assert_eq!(body, "body\n");
    }

    #[test]
    fn missing_frontmatter_returns_input_untouched() {
        let (meta, body) = strip_frontmatter("# just a heading\n");
        assert!(meta.is_empty());
        assert_eq!(body, "# just a heading\n");
    }

    #[test]
    fn unterminated_frontmatter_is_not_swallowed() {
        let md = "---\nname: foo\nno closing fence\n";
        let (meta, body) = strip_frontmatter(md);
        assert!(meta.is_empty());
        assert_eq!(body, md);
    }

    #[test]
    fn sections_split_on_h2_and_keep_h3_in_parent() {
        let md = "# Title\nintro text\n## One\nbody one\n### Sub\nsub body\n## Two\nbody two\n";
        let sections = split_sections(md);
        let headings: Vec<&str> = sections.iter().map(|(h, _)| h.as_str()).collect();
        assert_eq!(headings, [INTRO, "One", "Two"]);
        assert!(sections[1].1.contains("sub body"));
    }

    #[test]
    fn h2_inside_code_fence_is_not_a_heading() {
        let md = "## Real\n```sh\n## not a heading\n```\nafter\n";
        let sections = split_sections(md);
        assert_eq!(sections.len(), 1);
        assert!(sections[0].1.contains("## not a heading"));
    }

    #[test]
    fn empty_sections_are_dropped() {
        let sections = split_sections("## Empty\n## Full\ntext\n");
        let headings: Vec<&str> = sections.iter().map(|(h, _)| h.as_str()).collect();
        assert_eq!(headings, ["Full"]);
    }

    #[test]
    fn memories_skip_index_and_use_file_name_as_id() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("MEMORY.md"), "- [a](a.md)\n").unwrap();
        fs::write(
            dir.path().join("a.md"),
            "---\nname: alpha\ndescription: first one\n---\nbody text\n",
        )
        .unwrap();
        fs::write(dir.path().join("notes.txt"), "ignored").unwrap();
        let chunks = load_memories(dir.path()).unwrap();
        assert_eq!(
            chunks,
            [Chunk {
                id: "a.md".to_owned(),
                title: "alpha".to_owned(),
                text: "first one\nbody text".to_owned(),
            }]
        );
    }

    #[test]
    fn skill_sections_get_skill_relative_ids_across_subdirs() {
        let root = tempfile::tempdir().unwrap();
        let skill = root.path().join("prog");
        fs::create_dir_all(skill.join("languages")).unwrap();
        fs::write(
            skill.join("SKILL.md"),
            "---\nname: prog\n---\n# Prog\n## Rules\nbe good\n",
        )
        .unwrap();
        fs::write(skill.join("languages/rust.md"), "## Toolchain\nuse cargo\n").unwrap();
        let chunks = load_skill_sections(root.path(), &["prog".to_owned()]).unwrap();
        let ids: Vec<&str> = chunks.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(
            ids,
            [
                "prog/SKILL.md#(intro)",
                "prog/SKILL.md#Rules",
                "prog/languages/rust.md#Toolchain"
            ]
        );
    }

    #[test]
    fn missing_skill_dir_is_an_error_naming_the_path() {
        let root = tempfile::tempdir().unwrap();
        let err = load_skill_sections(root.path(), &["nope".to_owned()]).unwrap_err();
        assert!(err.to_string().contains("nope"));
    }
}

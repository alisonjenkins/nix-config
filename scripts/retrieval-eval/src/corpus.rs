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

/// One frontmatter field, including YAML block scalars (`>`, `|`) whose value
/// sits on the indented lines below the key.
pub fn frontmatter_field(md: &str, key: &str) -> Option<String> {
    let rest = md.strip_prefix("---\n")?;
    let header = rest.get(..rest.find("\n---\n")?)?;
    let mut lines = header.lines();
    while let Some(line) = lines.next() {
        let Some(value) = line.strip_prefix(key).and_then(|r| r.strip_prefix(':')) else {
            continue;
        };
        let value = value.trim();
        let text = if matches!(value, "" | ">" | "|" | ">-" | "|-" | ">+" | "|+") {
            lines
                .by_ref()
                .take_while(|l| l.starts_with(char::is_whitespace))
                .map(str::trim)
                .collect::<Vec<_>>()
                .join(" ")
        } else {
            value.to_owned()
        };
        let text = text.trim().trim_matches(['"', '\'']).to_owned();
        return if text.is_empty() { None } else { Some(text) };
    }
    None
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
/// A directory that does not exist yet holds no memories: a fresh setup has none.
pub fn load_memories(memory_dir: &Path) -> Result<Vec<Chunk>, CorpusError> {
    if !memory_dir.exists() {
        return Ok(Vec::new());
    }
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

/// What of a memory is embedded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryView {
    /// Description and body in one chunk, id `file.md`.
    Full,
    /// The frontmatter description alone, id `file.md`.
    Description,
    /// The description as chunk `file.md#d`, then the body in pieces of about
    /// this many characters as `file.md#1`, `file.md#2`, ... Rank files by their
    /// best chunk.
    Chunks(usize),
}

/// Memory file name for a chunk id (`file.md#2` -> `file.md`).
pub fn memory_file_of(chunk_id: &str) -> &str {
    chunk_id.split('#').next().unwrap_or(chunk_id)
}

/// Splits `body` on blank lines into pieces of at most about `max_chars`,
/// cutting an over-long paragraph at line breaks, then anywhere.
pub fn split_body_chunks(body: &str, max_chars: usize) -> Vec<String> {
    let mut pieces = Vec::new();
    let mut current = String::new();
    for paragraph in body.split("\n\n").map(str::trim).filter(|p| !p.is_empty()) {
        for part in cut_paragraph(paragraph, max_chars) {
            let joined = if current.is_empty() {
                part.chars().count()
            } else {
                current
                    .chars()
                    .count()
                    .saturating_add(2)
                    .saturating_add(part.chars().count())
            };
            if joined > max_chars && !current.is_empty() {
                pieces.push(std::mem::take(&mut current));
            }
            if !current.is_empty() {
                current.push_str("\n\n");
            }
            current.push_str(&part);
        }
    }
    if !current.is_empty() {
        pieces.push(current);
    }
    pieces
}

/// A paragraph of at most `max_chars`, else words packed up to that size; a
/// single word longer than the limit is cut by characters.
fn cut_paragraph(paragraph: &str, max_chars: usize) -> Vec<String> {
    if paragraph.chars().count() <= max_chars {
        return vec![paragraph.to_owned()];
    }
    let mut parts = Vec::new();
    let mut current = String::new();
    for word in paragraph.split_whitespace() {
        let mut word = word.to_owned();
        while word.chars().count() > max_chars {
            if !current.is_empty() {
                parts.push(std::mem::take(&mut current));
            }
            let head: String = word.chars().take(max_chars).collect();
            word = word.chars().skip(max_chars).collect();
            parts.push(head);
        }
        let joined = current
            .chars()
            .count()
            .saturating_add(usize::from(!current.is_empty()))
            .saturating_add(word.chars().count());
        if joined > max_chars && !current.is_empty() {
            parts.push(std::mem::take(&mut current));
        }
        if !current.is_empty() {
            current.push(' ');
        }
        current.push_str(&word);
    }
    if !current.is_empty() {
        parts.push(current);
    }
    parts
}

pub fn load_memories_view(memory_dir: &Path, view: MemoryView) -> Result<Vec<Chunk>, CorpusError> {
    if view == MemoryView::Full {
        return load_memories(memory_dir);
    }
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
        let title = meta
            .get("name")
            .cloned()
            .unwrap_or_else(|| file_name.trim_end_matches(".md").to_owned());
        let description = meta.get("description").cloned().unwrap_or_default();
        match view {
            MemoryView::Full => {}
            MemoryView::Description => chunks.push(Chunk {
                id: file_name,
                title,
                text: description,
            }),
            MemoryView::Chunks(max_chars) => {
                chunks.push(Chunk {
                    id: format!("{file_name}#d"),
                    title: title.clone(),
                    text: description,
                });
                for (n, piece) in split_body_chunks(body, max_chars).into_iter().enumerate() {
                    chunks.push(Chunk {
                        id: format!("{file_name}#{}", n.saturating_add(1)),
                        title: title.clone(),
                        text: piece,
                    });
                }
            }
        }
    }
    Ok(chunks)
}

/// Names of the folders under `skills_root` that hold a `SKILL.md`, sorted.
pub fn skill_names(skills_root: &Path) -> Result<Vec<String>, CorpusError> {
    // No skills directory yet is a fresh setup with no skills, not an error.
    if !skills_root.exists() {
        return Ok(Vec::new());
    }
    let entries = fs::read_dir(skills_root).map_err(|source| CorpusError::Read {
        path: skills_root.to_owned(),
        source,
    })?;
    let mut names: Vec<String> = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.path().join("SKILL.md").is_file())
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    names.sort();
    Ok(names)
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
    fn field_reads_a_single_line_value_and_strips_quotes() {
        let md = "---\nname: debugging\ndescription: \"Use when broken\"\n---\nbody";
        assert_eq!(frontmatter_field(md, "name").as_deref(), Some("debugging"));
        assert_eq!(
            frontmatter_field(md, "description").as_deref(),
            Some("Use when broken")
        );
    }

    #[test]
    fn field_joins_a_folded_block_scalar() {
        let md = "---\nname: x\ndescription: >\n  First line\n  second line.\nlicense: MIT\n---\n";
        assert_eq!(
            frontmatter_field(md, "description").as_deref(),
            Some("First line second line.")
        );
    }

    #[test]
    fn field_is_none_when_absent_or_without_frontmatter() {
        assert_eq!(
            frontmatter_field("---\nname: x\n---\n", "description"),
            None
        );
        assert_eq!(frontmatter_field("# no frontmatter", "name"), None);
    }

    #[test]
    fn field_matches_the_whole_key_not_a_prefix() {
        let md = "---\nnamespace: wrong\nname: right\n---\n";
        assert_eq!(frontmatter_field(md, "name").as_deref(), Some("right"));
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

    fn memory_dir_with_one_note() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("a.md"),
            "---\nname: alpha\ndescription: short summary\n---\nfirst paragraph\n\nsecond paragraph\n",
        )
        .unwrap();
        dir
    }

    #[test]
    fn memory_file_of_strips_the_chunk_suffix() {
        assert_eq!(memory_file_of("a.md#2"), "a.md");
        assert_eq!(memory_file_of("a.md#d"), "a.md");
        assert_eq!(memory_file_of("a.md"), "a.md");
    }

    #[test]
    fn full_view_equals_the_default_loader() {
        let dir = memory_dir_with_one_note();
        assert_eq!(
            load_memories_view(dir.path(), MemoryView::Full).unwrap(),
            load_memories(dir.path()).unwrap()
        );
    }

    #[test]
    fn description_view_holds_only_the_description() {
        let dir = memory_dir_with_one_note();
        let chunks = load_memories_view(dir.path(), MemoryView::Description).unwrap();
        assert_eq!(
            chunks,
            [Chunk {
                id: "a.md".to_owned(),
                title: "alpha".to_owned(),
                text: "short summary".to_owned(),
            }]
        );
    }

    #[test]
    fn chunks_view_has_a_description_chunk_then_body_pieces() {
        let dir = memory_dir_with_one_note();
        let chunks = load_memories_view(dir.path(), MemoryView::Chunks(20)).unwrap();
        let ids: Vec<&str> = chunks.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, ["a.md#d", "a.md#1", "a.md#2"]);
        assert_eq!(chunks[0].text, "short summary");
        assert_eq!(chunks[1].text, "first paragraph");
        assert_eq!(chunks[2].text, "second paragraph");
        assert!(chunks.iter().all(|c| c.title == "alpha"));
    }

    #[test]
    fn body_chunks_pack_paragraphs_up_to_the_limit() {
        let body = "aaa\n\nbbb\n\nccc\n\nddd";
        assert_eq!(split_body_chunks(body, 8), ["aaa\n\nbbb", "ccc\n\nddd"]);
        assert_eq!(split_body_chunks(body, 100), [body]);
    }

    #[test]
    fn an_overlong_paragraph_is_cut_without_losing_text() {
        let body = "one two three four five six seven eight nine ten";
        let pieces = split_body_chunks(body, 15);
        assert!(pieces.len() > 1);
        assert!(pieces.iter().all(|p| p.chars().count() <= 15));
        assert_eq!(pieces.join(" ").split_whitespace().count(), 10);
    }

    #[test]
    fn empty_body_yields_no_chunks() {
        assert!(split_body_chunks("  \n\n ", 100).is_empty());
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
    fn skill_names_lists_only_folders_with_a_skill_file_sorted() {
        let root = tempfile::tempdir().unwrap();
        for name in ["zeta", "alpha", "notes"] {
            fs::create_dir_all(root.path().join(name)).unwrap();
        }
        fs::write(root.path().join("zeta/SKILL.md"), "x").unwrap();
        fs::write(root.path().join("alpha/SKILL.md"), "x").unwrap();
        fs::write(root.path().join("stray.md"), "x").unwrap();
        assert_eq!(skill_names(root.path()).unwrap(), ["alpha", "zeta"]);
    }

    #[test]
    fn a_missing_skills_root_or_memory_directory_is_an_empty_corpus_not_an_error() {
        let root = tempfile::tempdir().unwrap();
        assert!(skill_names(&root.path().join("gone")).unwrap().is_empty());
        assert!(load_memories(&root.path().join("gone")).unwrap().is_empty());
        assert!(load_memories(root.path()).unwrap().is_empty());
    }

    #[test]
    fn a_file_where_the_directory_should_be_is_still_an_error() {
        let root = tempfile::tempdir().unwrap();
        let file = root.path().join("not-a-dir");
        fs::write(&file, "x").unwrap();
        assert!(skill_names(&file).is_err());
    }

    #[test]
    fn missing_skill_dir_is_an_error_naming_the_path() {
        let root = tempfile::tempdir().unwrap();
        let err = load_skill_sections(root.path(), &["nope".to_owned()]).unwrap_err();
        assert!(err.to_string().contains("nope"));
    }
}

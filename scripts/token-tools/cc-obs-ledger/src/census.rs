//! Estimates the tokens in the fixed parts of a session's context, from files on
//! disk, at session start. Characters divided by four is a rough estimate; it is
//! only used to split the measured fixed total into components.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

const CHARS_PER_TOKEN: u64 = 4;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Census {
    pub components: BTreeMap<String, u64>,
}

pub struct CensusInput<'a> {
    pub cwd: &'a Path,
    pub home: &'a Path,
    /// The session transcript; its directory is Claude Code's project directory for the session.
    pub transcript_path: Option<&'a Path>,
}

/// Claude Code's per-project directory name: the path with `/` and `.` as `-`.
pub fn project_dir_name(cwd: &Path) -> String {
    cwd.to_string_lossy()
        .chars()
        .map(|c| if c == '/' || c == '.' { '-' } else { c })
        .collect()
}

pub fn run(input: &CensusInput<'_>) -> Census {
    let mut components = BTreeMap::new();
    components.insert("instructions".to_owned(), tokens(instruction_chars(input)));
    components.insert("skills_listing".to_owned(), tokens(skill_chars(input.home)));
    components.insert("memory_index".to_owned(), tokens(memory_chars(input)));
    Census { components }
}

/// The first memory index that exists. A worktree session has its own project
/// directory with no memory in it; Claude Code reads the main checkout's.
fn memory_chars(input: &CensusInput<'_>) -> u64 {
    let projects = input.home.join(".claude/projects");
    let from_transcript = input
        .transcript_path
        .and_then(Path::parent)
        .map(|dir| dir.join("memory/MEMORY.md"));
    let from_cwd = projects
        .join(project_dir_name(input.cwd))
        .join("memory/MEMORY.md");
    let from_main_checkout = main_checkout(input.cwd).map(|main| {
        projects
            .join(project_dir_name(main))
            .join("memory/MEMORY.md")
    });
    from_transcript
        .into_iter()
        .chain([from_cwd])
        .chain(from_main_checkout)
        .find(|path| path.is_file())
        .map_or(0, |path| file_chars(&path))
}

/// The repository root a `<root>/.claude/worktrees/<name>` working directory belongs to.
fn main_checkout(cwd: &Path) -> Option<&Path> {
    let marker = Path::new(".claude/worktrees");
    cwd.ancestors().find_map(|dir| {
        let parent = dir.parent()?;
        parent
            .ends_with(marker)
            .then(|| parent.parent()?.parent())?
    })
}

fn tokens(chars: u64) -> u64 {
    chars.checked_div(CHARS_PER_TOKEN).unwrap_or(0)
}

fn file_chars(path: &Path) -> u64 {
    fs::read_to_string(path).map_or(0, |text| text.chars().count() as u64)
}

/// The user-level file, plus a `CLAUDE.md` in the working directory and each parent
/// up to the home directory.
fn instruction_chars(input: &CensusInput<'_>) -> u64 {
    let mut files: Vec<PathBuf> = vec![input.home.join(".claude/CLAUDE.md")];
    let mut dir = Some(input.cwd);
    while let Some(current) = dir {
        files.push(current.join("CLAUDE.md"));
        if current == input.home {
            break;
        }
        dir = current.parent();
    }
    files.sort();
    files.dedup();
    files
        .iter()
        .map(|path| file_chars(path))
        .fold(0u64, u64::saturating_add)
}

/// Name plus description of every skill: what the always-loaded listing holds.
fn skill_chars(home: &Path) -> u64 {
    let Ok(entries) = fs::read_dir(home.join(".claude/skills")) else {
        return 0;
    };
    entries
        .filter_map(Result::ok)
        .filter_map(|entry| fs::read_to_string(entry.path().join("SKILL.md")).ok())
        .map(|text| listing_chars(&text))
        .fold(0u64, u64::saturating_add)
}

fn listing_chars(skill: &str) -> u64 {
    let Some(frontmatter) = skill
        .strip_prefix("---\n")
        .and_then(|rest| rest.split("\n---").next())
    else {
        return 0;
    };
    let mut total = 0u64;
    let mut in_description = false;
    for line in frontmatter.lines() {
        let top_level_key = line
            .split_once(':')
            .filter(|(key, _)| !key.is_empty() && !key.starts_with(char::is_whitespace));
        if let Some((key, value)) = top_level_key {
            in_description = key == "description";
            if key == "name" || key == "description" {
                total = total.saturating_add(scalar_chars(value));
            }
        } else if in_description {
            total = total.saturating_add(line.trim().chars().count() as u64);
        }
    }
    total
}

/// The value after `key:`; a folded or literal block marker counts as nothing.
fn scalar_chars(value: &str) -> u64 {
    let value = value.trim().trim_matches(['"', '\'']);
    if matches!(value, ">" | "|" | ">-" | "|-") {
        return 0;
    }
    value.chars().count() as u64
}

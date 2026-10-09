//! Reports what the skill listing costs and how long descriptions can be as
//! skills are added. Exits 1 when the listing is over the cap.
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::Result;
use clap::Parser;
use retrieval_eval::skill_listing::{audit, load_entries, render};

/// 1% of a 200k-token context window, the share Claude Code gives the listing.
const DEFAULT_CAP_TOKENS: usize = 2000;
const DEFAULT_TARGET_SKILLS: usize = 100;
const DEFAULT_SHOW: usize = 10;

#[derive(Parser)]
#[command(about = "Audit the skill listing against its token cap")]
struct Cli {
    /// Directory holding one folder per skill, e.g. ~/.claude/skills.
    #[arg(long)]
    skills_root: PathBuf,
    /// Tokens the listing may use.
    #[arg(long, default_value_t = DEFAULT_CAP_TOKENS)]
    cap_tokens: usize,
    /// Skill count to size descriptions for.
    #[arg(long, default_value_t = DEFAULT_TARGET_SKILLS)]
    target_skills: usize,
    /// Heaviest skills to list.
    #[arg(long, default_value_t = DEFAULT_SHOW)]
    show: usize,
    /// Skills set to "name-only" in `skillOverrides`: listed without a description.
    #[arg(long, value_delimiter = ',')]
    name_only: Vec<String>,
}

fn run() -> Result<bool> {
    let cli = Cli::parse();
    let mut entries = load_entries(&cli.skills_root)?;
    for entry in &mut entries {
        if cli.name_only.contains(&entry.name) {
            entry.description.clear();
        }
    }
    let report = audit(&entries, cli.cap_tokens, cli.target_skills);
    print!("{}", render(&report, cli.show));
    Ok(!report.over_cap())
}

fn main() -> ExitCode {
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::from(2)
        }
    }
}

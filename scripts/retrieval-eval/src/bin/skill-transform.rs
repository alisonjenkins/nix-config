//! Writes a copy of a skills directory whose `SKILL.md` files carry a short
//! listing description, with the full description moved into the body.
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result};
use clap::Parser;
use retrieval_eval::skill_transform::transform_tree;

/// Room for a verb, the routing words and a negative case; the full text is
/// retrieved on demand.
const DEFAULT_SHORT_CHARS: usize = 160;

#[derive(Parser)]
#[command(about = "Shorten skill listing descriptions, keeping the full text in the body")]
struct Cli {
    /// Directory holding one folder per skill.
    #[arg(long)]
    input: PathBuf,
    /// Directory to write; created if missing.
    #[arg(long)]
    output: PathBuf,
    /// Longest listing description, in characters.
    #[arg(long, default_value_t = DEFAULT_SHORT_CHARS)]
    short_chars: usize,
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    fs::create_dir_all(&cli.output).with_context(|| format!("create {}", cli.output.display()))?;
    let outcomes = transform_tree(&cli.input, &cli.output, cli.short_chars)
        .with_context(|| format!("transform {}", cli.input.display()))?;
    let changed = outcomes.iter().filter(|o| o.skipped.is_none()).count();
    eprintln!(
        "{changed} of {} skills shortened to {} characters",
        outcomes.len(),
        cli.short_chars
    );
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}

//! Argument parsing, dispatch and the error/exit contract.
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use serde_json::json;

use crate::backend::Backend;
use crate::bounds::{
    render, Bounds, Format, Report, DEFAULT_LIMIT, DEFAULT_MAX_BYTES, DIGEST_MAX_BYTES,
};
use crate::commands::digest::{self, Opts};
use crate::commands::top::{By, Category};
use crate::commands::{compare, run_query, unused, Ctx};
use crate::error::Error;
use crate::pack::Pack;
use crate::window::{parse_range, parse_since, parse_until, Window, DEFAULT_SINCE};

pub const DEFAULT_PACK: &str = "docs/token-efficiency/questions.yaml";

#[derive(Debug, Parser)]
#[command(
    name = "cc-obs-query",
    version,
    about = "Bounded, read-only queries over the local observability stack"
)]
pub struct Cli {
    /// concise (default), detailed (adds per-row detail) or table
    #[arg(long, global = true, value_enum, default_value_t = Format::Concise)]
    pub format: Format,
    /// Most rows to print
    #[arg(long, global = true, default_value_t = DEFAULT_LIMIT)]
    pub limit: usize,
    /// Hard cap on output bytes (32768 for digest commands)
    #[arg(long, global = true)]
    pub max_bytes: Option<usize>,
    /// Rows to skip; the `next` marker of a truncated answer names it
    #[arg(long, global = true, default_value_t = 0)]
    pub offset: usize,
    /// Include the unattended review's own runs (review.run=1), excluded by default
    #[arg(long, global = true)]
    pub include_review: bool,
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Rank token consumers
    Top {
        #[arg(value_enum)]
        category: Category,
        #[arg(long, value_enum, default_value_t = By::Tokens)]
        by: By,
        #[arg(long, default_value = DEFAULT_SINCE)]
        since: String,
    },
    /// Calls, result size, share of tokens and repeat rate of one tool
    Tool {
        name: String,
        #[arg(long, default_value = DEFAULT_SINCE)]
        since: String,
    },
    /// Context per turn, cache hit ratio, fixed versus new tokens of one session
    Session {
        id: String,
        /// Add one row per turn
        #[arg(long)]
        detail: bool,
        #[arg(long, default_value = "30d")]
        since: String,
    },
    /// Repeated or near-identical tool calls and frequent call sequences
    Repeats {
        #[arg(long, default_value = DEFAULT_SINCE)]
        since: String,
        #[arg(long, default_value_t = 2)]
        min_count: u64,
    },
    /// Injected tokens per prompt, matches used, failures
    Recall {
        #[arg(long, default_value = DEFAULT_SINCE)]
        since: String,
    },
    /// Store reachability and disk guard state
    Health,
    /// One question's figure over two date ranges
    Compare {
        question_id: String,
        #[arg(long)]
        a: String,
        #[arg(long)]
        b: String,
        #[arg(long, default_value = DEFAULT_PACK)]
        pack: PathBuf,
    },
    /// Collected signals no question references
    UnusedSignals {
        #[arg(long, default_value = DEFAULT_PACK)]
        pack: PathBuf,
    },
    /// Build (--baseline) or validate (--write) a review digest
    Digest {
        /// Run the whole pack mechanically, no model
        #[arg(long, conflicts_with = "write")]
        baseline: bool,
        /// Validate a model-gathered digest file
        #[arg(long)]
        write: Option<PathBuf>,
        #[arg(long, default_value = DEFAULT_PACK)]
        pack: PathBuf,
        #[arg(long, default_value = DEFAULT_SINCE)]
        since: String,
        /// End of the period as a date (default: now)
        #[arg(long)]
        until: Option<String>,
        /// Save the digest here instead of printing it
        #[arg(long)]
        out: Option<PathBuf>,
        /// Directory of decision records (default: decisions/ beside the pack)
        #[arg(long)]
        decisions: Option<PathBuf>,
    },
}

impl Command {
    pub fn name(&self) -> &'static str {
        match self {
            Command::Top { .. } => "top",
            Command::Tool { .. } => "tool",
            Command::Session { .. } => "session",
            Command::Repeats { .. } => "repeats",
            Command::Recall { .. } => "recall",
            Command::Health => "health",
            Command::Compare { .. } => "compare",
            Command::UnusedSignals { .. } => "unused-signals",
            Command::Digest { .. } => "digest",
        }
    }

    fn since(&self) -> &str {
        match self {
            Command::Top { since, .. }
            | Command::Tool { since, .. }
            | Command::Session { since, .. }
            | Command::Repeats { since, .. }
            | Command::Recall { since }
            | Command::Digest { since, .. } => since,
            Command::Health | Command::Compare { .. } | Command::UnusedSignals { .. } => {
                DEFAULT_SINCE
            }
        }
    }
}

struct Output {
    text: String,
    failed: bool,
}

fn from_report(report: &Report, bounds: &Bounds) -> Result<Output, Error> {
    Ok(Output {
        text: render(report, bounds)?,
        failed: report.failed,
    })
}

fn to_text(value: &serde_json::Value) -> Result<String, Error> {
    serde_json::to_string(value).map_err(|source| Error::Render { source })
}

fn digest_output(cli: &Cli, backend: &Backend) -> Result<Output, Error> {
    let Command::Digest {
        baseline,
        write,
        pack,
        since,
        until,
        out,
        decisions,
    } = &cli.command
    else {
        return Err(Error::Usage {
            message: "not a digest command".to_owned(),
            input: cli.command.name().to_owned(),
        });
    };
    let end = until.as_deref().map(parse_until).transpose()?;
    let opts = Opts {
        pack: pack.clone(),
        decisions: decisions.clone(),
        window: parse_since(since)?.ending(end),
        include_review: cli.include_review,
        max_bytes: cli.max_bytes.unwrap_or(DIGEST_MAX_BYTES),
    };
    let (digest, checked) = match (baseline, write) {
        (true, None) => (digest::baseline(backend, &opts)?, None),
        (false, Some(file)) => {
            let validated = digest::validate(backend, file, &opts)?;
            (validated.digest, Some(validated.evidence_checked))
        }
        _ => {
            return Err(Error::Usage {
                message: "digest needs exactly one of --baseline or --write <file>".to_owned(),
                input: "digest".to_owned(),
            })
        }
    };
    let text = to_text(&digest)?;
    let Some(path) = out else {
        let text = match checked {
            None => text,
            Some(n) => {
                to_text(&json!({"valid": true, "bytes": text.len(), "evidence_checked": n}))?
            }
        };
        return Ok(Output {
            text,
            failed: false,
        });
    };
    std::fs::write(path, &text).map_err(|source| Error::DigestWrite {
        path: path.clone(),
        source,
    })?;
    let summary = json!({
        "valid": true,
        "bytes": text.len(),
        "evidence_checked": checked,
        "written": path.display().to_string(),
    });
    Ok(Output {
        text: to_text(&summary)?,
        failed: false,
    })
}

fn execute(cli: &Cli) -> Result<Output, Error> {
    let bounds = Bounds {
        format: cli.format,
        limit: cli.limit,
        max_bytes: cli.max_bytes.unwrap_or(DEFAULT_MAX_BYTES),
        offset: cli.offset,
    };
    match &cli.command {
        Command::UnusedSignals { pack } => from_report(&unused::run(&Pack::load(pack)?), &bounds),
        Command::Digest { .. } => digest_output(cli, &Backend::from_env()?),
        Command::Compare {
            question_id,
            a,
            b,
            pack,
        } => {
            let pack = Pack::load(pack)?;
            let report = compare::run(
                &Backend::from_env()?,
                cli.include_review,
                &pack,
                question_id,
                parse_range("--a", a)?,
                parse_range("--b", b)?,
            )?;
            from_report(&report, &bounds)
        }
        query => {
            let window: Window = parse_since(query.since())?;
            let backend = Backend::from_env()?;
            let ctx = Ctx::new(&backend, window, cli.include_review);
            from_report(&run_query(&ctx, query)?, &bounds)
        }
    }
}

fn args_text(args: &[OsString]) -> String {
    args.iter()
        .skip(1)
        .map(|a| a.to_string_lossy())
        .collect::<Vec<_>>()
        .join(" ")
}

fn fail(error: &Error, code: u8) -> ExitCode {
    let line = serde_json::to_string(&error.report())
        .unwrap_or_else(|_| r#"{"error":"could not serialise the error"}"#.to_owned());
    eprintln!("{line}");
    ExitCode::from(code)
}

pub fn run<I, T>(args: I) -> ExitCode
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let args: Vec<OsString> = args.into_iter().map(Into::into).collect();
    let cli = match Cli::try_parse_from(&args) {
        Ok(cli) => cli,
        Err(e) if !e.use_stderr() => {
            print!("{e}");
            return ExitCode::SUCCESS;
        }
        Err(e) => {
            return fail(
                &Error::Usage {
                    message: e.to_string().trim().to_owned(),
                    input: args_text(&args),
                },
                2,
            )
        }
    };
    match execute(&cli) {
        Ok(output) => {
            println!("{}", output.text);
            if output.failed {
                ExitCode::from(1)
            } else {
                ExitCode::SUCCESS
            }
        }
        Err(e) => fail(&e, 1),
    }
}

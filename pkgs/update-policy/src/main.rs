use std::path::{Path, PathBuf};

use std::process::ExitCode;
use update_policy::check::{check, Severity};
use update_policy::date::Date;
use update_policy::{files, lock, sources::Sources, workflows};

const USAGE: &str = "usage: update-policy check [--repo DIR] [--sources FILE] [--today YYYY-MM-DD]

Checks that every flake input in DIR/flake.lock and every GitHub Action in
DIR/.github has a trust tier in the sources file (default
DIR/pins/sources.json), and that Actions outside the `own` tier are pinned to
a commit SHA. See docs/update-policy.md.

Exit status: 0 no errors (warnings allowed), 1 policy errors, 2 could not run.";

struct Args {
    repo: PathBuf,
    sources: Option<PathBuf>,
    today: Option<Date>,
}

fn parse_args(mut argv: impl Iterator<Item = String>) -> Result<Args, String> {
    match argv.next().as_deref() {
        Some("check") => {}
        Some("-h" | "--help") => return Err(String::new()),
        Some(other) => return Err(format!("unknown command `{other}`")),
        None => return Err("missing command".into()),
    }
    let mut args = Args { repo: PathBuf::from("."), sources: None, today: None };
    while let Some(flag) = argv.next() {
        let mut value = || argv.next().ok_or_else(|| format!("`{flag}` needs a value"));
        match flag.as_str() {
            "--repo" => args.repo = PathBuf::from(value()?),
            "--sources" => args.sources = Some(PathBuf::from(value()?)),
            "--today" => {
                let v = value()?;
                args.today = Some(Date::parse(&v).ok_or_else(|| format!("`--today {v}` is not a YYYY-MM-DD date"))?);
            }
            "-h" | "--help" => return Err(String::new()),
            other => return Err(format!("unknown option `{other}`")),
        }
    }
    Ok(args)
}

fn read(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))
}

fn run(args: Args) -> Result<bool, String> {
    let sources_path = args.sources.unwrap_or_else(|| args.repo.join("pins/sources.json"));
    let sources = Sources::parse(&read(&sources_path)?).map_err(|errs| {
        let lines: Vec<String> = errs.iter().map(|e| format!("  {}: {e}", sources_path.display())).collect();
        format!("the sources file has {} problem(s):\n{}", errs.len(), lines.join("\n"))
    })?;

    let lock_path = args.repo.join("flake.lock");
    let inputs = if lock_path.exists() {
        lock::inputs(&read(&lock_path)?).map_err(|errs| {
            errs.iter().map(|e| format!("{}: {e}", lock_path.display())).collect::<Vec<_>>().join("\n")
        })?
    } else {
        Vec::new()
    };

    let mut actions = Vec::new();
    for file in files::workflow_files(&args.repo)? {
        let rel = file.strip_prefix(&args.repo).unwrap_or(&file).display().to_string();
        actions.extend(workflows::scan(&rel, &read(&file)?));
    }

    let findings = check(&sources, &inputs, &actions, args.today.unwrap_or_else(Date::today));
    for f in &findings {
        println!("{f}");
    }
    let errors = findings.iter().filter(|f| f.severity == Severity::Error).count();
    println!(
        "update-policy: {} flake inputs, {} action references checked; {errors} error(s), {} warning(s)",
        inputs.iter().filter(|i| i.key.is_some()).count(),
        actions.len(),
        findings.len() - errors,
    );
    Ok(errors == 0)
}

fn main() -> ExitCode {
    let args = match parse_args(std::env::args().skip(1)) {
        Ok(a) => a,
        Err(msg) => {
            if !msg.is_empty() {
                eprintln!("update-policy: {msg}\n");
            }
            eprintln!("{USAGE}");
            return ExitCode::from(if msg.is_empty() { 0 } else { 2 });
        }
    };
    match run(args) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::from(1),
        Err(msg) => {
            eprintln!("update-policy: {msg}");
            ExitCode::from(2)
        }
    }
}

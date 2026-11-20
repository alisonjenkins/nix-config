use std::path::{Path, PathBuf};

use std::process::ExitCode;
use update_policy::bump::{self, Action, Group, SeenFile};
use update_policy::check::{check, Severity};
use update_policy::date::Date;
use update_policy::{files, lock, sources::Sources};

const USAGE: &str = "usage: update-policy check [--repo DIR] [--sources FILE] [--today YYYY-MM-DD]
       update-policy bump  [--repo DIR] [--sources FILE] [--seen FILE] [--today YYYY-MM-DD]
                           [--heads FILE] [--group auto|manual] [--summary FILE] [--apply]

check:
Checks that every flake input in DIR/flake.lock and every GitHub Action in
DIR/.github has a trust tier in the sources file (default
DIR/pins/sources.json), and that Actions outside the `own` tier are pinned to
a commit SHA. See docs/update-policy.md.

bump: moves each direct flake input to the newest upstream commit that has
been visible for its tier's cooldown (first-seen times are kept in
DIR/pins/flake-seen.json). --group picks the auto-merge tiers or the manual
ones; --apply records today's heads (auto group or no group only) and runs
`nix flake lock --override-input` for the chosen inputs; without it nothing
is written. --heads reads {\"input\": \"rev\"} instead of asking GitHub.

Exit status: 0 success (check: warnings allowed), 1 policy errors (check),
2 could not run.";

#[derive(PartialEq)]
enum Cmd {
    Check,
    Bump,
}

struct Args {
    cmd: Cmd,
    repo: PathBuf,
    sources: Option<PathBuf>,
    today: Option<Date>,
    seen: Option<PathBuf>,
    heads: Option<PathBuf>,
    group: Option<Group>,
    summary: Option<PathBuf>,
    apply: bool,
}

fn parse_args(mut argv: impl Iterator<Item = String>) -> Result<Args, String> {
    let cmd = match argv.next().as_deref() {
        Some("check") => Cmd::Check,
        Some("bump") => Cmd::Bump,
        Some("-h" | "--help") => return Err(String::new()),
        Some(other) => return Err(format!("unknown command `{other}`")),
        None => return Err("missing command".into()),
    };
    let mut args = Args {
        cmd,
        repo: PathBuf::from("."),
        sources: None,
        today: None,
        seen: None,
        heads: None,
        group: None,
        summary: None,
        apply: false,
    };
    while let Some(flag) = argv.next() {
        let mut value = || argv.next().ok_or_else(|| format!("`{flag}` needs a value"));
        match flag.as_str() {
            "--repo" => args.repo = PathBuf::from(value()?),
            "--sources" => args.sources = Some(PathBuf::from(value()?)),
            "--today" => {
                let v = value()?;
                args.today = Some(Date::parse(&v).ok_or_else(|| format!("`--today {v}` is not a YYYY-MM-DD date"))?);
            }
            "--seen" if args.cmd == Cmd::Bump => args.seen = Some(PathBuf::from(value()?)),
            "--heads" if args.cmd == Cmd::Bump => args.heads = Some(PathBuf::from(value()?)),
            "--summary" if args.cmd == Cmd::Bump => args.summary = Some(PathBuf::from(value()?)),
            "--apply" if args.cmd == Cmd::Bump => args.apply = true,
            "--group" if args.cmd == Cmd::Bump => {
                args.group = Some(match value()?.as_str() {
                    "auto" => Group::Auto,
                    "manual" => Group::Manual,
                    other => return Err(format!("`--group {other}` must be `auto` or `manual`")),
                })
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

fn run_check(args: Args) -> Result<bool, String> {
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

    let actions = files::collect_actions(&args.repo)?;

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

fn write(path: &Path, text: &str) -> Result<(), String> {
    std::fs::write(path, text).map_err(|e| format!("cannot write {}: {e}", path.display()))
}

fn run_bump(args: Args) -> Result<bool, String> {
    let sources_path = args.sources.unwrap_or_else(|| args.repo.join("pins/sources.json"));
    let sources = Sources::parse(&read(&sources_path)?).map_err(|errs| {
        format!("{} is not valid; run `update-policy check` ({} problem(s))", sources_path.display(), errs.len())
    })?;
    let seen_path = args.seen.unwrap_or_else(|| args.repo.join("pins/flake-seen.json"));
    let mut seen = if seen_path.exists() {
        SeenFile::parse(&read(&seen_path)?).map_err(|e| format!("{}: {e}", seen_path.display()))?
    } else {
        SeenFile::default()
    };
    let lock_path = args.repo.join("flake.lock");
    let (inputs, skipped) = bump::direct_inputs(&read(&lock_path)?).map_err(|e| format!("{}: {e}", lock_path.display()))?;
    let heads = match &args.heads {
        Some(p) => bump::parse_heads(&read(p)?).map_err(|e| format!("{}: {e}", p.display()))?,
        None => bump::fetch_heads(&inputs),
    };
    let today = args.today.unwrap_or_else(Date::today);
    let decisions = bump::plan(&inputs, &heads, &mut seen, &sources, today);

    for d in &decisions {
        let tier = d.tier.as_deref().unwrap_or("untiered");
        match &d.action {
            Action::Update { to, .. } => println!("{} [{tier}, {}]: {} -> {}", d.input.name, d.group, &d.input.locked_rev[..8.min(d.input.locked_rev.len())], &to[..8.min(to.len())]),
            Action::Waiting { next, ready_on } => println!("{} [{tier}, {}]: waiting, {} eligible on {ready_on}", d.input.name, d.group, &next[..8.min(next.len())]),
            Action::UpToDate => {}
            Action::Skip(why) => eprintln!("warning: {}: not bumped: {why}", d.input.name),
        }
    }
    for k in &skipped {
        eprintln!("note: {}: {}", k.name, k.reason);
    }

    let chosen: Vec<&bump::Decision> = decisions
        .iter()
        .filter(|d| args.group.is_none_or(|g| d.group == g))
        .filter(|d| matches!(d.action, Action::Update { .. }))
        .collect();
    if let Some(p) = &args.summary {
        write(p, &bump::summary(&decisions, &skipped, args.group, today))?;
    }
    println!(
        "update-policy bump: {} input(s) to update{}{}",
        chosen.len(),
        args.group.map(|g| format!(" in the {g} group")).unwrap_or_default(),
        if args.apply { "" } else { " (dry run: nothing written)" }
    );
    if !args.apply {
        return Ok(true);
    }
    // Only the auto group's PR records what was seen, so two PRs never both
    // change the seen file. If it does not merge, the next night re-records.
    if args.group != Some(Group::Manual) {
        write(&seen_path, &seen.to_json())?;
    }
    if chosen.is_empty() {
        return Ok(true);
    }
    let mut cmd = std::process::Command::new("nix");
    cmd.current_dir(&args.repo).args(["flake", "lock"]);
    for d in &chosen {
        if let Action::Update { to, .. } = &d.action {
            cmd.args(["--override-input", &d.input.name, &d.input.url_at(to)]);
        }
    }
    let status = cmd.status().map_err(|e| format!("could not run nix: {e}"))?;
    if !status.success() {
        return Err(format!("`nix flake lock` failed ({status}); flake.lock is unchanged or partly updated, see the output above"));
    }
    Ok(true)
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
    let result = match args.cmd {
        Cmd::Check => run_check(args),
        Cmd::Bump => run_bump(args),
    };
    match result {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::from(1),
        Err(msg) => {
            eprintln!("update-policy: {msg}");
            ExitCode::from(2)
        }
    }
}

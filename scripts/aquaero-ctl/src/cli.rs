//! Command-line interface: argument parsing, output and the exit-code mapping
//! from `specs/008-aquaero-linux-config/contracts/cli.md`.

use std::error::Error;
use std::ffi::OsString;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{ArgAction, Parser, Subcommand};
use thiserror::Error;
use tracing_subscriber::EnvFilter;

use crate::apply::{restore_config, ApplyOptions, ApplyReport};
use crate::curve::FanCurve;
use crate::desired::{DesiredError, DesiredState, Mode};
use crate::diff::{diff, render_text, to_json, VolatileSet};
use crate::dump::{dump, DumpOptions};
use crate::error::{
    ApplyError, DumpError, HidError, LockError, ProfileError, RestoreError, SelectError,
    SnapshotError,
};
use crate::hid::{read_config, HidDevice, SystemClock};
use crate::hidraw::{HidrawDevice, UNKNOWN_SERIAL};
use crate::identity::data_version;
use crate::lock::{default_lock_path, DeviceLock, SpacedDevice};
use crate::plan::{build_plan, Change, Plan};
use crate::profile::Profile;
use crate::select::{choose, discover};
use crate::show;
use crate::snapshot::{ConfigBytes, ConfigSnapshot, SnapshotMeta};
use crate::timestamp::UtcTimestamp;
use crate::workflow::{apply_desired, plan_for_device, Outcome, ProfileInfo, WorkflowError};

const EXIT_ERROR: u8 = 1;
const EXIT_USAGE: u8 = 2;
const EXIT_NO_PROFILE: u8 = 3;
const EXIT_AMBIGUOUS: u8 = 4;
const EXIT_PERMISSION: u8 = 5;
const EXIT_WRITE_FAILED: u8 = 6;
const EXIT_LOCKED: u8 = 7;
const EXIT_DRIFT: u8 = 10;

/// Read and compare the stored configuration of an Aquacomputer aquaero.
#[derive(Debug, Parser)]
#[command(name = "aquaero-ctl", version)]
struct Cli {
    /// Machine-readable output.
    #[arg(long, global = true)]
    json: bool,

    /// More logging on stderr (-v, -vv).
    #[arg(short, long, action = ArgAction::Count, global = true)]
    verbose: u8,

    /// Which aquaero to use; required when more than one is connected.
    #[arg(long, global = true)]
    serial: Option<String>,

    /// Use this hidraw node instead of looking for one.
    #[arg(long, global = true)]
    hidraw: Option<PathBuf>,

    /// Lock file that keeps two copies from using the device at once
    /// (default: $XDG_RUNTIME_DIR/aquaero-ctl.lock, else /run/aquaero-ctl.lock).
    #[arg(long, global = true)]
    lock_file: Option<PathBuf>,

    // Where to look for hidraw nodes; tests point these at a fake tree.
    #[arg(long, global = true, hide = true, default_value = "/sys")]
    sysfs_root: PathBuf,
    #[arg(long, global = true, hide = true, default_value = "/dev")]
    dev_dir: PathBuf,

    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Save the device's stored configuration as a snapshot (read-only).
    Dump {
        /// Directory to write the snapshot into.
        #[arg(long)]
        out: PathBuf,
        /// Label added to the file name.
        #[arg(long, default_value = "snapshot")]
        label: String,
        /// Hide the serial number so the snapshot can be committed.
        #[arg(long)]
        redact_serial: bool,
    },
    /// Compare two snapshots.
    Diff {
        a: PathBuf,
        b: PathBuf,
        /// A second snapshot of the same untouched state as A: positions where
        /// they differ are marked volatile.
        #[arg(long)]
        baseline: Option<PathBuf>,
    },
    /// Show the settings this tool manages, from the device or a snapshot.
    Show {
        /// Decode this snapshot instead of reading the device.
        #[arg(long)]
        snapshot: Option<PathBuf>,
    },
    /// Show what applying a desired state would change (writes nothing).
    Plan {
        /// The desired-state JSON file.
        #[arg(long)]
        desired: PathBuf,
        /// Plan against this snapshot instead of reading the device.
        #[arg(long)]
        snapshot: Option<PathBuf>,
    },
    /// Make the device match a desired state: back up, write, save, read back.
    Apply {
        /// The desired-state JSON file.
        #[arg(long)]
        desired: PathBuf,
        /// Report drift and write nothing.
        #[arg(long)]
        check: bool,
        /// With --check, exit 10 when the device differs.
        #[arg(long)]
        fail_on_drift: bool,
        /// Where to save the backup (default: $STATE_DIRECTORY/backups, else
        /// $XDG_STATE_HOME/aquaero-ctl/backups, else
        /// ~/.local/state/aquaero-ctl/backups).
        #[arg(long)]
        backup_dir: Option<PathBuf>,
    },
    /// Write a snapshot back to the device.
    Restore {
        /// The snapshot's .bin file.
        snapshot: PathBuf,
        /// Do not ask first.
        #[arg(long)]
        yes: bool,
        /// Where to save the backup of the configuration this replaces.
        #[arg(long)]
        backup_dir: Option<PathBuf>,
    },
    /// List the automatic backups, newest first (no device access).
    ListBackups {
        /// Where the backups are kept (same default as for the writing commands).
        #[arg(long)]
        backup_dir: Option<PathBuf>,
    },
}

#[derive(Debug, Error)]
enum CliError {
    #[error("cannot read the desired state {}", path.display())]
    DesiredRead {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("the desired state {} is not usable", path.display())]
    Desired {
        path: PathBuf,
        #[source]
        source: DesiredError,
    },

    #[error("cannot show or restore this configuration")]
    Profile {
        #[source]
        source: ProfileError,
    },

    #[error("cannot carry out the request")]
    Workflow {
        #[source]
        source: WorkflowError,
    },

    #[error("cannot restore the snapshot")]
    Restore {
        #[source]
        source: RestoreError,
    },

    #[error("restoring replaces the device's configuration: pass --yes to confirm, since there is no terminal to ask on")]
    ConfirmationNeeded,

    #[error("restore declined; nothing was written")]
    Declined,

    #[error("cannot read the answer")]
    Prompt {
        #[source]
        source: io::Error,
    },

    #[error(
        "no backup directory: pass --backup-dir, or set STATE_DIRECTORY, XDG_STATE_HOME or HOME"
    )]
    NoBackupDir,

    #[error("cannot list the backups in {}", path.display())]
    ListBackups {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("cannot find the aquaero")]
    Select {
        #[source]
        source: SelectError,
    },

    #[error("cannot take the device lock")]
    Lock {
        #[source]
        source: LockError,
    },

    #[error("cannot read a snapshot")]
    Snapshot {
        #[source]
        source: SnapshotError,
    },

    #[error("cannot dump the configuration")]
    Dump {
        #[source]
        source: DumpError,
    },

    #[error("no hidraw node answered with the configuration report")]
    NoNodeAnswered { failures: Vec<HidError> },

    #[error("cannot write the output")]
    Output {
        #[source]
        source: io::Error,
    },
}

impl CliError {
    fn exit_code(&self) -> u8 {
        match self {
            CliError::Select {
                source: SelectError::Ambiguous { .. } | SelectError::SerialNotFound { .. },
            } => EXIT_AMBIGUOUS,
            CliError::Lock {
                source: LockError::Held { .. },
            } => EXIT_LOCKED,
            CliError::NoNodeAnswered { failures } if failures.iter().any(is_permission_denied) => {
                EXIT_PERMISSION
            }
            CliError::DesiredRead { .. }
            | CliError::Desired { .. }
            | CliError::ConfirmationNeeded => EXIT_USAGE,
            CliError::Profile { .. } => EXIT_NO_PROFILE,
            CliError::Workflow { source } => match source {
                WorkflowError::NoProfile { .. } => EXIT_NO_PROFILE,
                WorkflowError::Plan { .. } => EXIT_USAGE,
                WorkflowError::Apply { source } if write_failed(source) => EXIT_WRITE_FAILED,
                _ => EXIT_ERROR,
            },
            CliError::Restore { source } => match source {
                RestoreError::WrongDevice { .. } => EXIT_USAGE,
                RestoreError::FirmwareMismatch { .. } => EXIT_NO_PROFILE,
                RestoreError::Apply { source } if write_failed(source) => EXIT_WRITE_FAILED,
                _ => EXIT_ERROR,
            },
            _ => EXIT_ERROR,
        }
    }

    fn hint(&self) -> Option<&'static str> {
        match self {
            CliError::NoNodeAnswered { failures } if failures.iter().any(is_permission_denied) => {
                Some("the hidraw node needs read and write access: run as root, or add a udev rule for it")
            }
            CliError::Lock {
                source: LockError::Held { .. },
            } => Some("wait for the other aquaero-ctl to finish"),
            CliError::Lock {
                source: LockError::Create { .. },
            } => Some("use --lock-file to put the lock somewhere you can write"),
            _ => None,
        }
    }
}

/// The failures that follow a changed device, where the backup matters.
fn write_failed(error: &ApplyError) -> bool {
    matches!(
        error,
        ApplyError::Write { .. }
            | ApplyError::Commit { .. }
            | ApplyError::ReadBack { .. }
            | ApplyError::Mismatch { .. }
    )
}

fn is_permission_denied(error: &HidError) -> bool {
    matches!(error, HidError::Open { source, .. } if source.kind() == io::ErrorKind::PermissionDenied)
}

/// Parses the command line, runs the command, prints its output and returns
/// the exit code.
pub fn run() -> ExitCode {
    let cli = Cli::parse();
    init_logging(cli.verbose);

    match execute(&cli) {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            report(&error);
            ExitCode::from(error.exit_code())
        }
    }
}

fn init_logging(verbosity: u8) {
    let default = match verbosity {
        0 => "warn",
        1 => "info",
        _ => "debug",
    };
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default));
    if let Err(e) = tracing_subscriber::fmt()
        .with_writer(io::stderr)
        .with_env_filter(filter)
        .try_init()
    {
        eprintln!("warning: logging is not set up: {e}");
    }
}

fn report(error: &CliError) {
    eprintln!("error: {error}");
    let mut source = error.source();
    while let Some(cause) = source {
        eprintln!("  caused by: {cause}");
        source = cause.source();
    }
    if let CliError::NoNodeAnswered { failures } = error {
        for failure in failures {
            eprintln!("  {failure}");
            let mut cause = failure.source();
            while let Some(c) = cause {
                eprintln!("    caused by: {c}");
                cause = c.source();
            }
        }
    }
    if let Some(hint) = error.hint() {
        eprintln!("hint: {hint}");
    }
}

fn execute(cli: &Cli) -> Result<u8, CliError> {
    match &cli.command {
        Command::Diff { a, b, baseline } => run_diff(cli, a, b, baseline.as_deref()).map(|()| 0),
        Command::Dump {
            out,
            label,
            redact_serial,
        } => run_dump(cli, out, label, *redact_serial).map(|()| 0),
        Command::Show { snapshot } => run_show(cli, snapshot.as_deref()).map(|()| 0),
        Command::Plan { desired, snapshot } => {
            run_plan(cli, desired, snapshot.as_deref()).map(|()| 0)
        }
        Command::Apply {
            desired,
            check,
            fail_on_drift,
            backup_dir,
        } => run_apply(cli, desired, *check, *fail_on_drift, backup_dir.as_deref()),
        Command::Restore {
            snapshot,
            yes,
            backup_dir,
        } => run_restore(cli, snapshot, *yes, backup_dir.as_deref()).map(|()| 0),
        Command::ListBackups { backup_dir } => {
            run_list_backups(cli, backup_dir.as_deref()).map(|()| 0)
        }
    }
}

fn emit(text: &str) -> Result<(), CliError> {
    io::stdout()
        .write_all(text.as_bytes())
        .map_err(|source| CliError::Output { source })
}

fn read_snapshot(path: &Path) -> Result<ConfigSnapshot, CliError> {
    ConfigSnapshot::read(path).map_err(|source| CliError::Snapshot { source })
}

fn run_diff(cli: &Cli, a: &Path, b: &Path, baseline: Option<&Path>) -> Result<(), CliError> {
    let a = read_snapshot(a)?;
    let b = read_snapshot(b)?;
    let volatile = match baseline {
        Some(path) => VolatileSet::from_untouched_pair(a.bytes(), read_snapshot(path)?.bytes()),
        None => VolatileSet::none(),
    };

    let runs = diff(a.bytes(), b.bytes(), &volatile);
    if cli.json {
        let json = to_json(&runs);
        emit(&format!("{json}\n"))
    } else {
        emit(&render_text(&runs))
    }
}

fn run_dump(cli: &Cli, out: &Path, label: &str, redact_serial: bool) -> Result<(), CliError> {
    let options = DumpOptions {
        out_dir: out.to_path_buf(),
        label: label.to_string(),
        redact_serial,
    };
    let (node, written) = with_device(cli, cli.serial.as_deref(), |_, device| {
        dump(device, &options, UtcTimestamp::now()).map_err(|error| match error {
            DumpError::Read { source } => Attempt::NextNode(source),
            source @ DumpError::Save { .. } => Attempt::Fatal(CliError::Dump { source }),
        })
    })?;
    report_dump(cli, &node, &written.bin, &written.json)
}

/// A node the device command could not finish on.
enum Attempt {
    /// This node did not answer; another node of the device may.
    NextNode(HidError),
    Fatal(CliError),
}

/// Each hidraw node of the chosen device with the serial it reports.
type Nodes = Vec<(PathBuf, String)>;

fn select_nodes(cli: &Cli, serial: Option<&str>) -> Result<Nodes, SelectError> {
    match &cli.hidraw {
        Some(path) => {
            let serial = discover(&cli.sysfs_root, &cli.dev_dir)
                .ok()
                .and_then(|nodes| nodes.into_iter().find(|n| &n.dev_path == path))
                .and_then(|n| n.serial)
                .unwrap_or_else(|| UNKNOWN_SERIAL.to_string());
            Ok(vec![(path.clone(), serial)])
        }
        None => {
            let nodes =
                discover(&cli.sysfs_root, &cli.dev_dir).and_then(|nodes| choose(nodes, serial))?;
            Ok(nodes
                .into_iter()
                .map(|n| {
                    let serial = n.serial.clone().unwrap_or_else(|| n.device_label());
                    (n.dev_path, serial)
                })
                .collect())
        }
    }
}

fn acquire_lock(cli: &Cli) -> Result<DeviceLock, CliError> {
    let lock_path = cli.lock_file.clone().unwrap_or_else(|| {
        let runtime_dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from);
        default_lock_path(runtime_dir.as_deref())
    });
    DeviceLock::acquire(&lock_path).map_err(|source| CliError::Lock { source })
}

/// Finds the device, takes the lock and runs `operation` on the first node
/// that answers; returns that node's path with the result.
fn with_device<T>(
    cli: &Cli,
    serial: Option<&str>,
    operation: impl FnMut(&Path, &mut dyn HidDevice) -> Result<T, Attempt>,
) -> Result<(PathBuf, T), CliError> {
    let nodes = select_nodes(cli, serial).map_err(|source| CliError::Select { source })?;
    with_nodes(cli, nodes, operation)
}

/// Takes the lock, then tries each node until one answers. Which node carries
/// the configuration report is not visible in sysfs.
fn with_nodes<T>(
    cli: &Cli,
    nodes: Nodes,
    mut operation: impl FnMut(&Path, &mut dyn HidDevice) -> Result<T, Attempt>,
) -> Result<(PathBuf, T), CliError> {
    let mut lock = acquire_lock(cli)?;
    let clock = SystemClock::new();

    let mut failures = Vec::new();
    for (path, serial) in nodes {
        tracing::debug!(node = %path.display(), "trying hidraw node");
        let device = match HidrawDevice::open(&path) {
            Ok(device) => device.with_serial(&serial),
            Err(error) => {
                failures.push(error);
                continue;
            }
        };
        let mut spaced = SpacedDevice::new(device, &mut lock, &clock);
        match operation(&path, &mut spaced) {
            Ok(value) => return Ok((path, value)),
            Err(Attempt::NextNode(error)) => failures.push(error),
            Err(Attempt::Fatal(error)) => return Err(error),
        }
    }
    Err(CliError::NoNodeAnswered { failures })
}

/// A failure before the device was changed moves on to the next node; anything
/// else ends the command.
fn workflow_attempt(error: WorkflowError) -> Attempt {
    match error {
        WorkflowError::Read { source }
        | WorkflowError::Apply {
            source: ApplyError::Read { source },
        } => Attempt::NextNode(source),
        source => Attempt::Fatal(CliError::Workflow { source }),
    }
}

fn load_desired(path: &Path) -> Result<(DesiredState, FanCurve), CliError> {
    let text = fs::read_to_string(path).map_err(|source| CliError::DesiredRead {
        path: path.to_path_buf(),
        source,
    })?;
    let on_desired = |source| CliError::Desired {
        path: path.to_path_buf(),
        source,
    };
    let desired = DesiredState::from_json(&text).map_err(on_desired)?;
    let curve = desired.curve().map_err(on_desired)?;
    Ok((desired, curve))
}

fn plan_offline(config: &ConfigBytes, curve: &FanCurve) -> Result<(Profile, Plan), CliError> {
    let on_workflow = |source| CliError::Workflow { source };
    let profile = Profile::for_data_version(data_version(config))
        .map_err(|source| on_workflow(WorkflowError::NoProfile { source }))?;
    let plan = build_plan(config, curve, &profile)
        .map_err(|source| on_workflow(WorkflowError::Plan { source }))?;
    Ok((profile, plan))
}

fn run_show(cli: &Cli, snapshot: Option<&Path>) -> Result<(), CliError> {
    let config = match snapshot {
        Some(path) => read_snapshot(path)?.bytes().clone(),
        None => {
            with_device(cli, cli.serial.as_deref(), |_, device| {
                read_config(device).map_err(Attempt::NextNode)
            })?
            .1
        }
    };
    let shown = show::show(&config).map_err(|source| CliError::Profile { source })?;
    if cli.json {
        emit(&format!("{}\n", show::to_json(&shown)))
    } else {
        emit(&show::render_text(&shown))
    }
}

fn describe_change(change: &Change) -> String {
    let ranges: Vec<String> = change
        .positions
        .iter()
        .map(|range| format!("{:#06x}..{:#06x}", range.start, range.end))
        .collect();
    format!(
        "{}: {} -> {} (bytes {})",
        change.name,
        change.old,
        change.new,
        ranges.join(", ")
    )
}

fn plan_summary(plan: &Plan) -> String {
    let count = plan.changes.len();
    if plan.already_applied {
        "already as desired; nothing to write\n".to_string()
    } else if plan.untouched_equal {
        let noun = if count == 1 { "change" } else { "changes" };
        format!("{count} {noun}; every other byte is unchanged\n")
    } else {
        let noun = if count == 1 { "change" } else { "changes" };
        format!("{count} {noun}; other bytes differ too\n")
    }
}

fn plan_to_json(plan: &Plan) -> serde_json::Value {
    let changes: Vec<serde_json::Value> = plan
        .changes
        .iter()
        .map(|change| {
            let positions: Vec<[usize; 2]> = change
                .positions
                .iter()
                .map(|range| [range.start, range.end])
                .collect();
            serde_json::json!({
                "name": change.name,
                "old": change.old,
                "new": change.new,
                "positions": positions,
            })
        })
        .collect();
    serde_json::json!({
        "changes": changes,
        "already_applied": plan.already_applied,
        "untouched_equal": plan.untouched_equal,
    })
}

fn run_plan(cli: &Cli, desired_path: &Path, snapshot: Option<&Path>) -> Result<(), CliError> {
    let (desired, curve) = load_desired(desired_path)?;
    let plan = match snapshot {
        Some(path) => plan_offline(read_snapshot(path)?.bytes(), &curve)?.1,
        None => {
            let serial = cli.serial.as_deref().or(desired.device_serial.as_deref());
            let (_, (_, plan)) = with_device(cli, serial, |_, device| {
                plan_for_device(device, &curve).map_err(workflow_attempt)
            })?;
            plan
        }
    };
    if cli.json {
        return emit(&format!("{}\n", plan_to_json(&plan)));
    }
    let mut text = String::new();
    for change in &plan.changes {
        text.push_str(&describe_change(change));
        text.push('\n');
    }
    text.push_str(&plan_summary(&plan));
    emit(&text)
}

fn describe_profile(profile: ProfileInfo) -> String {
    format!(
        "profile: data version {}, layout verified on firmware {}\n",
        profile.data_version, profile.firmware
    )
}

fn run_apply(
    cli: &Cli,
    desired_path: &Path,
    check_flag: bool,
    fail_on_drift: bool,
    backup_dir: Option<&Path>,
) -> Result<u8, CliError> {
    let (desired, curve) = load_desired(desired_path)?;
    let check = check_flag || desired.mode == Mode::Check;
    let backup_dir = match backup_dir {
        Some(dir) => dir.to_path_buf(),
        None => default_backup_dir()?,
    };

    let serial = cli.serial.as_deref().or(desired.device_serial.as_deref());
    let nodes = match select_nodes(cli, serial) {
        Ok(nodes) => nodes,
        Err(error @ SelectError::Absent) => {
            eprintln!("warning: {error}; nothing was applied");
            return Ok(0);
        }
        Err(source) => return Err(CliError::Select { source }),
    };

    let (_, outcome) = with_nodes(cli, nodes, |_, device| {
        apply_desired(device, &curve, check, &backup_dir, UtcTimestamp::now())
            .map_err(workflow_attempt)
    })?;

    match outcome {
        Outcome::AlreadyApplied { profile } => {
            emit(&format!(
                "{}already as desired; nothing written\n",
                describe_profile(profile)
            ))?;
            Ok(0)
        }
        Outcome::Drift { profile, plan } => {
            let mut text = describe_profile(profile);
            for change in &plan.changes {
                text.push_str(&format!("drift: {}\n", describe_change(change)));
            }
            emit(&text)?;
            Ok(if fail_on_drift { EXIT_DRIFT } else { 0 })
        }
        Outcome::Applied {
            profile,
            plan,
            backup,
        } => {
            let mut text = describe_profile(profile);
            text.push_str(&format!("backup: {}\n", backup.bin.display()));
            for change in &plan.changes {
                text.push_str(&format!("wrote: {}\n", describe_change(change)));
            }
            text.push_str("saved: the device was told to keep the change\n");
            text.push_str("read-back: matches the intended configuration\n");
            emit(&text)?;
            Ok(0)
        }
    }
}

fn run_restore(
    cli: &Cli,
    snapshot_path: &Path,
    yes: bool,
    backup_dir: Option<&Path>,
) -> Result<(), CliError> {
    let snapshot = read_snapshot(snapshot_path)?;
    // The snapshot's own data version decides which layout and commit
    // sequence apply to it.
    let profile = Profile::for_data_version(snapshot.meta().firmware)
        .map_err(|source| CliError::Profile { source })?;
    confirm_restore(snapshot_path, yes)?;

    let options = ApplyOptions {
        backup_dir: match backup_dir {
            Some(dir) => dir.to_path_buf(),
            None => default_backup_dir()?,
        },
        commit_reports: profile.commit_reports(),
    };
    let (_, report) = with_device(cli, cli.serial.as_deref(), |_, device| {
        restore_config(device, &snapshot, &options, UtcTimestamp::now()).map_err(
            |error| match error {
                RestoreError::Read { source } => Attempt::NextNode(source),
                source => Attempt::Fatal(CliError::Restore { source }),
            },
        )
    })?;

    match report {
        ApplyReport::AlreadyApplied => {
            emit("already as the snapshot; nothing written\n")
        }
        ApplyReport::Applied { backup, .. } => emit(&format!(
            "backup: {}\nsaved: the device was told to keep the change\nread-back: matches the snapshot\n",
            backup.bin.display()
        )),
    }
}

fn confirm_restore(snapshot: &Path, yes: bool) -> Result<(), CliError> {
    if yes {
        return Ok(());
    }
    let stdin = io::stdin();
    if !stdin.is_terminal() {
        return Err(CliError::ConfirmationNeeded);
    }
    eprint!("restore {} to the device? [y/N] ", snapshot.display());
    // A prompt left unflushed would wait on an answer nobody was asked for.
    io::stderr()
        .flush()
        .map_err(|source| CliError::Prompt { source })?;
    let mut answer = String::new();
    stdin
        .read_line(&mut answer)
        .map_err(|source| CliError::Prompt { source })?;
    if answer.trim().eq_ignore_ascii_case("y") {
        Ok(())
    } else {
        Err(CliError::Declined)
    }
}

/// `$STATE_DIRECTORY/backups` under systemd, else
/// `$XDG_STATE_HOME/aquaero-ctl/backups`, else
/// `$HOME/.local/state/aquaero-ctl/backups`.
fn default_backup_dir() -> Result<PathBuf, CliError> {
    let set = |name: &str| std::env::var_os(name).filter(|value| !value.is_empty());
    backup_dir_from(set("STATE_DIRECTORY"), set("XDG_STATE_HOME"), set("HOME"))
        .ok_or(CliError::NoBackupDir)
}

fn backup_dir_from(
    state_directory: Option<OsString>,
    xdg_state_home: Option<OsString>,
    home: Option<OsString>,
) -> Option<PathBuf> {
    if let Some(dir) = state_directory {
        // systemd gives a colon-separated list when a unit has several.
        let first = dir
            .to_string_lossy()
            .split(':')
            .next()
            .unwrap_or_default()
            .to_string();
        return Some(PathBuf::from(first).join("backups"));
    }
    if let Some(dir) = xdg_state_home {
        return Some(PathBuf::from(dir).join("aquaero-ctl/backups"));
    }
    home.map(|dir| PathBuf::from(dir).join(".local/state/aquaero-ctl/backups"))
}

fn run_list_backups(cli: &Cli, backup_dir: Option<&Path>) -> Result<(), CliError> {
    let dir = match backup_dir {
        Some(dir) => dir.to_path_buf(),
        None => default_backup_dir()?,
    };
    let on_dir = |source| CliError::ListBackups {
        path: dir.clone(),
        source,
    };
    let mut sidecars = Vec::new();
    match fs::read_dir(&dir) {
        Ok(entries) => {
            for entry in entries {
                let path = entry.map_err(on_dir)?.path();
                if path.extension().is_some_and(|ext| ext == "json") {
                    sidecars.push(path);
                }
            }
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(source) => return Err(on_dir(source)),
    }
    // File names start with the UTC time, so name order is time order.
    sidecars.sort();
    sidecars.reverse();

    let mut backups: Vec<(SnapshotMeta, PathBuf)> = Vec::new();
    for sidecar in sidecars {
        let meta = fs::read_to_string(&sidecar)
            .map_err(|e| e.to_string())
            .and_then(|text| {
                serde_json::from_str::<SnapshotMeta>(&text).map_err(|e| e.to_string())
            });
        match meta {
            Ok(meta)
                if cli
                    .serial
                    .as_deref()
                    .is_none_or(|wanted| meta.serial == wanted) =>
            {
                backups.push((meta, sidecar.with_extension("bin")));
            }
            Ok(_) => {}
            Err(reason) => eprintln!("warning: skipping {}: {reason}", sidecar.display()),
        }
    }

    if cli.json {
        let items: Vec<serde_json::Value> = backups
            .iter()
            .map(|(meta, bin)| {
                serde_json::json!({
                    "taken_at": meta.taken_at,
                    "label": meta.label,
                    "serial": meta.serial,
                    "data_version": meta.firmware,
                    "bin": bin,
                })
            })
            .collect();
        return emit(&format!("{}\n", serde_json::Value::Array(items)));
    }
    if backups.is_empty() {
        return emit("no backups\n");
    }
    let mut text = String::new();
    for (meta, bin) in &backups {
        text.push_str(&format!(
            "{}  {}  {}  data version {}  {}\n",
            meta.taken_at,
            meta.label,
            meta.serial,
            meta.firmware,
            bin.display()
        ));
    }
    emit(&text)
}

fn report_dump(cli: &Cli, node: &Path, bin: &Path, json: &Path) -> Result<(), CliError> {
    let snapshot = read_snapshot(bin)?;
    let meta = snapshot.meta();
    if cli.json {
        let value = serde_json::json!({
            "bin": bin,
            "json": json,
            "hidraw": node,
            "serial": meta.serial,
            "firmware": meta.firmware,
            "sha256": meta.sha256,
        });
        emit(&format!("{value}\n"))
    } else {
        emit(&format!(
            "wrote {}\nwrote {}\nserial {}, firmware {}, sha256 {}, read from {}\n",
            bin.display(),
            json.display(),
            meta.serial,
            meta.firmware,
            meta.sha256,
            node.display()
        ))
    }
}

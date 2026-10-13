//! Command-line interface: argument parsing, output and the exit-code mapping
//! from `specs/008-aquaero-linux-config/contracts/cli.md`.

use std::error::Error;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{ArgAction, Parser, Subcommand};
use thiserror::Error;
use tracing_subscriber::EnvFilter;

use crate::diff::{diff, render_text, to_json, VolatileSet};
use crate::dump::{dump, DumpOptions};
use crate::error::{DumpError, HidError, LockError, SelectError, SnapshotError};
use crate::hid::SystemClock;
use crate::hidraw::{HidrawDevice, UNKNOWN_SERIAL};
use crate::lock::{DeviceLock, SpacedDevice};
use crate::select::{choose, discover};
use crate::snapshot::ConfigSnapshot;
use crate::timestamp::UtcTimestamp;

const EXIT_ERROR: u8 = 1;
const EXIT_PERMISSION: u8 = 5;
const EXIT_AMBIGUOUS: u8 = 4;
const EXIT_LOCKED: u8 = 7;

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

    /// Lock file that keeps two copies from using the device at once.
    #[arg(long, global = true, default_value = "/run/aquaero-ctl.lock")]
    lock_file: PathBuf,

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
}

#[derive(Debug, Error)]
enum CliError {
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

fn is_permission_denied(error: &HidError) -> bool {
    matches!(error, HidError::Open { source, .. } if source.kind() == io::ErrorKind::PermissionDenied)
}

/// Parses the command line, runs the command, prints its output and returns
/// the exit code.
pub fn run() -> ExitCode {
    let cli = Cli::parse();
    init_logging(cli.verbose);

    match execute(&cli) {
        Ok(()) => ExitCode::SUCCESS,
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

fn execute(cli: &Cli) -> Result<(), CliError> {
    match &cli.command {
        Command::Diff { a, b, baseline } => run_diff(cli, a, b, baseline.as_deref()),
        Command::Dump {
            out,
            label,
            redact_serial,
        } => run_dump(cli, out, label, *redact_serial),
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
    // Each node with the serial its device reports.
    let paths: Vec<(PathBuf, String)> = match &cli.hidraw {
        Some(path) => {
            let serial = discover(&cli.sysfs_root, &cli.dev_dir)
                .ok()
                .and_then(|nodes| nodes.into_iter().find(|n| &n.dev_path == path))
                .and_then(|n| n.serial)
                .unwrap_or_else(|| UNKNOWN_SERIAL.to_string());
            vec![(path.clone(), serial)]
        }
        None => {
            let nodes = discover(&cli.sysfs_root, &cli.dev_dir)
                .and_then(|nodes| choose(nodes, cli.serial.as_deref()))
                .map_err(|source| CliError::Select { source })?;
            nodes
                .into_iter()
                .map(|n| {
                    let serial = n.serial.clone().unwrap_or_else(|| n.device_label());
                    (n.dev_path, serial)
                })
                .collect()
        }
    };

    let mut lock =
        DeviceLock::acquire(&cli.lock_file).map_err(|source| CliError::Lock { source })?;
    let clock = SystemClock::new();
    let options = DumpOptions {
        out_dir: out.to_path_buf(),
        label: label.to_string(),
        redact_serial,
    };

    // Which hidraw node carries the configuration report is not visible in
    // sysfs, so each node of the device is tried until one answers.
    let mut failures = Vec::new();
    for (path, serial) in paths {
        tracing::debug!(node = %path.display(), "trying hidraw node");
        let device = match HidrawDevice::open(&path) {
            Ok(device) => device.with_serial(&serial),
            Err(error) => {
                failures.push(error);
                continue;
            }
        };
        let mut spaced = SpacedDevice::new(device, &mut lock, &clock);
        match dump(&mut spaced, &options, UtcTimestamp::now()) {
            Ok(written) => return report_dump(cli, &path, &written.bin, &written.json),
            Err(DumpError::Read { source }) => failures.push(source),
            Err(source @ DumpError::Save { .. }) => return Err(CliError::Dump { source }),
        }
    }
    Err(CliError::NoNodeAnswered { failures })
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

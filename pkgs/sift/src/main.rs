mod cli;
mod event;
mod output;
mod platform;
mod reduce;

use chrono::Utc;
use clap::Parser;
use cli::{Cli, Format, LgtmSignal, Mode, Platform, QueryArgs};
use event::Event;
use output::ToTable;
use std::process::ExitCode;
use tracing::{error, info};

fn main() -> ExitCode {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();

    let result = match cli.platform {
        Platform::Lgtm { signal } => match signal {
            LgtmSignal::Logs(args) => run_loki(&args),
            LgtmSignal::Metrics(args) => run_prometheus(&args),
        },
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            error!(error = %message, "sift query failed");
            ExitCode::FAILURE
        }
    }
}

/// Computes the (start, now) query window from `--since`, shared by
/// every platform's fetch — the parse-duration-then-subtract logic is
/// identical regardless of which platform's timestamp format the
/// caller ends up needing it in.
fn query_window(args: &QueryArgs) -> Result<(chrono::DateTime<Utc>, chrono::DateTime<Utc>), String> {
    let since = humantime::parse_duration(&args.since)
        .map_err(|e| format!("invalid --since {:?}: {e}", args.since))?;
    let now = Utc::now();
    let since_duration = chrono::Duration::from_std(since).map_err(|e| e.to_string())?;
    let start = now
        .checked_sub_signed(since_duration)
        .ok_or_else(|| format!("--since {:?} underflows the current time", args.since))?;
    Ok((start, now))
}

fn run_loki(args: &QueryArgs) -> Result<(), String> {
    let (start, now) = query_window(args)?;
    let start_ns = i64_seconds_to_nanos(start.timestamp())?;
    let end_ns = i64_seconds_to_nanos(now.timestamp())?;

    info!(query = %args.query, url = %args.url, "querying Loki");
    let events = platform::loki::fetch(&args.url, &args.query, start_ns, end_ns, args.limit)
        .map_err(|e| e.to_string())?;

    emit(&events, args)
}

fn run_prometheus(args: &QueryArgs) -> Result<(), String> {
    let (start, now) = query_window(args)?;

    info!(query = %args.query, url = %args.url, "querying Prometheus/Mimir");
    let events = platform::prometheus::fetch(
        &args.url,
        &args.query,
        start.timestamp(),
        now.timestamp(),
        60,
    )
    .map_err(|e| e.to_string())?;

    emit(&events, args)
}

/// Converts a unix-second timestamp to nanoseconds for Loki's API,
/// which expects nanosecond-precision start/end query parameters.
fn i64_seconds_to_nanos(seconds: i64) -> Result<i64, String> {
    seconds
        .checked_mul(1_000_000_000)
        .ok_or_else(|| format!("timestamp {seconds} overflows when converted to nanoseconds"))
}

fn emit(events: &[Event], args: &QueryArgs) -> Result<(), String> {
    match args.mode {
        Mode::Aggregate => {
            let result = reduce::aggregate(events, &args.group_by);
            print_result(&result, &args.format)
        }
        Mode::Topn => {
            let result = reduce::topn(events, &args.group_by, args.top);
            print_result(&result, &args.format)
        }
        Mode::Histogram => {
            let bucket = reduce::parse_bucket_duration(&args.bucket).map_err(|e| e.to_string())?;
            let result = reduce::histogram(events, bucket);
            print_result(&result, &args.format)
        }
        Mode::Diff => {
            // The baseline window is a second query for a prior window
            // of the same duration as --since, ending where the
            // current window begins. Not yet wired into the CLI — see
            // the sift-cli plan's Fast-follow section: reduce::diff
            // itself is fully implemented and tested, what's missing
            // is a second QueryArgs-driven fetch for the baseline
            // window, which needs its own CLI design (two query
            // windows, not one).
            Err("diff mode requires a second query for the baseline window; not yet wired into the CLI — see reduce::diff for the underlying logic".to_string())
        }
        Mode::Raw => {
            for event in events.iter().take(args.limit) {
                match &event.body {
                    Some(body) => println!("{} {}", event.timestamp, body),
                    None => println!("{} {:?}", event.timestamp, event.value),
                }
            }
            Ok(())
        }
    }
}

fn print_result<T: serde::Serialize + ToTable>(result: &T, format: &Format) -> Result<(), String> {
    match format {
        Format::Json => {
            let json = output::format_json(result).map_err(|e| e.to_string())?;
            println!("{json}");
        }
        Format::Table => {
            print!("{}", result.to_table());
        }
    }
    Ok(())
}

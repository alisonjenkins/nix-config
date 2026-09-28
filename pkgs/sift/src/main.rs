mod auth;
mod cli;
mod event;
mod output;
mod platform;
mod reduce;

use chrono::Utc;
use clap::Parser;
use cli::{
    Cli, DatadogArgs, DatadogLogsArgs, DatadogMetricsArgs, DatadogSignal, DatadogTracesArgs,
    Format, LgtmSignal, Mode, Platform, QueryArgs,
};
use event::Event;
use output::ToTable;
use std::process::ExitCode;
use tracing::{error, info, warn};

fn main() -> ExitCode {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();

    let result = match cli.platform {
        Platform::Lgtm { signal } => match signal {
            LgtmSignal::Logs(args) => run_loki(&args),
            LgtmSignal::Metrics(args) => run_prometheus(&args),
        },
        Platform::Datadog { signal } => match signal {
            DatadogSignal::Logs(args) => run_datadog_logs(&args),
            DatadogSignal::Metrics(args) => run_datadog_metrics(&args),
            DatadogSignal::Traces(args) => run_datadog_traces(&args),
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
fn query_window(since: &str) -> Result<(chrono::DateTime<Utc>, chrono::DateTime<Utc>), String> {
    let since_duration = humantime::parse_duration(since)
        .map_err(|e| format!("invalid --since {since:?}: {e}"))?;
    let now = Utc::now();
    let since_duration = chrono::Duration::from_std(since_duration).map_err(|e| e.to_string())?;
    let start = now
        .checked_sub_signed(since_duration)
        .ok_or_else(|| format!("--since {since:?} underflows the current time"))?;
    Ok((start, now))
}

/// Resolves LGTM credentials from `--auth-profile` via secretspec, or
/// no credentials at all when the flag is omitted (unauthenticated
/// query — the default for a local, unsecured Loki/Prometheus). See
/// pkgs/sift/docs/adr/0006-secretspec-credential-resolution.md: the resolved
/// secret value never becomes a CLI argument, so it never appears in
/// anything an LLM-driven invocation of `sift` could observe.
fn resolve_auth(args: &QueryArgs) -> Result<auth::Auth, String> {
    match &args.auth_profile {
        Some(profile) => {
            auth::Auth::from_secretspec_profile(profile).map_err(|e| e.to_string())
        }
        None => Ok(auth::Auth::none()),
    }
}

/// Resolves Datadog credentials from `--auth-profile`, or from
/// secretspec's "default" profile (bound to the `env` provider — see
/// secretspec.toml) when the flag is omitted. Unlike LGTM, there is no
/// unauthenticated fallback: Datadog's API rejects every request
/// without DD-API-KEY/DD-APPLICATION-KEY, so a missing key surfaces as
/// a clear error naming which one before any request is sent.
fn resolve_datadog_auth(args: &DatadogArgs) -> Result<auth::DatadogAuth, String> {
    let profile = args.auth_profile.as_deref().unwrap_or("default");
    auth::DatadogAuth::from_secretspec_profile(profile).map_err(|e| e.to_string())
}

fn run_loki(args: &QueryArgs) -> Result<(), String> {
    let (start, now) = query_window(&args.common.since)?;
    // timestamp_nanos_opt(), not timestamp()*1_000_000_000 — the
    // latter drops the sub-second component of the query window
    // itself, silently narrowing it by up to ~1s at each edge.
    let start_ns = start
        .timestamp_nanos_opt()
        .ok_or_else(|| format!("start timestamp {start} overflows i64 nanoseconds"))?;
    let end_ns = now
        .timestamp_nanos_opt()
        .ok_or_else(|| format!("end timestamp {now} overflows i64 nanoseconds"))?;
    let auth = resolve_auth(args)?;

    info!(query = %args.common.query, url = %args.url, "querying Loki");
    let events = platform::loki::fetch(
        &args.url,
        &args.common.query,
        start_ns,
        end_ns,
        args.common.limit,
        &auth,
    )
    .map_err(|e| e.to_string())?;

    emit(&events, &args.common.mode, &args.group_by, args.common.top, &args.common.bucket, &args.common.format, args.common.limit)
}

fn run_prometheus(args: &QueryArgs) -> Result<(), String> {
    let (start, now) = query_window(&args.common.since)?;
    let auth = resolve_auth(args)?;

    info!(query = %args.common.query, url = %args.url, "querying Prometheus/Mimir");
    let events = platform::prometheus::fetch(
        &args.url,
        &args.common.query,
        fractional_unix_secs(start),
        fractional_unix_secs(now),
        60,
        &auth,
    )
    .map_err(|e| e.to_string())?;

    emit(&events, &args.common.mode, &args.group_by, args.common.top, &args.common.bucket, &args.common.format, args.common.limit)
}

/// `--mode raw` fetches up to `--limit` events; every reducing mode pages
/// up to `--max-events`.
fn datadog_fetch_limit(args: &DatadogArgs) -> usize {
    match args.common.mode {
        Mode::Raw => args.common.limit,
        _ => args.max_events,
    }
}

/// A reduction over a capped fetch covers only the newest events, so its
/// counts are not totals for the whole window; say so rather than let
/// them read as complete.
fn warn_if_capped(args: &DatadogArgs, fetched: usize, signal: &str) {
    if !matches!(args.common.mode, Mode::Raw) && fetched >= args.max_events {
        warn!(
            signal,
            max_events = args.max_events,
            "fetch hit --max-events: results cover only the newest events in the window; raise --max-events or narrow the query/--since for complete counts"
        );
    }
}

fn run_datadog_logs(args: &DatadogLogsArgs) -> Result<(), String> {
    let (start, now) = query_window(&args.datadog.common.since)?;
    let auth = resolve_datadog_auth(&args.datadog)?;
    let base_url = platform::datadog::base_url(&args.datadog.site);
    let limit = datadog_fetch_limit(&args.datadog);

    info!(query = %args.datadog.common.query, site = %args.datadog.site, "querying Datadog logs");
    let events =
        platform::datadog::fetch_logs(&base_url, &args.datadog.common.query, start, now, limit, &auth)
            .map_err(|e| e.to_string())?;
    warn_if_capped(&args.datadog, events.len(), "logs");

    emit(
        &events,
        &args.datadog.common.mode,
        &args.group_by,
        args.datadog.common.top,
        &args.datadog.common.bucket,
        &args.datadog.common.format,
        args.datadog.common.limit,
    )
}

fn run_datadog_metrics(args: &DatadogMetricsArgs) -> Result<(), String> {
    let (start, now) = query_window(&args.datadog.common.since)?;
    let auth = resolve_datadog_auth(&args.datadog)?;
    let base_url = platform::datadog::base_url(&args.datadog.site);

    info!(query = %args.datadog.common.query, site = %args.datadog.site, "querying Datadog metrics");
    let events = platform::datadog::fetch_metrics(
        &base_url,
        &args.datadog.common.query,
        start.timestamp(),
        now.timestamp(),
        &auth,
    )
    .map_err(|e| e.to_string())?;

    emit(
        &events,
        &args.datadog.common.mode,
        &args.group_by,
        args.datadog.common.top,
        &args.datadog.common.bucket,
        &args.datadog.common.format,
        args.datadog.common.limit,
    )
}

fn run_datadog_traces(args: &DatadogTracesArgs) -> Result<(), String> {
    let (start, now) = query_window(&args.datadog.common.since)?;
    let auth = resolve_datadog_auth(&args.datadog)?;
    let base_url = platform::datadog::base_url(&args.datadog.site);
    let limit = datadog_fetch_limit(&args.datadog);

    info!(query = %args.datadog.common.query, site = %args.datadog.site, "querying Datadog traces");
    let events = platform::datadog::fetch_traces(
        &base_url,
        &args.datadog.common.query,
        start,
        now,
        limit,
        &auth,
    )
    .map_err(|e| e.to_string())?;
    warn_if_capped(&args.datadog, events.len(), "traces");

    emit(
        &events,
        &args.datadog.common.mode,
        &args.group_by,
        args.datadog.common.top,
        &args.datadog.common.bucket,
        &args.datadog.common.format,
        args.datadog.common.limit,
    )
}

/// Converts to a fractional-second Unix timestamp — plain
/// `.timestamp()` truncates to whole seconds, which would silently
/// narrow the query window sent to Prometheus by up to ~1s at each
/// edge.
fn fractional_unix_secs(dt: chrono::DateTime<Utc>) -> f64 {
    #[allow(clippy::arithmetic_side_effects)] // timestamp_subsec_nanos() is bounded to [0, 1_999_999_999], so this stays far below f64's precision limits.
    let subsec = f64::from(dt.timestamp_subsec_nanos()) / 1_000_000_000.0;
    dt.timestamp() as f64 + subsec
}

fn emit(
    events: &[Event],
    mode: &Mode,
    group_by: &str,
    top: usize,
    bucket: &str,
    format: &Format,
    limit: usize,
) -> Result<(), String> {
    match mode {
        Mode::Aggregate => {
            let result = reduce::aggregate(events, group_by);
            print_result(&result, format)
        }
        Mode::Topn => {
            let result = reduce::topn(events, group_by, top);
            print_result(&result, format)
        }
        Mode::Histogram => {
            let bucket = reduce::parse_bucket_duration(bucket).map_err(|e| e.to_string())?;
            let result = reduce::histogram(events, bucket);
            print_result(&result, format)
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
            for event in events.iter().take(limit) {
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

use clap::{Args, Parser, Subcommand, ValueEnum};

#[derive(Parser)]
#[command(
    name = "sift",
    version,
    about = "Reduce observability platform output before it reaches an LLM context"
)]
pub struct Cli {
    #[command(subcommand)]
    pub platform: Platform,
}

#[derive(Subcommand)]
pub enum Platform {
    /// Query the Grafana LGTM stack (Loki, Mimir/Prometheus)
    Lgtm {
        #[command(subcommand)]
        signal: LgtmSignal,
    },
    /// Query Datadog (logs, metrics, APM traces) directly over its HTTP API
    Datadog {
        #[command(subcommand)]
        signal: DatadogSignal,
    },
}

#[derive(Subcommand)]
pub enum LgtmSignal {
    /// Query Loki logs with LogQL
    Logs(QueryArgs),
    /// Query Mimir/Prometheus metrics with PromQL
    Metrics(QueryArgs),
}

#[derive(Subcommand)]
pub enum DatadogSignal {
    /// Search Datadog logs
    Logs(DatadogLogsArgs),
    /// Query Datadog metrics (v1 timeseries query)
    Metrics(DatadogMetricsArgs),
    /// Search Datadog APM traces (spans)
    Traces(DatadogTracesArgs),
}

/// Reduction/output flags shared by every platform and signal — how to
/// window, reduce, and print the events a fetch returns, independent of
/// which platform or signal produced them.
#[derive(Args)]
pub struct CommonArgs {
    /// The query, in the platform's own query syntax (LogQL, PromQL,
    /// Datadog log/span search syntax, or a Datadog metric query)
    pub query: String,

    /// Reduction mode
    #[arg(long, value_enum, default_value = "aggregate")]
    pub mode: Mode,

    /// Number of top entries to keep (topn mode)
    #[arg(long, default_value_t = 10)]
    pub top: usize,

    /// Bucket duration for histogram mode, e.g. "5m"
    #[arg(long, default_value = "5m")]
    pub bucket: String,

    /// Baseline lookback duration for diff mode, e.g. "1h" (not yet
    /// wired: diff mode is implemented in reduce::diff but not callable
    /// from the CLI yet — see pkgs/sift/docs/adr/0003-diff-mode-logic-without-cli-wiring.md)
    #[arg(long, default_value = "1h")]
    pub baseline: String,

    /// Lookback duration for the query window itself, e.g. "15m"
    #[arg(long, default_value = "15m")]
    pub since: String,

    /// Output format
    #[arg(long, value_enum, default_value = "table")]
    pub format: Format,

    /// Hard cap on rows fetched when --mode raw is used
    #[arg(long, default_value_t = 200)]
    pub limit: usize,
}

#[derive(Args)]
pub struct QueryArgs {
    #[command(flatten)]
    pub common: CommonArgs,

    /// Base URL of the Loki or Prometheus/Mimir instance
    #[arg(long, env = "SIFT_LGTM_URL")]
    pub url: String,

    /// secretspec profile to resolve LGTM credentials from (e.g.
    /// "work", "home") — resolved via secretspec.toml's provider
    /// bindings (1Password, AWS SSM/Secrets Manager, Azure Key Vault,
    /// ...). Omit for an unauthenticated query. The resolved secret
    /// value itself is never a CLI argument or printed anywhere — only
    /// this profile name crosses the command line. See
    /// pkgs/sift/docs/adr/0006-secretspec-credential-resolution.md
    #[arg(long, env = "SIFT_LGTM_AUTH_PROFILE")]
    pub auth_profile: Option<String>,

    /// Label to group by (aggregate/topn/diff modes)
    #[arg(long, default_value = "level")]
    pub group_by: String,
}

/// Datadog connection flags shared across logs/metrics/traces — only
/// `--group-by`'s default differs per signal, so it lives on each
/// signal's own args struct instead of here.
#[derive(Args)]
pub struct DatadogArgs {
    #[command(flatten)]
    pub common: CommonArgs,

    /// Datadog site to query, e.g. "datadoghq.com" (US1, default),
    /// "us3.datadoghq.com", "datadoghq.eu" — see
    /// https://docs.datadoghq.com/getting_started/site/. The request
    /// goes to https://api.{site}.
    #[arg(long, env = "DD_SITE", default_value = "datadoghq.com")]
    pub site: String,

    /// secretspec profile to resolve DD_API_KEY/DD_APP_KEY from (e.g.
    /// "work", "personal") — same mechanism as LGTM's --auth-profile,
    /// see pkgs/sift/docs/adr/0006-secretspec-credential-resolution.md.
    /// Omitting this still resolves via secretspec's "default" profile,
    /// which is bound to the "env" provider — so plain DD_API_KEY/
    /// DD_APP_KEY environment variables work with no profile at all.
    #[arg(long, env = "SIFT_DD_AUTH_PROFILE")]
    pub auth_profile: Option<String>,

    /// Most events to page through (1000 per request) for a reducing
    /// mode (logs and traces). Raise it for complete counts over a busy
    /// window; each extra 1000 costs one more API request against the
    /// org's rate limit. `--mode raw` uses --limit instead.
    #[arg(long, default_value_t = crate::platform::datadog::DEFAULT_MAX_EVENTS)]
    pub max_events: usize,
}

#[derive(Args)]
pub struct DatadogLogsArgs {
    #[command(flatten)]
    pub datadog: DatadogArgs,

    /// Facet or tag to group by (aggregate/topn/diff modes). Defaults
    /// to "status" — the most common first split for a log search.
    #[arg(long, default_value = "status")]
    pub group_by: String,
}

#[derive(Args)]
pub struct DatadogMetricsArgs {
    #[command(flatten)]
    pub datadog: DatadogArgs,

    /// Tag to group by (aggregate/topn/diff modes). Defaults to
    /// "metric" — the metric name itself, since a metrics query
    /// commonly already scopes to one or a few tag combinations.
    #[arg(long, default_value = "metric")]
    pub group_by: String,
}

#[derive(Args)]
pub struct DatadogTracesArgs {
    #[command(flatten)]
    pub datadog: DatadogArgs,

    /// Tag to group by (aggregate/topn/diff modes). Defaults to
    /// "service" — the most common first split for a trace search.
    #[arg(long, default_value = "service")]
    pub group_by: String,
}

#[derive(Clone, ValueEnum)]
pub enum Mode {
    Aggregate,
    Topn,
    Histogram,
    Diff,
    Raw,
}

#[derive(Clone, ValueEnum)]
pub enum Format {
    Table,
    Json,
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        clippy::expect_used,
        clippy::indexing_slicing,
        clippy::panic
    )]
    use super::*;

    #[test]
    fn mode_defaults_to_aggregate_not_raw() {
        let cli = Cli::parse_from([
            "sift", "lgtm", "logs", "{app=\"checkout\"}", "--url", "http://localhost:3100",
        ]);
        let Platform::Lgtm { signal } = cli.platform else {
            panic!("expected Lgtm platform");
        };
        let LgtmSignal::Logs(args) = signal else {
            panic!("expected Logs subcommand");
        };
        assert!(matches!(args.common.mode, Mode::Aggregate));
    }

    #[test]
    fn datadog_logs_parses_with_site_flag() {
        let cli = Cli::parse_from([
            "sift", "datadog", "logs", "service:web", "--site", "us3.datadoghq.com",
        ]);
        let Platform::Datadog { signal } = cli.platform else {
            panic!("expected Datadog platform");
        };
        let DatadogSignal::Logs(args) = signal else {
            panic!("expected Logs subcommand");
        };
        assert_eq!(args.datadog.common.query, "service:web");
        assert_eq!(args.datadog.site, "us3.datadoghq.com");
        assert_eq!(args.group_by, "status");
        assert_eq!(args.datadog.max_events, crate::platform::datadog::DEFAULT_MAX_EVENTS);
    }

    #[test]
    fn datadog_max_events_is_overridable() {
        let cli = Cli::parse_from([
            "sift", "datadog", "traces", "service:web", "--max-events", "20000",
        ]);
        let Platform::Datadog { signal } = cli.platform else {
            panic!("expected Datadog platform");
        };
        let DatadogSignal::Traces(args) = signal else {
            panic!("expected Traces subcommand");
        };
        assert_eq!(args.datadog.max_events, 20000);
    }

    #[test]
    fn datadog_site_defaults_to_datadoghq_com() {
        let cli = Cli::parse_from(["sift", "datadog", "metrics", "avg:system.load.1{*}"]);
        let Platform::Datadog { signal } = cli.platform else {
            panic!("expected Datadog platform");
        };
        let DatadogSignal::Metrics(args) = signal else {
            panic!("expected Metrics subcommand");
        };
        assert_eq!(args.datadog.site, "datadoghq.com");
        assert_eq!(args.group_by, "metric");
    }

    #[test]
    fn datadog_traces_group_by_defaults_to_service() {
        let cli = Cli::parse_from(["sift", "datadog", "traces", "service:checkout"]);
        let Platform::Datadog { signal } = cli.platform else {
            panic!("expected Datadog platform");
        };
        let DatadogSignal::Traces(args) = signal else {
            panic!("expected Traces subcommand");
        };
        assert_eq!(args.group_by, "service");
    }
}

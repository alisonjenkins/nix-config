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
}

#[derive(Subcommand)]
pub enum LgtmSignal {
    /// Query Loki logs with LogQL
    Logs(QueryArgs),
    /// Query Mimir/Prometheus metrics with PromQL
    Metrics(QueryArgs),
}

#[derive(Args)]
pub struct QueryArgs {
    /// The LogQL or PromQL query
    pub query: String,

    /// Base URL of the Loki or Prometheus/Mimir instance
    #[arg(long, env = "SIFT_LGTM_URL")]
    pub url: String,

    /// Reduction mode
    #[arg(long, value_enum, default_value = "aggregate")]
    pub mode: Mode,

    /// Label to group by (aggregate/topn/diff modes)
    #[arg(long, default_value = "level")]
    pub group_by: String,

    /// Number of top entries to keep (topn mode)
    #[arg(long, default_value_t = 10)]
    pub top: usize,

    /// Bucket duration for histogram mode, e.g. "5m"
    #[arg(long, default_value = "5m")]
    pub bucket: String,

    /// Baseline lookback duration for diff mode, e.g. "1h" (not yet
    /// wired: diff mode is implemented in reduce::diff but not callable
    /// from the CLI yet — see pkgs/sift/docs/adr/0003)
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
        let Platform::Lgtm { signal } = cli.platform;
        let LgtmSignal::Logs(args) = signal else {
            panic!("expected Logs subcommand");
        };
        assert!(matches!(args.mode, Mode::Aggregate));
    }
}

//! Sends one hook log entry (a JSON line on stdin) to Loki and Tempo. Started in
//! the background by the hooks; see `retrieval_eval::telemetry`.
use std::io::Read;
use std::process::ExitCode;

use clap::Parser;
use retrieval_eval::recall_log::parse_log;
use retrieval_eval::telemetry::{send, Targets};

#[derive(Parser)]
#[command(about = "Ship one memory-recall or skill-recall log entry to Loki and Tempo")]
struct Cli {
    #[command(flatten)]
    targets: Targets,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let mut stdin = String::new();
    if std::io::stdin().read_to_string(&mut stdin).is_err() {
        return ExitCode::FAILURE;
    }
    let Some(entry) = parse_log(&stdin).into_iter().next() else {
        eprintln!("recall-ship: no log entry on stdin");
        return ExitCode::FAILURE;
    };
    let mut failed = false;
    for result in send(&cli.targets, &entry) {
        if let Err(error) = result {
            eprintln!("recall-ship: {error}");
            failed = true;
        }
    }
    if failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

use std::fs;
use std::io::Write;
use std::net::TcpListener;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Barrier};
use std::thread;
use std::time::Duration;

use cc_obs_ledger::otlp::{Payload, Signal};
use cc_obs_ledger::ship::{ship_spool, ship_spool_within, write_spool, ShipReport};

mod common;

use common::read_request;

/// Accepts `count` requests, answers 200, returns "<path> <body>" for each.
fn serve(count: usize) -> (String, thread::JoinHandle<Vec<String>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        let mut seen = Vec::new();
        for _ in 0..count {
            let (mut stream, _) = listener.accept().unwrap();
            seen.push(read_request(&mut stream));
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
                .unwrap();
        }
        seen
    });
    (url, handle)
}

/// Files in the spool, not counting the sender's lock file.
fn spooled(dir: &std::path::Path) -> usize {
    fs::read_dir(dir)
        .unwrap()
        .filter(|entry| entry.as_ref().unwrap().file_name() != ".lock")
        .count()
}

fn payload(signal: Signal) -> Payload {
    let key = match signal {
        Signal::Metrics => "resourceMetrics",
        Signal::Logs => "resourceLogs",
    };
    Payload {
        signal,
        body: serde_json::json!({ key: [] }),
    }
}

#[test]
fn spooled_payloads_are_posted_to_the_matching_signal_path_and_removed() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    write_spool(dir.path(), &payload(Signal::Logs)).unwrap();
    let (url, server) = serve(2);
    let report = ship_spool(dir.path(), &url, Duration::from_secs(3));
    assert_eq!(report.sent, 2);
    assert!(report.failed.is_empty(), "{:?}", report.failed);
    assert_eq!(spooled(dir.path()), 0);
    let mut seen = server.join().unwrap();
    seen.sort();
    assert!(seen[0].starts_with("/v1/logs "), "{seen:?}");
    assert!(seen[1].starts_with("/v1/metrics "), "{seen:?}");
}

#[test]
fn an_unreachable_endpoint_keeps_the_files_and_names_the_target() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    let report = ship_spool(dir.path(), "http://127.0.0.1:1", Duration::from_secs(1));
    assert_eq!(report.sent, 0);
    assert_eq!(report.failed.len(), 1);
    assert!(
        report.failed[0].contains("http://127.0.0.1:1/v1/metrics"),
        "{:?}",
        report.failed
    );
    assert_eq!(spooled(dir.path()), 1);
}

/// Answers 200 to every request until `stop` is set, after a short pause so
/// overlapping senders really overlap. Returns the number of requests seen.
fn serve_counting(stop: Arc<AtomicBool>) -> (String, thread::JoinHandle<usize>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        let mut seen = 0usize;
        while !stop.load(Ordering::SeqCst) {
            let Ok((mut stream, _)) = listener.accept() else {
                thread::sleep(Duration::from_millis(2));
                continue;
            };
            stream.set_nonblocking(false).unwrap();
            read_request(&mut stream);
            seen += 1;
            thread::sleep(Duration::from_millis(20));
            let _ = stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}");
        }
        seen
    });
    (url, handle)
}

#[test]
fn overlapping_ship_runs_post_each_spool_file_once() {
    let dir = tempfile::tempdir().unwrap();
    for _ in 0..4 {
        write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    }
    let stop = Arc::new(AtomicBool::new(false));
    let (url, server) = serve_counting(Arc::clone(&stop));
    let barrier = Arc::new(Barrier::new(2));
    let runs: Vec<_> = (0..2)
        .map(|_| {
            let (path, url, barrier) = (dir.path().to_owned(), url.clone(), Arc::clone(&barrier));
            thread::spawn(move || {
                barrier.wait();
                ship_spool(&path, &url, Duration::from_secs(3))
            })
        })
        .collect();
    let sent: usize = runs.into_iter().map(|r| r.join().unwrap().sent).sum();
    stop.store(true, Ordering::SeqCst);
    assert_eq!(server.join().unwrap(), 4, "a file was posted twice");
    assert_eq!(sent, 4);
}

fn age(path: &std::path::Path, secs: u64) {
    let old = std::time::SystemTime::now() - Duration::from_secs(secs);
    fs::File::options()
        .write(true)
        .open(path)
        .unwrap()
        .set_modified(old)
        .unwrap();
}

#[test]
fn stale_partial_and_unknown_files_are_removed_but_fresh_ones_are_left() {
    let dir = tempfile::tempdir().unwrap();
    let stale_partial = dir.path().join(".1-2-3.metrics.json.partial");
    let stale_unknown = dir.path().join("junk.txt");
    let fresh_partial = dir.path().join(".4-5-6.logs.json.partial");
    let fresh_unknown = dir.path().join("notes.txt");
    for path in [
        &stale_partial,
        &stale_unknown,
        &fresh_partial,
        &fresh_unknown,
    ] {
        fs::write(path, "x").unwrap();
    }
    age(&stale_partial, 3 * 24 * 3600);
    age(&stale_unknown, 3 * 24 * 3600);
    let report = ship_spool(dir.path(), "http://127.0.0.1:1", Duration::from_secs(1));
    assert_eq!(report.expired, 2);
    assert!(!stale_partial.exists());
    assert!(!stale_unknown.exists());
    assert!(fresh_partial.exists());
    assert!(fresh_unknown.exists());
}

#[test]
fn a_run_with_activity_has_one_summary_line() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    write_spool(dir.path(), &payload(Signal::Logs)).unwrap();
    let report = ship_spool(dir.path(), "http://127.0.0.1:1", Duration::from_secs(1));
    let summary = report.summary().unwrap();
    assert!(!summary.contains('\n'));
    assert!(summary.contains("sent=0"), "{summary}");
    assert!(summary.contains("failed=2"), "{summary}");
    assert!(summary.contains("http://127.0.0.1:1/v1/"), "{summary}");
    assert_eq!(ShipReport::default().summary(), None);
}

#[test]
fn a_spool_file_older_than_a_day_is_dropped_instead_of_retried_forever() {
    let dir = tempfile::tempdir().unwrap();
    let path = write_spool(dir.path(), &payload(Signal::Logs)).unwrap();
    let old = std::time::SystemTime::now() - Duration::from_secs(3 * 24 * 3600);
    fs::File::options()
        .write(true)
        .open(&path)
        .unwrap()
        .set_modified(old)
        .unwrap();
    let report = ship_spool(dir.path(), "http://127.0.0.1:1", Duration::from_secs(1));
    assert_eq!(report.expired, 1);
    assert_eq!(spooled(dir.path()), 0);
}

/// Answers 200 to each of `count` requests after `delay`, then runs `on_request(n)`.
fn serve_slowly(
    count: usize,
    delay: Duration,
    on_request: impl Fn(usize) + Send + 'static,
) -> (String, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        for n in 0..count {
            let (mut stream, _) = listener.accept().unwrap();
            read_request(&mut stream);
            thread::sleep(delay);
            on_request(n);
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
                .unwrap();
        }
    });
    (url, handle)
}

#[test]
fn a_run_that_spends_its_budget_leaves_the_rest_and_says_so() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    write_spool(dir.path(), &payload(Signal::Logs)).unwrap();
    let (url, server) = serve_slowly(1, Duration::from_millis(300), |_| {});
    let report = ship_spool_within(
        dir.path(),
        &url,
        Duration::from_secs(3),
        Duration::from_millis(100),
    );
    server.join().unwrap();
    assert_eq!(report.sent, 1);
    assert_eq!(spooled(dir.path()), 1, "the second payload must stay");
    let summary = report.summary().unwrap();
    assert!(summary.contains("run budget"), "{summary}");
    assert!(summary.contains("1 files left"), "{summary}");
    assert!(summary.contains("failed=0"), "{summary}");
}

#[test]
fn a_payload_spooled_during_the_second_pass_is_not_stranded() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    let spool = dir.path().to_owned();
    let (url, server) = serve_slowly(3, Duration::ZERO, move |n| {
        if n < 2 {
            write_spool(&spool, &payload(Signal::Logs)).unwrap();
        }
    });
    let report = ship_spool(dir.path(), &url, Duration::from_secs(3));
    server.join().unwrap();
    assert_eq!(report.sent, 3, "{:?}", report.failed);
    assert_eq!(spooled(dir.path()), 0);
}

#[test]
fn files_that_are_not_payloads_do_not_count_as_left_by_the_budget() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    fs::write(dir.path().join("zz-notes.txt"), "x").unwrap();
    let (url, server) = serve_slowly(1, Duration::from_millis(300), |_| {});
    let report = ship_spool_within(
        dir.path(),
        &url,
        Duration::from_secs(3),
        Duration::from_millis(100),
    );
    server.join().unwrap();
    assert_eq!(report.sent, 1);
    assert!(report.failed.is_empty(), "{:?}", report.failed);
}

#[test]
fn a_payload_spooled_while_the_sender_was_posting_goes_out_in_the_same_run() {
    let dir = tempfile::tempdir().unwrap();
    write_spool(dir.path(), &payload(Signal::Metrics)).unwrap();
    let spool = dir.path().to_owned();
    let (url, server) = serve_slowly(2, Duration::ZERO, move |n| {
        if n == 0 {
            write_spool(&spool, &payload(Signal::Logs)).unwrap();
        }
    });
    let report = ship_spool(dir.path(), &url, Duration::from_secs(3));
    server.join().unwrap();
    assert_eq!(report.sent, 2, "{:?}", report.failed);
    assert_eq!(spooled(dir.path()), 0);
}

#[test]
fn a_spool_path_that_is_not_a_directory_is_reported_not_skipped_silently() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("spool");
    fs::write(&file, "x").unwrap();
    let report = ship_spool(&file, "http://127.0.0.1:1", Duration::from_secs(1));
    assert_eq!(report.failed.len(), 1, "{report:?}");
    assert!(
        report.failed[0].contains("is not a directory"),
        "{report:?}"
    );
}

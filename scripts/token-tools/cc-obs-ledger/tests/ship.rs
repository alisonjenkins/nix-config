#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Barrier};
use std::thread;
use std::time::Duration;

use cc_obs_ledger::otlp::{Payload, Signal};
use cc_obs_ledger::ship::{ship_spool, write_spool, ShipReport};

/// Reads one HTTP request and returns "<path> <body>".
fn read_request(stream: &mut TcpStream) -> String {
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        let n = stream.read(&mut chunk).unwrap_or(0);
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
        let text = String::from_utf8_lossy(&buf).to_string();
        if let Some(split) = text.find("\r\n\r\n") {
            let length = text
                .lines()
                .find_map(|l| {
                    l.to_ascii_lowercase()
                        .strip_prefix("content-length:")
                        .map(|v| v.trim().parse::<usize>().unwrap())
                })
                .unwrap_or(0);
            if buf.len() >= split.saturating_add(4).saturating_add(length) {
                break;
            }
        }
    }
    let text = String::from_utf8_lossy(&buf).to_string();
    let path = text.split_whitespace().nth(1).unwrap_or("").to_string();
    let body = text.split("\r\n\r\n").nth(1).unwrap_or("").to_string();
    format!("{path} {body}")
}

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

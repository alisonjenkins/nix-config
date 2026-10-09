#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::sync::{Arc, Barrier};
use std::thread;

use std::io;

use cc_obs_ledger::config::{
    load_or_create_key, load_or_create_key_with, log_line_capped, write_atomic, write_atomic_with,
};

#[test]
fn racing_callers_all_get_the_same_key_and_the_file_is_32_bytes_mode_0600() {
    for _ in 0..20 {
        let dir = tempfile::tempdir().unwrap();
        let state = Arc::new(dir.path().join("state"));
        let barrier = Arc::new(Barrier::new(16));
        let handles: Vec<_> = (0..16)
            .map(|_| {
                let (state, barrier) = (Arc::clone(&state), Arc::clone(&barrier));
                thread::spawn(move || {
                    barrier.wait();
                    load_or_create_key(&state).unwrap()
                })
            })
            .collect();
        let keys: Vec<Vec<u8>> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        let on_disk = fs::read(state.join("hmac.key")).unwrap();
        assert_eq!(on_disk.len(), 32);
        assert!(keys.iter().all(|key| *key == on_disk), "callers disagree");
        let mode = fs::metadata(state.join("hmac.key"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
        let entries = fs::read_dir(&*state).unwrap().count();
        assert_eq!(entries, 1, "temp files must not be left behind");
    }
}

#[test]
fn the_log_rotates_once_it_passes_the_cap_and_keeps_one_previous_file() {
    let dir = tempfile::tempdir().unwrap();
    let log = dir.path().join("ledger.log");
    let old = dir.path().join("ledger.log.1");
    for n in 0..20 {
        log_line_capped(dir.path(), &format!("line {n}"), 200);
    }
    assert!(old.exists(), "no rotated file");
    assert!(fs::metadata(&log).unwrap().len() <= 200 + 64);
    assert!(fs::metadata(&old).unwrap().len() <= 200 + 64);
    let all = format!(
        "{}{}",
        fs::read_to_string(&old).unwrap(),
        fs::read_to_string(&log).unwrap()
    );
    assert!(all.contains("line 19"));
    assert!(!dir.path().join("ledger.log.2").exists());
}

#[test]
fn a_key_shorter_than_32_bytes_is_replaced() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("hmac.key"), b"short").unwrap();
    let key = load_or_create_key(dir.path()).unwrap();
    assert_eq!(key.len(), 32);
    assert_eq!(fs::read(dir.path().join("hmac.key")).unwrap(), key);
    let again = load_or_create_key(dir.path()).unwrap();
    assert_eq!(again, key);
}

fn no_hard_links(_temp: &std::path::Path, _path: &std::path::Path) -> io::Result<()> {
    Err(io::Error::from(io::ErrorKind::Unsupported))
}

#[test]
fn an_unreadable_existing_key_is_an_error_and_is_never_replaced() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("hmac.key");
    fs::write(&path, [7u8; 32]).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o000)).unwrap();
    if fs::File::open(&path).is_ok() {
        return;
    }
    let error = load_or_create_key(dir.path()).unwrap_err();
    assert!(error.to_string().contains("hmac.key"), "{error}");
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    assert_eq!(fs::read(&path).unwrap(), [7u8; 32]);
}

#[test]
fn without_hard_link_support_the_key_is_still_created_with_mode_0600() {
    let dir = tempfile::tempdir().unwrap();
    let key = load_or_create_key_with(dir.path(), &no_hard_links).unwrap();
    assert_eq!(key.len(), 32);
    assert_eq!(fs::read(dir.path().join("hmac.key")).unwrap(), key);
    let mode = fs::metadata(dir.path().join("hmac.key"))
        .unwrap()
        .permissions()
        .mode();
    assert_eq!(mode & 0o777, 0o600);
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
}

#[test]
fn racing_callers_agree_on_one_key_when_hard_link_is_unsupported() {
    for _ in 0..20 {
        let dir = tempfile::tempdir().unwrap();
        let state = Arc::new(dir.path().join("state"));
        let barrier = Arc::new(Barrier::new(16));
        let handles: Vec<_> = (0..16)
            .map(|_| {
                let (state, barrier) = (Arc::clone(&state), Arc::clone(&barrier));
                thread::spawn(move || {
                    barrier.wait();
                    load_or_create_key_with(&state, &no_hard_links).unwrap()
                })
            })
            .collect();
        let keys: Vec<Vec<u8>> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        let on_disk = fs::read(state.join("hmac.key")).unwrap();
        assert_eq!(on_disk.len(), 32);
        assert!(keys.iter().all(|key| *key == on_disk), "callers disagree");
        assert_eq!(fs::read_dir(&*state).unwrap().count(), 1);
    }
}

#[test]
fn write_atomic_replaces_the_content_and_leaves_no_temp_file() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("cursor.json");
    write_atomic(&path, b"old").unwrap();
    write_atomic(&path, b"new").unwrap();
    assert_eq!(fs::read(&path).unwrap(), b"new");
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
}

#[test]
fn a_write_that_fails_midway_leaves_the_old_content_and_no_temp_file() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("cursor.json");
    fs::write(&path, b"old").unwrap();
    let half_then_fail = |temp: &std::path::Path, bytes: &[u8]| -> io::Result<()> {
        fs::write(temp, bytes.get(..2).unwrap_or_default())?;
        Err(io::Error::other("disk full"))
    };
    let error = write_atomic_with(&path, b"new content", &half_then_fail).unwrap_err();
    assert!(error.to_string().contains("cursor.json"), "{error}");
    assert_eq!(fs::read(&path).unwrap(), b"old");
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
}

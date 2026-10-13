// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use aquaero_ctl::error::SnapshotError;
use aquaero_ctl::snapshot::{normalise_label, ConfigBytes, ConfigSnapshot, CONFIG_LEN};
use aquaero_ctl::timestamp::UtcTimestamp;
use proptest::prelude::*;

fn sample_bytes(seed: u8) -> ConfigBytes {
    let bytes: Vec<u8> = (0..CONFIG_LEN)
        .map(|i| (i as u8).wrapping_add(seed))
        .collect();
    ConfigBytes::new(bytes).unwrap()
}

fn sample_snapshot(seed: u8, secs: i64, label: &str) -> ConfigSnapshot {
    ConfigSnapshot::new(
        sample_bytes(seed),
        "21998-56576".to_string(),
        1036,
        UtcTimestamp::from_unix(secs),
        label,
    )
}

#[test]
fn config_length_is_0xa93() {
    assert_eq!(CONFIG_LEN, 0xa93);
}

#[test]
fn bytes_of_the_wrong_length_are_rejected() {
    for len in [0, 1, CONFIG_LEN - 1, CONFIG_LEN + 1] {
        let err = ConfigBytes::new(vec![0; len]).unwrap_err();
        assert!(
            matches!(
                err,
                SnapshotError::Length { got, expected } if got == len && expected == CONFIG_LEN
            ),
            "length {len} gave {err:?}"
        );
    }
}

#[test]
fn a_snapshot_round_trips_through_its_files() {
    let dir = tempfile::tempdir().unwrap();
    let snap = sample_snapshot(7, 1_700_000_000, "baseline");

    let paths = snap.write_to(dir.path()).unwrap();
    let back = ConfigSnapshot::read(&paths.bin).unwrap();

    assert_eq!(back, snap);
}

#[test]
fn the_sidecar_is_readable_json_with_the_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let snap = sample_snapshot(1, 1_700_000_000, "baseline");

    let paths = snap.write_to(dir.path()).unwrap();
    let json: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(&paths.json).unwrap()).unwrap();

    assert_eq!(json["serial"], "21998-56576");
    assert_eq!(json["firmware"], 1036);
    assert_eq!(json["taken_at"], "2023-11-14T22:13:20Z");
    assert_eq!(json["label"], "baseline");
    assert_eq!(json["sha256"], snap.bytes().sha256_hex());
    assert_eq!(json["length"], CONFIG_LEN);
}

#[test]
fn a_changed_byte_fails_the_hash_check() {
    let dir = tempfile::tempdir().unwrap();
    let paths = sample_snapshot(3, 1_700_000_000, "x")
        .write_to(dir.path())
        .unwrap();

    let mut raw = std::fs::read(&paths.bin).unwrap();
    raw[100] ^= 0xff;
    std::fs::write(&paths.bin, raw).unwrap();

    let err = ConfigSnapshot::read(&paths.bin).unwrap_err();
    assert!(matches!(err, SnapshotError::HashMismatch { .. }), "{err:?}");
}

#[test]
fn a_truncated_file_reports_the_length_not_the_hash() {
    let dir = tempfile::tempdir().unwrap();
    let paths = sample_snapshot(3, 1_700_000_000, "x")
        .write_to(dir.path())
        .unwrap();

    let mut raw = std::fs::read(&paths.bin).unwrap();
    raw.truncate(CONFIG_LEN - 5);
    std::fs::write(&paths.bin, raw).unwrap();

    let err = ConfigSnapshot::read(&paths.bin).unwrap_err();
    assert!(matches!(err, SnapshotError::Length { .. }), "{err:?}");
}

#[test]
fn a_missing_sidecar_is_an_error_naming_the_path() {
    let dir = tempfile::tempdir().unwrap();
    let paths = sample_snapshot(3, 1_700_000_000, "x")
        .write_to(dir.path())
        .unwrap();
    std::fs::remove_file(&paths.json).unwrap();

    let err = ConfigSnapshot::read(&paths.bin).unwrap_err();
    assert!(
        matches!(&err, SnapshotError::Read { path, .. } if *path == paths.json),
        "{err:?}"
    );
}

#[test]
fn file_stems_sort_by_time() {
    let earlier = sample_snapshot(0, 1_000_000_000, "b");
    let later = sample_snapshot(0, 1_700_000_000, "a");

    assert_eq!(earlier.file_stem(), "20010909T014640Z-b");
    assert_eq!(later.file_stem(), "20231114T221320Z-a");
    assert!(earlier.file_stem() < later.file_stem());
}

#[test]
fn labels_are_reduced_to_lowercase_letters_digits_and_dashes() {
    assert_eq!(normalise_label("Fan 4 / min speed"), "fan-4-min-speed");
    assert_eq!(normalise_label("  --Baseline--  "), "baseline");
    assert_eq!(normalise_label("a__b"), "a-b");
    assert_eq!(normalise_label(""), "snapshot");
    assert_eq!(normalise_label("///"), "snapshot");
}

#[test]
fn redacting_the_serial_clears_it_in_the_metadata() {
    let mut snap = sample_snapshot(5, 1_700_000_000, "baseline");
    snap.redact_serial();
    assert_eq!(snap.meta().serial, "REDACTED");
}

#[test]
fn redacting_a_byte_range_zeroes_it_and_keeps_the_snapshot_valid() {
    let dir = tempfile::tempdir().unwrap();
    let mut snap = sample_snapshot(5, 1_700_000_000, "baseline");
    snap.redact_range(7, 4).unwrap();

    assert_eq!(&snap.bytes().as_slice()[7..11], &[0, 0, 0, 0]);
    assert_ne!(snap.bytes().as_slice()[6], 0);
    assert_ne!(snap.bytes().as_slice()[11], 0);

    let paths = snap.write_to(dir.path()).unwrap();
    assert_eq!(ConfigSnapshot::read(&paths.bin).unwrap(), snap);
}

#[test]
fn redacting_past_the_end_is_an_error() {
    let mut snap = sample_snapshot(5, 1_700_000_000, "baseline");
    let err = snap.redact_range(CONFIG_LEN - 2, 4).unwrap_err();
    assert!(
        matches!(err, SnapshotError::RedactRange { offset, len } if offset == CONFIG_LEN - 2 && len == 4),
        "{err:?}"
    );
}

#[test]
fn timestamps_format_as_iso_8601_utc() {
    for (secs, extended, compact) in [
        (0, "1970-01-01T00:00:00Z", "19700101T000000Z"),
        (1_000_000_000, "2001-09-09T01:46:40Z", "20010909T014640Z"),
        (951_782_400, "2000-02-29T00:00:00Z", "20000229T000000Z"),
        (1_700_000_000, "2023-11-14T22:13:20Z", "20231114T221320Z"),
    ] {
        let ts = UtcTimestamp::from_unix(secs);
        assert_eq!(ts.iso(), extended);
        assert_eq!(ts.compact(), compact);
    }
}

proptest! {
    #[test]
    fn any_snapshot_round_trips(
        bytes in proptest::collection::vec(any::<u8>(), CONFIG_LEN),
        serial in "[A-Za-z0-9-]{1,16}",
        firmware in any::<u32>(),
        secs in 0i64..4_102_444_800,
        label in ".{0,24}",
    ) {
        let dir = tempfile::tempdir().unwrap();
        let snap = ConfigSnapshot::new(
            ConfigBytes::new(bytes).unwrap(),
            serial,
            firmware,
            UtcTimestamp::from_unix(secs),
            &label,
        );
        let paths = snap.write_to(dir.path()).unwrap();
        prop_assert_eq!(ConfigSnapshot::read(&paths.bin).unwrap(), snap);
    }
}

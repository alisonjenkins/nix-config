// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use aquaero_ctl::error::ProfileError;
use aquaero_ctl::show::{render_text, show, to_json};
use aquaero_ctl::snapshot::ConfigBytes;

fn fixture(name: &str) -> ConfigBytes {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ConfigBytes::new(std::fs::read(path).unwrap()).unwrap()
}

#[test]
fn before_reflash_fan_four() {
    let shown = show(&fixture("before-reflash.bin")).unwrap();
    assert_eq!(shown.data_version, 1200);
    assert_eq!(shown.verified_firmware, 2104);
    let fan = shown.fans.iter().find(|f| f.fan == 4).unwrap();
    assert_eq!(fan.min_hundredths, 0);
    assert_eq!(fan.max_hundredths, 10000);
    assert!(
        fan.controller.contains("source 0x005f"),
        "{}",
        fan.controller
    );
}

#[test]
fn after_reflash_fan_four_and_curve_one() {
    let shown = show(&fixture("after-reflash.bin")).unwrap();
    let fan = shown.fans.iter().find(|f| f.fan == 4).unwrap();
    assert_eq!(fan.min_hundredths, 3500);
    assert_eq!(fan.max_hundredths, 10000);
    assert!(
        fan.controller.contains("source 0x005c"),
        "{}",
        fan.controller
    );

    let curve = shown.curves.iter().find(|c| c.slot == 1).unwrap();
    assert_eq!(curve.data_source, "none");
    assert_eq!(curve.start_hundredths, 3000);
    assert_eq!(curve.points.len(), 16);
    assert_eq!(curve.points.first().unwrap(), &(2700, 0));
    assert_eq!(curve.points.last().unwrap(), &(4000, 10000));
}

#[test]
fn every_fan_and_slot_is_listed() {
    let shown = show(&fixture("after-reflash.bin")).unwrap();
    let fans: Vec<usize> = shown.fans.iter().map(|f| f.fan).collect();
    let expected_fans: Vec<usize> = (1..=fans.len()).collect();
    assert!(!fans.is_empty());
    assert_eq!(fans, expected_fans);
    let slots: Vec<usize> = shown.curves.iter().map(|c| c.slot).collect();
    let expected_slots: Vec<usize> = (1..=slots.len()).collect();
    assert!(!slots.is_empty());
    assert_eq!(slots, expected_slots);
}

#[test]
fn curve_controller_fixture_curve_one() {
    let shown = show(&fixture("curve-controller-1.bin")).unwrap();
    let curve = shown.curves.iter().find(|c| c.slot == 1).unwrap();
    assert_eq!(curve.data_source, "sensor 1 (source 0x0000)");
    assert_eq!(curve.start_hundredths, 3170);
    assert_eq!(curve.points[2].1, 360);
}

#[test]
fn unknown_data_version_is_an_error() {
    let mut bytes = fixture("after-reflash.bin").as_slice().to_vec();
    bytes[1] = 0x04;
    bytes[2] = 0xb1;
    let config = ConfigBytes::new(bytes).unwrap();
    match show(&config) {
        Err(ProfileError::UnknownVersion { version, .. }) => assert_eq!(version, 1201),
        other => panic!("expected UnknownVersion, got {other:?}"),
    }
}

#[test]
fn text_starts_with_header_fans_and_curves() {
    let shown = show(&fixture("after-reflash.bin")).unwrap();
    let text = render_text(&shown);
    assert!(text.ends_with('\n') && !text.ends_with("\n\n"));
    let mut lines = text.lines();
    assert_eq!(
        lines.next().unwrap(),
        "data version 1200 (layout verified on firmware 2104)"
    );
    assert!(text.contains(
        "fan 4: minimum 35.00 %, maximum 100.00 %, controller: curve controller 1 (source 0x005c)"
    ) || text.contains("fan 4: minimum 35.00 %, maximum 100.00 %, controller: "));
    let block = "curve controller 1: data source: none, start 30.00 °C\n  27.00 °C -> 0.00 %\n";
    assert!(text.contains(block), "{text}");
    assert!(text.contains("  40.00 °C -> 100.00 %\n"), "{text}");
}

#[test]
fn json_shape() {
    let shown = show(&fixture("curve-controller-1.bin")).unwrap();
    let json = to_json(&shown);
    assert_eq!(json["data_version"], 1200);
    assert_eq!(json["verified_firmware"], 2104);
    let fan = &json["fans"][0];
    assert_eq!(fan["fan"], 1);
    assert!(fan["min_percent"].is_f64());
    assert!(fan["controller"].is_string());
    let curve = &json["curves"][0];
    assert_eq!(curve["slot"], 1);
    assert_eq!(curve["data_source"], "sensor 1 (source 0x0000)");
    assert_eq!(curve["start_temperature"], 31.7);
    assert_eq!(curve["points"][2]["output_percent"], 3.6);
    assert!(curve["points"][0]["temperature"].is_f64());
}

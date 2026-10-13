// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use aquaero_ctl::curve::Point;
use aquaero_ctl::desired::{DesiredError, DesiredState, Mode};

const EXAMPLE: &str = r#"{"device_serial":null,"mode":"check","fans":{"4":{"sensor":1,"min_percent":30,"points":[{"temp":30,"percent":30},{"temp":45,"percent":100}]}}}"#;

fn one_fan(key: &str) -> String {
    format!(r#"{{"fans":{{"{key}":{{"sensor":1,"min_percent":30,"points":[]}}}}}}"#)
}

#[test]
fn example_parses_and_yields_the_curve() {
    let state = DesiredState::from_json(EXAMPLE).unwrap();
    assert_eq!(state.mode, Mode::Check);
    assert_eq!(state.device_serial, None);
    let curve = state.curve().unwrap();
    assert_eq!(curve.fan, 4);
    assert_eq!(curve.sensor, 1);
    assert_eq!(curve.min_percent, 30.0);
    assert_eq!(
        curve.points,
        vec![
            Point {
                temp: 30.0,
                percent: 30.0
            },
            Point {
                temp: 45.0,
                percent: 100.0
            }
        ]
    );
}

#[test]
fn mode_and_serial_default_when_absent() {
    let state = DesiredState::from_json(&one_fan("4")).unwrap();
    assert_eq!(state.mode, Mode::Apply);
    assert_eq!(state.device_serial, None);
}

#[test]
fn serial_is_read_when_present() {
    let text = r#"{"device_serial":"1234","mode":"apply","fans":{}}"#;
    let state = DesiredState::from_json(text).unwrap();
    assert_eq!(state.device_serial.as_deref(), Some("1234"));
    assert_eq!(state.mode, Mode::Apply);
}

#[test]
fn unknown_fields_and_modes_are_parse_errors() {
    let cases = [
        r#"{"fans":{},"extra":1}"#,
        r#"{"fans":{"4":{"sensor":1,"min_percent":30,"points":[],"extra":2}}}"#,
        r#"{"mode":"destroy","fans":{}}"#,
        "not json",
    ];
    for text in cases {
        let err = DesiredState::from_json(text).unwrap_err();
        assert!(matches!(err, DesiredError::Parse { .. }), "{text}: {err:?}");
    }
}

#[test]
fn empty_fans_is_no_fans() {
    let state = DesiredState::from_json(r#"{"fans":{}}"#).unwrap();
    let err = state.curve().unwrap_err();
    assert!(matches!(err, DesiredError::NoFans));
}

#[test]
fn two_fans_is_more_than_one() {
    let text = r#"{"fans":{
        "3":{"sensor":1,"min_percent":30,"points":[]},
        "4":{"sensor":1,"min_percent":30,"points":[]}}}"#;
    let err = DesiredState::from_json(text).unwrap().curve().unwrap_err();
    assert!(matches!(err, DesiredError::MoreThanOneFan { count: 2 }));
    assert!(err.to_string().contains('2'));
}

#[test]
fn bad_fan_keys_name_the_key() {
    for key in ["x", "", "0", "-1"] {
        let err = DesiredState::from_json(&one_fan(key))
            .unwrap()
            .curve()
            .unwrap_err();
        match &err {
            DesiredError::BadFanKey { key: got } => assert_eq!(got, key),
            other => panic!("key {key:?}: {other:?}"),
        }
        assert!(err.to_string().contains(&format!("{key:?}")), "{err}");
    }
}

#[test]
fn parse_error_text_names_the_cause() {
    let err = DesiredState::from_json(r#"{"mode":"destroy","fans":{}}"#).unwrap_err();
    assert!(err.to_string().contains("destroy"), "{err}");
}

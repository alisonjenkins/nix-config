// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use aquaero_ctl::curve::{FanCurve, Point};
use aquaero_ctl::error::CurveError;
use proptest::prelude::*;

const DEVICE_POINTS: usize = 16;

fn p(temp: f64, percent: f64) -> Point {
    Point { temp, percent }
}

fn curve(min_percent: f64, points: Vec<Point>) -> FanCurve {
    FanCurve {
        fan: 4,
        sensor: 1,
        min_percent,
        points,
    }
}

fn valid() -> FanCurve {
    curve(30.0, vec![p(30.0, 30.0), p(40.0, 60.0), p(45.0, 100.0)])
}

#[test]
fn a_valid_curve_is_accepted() {
    valid().validate(DEVICE_POINTS).unwrap();
}

#[test]
fn only_fan_four_and_sensor_one_are_supported() {
    let mut c = valid();
    c.fan = 2;
    assert!(matches!(
        c.validate(DEVICE_POINTS),
        Err(CurveError::FanNotSupported { fan: 2 })
    ));
    let mut c = valid();
    c.sensor = 3;
    assert!(matches!(
        c.validate(DEVICE_POINTS),
        Err(CurveError::SensorNotSupported { sensor: 3 })
    ));
}

#[test]
fn a_minimum_outside_zero_to_one_hundred_names_the_value() {
    for bad in [-1.0, 100.5, 250.0] {
        let err = curve(bad, valid().points)
            .validate(DEVICE_POINTS)
            .unwrap_err();
        match err {
            CurveError::MinPercentOutOfRange { value } => assert_eq!(value, bad),
            other => panic!("{other:?}"),
        }
        assert!(err_text(bad).contains(&format!("{bad}")));
    }
}

fn err_text(bad: f64) -> String {
    curve(bad, valid().points)
        .validate(DEVICE_POINTS)
        .unwrap_err()
        .to_string()
}

#[test]
fn fewer_than_two_points_are_rejected() {
    for n in 0..2 {
        let points = valid().points.into_iter().take(n).collect();
        let err = curve(30.0, points).validate(DEVICE_POINTS).unwrap_err();
        assert!(
            matches!(err, CurveError::TooFewPoints { count } if count == n),
            "{err:?}"
        );
    }
}

#[test]
fn more_points_than_the_device_holds_are_rejected() {
    let points = (0..17)
        .map(|i| p(20.0 + f64::from(i), 40.0 + f64::from(i)))
        .collect();
    let err = curve(30.0, points).validate(DEVICE_POINTS).unwrap_err();
    assert!(
        matches!(err, CurveError::TooManyPoints { count: 17, max: 16 }),
        "{err:?}"
    );
}

#[test]
fn temperatures_must_strictly_increase() {
    let err = curve(30.0, vec![p(30.0, 30.0), p(30.0, 50.0), p(45.0, 100.0)])
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(
        matches!(err, CurveError::TemperaturesNotIncreasing { index: 1, previous, value } if previous == 30.0 && value == 30.0),
        "{err:?}"
    );
    let err = curve(30.0, vec![p(40.0, 30.0), p(35.0, 50.0)])
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(
        matches!(err, CurveError::TemperaturesNotIncreasing { index: 1, .. }),
        "{err:?}"
    );
}

#[test]
fn a_point_below_the_minimum_is_rejected_naming_it() {
    let err = curve(30.0, vec![p(30.0, 25.0), p(45.0, 100.0)])
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(
        matches!(err, CurveError::PercentBelowMinimum { index: 0, value, min } if value == 25.0 && min == 30.0),
        "{err:?}"
    );
}

#[test]
fn a_percent_that_decreases_or_exceeds_one_hundred_is_rejected() {
    let err = curve(30.0, vec![p(30.0, 50.0), p(40.0, 40.0)])
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(
        matches!(err, CurveError::PercentDecreases { index: 1, .. }),
        "{err:?}"
    );
    let err = curve(30.0, vec![p(30.0, 50.0), p(40.0, 101.0)])
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(
        matches!(err, CurveError::PercentOutOfRange { index: 1, .. }),
        "{err:?}"
    );
}

#[test]
fn values_that_are_not_numbers_are_rejected() {
    let err = curve(f64::NAN, valid().points)
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(matches!(err, CurveError::NotFinite { .. }), "{err:?}");
    let err = curve(30.0, vec![p(f64::INFINITY, 30.0), p(45.0, 100.0)])
        .validate(DEVICE_POINTS)
        .unwrap_err();
    assert!(matches!(err, CurveError::NotFinite { .. }), "{err:?}");
}

#[test]
fn a_curve_expands_to_exactly_the_devices_point_count() {
    let expanded = valid().expand(DEVICE_POINTS).unwrap();
    assert_eq!(expanded.len(), DEVICE_POINTS);
    // Strictly increasing in temperature, in hundredths of a degree.
    assert!(expanded.windows(2).all(|w| w[0].0 < w[1].0));
}

#[test]
fn the_original_points_survive_expansion() {
    let c = valid();
    let expanded = c.expand(DEVICE_POINTS).unwrap();
    for point in &c.points {
        let temp = (point.temp * 100.0).round() as i64;
        let found = expanded.iter().find(|(t, _)| *t == temp).unwrap();
        assert_eq!(found.1, (point.percent * 100.0).round() as i64);
    }
}

#[test]
fn the_curve_value_between_points_is_a_straight_line() {
    let c = curve(0.0, vec![p(30.0, 20.0), p(40.0, 60.0)]);
    assert!((c.percent_at(35.0) - 40.0).abs() < 1e-9);
    // Outside the points the curve holds its end values.
    assert!((c.percent_at(10.0) - 20.0).abs() < 1e-9);
    assert!((c.percent_at(80.0) - 60.0).abs() < 1e-9);
}

#[test]
fn points_too_close_to_spread_over_the_devices_points_are_refused() {
    let c = curve(0.0, vec![p(30.0, 20.0), p(30.01, 21.0)]);
    c.validate(DEVICE_POINTS).unwrap();
    assert!(matches!(
        c.expand(DEVICE_POINTS),
        Err(CurveError::CannotExpand { count: 16 })
    ));
}

proptest! {
    #[test]
    fn expansion_keeps_the_shape_of_any_valid_curve(
        min in 0u32..60,
        // At least 0.2 degrees between points: closer than that cannot be
        // spread over the device's 16 points (see the next test).
        steps in proptest::collection::vec((20u32..400, 0u32..200), 2..=16),
    ) {
        // Build strictly increasing temperatures (in 0.01 degrees) and a
        // non-decreasing percent from the generated steps.
        let mut temp = 2_000u32;
        let mut percent = min * 100;
        let mut points = Vec::new();
        for (dt, dp) in steps {
            temp += dt;
            percent = (percent + dp).min(10_000);
            points.push(p(f64::from(temp) / 100.0, f64::from(percent) / 100.0));
        }
        let c = curve(f64::from(min), points);
        prop_assume!(c.validate(DEVICE_POINTS).is_ok());

        let expanded = c.expand(DEVICE_POINTS).unwrap();
        prop_assert_eq!(expanded.len(), DEVICE_POINTS);
        prop_assert!(expanded.windows(2).all(|w| w[0].0 < w[1].0));
        // Every expanded point lies on the original curve, within a rounding step.
        for (t, pct) in expanded {
            let want = c.percent_at(t as f64 / 100.0);
            prop_assert!((pct as f64 / 100.0 - want).abs() <= 0.011, "at {t}: {pct} vs {want}");
        }
    }
}

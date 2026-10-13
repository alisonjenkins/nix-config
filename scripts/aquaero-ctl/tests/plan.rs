// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

//! Plans computed against dumps of the real device.

use aquaero_ctl::curve::{FanCurve, Point};
use aquaero_ctl::diff::{diff, VolatileSet};
use aquaero_ctl::error::{CurveError, PlanError};
use aquaero_ctl::plan::build_plan;
use aquaero_ctl::profile::Profile;
use aquaero_ctl::snapshot::ConfigBytes;

fn fixture(name: &str) -> ConfigBytes {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    ConfigBytes::new(std::fs::read(path).unwrap()).unwrap()
}

fn profile() -> Profile {
    Profile::for_data_version(1200).unwrap()
}

fn p(temp: f64, percent: f64) -> Point {
    Point { temp, percent }
}

fn desired() -> FanCurve {
    FanCurve {
        fan: 4,
        sensor: 1,
        min_percent: 30.0,
        points: vec![p(30.0, 30.0), p(40.0, 60.0), p(45.0, 100.0)],
    }
}

fn with_bytes(config: &ConfigBytes, changes: &[(usize, u8)]) -> ConfigBytes {
    let mut bytes = config.as_slice().to_vec();
    for &(offset, value) in changes {
        bytes[offset] = value;
    }
    ConfigBytes::new(bytes).unwrap()
}

/// Byte ranges the profile owns for this plan: fan 4's minimum and source and
/// the whole of curve controller 1.
fn owned(profile: &Profile) -> Vec<std::ops::Range<usize>> {
    let fan = profile.fan_offsets(4).unwrap();
    let curve = profile.curve_offsets(1).unwrap();
    vec![
        fan.min..fan.min + 2,
        fan.source..fan.source + 2,
        fan.settings..fan.settings + 1,
        fan.mode..fan.mode + 1,
        curve.source..curve.outputs + profile.curve_points() * 2,
    ]
}

#[test]
fn the_plan_lists_each_change_with_its_old_and_new_value_and_position() {
    let plan = build_plan(&fixture("after-reflash.bin"), &desired(), &profile()).unwrap();

    let by_name = |name: &str| {
        plan.changes
            .iter()
            .find(|c| c.name == name)
            .unwrap_or_else(|| panic!("no change named {name:?} in {:?}", plan.changes))
    };
    let min = by_name("fan 4 minimum power");
    assert_eq!(min.old, "35.00 %");
    assert_eq!(min.new, "30.00 %");
    assert_eq!(min.positions, vec![0x24c..0x24e]);

    let controller = by_name("fan 4 controller");
    assert!(controller.old.contains("0x005c"), "{}", controller.old);
    assert!(
        controller.new.contains("curve controller 1"),
        "{}",
        controller.new
    );
    assert!(controller.new.contains("0x0058"), "{}", controller.new);

    // The fan must never switch off: hold minimum power goes on.
    let hold = by_name("fan 4 hold minimum power");
    assert_eq!(hold.old, "off");
    assert_eq!(hold.new, "on");
    assert_eq!(hold.positions, vec![0x256..0x257]);

    // The radiators' power comes from elsewhere, so only the PWM signal is sent.
    let mode = by_name("fan 4 control mode");
    assert_eq!(mode.old, "power controlled");
    assert_eq!(mode.new, "PWM controlled");
    assert_eq!(mode.positions, vec![0x257..0x258]);

    let source = by_name("curve controller 1 data source");
    assert_eq!(source.old, "none");
    assert!(source.new.contains("sensor 1"), "{}", source.new);

    let start = by_name("curve controller 1 start temperature");
    assert_eq!(start.old, "30.00 °C");
    assert_eq!(start.new, "0.00 °C");

    assert!(!plan.already_applied);
}

#[test]
fn every_byte_outside_the_profiles_fields_is_preserved() {
    let before = fixture("after-reflash.bin");
    let profile = profile();
    let plan = build_plan(&before, &desired(), &profile).unwrap();

    assert!(plan.untouched_equal);
    let owned = owned(&profile);
    for run in diff(&before, &plan.intended, &VolatileSet::none()) {
        for at in run.offset..run.offset + run.before.len() {
            assert!(
                owned.iter().any(|range| range.contains(&at)),
                "byte {at:#06x} changed but is not a profile field"
            );
        }
    }
    assert_eq!(plan.intended.as_slice().len(), before.as_slice().len());
    assert_eq!(&plan.intended.as_slice()[..3], &before.as_slice()[..3]);
}

#[test]
fn the_intended_bytes_encode_the_curve() {
    let profile = profile();
    let plan = build_plan(&fixture("after-reflash.bin"), &desired(), &profile).unwrap();

    let curve = profile.curve_settings(&plan.intended, 1).unwrap();
    assert_eq!(curve.source, 0, "sensor 1");
    assert_eq!(curve.start_hundredths, 0, "active at every temperature");
    assert_eq!(curve.temperatures_hundredths.len(), 16);
    assert_eq!(curve.temperatures_hundredths[0], 3_000);
    assert_eq!(curve.temperatures_hundredths[15], 4_500);
    assert!(curve
        .temperatures_hundredths
        .windows(2)
        .all(|w| w[0] < w[1]));
    // 30 % is the floor, so the first point is the smallest output the
    // device accepts without switching the fan off; 100 % is full output.
    assert_eq!(curve.outputs_hundredths[0], 1);
    assert_eq!(curve.outputs_hundredths[15], 10_000);
    // 60 % of a 30 to 100 % range is (60 - 30) / 70 of the output.
    let at_40 = curve
        .temperatures_hundredths
        .iter()
        .position(|t| *t == 4_000)
        .unwrap();
    assert_eq!(curve.outputs_hundredths[at_40], 4_286);

    let fan = profile.fan_settings(&plan.intended, 4).unwrap();
    assert_eq!(fan.min_hundredths, 3_000);
    assert_eq!(fan.max_hundredths, 10_000);
    assert_eq!(fan.source, 0x0058, "curve controller 1");
    assert!(fan.hold_min_power);
    assert_eq!(fan.mode, 2, "PWM controlled");
}

#[test]
fn a_fan_already_in_pwm_mode_gets_no_change_for_it() {
    let plan = build_plan(&fixture("pwm-controlled.bin"), &desired(), &profile()).unwrap();
    assert!(plan.changes.iter().all(|c| c.name != "fan 4 control mode"));
}

#[test]
fn other_flags_in_the_fans_settings_byte_are_kept() {
    // Start boost (4) and current limit (2) already set on fan 4.
    let config = with_bytes(&fixture("after-reflash.bin"), &[(0x256, 0x06)]);
    let profile = profile();

    let plan = build_plan(&config, &desired(), &profile).unwrap();

    assert_eq!(plan.intended.as_slice()[0x256], 0x07);
    assert!(plan.untouched_equal);
}

#[test]
fn a_fan_that_already_holds_its_minimum_gets_no_change_for_it() {
    let plan = build_plan(
        &fixture("hold-minimum-power-on.bin"),
        &desired(),
        &profile(),
    )
    .unwrap();
    assert!(plan
        .changes
        .iter()
        .all(|c| c.name != "fan 4 hold minimum power"));
}

#[test]
fn applying_the_plan_makes_the_next_plan_empty() {
    let profile = profile();
    let first = build_plan(&fixture("after-reflash.bin"), &desired(), &profile).unwrap();
    let second = build_plan(&first.intended, &desired(), &profile).unwrap();

    assert!(second.already_applied);
    assert!(second.changes.is_empty());
    assert_eq!(second.intended, first.intended);
}

#[test]
fn a_plan_from_the_original_configuration_works_too() {
    let plan = build_plan(&fixture("before-reflash.bin"), &desired(), &profile()).unwrap();
    // Fan 4 was driven by Preset value 4 and had no minimum.
    let min = plan
        .changes
        .iter()
        .find(|c| c.name == "fan 4 minimum power")
        .unwrap();
    assert_eq!(min.old, "0.00 %");
    assert!(plan.untouched_equal);
}

#[test]
fn a_curve_controller_another_fan_uses_is_not_taken_over() {
    // Fan 3's source (0x0244) set to curve controller 1.
    let config = with_bytes(
        &fixture("after-reflash.bin"),
        &[(0x244, 0x00), (0x245, 0x58)],
    );
    let err = build_plan(&config, &desired(), &profile()).unwrap_err();
    assert!(
        matches!(err, PlanError::CurveInUse { slot: 1, fan: 3 }),
        "{err:?}"
    );
}

#[test]
fn a_point_above_the_fans_own_maximum_is_refused() {
    // Fan 4's maximum (0x24e) lowered to 80 %.
    let config = with_bytes(
        &fixture("after-reflash.bin"),
        &[(0x24e, 0x1f), (0x24f, 0x40)],
    );
    let err = build_plan(&config, &desired(), &profile()).unwrap_err();
    assert!(
        matches!(err, PlanError::PercentAboveFanMaximum { index: 2, .. }),
        "{err:?}"
    );
}

#[test]
fn an_invalid_curve_is_refused_with_its_own_error() {
    let mut curve = desired();
    curve.points = vec![p(40.0, 60.0), p(30.0, 70.0)];
    let err = build_plan(&fixture("after-reflash.bin"), &curve, &profile()).unwrap_err();
    assert!(
        matches!(
            err,
            PlanError::Curve {
                source: CurveError::TemperaturesNotIncreasing { index: 1, .. }
            }
        ),
        "{err:?}"
    );
}

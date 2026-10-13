//! What it would take to make the device match a desired curve: the intended
//! configuration, and each change with its old and new value and the bytes it
//! touches. Building a plan never touches the device.

use std::ops::Range;

use crate::curve::FanCurve;
use crate::diff::{diff, VolatileSet};
use crate::error::{PlanError, ProfileError};
use crate::profile::Profile;
use crate::snapshot::ConfigBytes;

/// v1 uses the first curve controller for the fan it manages.
const CURVE_SLOT: usize = 1;

/// The smallest controller output the device accepts without treating it as
/// "off" (0.01 %), so a curve that reaches its floor never stops the fan.
const MIN_OUTPUT_HUNDREDTHS: i64 = 1;
const FULL_OUTPUT_HUNDREDTHS: i64 = 10_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Change {
    pub name: String,
    pub old: String,
    pub new: String,
    /// The byte positions this change touches.
    pub positions: Vec<Range<usize>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub changes: Vec<Change>,
    /// True when every byte outside the changes is as it was.
    pub untouched_equal: bool,
    /// True when the device already holds this state: no changes, no write.
    pub already_applied: bool,
    /// The whole configuration to write.
    pub intended: ConfigBytes,
}

pub fn build_plan(
    snapshot: &ConfigBytes,
    desired: &FanCurve,
    profile: &Profile,
) -> Result<Plan, PlanError> {
    let on_profile = |source| PlanError::Profile { source };
    desired
        .validate(profile.curve_points())
        .map_err(|source| PlanError::Curve { source })?;

    let fan = desired.fan;
    let fan_offsets = profile.fan_offsets(fan).map_err(on_profile)?;
    let fan_now = profile.fan_settings(snapshot, fan).map_err(on_profile)?;
    let curve_offsets = profile.curve_offsets(CURVE_SLOT).map_err(on_profile)?;
    let curve_now = profile
        .curve_settings(snapshot, CURVE_SLOT)
        .map_err(on_profile)?;
    let curve_source = profile.curve_source(CURVE_SLOT).map_err(on_profile)?;
    let sensor_source = profile.sensor_source(desired.sensor).map_err(on_profile)?;

    // Do not take a curve controller away from another fan.
    for other in 1..=profile.fan_count() {
        if other == fan {
            continue;
        }
        let settings = profile.fan_settings(snapshot, other).map_err(on_profile)?;
        if settings.source == curve_source {
            return Err(PlanError::CurveInUse {
                slot: CURVE_SLOT,
                fan: other,
            });
        }
    }

    // The fan's own range is what the controller's 0 to 100 % maps onto.
    let min = to_hundredths(desired.min_percent);
    let max = i64::from(fan_now.max_hundredths);
    if max <= min {
        return Err(PlanError::NoFanRange {
            min: desired.min_percent,
            max: hundredths_to_percent(max),
        });
    }
    for (index, point) in desired.points.iter().enumerate() {
        if to_hundredths(point.percent) > max {
            return Err(PlanError::PercentAboveFanMaximum {
                index,
                value: point.percent,
                max: hundredths_to_percent(max),
            });
        }
    }

    let expanded = desired
        .expand(profile.curve_points())
        .map_err(|source| PlanError::Curve { source })?;
    let temperatures: Vec<u16> = expanded.iter().map(|(temp, _)| clamp_u16(*temp)).collect();
    let outputs: Vec<u16> = expanded
        .iter()
        .map(|(_, percent)| clamp_u16(output_for(*percent, min, max)))
        .collect();

    // Build the intended bytes.
    let mut bytes = snapshot.as_slice().to_vec();
    let put = |bytes: &mut [u8], offset: usize, value: u16| -> Result<(), PlanError> {
        let end = offset.checked_add(2).ok_or(PlanError::Profile {
            source: ProfileError::OutOfRange { offset },
        })?;
        match bytes.get_mut(offset..end) {
            Some([hi, lo]) => {
                let [a, b] = value.to_be_bytes();
                *hi = a;
                *lo = b;
                Ok(())
            }
            _ => Err(PlanError::Profile {
                source: ProfileError::OutOfRange { offset },
            }),
        }
    };
    let min_value = clamp_u16(min);
    // Hold minimum power: the fan never switches off. Other flags stay as they are.
    let flags_now = snapshot
        .as_slice()
        .get(fan_offsets.settings)
        .copied()
        .ok_or(PlanError::Profile {
            source: ProfileError::OutOfRange {
                offset: fan_offsets.settings,
            },
        })?;
    let flags_new = flags_now | profile.hold_min_power_flag();
    if let Some(byte) = bytes.get_mut(fan_offsets.settings) {
        *byte = flags_new;
    }
    put(&mut bytes, fan_offsets.min, min_value)?;
    put(&mut bytes, fan_offsets.source, curve_source)?;
    put(&mut bytes, curve_offsets.source, sensor_source)?;
    put(&mut bytes, curve_offsets.start, 0)?;
    for (index, value) in temperatures.iter().enumerate() {
        put(
            &mut bytes,
            nth_u16(curve_offsets.temperatures, index),
            *value,
        )?;
    }
    for (index, value) in outputs.iter().enumerate() {
        put(&mut bytes, nth_u16(curve_offsets.outputs, index), *value)?;
    }
    let intended = ConfigBytes::new(bytes).map_err(|_| PlanError::Profile {
        source: ProfileError::OutOfRange { offset: 0 },
    })?;

    // Describe what changed.
    let mut changes = Vec::new();
    let mut add = |name: String, old: String, new: String, positions: Vec<Range<usize>>| {
        if old != new {
            changes.push(Change {
                name,
                old,
                new,
                positions,
            });
        }
    };
    add(
        format!("fan {fan} minimum power"),
        percent_text(i64::from(fan_now.min_hundredths)),
        percent_text(min),
        vec![span(fan_offsets.min, 2)],
    );
    add(
        format!("fan {fan} hold minimum power"),
        on_off(fan_now.hold_min_power),
        on_off(true),
        vec![span(fan_offsets.settings, 1)],
    );
    add(
        format!("fan {fan} controller"),
        profile.describe_source(fan_now.source),
        profile.describe_source(curve_source),
        vec![span(fan_offsets.source, 2)],
    );
    add(
        format!("curve controller {CURVE_SLOT} data source"),
        profile.describe_source(curve_now.source),
        profile.describe_source(sensor_source),
        vec![span(curve_offsets.source, 2)],
    );
    add(
        format!("curve controller {CURVE_SLOT} start temperature"),
        temperature_text(i64::from(curve_now.start_hundredths)),
        temperature_text(0),
        vec![span(curve_offsets.start, 2)],
    );
    add(
        format!("curve controller {CURVE_SLOT} points"),
        points_text(
            &curve_now.temperatures_hundredths,
            &curve_now.outputs_hundredths,
        ),
        points_text(&temperatures, &outputs),
        vec![
            span(
                curve_offsets.temperatures,
                temperatures.len().saturating_mul(2),
            ),
            span(curve_offsets.outputs, outputs.len().saturating_mul(2)),
        ],
    );

    let untouched_equal = diff(snapshot, &intended, &VolatileSet::none())
        .iter()
        .all(|run| {
            (run.offset..run.offset.saturating_add(run.before.len())).all(|at| {
                changes
                    .iter()
                    .any(|change| change.positions.iter().any(|range| range.contains(&at)))
            })
        });

    Ok(Plan {
        already_applied: changes.is_empty(),
        changes,
        untouched_equal,
        intended,
    })
}

/// The controller output (hundredths of a percent) that makes the fan run at
/// `percent` (hundredths): the fan's min to max range is spread over the
/// controller's 0 to 100 %. Never 0, which would let the fan switch off.
fn output_for(percent: i64, min: i64, max: i64) -> i64 {
    let range = (max.saturating_sub(min)) as f64;
    let output = ((percent.saturating_sub(min)) as f64 / range * FULL_OUTPUT_HUNDREDTHS as f64)
        .round() as i64;
    output.clamp(MIN_OUTPUT_HUNDREDTHS, FULL_OUTPUT_HUNDREDTHS)
}

fn to_hundredths(value: f64) -> i64 {
    (value * 100.0).round() as i64
}

fn hundredths_to_percent(value: i64) -> f64 {
    value as f64 / 100.0
}

fn clamp_u16(value: i64) -> u16 {
    u16::try_from(value.clamp(0, i64::from(u16::MAX))).unwrap_or(u16::MAX)
}

fn nth_u16(first: usize, index: usize) -> usize {
    first.saturating_add(index.saturating_mul(2))
}

fn span(start: usize, len: usize) -> Range<usize> {
    start..start.saturating_add(len)
}

fn on_off(value: bool) -> String {
    if value { "on" } else { "off" }.to_string()
}

fn percent_text(hundredths: i64) -> String {
    format!("{:.2} %", hundredths_to_percent(hundredths))
}

fn temperature_text(hundredths: i64) -> String {
    format!("{:.2} °C", hundredths as f64 / 100.0)
}

fn points_text(temperatures: &[u16], outputs: &[u16]) -> String {
    temperatures
        .iter()
        .zip(outputs)
        .map(|(t, o)| {
            format!(
                "{} -> {}",
                temperature_text(i64::from(*t)),
                percent_text(i64::from(*o))
            )
        })
        .collect::<Vec<_>>()
        .join(", ")
}

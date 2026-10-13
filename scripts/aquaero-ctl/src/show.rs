//! The in-scope settings of a stored configuration, for the `show` command.

use std::fmt::Write as _;

use serde_json::{json, Value};

use crate::error::ProfileError;
use crate::identity::data_version;
use crate::profile::Profile;
use crate::snapshot::ConfigBytes;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShownFan {
    pub fan: usize,
    pub min_hundredths: u16,
    pub max_hundredths: u16,
    pub controller: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShownCurve {
    pub slot: usize,
    pub data_source: String,
    pub start_hundredths: u16,
    /// (temperature, controller output), both in hundredths.
    pub points: Vec<(u16, u16)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Shown {
    pub data_version: u32,
    pub verified_firmware: u32,
    pub fans: Vec<ShownFan>,
    pub curves: Vec<ShownCurve>,
}

/// Decodes every fan and curve slot the configuration's own profile knows.
pub fn show(config: &ConfigBytes) -> Result<Shown, ProfileError> {
    let profile = Profile::for_data_version(data_version(config))?;
    let fans = (1..=profile.fan_count())
        .map(|fan| {
            let s = profile.fan_settings(config, fan)?;
            Ok(ShownFan {
                fan,
                min_hundredths: s.min_hundredths,
                max_hundredths: s.max_hundredths,
                controller: profile.describe_source(s.source),
            })
        })
        .collect::<Result<Vec<_>, ProfileError>>()?;
    let curves = (1..=profile.curve_slots())
        .map(|slot| {
            let s = profile.curve_settings(config, slot)?;
            Ok(ShownCurve {
                slot,
                data_source: profile.describe_source(s.source),
                start_hundredths: s.start_hundredths,
                points: s
                    .temperatures_hundredths
                    .into_iter()
                    .zip(s.outputs_hundredths)
                    .collect(),
            })
        })
        .collect::<Result<Vec<_>, ProfileError>>()?;
    Ok(Shown {
        data_version: profile.data_version(),
        verified_firmware: profile.firmware(),
        fans,
        curves,
    })
}

fn units(hundredths: u16) -> f64 {
    f64::from(hundredths) / 100.0
}

pub fn render_text(shown: &Shown) -> String {
    let mut out = String::new();
    // Writing to a String cannot fail.
    let _ = writeln!(
        out,
        "data version {} (layout verified on firmware {})",
        shown.data_version, shown.verified_firmware
    );
    for fan in &shown.fans {
        let _ = writeln!(
            out,
            "fan {}: minimum {:.2} %, maximum {:.2} %, controller: {}",
            fan.fan,
            units(fan.min_hundredths),
            units(fan.max_hundredths),
            fan.controller
        );
    }
    for curve in &shown.curves {
        let _ = writeln!(
            out,
            "curve controller {}: data source: {}, start {:.2} °C",
            curve.slot,
            curve.data_source,
            units(curve.start_hundredths)
        );
        for (temperature, output) in &curve.points {
            let _ = writeln!(
                out,
                "  {:.2} °C -> {:.2} %",
                units(*temperature),
                units(*output)
            );
        }
    }
    out
}

pub fn to_json(shown: &Shown) -> Value {
    let fans: Vec<Value> = shown
        .fans
        .iter()
        .map(|fan| {
            json!({
                "fan": fan.fan,
                "min_percent": units(fan.min_hundredths),
                "max_percent": units(fan.max_hundredths),
                "controller": fan.controller,
            })
        })
        .collect();
    let curves: Vec<Value> = shown
        .curves
        .iter()
        .map(|curve| {
            let points: Vec<Value> = curve
                .points
                .iter()
                .map(|(t, o)| json!({"temperature": units(*t), "output_percent": units(*o)}))
                .collect();
            json!({
                "slot": curve.slot,
                "data_source": curve.data_source,
                "start_temperature": units(curve.start_hundredths),
                "points": points,
            })
        })
        .collect();
    json!({
        "data_version": shown.data_version,
        "verified_firmware": shown.verified_firmware,
        "fans": fans,
        "curves": curves,
    })
}

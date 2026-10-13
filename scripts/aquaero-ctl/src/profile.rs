//! What is stored where, for one firmware's configuration layout.
//!
//! A profile is data (`profiles/<version>.toml`), embedded in the binary and
//! added only once its layout has been verified on a real device. A device
//! whose version has no profile cannot be written.

use std::time::Duration;

use serde::Deserialize;

use crate::apply::CommitReport;
use crate::error::ProfileError;
use crate::snapshot::ConfigBytes;

/// The source value meaning "nothing drives this".
pub const NO_SOURCE: u16 = 0xffff;

const BUILTIN: &[&str] = &[include_str!("../profiles/1200.toml")];

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct FanLayout {
    base: usize,
    stride: usize,
    count: usize,
    min_offset: usize,
    max_offset: usize,
    source_offset: usize,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct CurveLayout {
    base: usize,
    stride: usize,
    slots: usize,
    points: usize,
    source_offset: usize,
    start_offset: usize,
    temperatures_offset: usize,
    outputs_offset: usize,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Sources {
    sensor_base: u16,
    sensor_count: u16,
    curve_base: u16,
    curve_count: u16,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct CommitSpec {
    bytes: Vec<u8>,
    delay_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    data_version: u32,
    firmware: u32,
    verified_on: Vec<String>,
    fan: FanLayout,
    curve: CurveLayout,
    sources: Sources,
    #[serde(default)]
    commit: Vec<CommitSpec>,
}

/// Where one fan's fields sit in the configuration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FanOffsets {
    pub min: usize,
    pub max: usize,
    pub source: usize,
}

/// Where one curve controller's fields sit in the configuration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CurveOffsets {
    pub source: usize,
    pub start: usize,
    /// Position of the first temperature; each is a u16.
    pub temperatures: usize,
    /// Position of the first output; each is a u16.
    pub outputs: usize,
    pub points: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FanSettings {
    pub source: u16,
    pub min_hundredths: u16,
    pub max_hundredths: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CurveSettings {
    pub source: u16,
    pub start_hundredths: u16,
    pub temperatures_hundredths: Vec<u16>,
    pub outputs_hundredths: Vec<u16>,
}

impl Profile {
    /// Parses and checks one profile document.
    pub fn from_toml(text: &str) -> Result<Self, ProfileError> {
        let profile: Self =
            toml::from_str(text).map_err(|source| ProfileError::Parse { source })?;
        profile.check()?;
        Ok(profile)
    }

    /// The profile for a configuration data version.
    pub fn for_data_version(version: u32) -> Result<Self, ProfileError> {
        BUILTIN
            .iter()
            .filter_map(|text| Self::from_toml(text).ok())
            .find(|profile| profile.data_version == version)
            .ok_or_else(|| ProfileError::UnknownVersion {
                version,
                known: Self::known_versions(),
            })
    }

    pub fn known_versions() -> Vec<u32> {
        let mut versions: Vec<u32> = BUILTIN
            .iter()
            .filter_map(|text| Self::from_toml(text).ok())
            .map(|profile| profile.data_version)
            .collect();
        versions.sort_unstable();
        versions
    }

    pub fn data_version(&self) -> u32 {
        self.data_version
    }

    /// The firmware this layout was verified on.
    pub fn firmware(&self) -> u32 {
        self.firmware
    }

    pub fn verified_on(&self) -> &[String] {
        &self.verified_on
    }

    /// Reports to send after the configuration, each after its own delay.
    pub fn commit_reports(&self) -> Vec<CommitReport> {
        self.commit
            .iter()
            .map(|spec| CommitReport {
                bytes: spec.bytes.clone(),
                delay_before: Duration::from_millis(spec.delay_ms),
            })
            .collect()
    }

    pub fn fan_count(&self) -> usize {
        self.fan.count
    }

    pub fn curve_slots(&self) -> usize {
        self.curve.slots
    }

    pub fn curve_points(&self) -> usize {
        self.curve.points
    }

    /// Absolute positions of fan `fan` (1-based).
    pub fn fan_offsets(&self, fan: usize) -> Result<FanOffsets, ProfileError> {
        let layout = &self.fan;
        let start =
            nth(layout.base, layout.stride, fan, layout.count).ok_or(ProfileError::NoSuchFan {
                fan,
                count: layout.count,
            })?;
        let at = |field: usize| {
            start
                .checked_add(field)
                .ok_or(ProfileError::OutOfRange { offset: field })
        };
        Ok(FanOffsets {
            min: at(layout.min_offset)?,
            max: at(layout.max_offset)?,
            source: at(layout.source_offset)?,
        })
    }

    /// Absolute positions of curve controller `slot` (1-based).
    pub fn curve_offsets(&self, slot: usize) -> Result<CurveOffsets, ProfileError> {
        let layout = &self.curve;
        let start = nth(layout.base, layout.stride, slot, layout.slots).ok_or(
            ProfileError::NoSuchCurve {
                slot,
                count: layout.slots,
            },
        )?;
        let at = |field: usize| {
            start
                .checked_add(field)
                .ok_or(ProfileError::OutOfRange { offset: field })
        };
        Ok(CurveOffsets {
            source: at(layout.source_offset)?,
            start: at(layout.start_offset)?,
            temperatures: at(layout.temperatures_offset)?,
            outputs: at(layout.outputs_offset)?,
            points: layout.points,
        })
    }

    /// The source number of temperature sensor `sensor` (1-based).
    pub fn sensor_source(&self, sensor: usize) -> Result<u16, ProfileError> {
        let count = usize::from(self.sources.sensor_count);
        source_number(self.sources.sensor_base, sensor, count)
            .ok_or(ProfileError::NoSuchSensor { sensor, count })
    }

    /// The source number of curve controller `slot` (1-based).
    pub fn curve_source(&self, slot: usize) -> Result<u16, ProfileError> {
        let count = usize::from(self.sources.curve_count);
        source_number(self.sources.curve_base, slot, count)
            .ok_or(ProfileError::NoSuchCurve { slot, count })
    }

    pub fn fan_settings(
        &self,
        config: &ConfigBytes,
        fan: usize,
    ) -> Result<FanSettings, ProfileError> {
        let offsets = self.fan_offsets(fan)?;
        Ok(FanSettings {
            source: be16(config, offsets.source)?,
            min_hundredths: be16(config, offsets.min)?,
            max_hundredths: be16(config, offsets.max)?,
        })
    }

    pub fn curve_settings(
        &self,
        config: &ConfigBytes,
        slot: usize,
    ) -> Result<CurveSettings, ProfileError> {
        let offsets = self.curve_offsets(slot)?;
        let series = |first: usize| -> Result<Vec<u16>, ProfileError> {
            (0..offsets.points)
                .map(|point| {
                    let at = point
                        .checked_mul(2)
                        .and_then(|delta| first.checked_add(delta))
                        .ok_or(ProfileError::OutOfRange { offset: first })?;
                    be16(config, at)
                })
                .collect()
        };
        Ok(CurveSettings {
            source: be16(config, offsets.source)?,
            start_hundredths: be16(config, offsets.start)?,
            temperatures_hundredths: series(offsets.temperatures)?,
            outputs_hundredths: series(offsets.outputs)?,
        })
    }

    /// A profile must describe positions that fit in the report.
    fn check(&self) -> Result<(), ProfileError> {
        let invalid = |reason: &str| ProfileError::Invalid {
            reason: reason.to_string(),
        };
        if self.fan.count == 0 || self.curve.slots == 0 || self.curve.points < 2 {
            return Err(invalid(
                "fan count, curve slots and curve points must be positive",
            ));
        }
        for fan in 1..=self.fan.count {
            let o = self.fan_offsets(fan)?;
            for field in [o.min, o.max, o.source] {
                if field.saturating_add(2) > crate::snapshot::CONFIG_LEN {
                    return Err(invalid("a fan field lies past the end of the report"));
                }
            }
        }
        for slot in 1..=self.curve.slots {
            let o = self.curve_offsets(slot)?;
            let last_output = o.points.saturating_mul(2).saturating_add(o.outputs);
            if last_output > crate::snapshot::CONFIG_LEN {
                return Err(invalid(
                    "a curve controller lies past the end of the report",
                ));
            }
        }
        for spec in &self.commit {
            if spec.bytes.is_empty() {
                return Err(invalid("a commit report is empty"));
            }
        }
        Ok(())
    }
}

/// The start of the `index`th (1-based) of `count` records.
fn nth(base: usize, stride: usize, index: usize, count: usize) -> Option<usize> {
    if index == 0 || index > count {
        return None;
    }
    index
        .checked_sub(1)
        .and_then(|zero_based| zero_based.checked_mul(stride))
        .and_then(|delta| base.checked_add(delta))
}

fn source_number(base: u16, index: usize, count: usize) -> Option<u16> {
    if index == 0 || index > count {
        return None;
    }
    let zero_based = u16::try_from(index.checked_sub(1)?).ok()?;
    base.checked_add(zero_based)
}

fn be16(config: &ConfigBytes, offset: usize) -> Result<u16, ProfileError> {
    let bytes = config.as_slice();
    let end = offset
        .checked_add(2)
        .ok_or(ProfileError::OutOfRange { offset })?;
    match bytes.get(offset..end) {
        Some([hi, lo]) => Ok(u16::from_be_bytes([*hi, *lo])),
        _ => Err(ProfileError::OutOfRange { offset }),
    }
}

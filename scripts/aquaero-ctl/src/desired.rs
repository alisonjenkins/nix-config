//! The desired-state file the NixOS module renders to JSON.

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::curve::{FanCurve, Point};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    #[default]
    Apply,
    Check,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DesiredFan {
    pub sensor: usize,
    pub min_percent: f64,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DesiredState {
    /// `None` means the only aquaero present.
    #[serde(default)]
    pub device_serial: Option<String>,
    #[serde(default)]
    pub mode: Mode,
    /// Key is the fan number as a string.
    pub fans: BTreeMap<String, DesiredFan>,
}

#[derive(Debug, thiserror::Error)]
pub enum DesiredError {
    #[error("desired state is not valid: {source}")]
    Parse { source: serde_json::Error },
    #[error("desired state has no fans")]
    NoFans,
    #[error("desired state has {count} fans, v1 manages exactly one")]
    MoreThanOneFan { count: usize },
    #[error("fan key {key:?} is not a positive integer")]
    BadFanKey { key: String },
}

impl DesiredState {
    pub fn from_json(text: &str) -> Result<Self, DesiredError> {
        serde_json::from_str(text).map_err(|source| DesiredError::Parse { source })
    }

    /// The single fan curve in the state, with the fan number taken from its key.
    pub fn curve(&self) -> Result<FanCurve, DesiredError> {
        let mut entries = self.fans.iter();
        let Some((key, fan)) = entries.next() else {
            return Err(DesiredError::NoFans);
        };
        if entries.next().is_some() {
            return Err(DesiredError::MoreThanOneFan {
                count: self.fans.len(),
            });
        }
        let number = match key.parse::<usize>() {
            Ok(n) if n > 0 => n,
            _ => return Err(DesiredError::BadFanKey { key: key.clone() }),
        };
        Ok(FanCurve {
            fan: number,
            sensor: fan.sensor,
            min_percent: fan.min_percent,
            points: fan.points.clone(),
        })
    }
}

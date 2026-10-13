//! A fan speed curve driven by a temperature, and the checks it must pass
//! before anything touches the device.

use serde::Deserialize;

use crate::error::CurveError;

/// v1 drives the radiator fans (fan 4) from the coolant sensor (Sensor 1).
pub const SUPPORTED_FAN: usize = 4;
pub const SUPPORTED_SENSOR: usize = 1;

/// Highest temperature a curve may use. The device's own limit is not known;
/// this keeps values in a range that makes sense for coolant.
const MAX_TEMP: f64 = 100.0;

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Point {
    /// Degrees Celsius.
    pub temp: f64,
    /// Fan speed, percent.
    pub percent: f64,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FanCurve {
    pub fan: usize,
    pub sensor: usize,
    /// The floor: the fans never run slower than this.
    pub min_percent: f64,
    pub points: Vec<Point>,
}

impl FanCurve {
    /// Checks the curve against the rules in the data model. `max_points` is
    /// how many points the device holds. Every failure names the value.
    pub fn validate(&self, max_points: usize) -> Result<(), CurveError> {
        if self.fan != SUPPORTED_FAN {
            return Err(CurveError::FanNotSupported { fan: self.fan });
        }
        if self.sensor != SUPPORTED_SENSOR {
            return Err(CurveError::SensorNotSupported {
                sensor: self.sensor,
            });
        }
        finite("the minimum percent", self.min_percent)?;
        if !(0.0..=100.0).contains(&self.min_percent) {
            return Err(CurveError::MinPercentOutOfRange {
                value: self.min_percent,
            });
        }
        let count = self.points.len();
        if count < 2 {
            return Err(CurveError::TooFewPoints { count });
        }
        if count > max_points {
            return Err(CurveError::TooManyPoints {
                count,
                max: max_points,
            });
        }

        let mut previous: Option<Point> = None;
        for (index, point) in self.points.iter().enumerate() {
            finite("a temperature", point.temp)?;
            finite("a percent", point.percent)?;
            if !(0.0..=MAX_TEMP).contains(&point.temp) {
                return Err(CurveError::TemperatureOutOfRange {
                    index,
                    value: point.temp,
                });
            }
            if !(0.0..=100.0).contains(&point.percent) {
                return Err(CurveError::PercentOutOfRange {
                    index,
                    value: point.percent,
                });
            }
            if point.percent < self.min_percent {
                return Err(CurveError::PercentBelowMinimum {
                    index,
                    value: point.percent,
                    min: self.min_percent,
                });
            }
            if let Some(before) = previous {
                if hundredths(point.temp) <= hundredths(before.temp) {
                    return Err(CurveError::TemperaturesNotIncreasing {
                        index,
                        previous: before.temp,
                        value: point.temp,
                    });
                }
                if point.percent < before.percent {
                    return Err(CurveError::PercentDecreases {
                        index,
                        previous: before.percent,
                        value: point.percent,
                    });
                }
            }
            previous = Some(*point);
        }
        Ok(())
    }

    /// The curve as exactly `count` points, `(temperature, percent)` in
    /// hundredths, strictly increasing in temperature. The device holds a
    /// fixed number of points, so extra points are placed on the straight
    /// lines between the given ones: the shape does not change.
    pub fn expand(&self, count: usize) -> Result<Vec<(i64, i64)>, CurveError> {
        let mut points: Vec<(i64, i64)> = self
            .points
            .iter()
            .map(|p| (hundredths(p.temp), hundredths(p.percent)))
            .collect();
        while points.len() < count {
            // Split the widest gap in half.
            let widest = points
                .windows(2)
                .enumerate()
                .filter_map(|(index, pair)| match pair {
                    [a, b] => Some((index, *a, *b)),
                    _ => None,
                })
                .max_by_key(|(_, a, b)| b.0.saturating_sub(a.0));
            let Some((index, a, b)) = widest else {
                return Err(CurveError::CannotExpand { count });
            };
            let gap = b.0.saturating_sub(a.0);
            if gap < 2 {
                return Err(CurveError::CannotExpand { count });
            }
            let temp = a.0.saturating_add(gap.saturating_div(2));
            // Read the value off the original curve, not from the rounded
            // neighbours, so rounding errors do not add up.
            let percent = hundredths(self.percent_at(temp as f64 / 100.0));
            points.insert(index.saturating_add(1), (temp, percent.clamp(a.1, b.1)));
        }
        Ok(points)
    }

    /// The speed the curve asks for at `temp`: straight lines between the
    /// points, and the end values beyond them.
    pub fn percent_at(&self, temp: f64) -> f64 {
        let (Some(first), Some(last)) = (self.points.first(), self.points.last()) else {
            return 0.0;
        };
        if temp <= first.temp {
            return first.percent;
        }
        if temp >= last.temp {
            return last.percent;
        }
        for pair in self.points.windows(2) {
            if let [a, b] = pair {
                if temp >= a.temp && temp <= b.temp {
                    let span = b.temp - a.temp;
                    if span <= 0.0 {
                        return a.percent;
                    }
                    return a.percent + (b.percent - a.percent) * (temp - a.temp) / span;
                }
            }
        }
        last.percent
    }
}

fn hundredths(value: f64) -> i64 {
    (value * 100.0).round() as i64
}

fn finite(what: &'static str, value: f64) -> Result<(), CurveError> {
    if value.is_finite() {
        Ok(())
    } else {
        Err(CurveError::NotFinite { what, value })
    }
}

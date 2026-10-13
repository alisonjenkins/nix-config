//! Finding the aquaero's `hidraw` nodes through sysfs.
//!
//! One physical aquaero can show up as several nodes (one per HID interface),
//! and which of them carries the configuration report is settled by trying
//! each, not by looking at sysfs. So this module returns every node of the
//! chosen device and leaves the probing to the caller.

use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::error::SelectError;
use crate::hid::{PRODUCT_ID, VENDOR_ID};

/// One `/dev/hidrawN` node that belongs to an aquaero.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HidrawNode {
    pub dev_path: PathBuf,
    pub number: u32,
    /// The USB serial string the device reports, if it reports one.
    pub serial: Option<String>,
    /// The USB port path, e.g. `usb-0000:00:14.0-3/input0`.
    pub phys: String,
}

impl HidrawNode {
    /// What names this node's physical device: its serial, else its USB port.
    fn device_label(&self) -> String {
        match &self.serial {
            Some(serial) => serial.clone(),
            None => self
                .phys
                .split('/')
                .next()
                .unwrap_or(&self.phys)
                .to_string(),
        }
    }
}

/// Every aquaero node under `<sysfs_root>/class/hidraw`, ordered by node
/// number. `dev_dir` is where the `hidrawN` device files live (`/dev`).
/// A system with no hidraw class at all simply has no aquaero.
pub fn discover(sysfs_root: &Path, dev_dir: &Path) -> Result<Vec<HidrawNode>, SelectError> {
    let class = sysfs_root.join("class/hidraw");
    let entries = match fs::read_dir(&class) {
        Ok(entries) => entries,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(source) => {
            return Err(SelectError::Sysfs {
                path: class,
                source,
            })
        }
    };

    let mut nodes = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|source| SelectError::Sysfs {
            path: class.clone(),
            source,
        })?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let Some(number) = name
            .strip_prefix("hidraw")
            .and_then(|n| n.parse::<u32>().ok())
        else {
            continue;
        };

        let uevent_path = entry.path().join("device/uevent");
        let uevent = match fs::read_to_string(&uevent_path) {
            Ok(text) => text,
            // The node can vanish between listing and reading (unplug).
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(source) => {
                return Err(SelectError::Sysfs {
                    path: uevent_path,
                    source,
                })
            }
        };

        if let Some(node) = parse_uevent(&uevent, number, dev_dir) {
            nodes.push(node);
        }
    }
    nodes.sort_by_key(|n| n.number);
    Ok(nodes)
}

fn parse_uevent(uevent: &str, number: u32, dev_dir: &Path) -> Option<HidrawNode> {
    let mut hid_id = None;
    let mut phys = String::new();
    let mut serial = None;
    for line in uevent.lines() {
        match line.split_once('=') {
            Some(("HID_ID", v)) => hid_id = Some(v),
            Some(("HID_PHYS", v)) => phys = v.to_string(),
            Some(("HID_UNIQ", v)) if !v.is_empty() => serial = Some(v.to_string()),
            _ => {}
        }
    }

    // HID_ID is `bus:vendor:product`, each in hex.
    let mut ids = hid_id?.split(':').skip(1);
    let vendor = u32::from_str_radix(ids.next()?, 16).ok()?;
    let product = u32::from_str_radix(ids.next()?, 16).ok()?;
    if vendor != u32::from(VENDOR_ID) || product != u32::from(PRODUCT_ID) {
        return None;
    }

    Some(HidrawNode {
        dev_path: dev_dir.join(format!("hidraw{number}")),
        number,
        serial,
        phys,
    })
}

/// Narrows nodes to one physical device: all of them if only one device is
/// present, or those with `serial` when given. Several devices and no serial
/// is an error rather than a guess.
pub fn choose(
    nodes: Vec<HidrawNode>,
    serial: Option<&str>,
) -> Result<Vec<HidrawNode>, SelectError> {
    if nodes.is_empty() {
        return Err(SelectError::Absent);
    }
    let present: Vec<String> = nodes
        .iter()
        .map(HidrawNode::device_label)
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();

    match serial {
        Some(wanted) => {
            let matching: Vec<HidrawNode> = nodes
                .into_iter()
                .filter(|n| n.serial.as_deref() == Some(wanted))
                .collect();
            if matching.is_empty() {
                return Err(SelectError::SerialNotFound {
                    wanted: wanted.to_string(),
                    present,
                });
            }
            Ok(matching)
        }
        None if present.len() > 1 => Err(SelectError::Ambiguous { devices: present }),
        None => Ok(nodes),
    }
}

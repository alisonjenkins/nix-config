//! The whole sequence for one desired curve: read the device, check a profile
//! exists for its configuration, validate and plan, then either report the
//! drift (check mode) or back up, write, save and read back.

use std::path::Path;

use crate::apply::{apply_config, ApplyOptions, ApplyReport};
use crate::curve::FanCurve;
use crate::error::{ApplyError, HidError, PlanError, ProfileError};
use crate::hid::{read_config, HidDevice};
use crate::identity;
use crate::plan::{build_plan, Plan};
use crate::profile::Profile;
use crate::snapshot::SnapshotPaths;
use crate::timestamp::UtcTimestamp;

/// Which layout was used, for the report the owner sees.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProfileInfo {
    pub data_version: u32,
    pub firmware: u32,
}

#[derive(Debug)]
pub enum Outcome {
    /// The device already holds the desired state; nothing was written.
    AlreadyApplied { profile: ProfileInfo },
    /// Check mode found differences and wrote nothing.
    Drift { profile: ProfileInfo, plan: Plan },
    /// The change was backed up, written, saved and read back.
    Applied {
        profile: ProfileInfo,
        plan: Plan,
        backup: SnapshotPaths,
    },
}

#[derive(Debug, thiserror::Error)]
pub enum WorkflowError {
    #[error("cannot read the device's configuration")]
    Read {
        #[source]
        source: HidError,
    },

    #[error("this device's configuration cannot be written by this version")]
    NoProfile {
        #[source]
        source: ProfileError,
    },

    #[error("the desired state cannot be applied to this device")]
    Plan {
        #[source]
        source: PlanError,
    },

    #[error("the change could not be completed")]
    Apply {
        #[source]
        source: ApplyError,
    },
}

/// Reads the device and plans the change. Writes nothing.
pub fn plan_for_device(
    device: &mut dyn HidDevice,
    curve: &FanCurve,
) -> Result<(Profile, Plan), WorkflowError> {
    let config = read_config(device).map_err(|source| WorkflowError::Read { source })?;
    let profile = Profile::for_data_version(identity::data_version(&config))
        .map_err(|source| WorkflowError::NoProfile { source })?;
    let plan =
        build_plan(&config, curve, &profile).map_err(|source| WorkflowError::Plan { source })?;
    Ok((profile, plan))
}

/// Plans, and unless `check` is set, makes the device match. In check mode
/// nothing is written and no backup is made.
pub fn apply_desired(
    device: &mut dyn HidDevice,
    curve: &FanCurve,
    check: bool,
    backup_dir: &Path,
    now: UtcTimestamp,
) -> Result<Outcome, WorkflowError> {
    let (profile, plan) = plan_for_device(device, curve)?;
    let info = ProfileInfo {
        data_version: profile.data_version(),
        firmware: profile.firmware(),
    };

    if plan.already_applied {
        return Ok(Outcome::AlreadyApplied { profile: info });
    }
    if check {
        return Ok(Outcome::Drift {
            profile: info,
            plan,
        });
    }

    let options = ApplyOptions {
        backup_dir: backup_dir.to_path_buf(),
        commit_reports: profile.commit_reports(),
    };
    match apply_config(device, &plan.intended, &options, now)
        .map_err(|source| WorkflowError::Apply { source })?
    {
        ApplyReport::AlreadyApplied => Ok(Outcome::AlreadyApplied { profile: info }),
        ApplyReport::Applied { backup, .. } => Ok(Outcome::Applied {
            profile: info,
            plan,
            backup,
        }),
    }
}

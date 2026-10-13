// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

// The real device cannot be exercised without hardware. These cover what can
// be: the open error, and the ioctl call and its error mapping, using a file
// that rejects the HID ioctls.

use std::path::Path;

use aquaero_ctl::error::HidError;
use aquaero_ctl::hid::{HidDevice, CTRL_REPORT_ID};
use aquaero_ctl::hidraw::HidrawDevice;

#[test]
fn opening_a_missing_node_names_the_path() {
    let path = Path::new("/dev/no-such-hidraw-node");
    let err = HidrawDevice::open(path).unwrap_err();
    assert!(
        matches!(&err, HidError::Open { path: p, .. } if p == path),
        "{err:?}"
    );
}

#[test]
fn the_open_error_keeps_the_os_error_kind() {
    let err = HidrawDevice::open(Path::new("/dev/no-such-hidraw-node")).unwrap_err();
    match err {
        HidError::Open { source, .. } => assert_eq!(source.kind(), std::io::ErrorKind::NotFound),
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_node_that_rejects_the_ioctl_gives_a_read_error_naming_the_report() {
    let mut dev = HidrawDevice::open(Path::new("/dev/null")).unwrap();
    let err = dev.get_feature(CTRL_REPORT_ID, 16).unwrap_err();
    assert!(
        matches!(&err, HidError::GetFeature { report_id, path, .. }
            if *report_id == CTRL_REPORT_ID && path == Path::new("/dev/null")),
        "{err:?}"
    );
}

#[test]
fn a_node_that_rejects_the_ioctl_gives_a_write_error_with_the_length() {
    let mut dev = HidrawDevice::open(Path::new("/dev/null")).unwrap();
    let err = dev.set_feature(&[CTRL_REPORT_ID, 1, 2, 3]).unwrap_err();
    assert!(
        matches!(&err, HidError::SetFeature { report_id, len: 4, .. } if *report_id == CTRL_REPORT_ID),
        "{err:?}"
    );
}

#[test]
fn the_path_is_the_one_opened() {
    let dev = HidrawDevice::open(Path::new("/dev/null")).unwrap();
    assert_eq!(dev.path(), Path::new("/dev/null"));
}

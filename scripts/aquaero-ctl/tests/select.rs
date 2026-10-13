// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use std::fs;
use std::path::{Path, PathBuf};

use aquaero_ctl::error::SelectError;
use aquaero_ctl::select::{choose, discover, HidrawNode};

const AQUAERO: &str = "0003:00000C70:0000F001";
const OTHER: &str = "0003:000026CE:000001A2";

struct Sysfs {
    root: tempfile::TempDir,
}

impl Sysfs {
    fn new() -> Self {
        Self {
            root: tempfile::tempdir().unwrap(),
        }
    }

    fn root(&self) -> &Path {
        self.root.path()
    }

    fn dev(&self) -> PathBuf {
        PathBuf::from("/dev")
    }

    /// One `/sys/class/hidraw/hidrawN` node with the uevent the kernel writes.
    fn node(&self, n: u32, hid_id: &str, phys: &str, uniq: Option<&str>) {
        let dir = self.root().join(format!("class/hidraw/hidraw{n}/device"));
        fs::create_dir_all(&dir).unwrap();
        let mut uevent =
            format!("DRIVER=hid-generic\nHID_ID={hid_id}\nHID_NAME=some device\nHID_PHYS={phys}\n");
        if let Some(u) = uniq {
            uevent.push_str(&format!("HID_UNIQ={u}\n"));
        }
        fs::write(dir.join("uevent"), uevent).unwrap();
    }
}

fn numbers(nodes: &[HidrawNode]) -> Vec<u32> {
    nodes.iter().map(|n| n.number).collect()
}

#[test]
fn only_aquaero_nodes_are_found() {
    let sys = Sysfs::new();
    sys.node(0, OTHER, "usb-0000:0a:00.0-1/input0", None);
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", Some("21998-56576"));

    let nodes = discover(sys.root(), &sys.dev()).unwrap();

    assert_eq!(numbers(&nodes), vec![3]);
    assert_eq!(nodes[0].dev_path, PathBuf::from("/dev/hidraw3"));
    assert_eq!(nodes[0].serial.as_deref(), Some("21998-56576"));
}

#[test]
fn nodes_are_ordered_by_number_not_by_name() {
    let sys = Sysfs::new();
    for n in [10, 2, 1] {
        sys.node(n, AQUAERO, "usb-0000:00:14.0-3/input0", Some("s"));
    }
    assert_eq!(
        numbers(&discover(sys.root(), &sys.dev()).unwrap()),
        vec![1, 2, 10]
    );
}

#[test]
fn the_ids_match_whatever_the_case() {
    let sys = Sysfs::new();
    sys.node(1, "0003:00000c70:0000f001", "usb-x-3/input0", None);
    assert_eq!(numbers(&discover(sys.root(), &sys.dev()).unwrap()), vec![1]);
}

#[test]
fn no_hidraw_class_at_all_means_no_device_not_an_error() {
    let sys = Sysfs::new();
    assert_eq!(discover(sys.root(), &sys.dev()).unwrap(), vec![]);
}

#[test]
fn a_node_without_a_uevent_is_ignored() {
    let sys = Sysfs::new();
    fs::create_dir_all(sys.root().join("class/hidraw/hidraw5/device")).unwrap();
    sys.node(6, AQUAERO, "usb-x-3/input0", None);
    assert_eq!(numbers(&discover(sys.root(), &sys.dev()).unwrap()), vec![6]);
}

#[test]
fn choosing_with_nothing_present_says_absent() {
    let err = choose(vec![], None).unwrap_err();
    assert!(matches!(err, SelectError::Absent), "{err:?}");
}

#[test]
fn several_interfaces_of_one_device_are_all_candidates() {
    let sys = Sysfs::new();
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", Some("21998-56576"));
    sys.node(4, AQUAERO, "usb-0000:00:14.0-3/input1", Some("21998-56576"));

    let chosen = choose(discover(sys.root(), &sys.dev()).unwrap(), None).unwrap();
    assert_eq!(numbers(&chosen), vec![3, 4]);
}

#[test]
fn two_devices_need_an_explicit_serial() {
    let sys = Sysfs::new();
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", Some("11111-22222"));
    sys.node(5, AQUAERO, "usb-0000:00:14.0-4/input0", Some("33333-44444"));

    let err = choose(discover(sys.root(), &sys.dev()).unwrap(), None).unwrap_err();
    match err {
        SelectError::Ambiguous { devices } => {
            assert_eq!(
                devices,
                vec!["11111-22222".to_string(), "33333-44444".to_string()]
            );
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_serial_picks_one_of_two_devices() {
    let sys = Sysfs::new();
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", Some("11111-22222"));
    sys.node(4, AQUAERO, "usb-0000:00:14.0-3/input1", Some("11111-22222"));
    sys.node(5, AQUAERO, "usb-0000:00:14.0-4/input0", Some("33333-44444"));

    let chosen = choose(
        discover(sys.root(), &sys.dev()).unwrap(),
        Some("33333-44444"),
    )
    .unwrap();
    assert_eq!(numbers(&chosen), vec![5]);
}

#[test]
fn an_unknown_serial_lists_the_ones_present() {
    let sys = Sysfs::new();
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", Some("11111-22222"));

    let err = choose(
        discover(sys.root(), &sys.dev()).unwrap(),
        Some("99999-99999"),
    )
    .unwrap_err();
    match err {
        SelectError::SerialNotFound { wanted, present } => {
            assert_eq!(wanted, "99999-99999");
            assert_eq!(present, vec!["11111-22222".to_string()]);
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn two_devices_without_serials_are_told_apart_by_their_usb_port() {
    let sys = Sysfs::new();
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", None);
    sys.node(5, AQUAERO, "usb-0000:00:14.0-4/input0", None);

    let err = choose(discover(sys.root(), &sys.dev()).unwrap(), None).unwrap_err();
    match err {
        SelectError::Ambiguous { devices } => assert_eq!(
            devices,
            vec![
                "usb-0000:00:14.0-3".to_string(),
                "usb-0000:00:14.0-4".to_string()
            ]
        ),
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_single_device_without_a_serial_is_accepted() {
    let sys = Sysfs::new();
    sys.node(3, AQUAERO, "usb-0000:00:14.0-3/input0", None);
    let chosen = choose(discover(sys.root(), &sys.dev()).unwrap(), None).unwrap();
    assert_eq!(numbers(&chosen), vec![3]);
}

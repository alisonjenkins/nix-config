// Panicking on a bad fixture is the correct failure inside a test.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects,
    clippy::panic
)]

use aquaero_ctl::diff::{diff, DiffRun, VolatileSet};
use aquaero_ctl::snapshot::{ConfigBytes, CONFIG_LEN};
use proptest::prelude::*;

fn zeros() -> Vec<u8> {
    vec![0u8; CONFIG_LEN]
}

fn with(changes: &[(usize, u8)]) -> ConfigBytes {
    let mut bytes = zeros();
    for &(offset, value) in changes {
        bytes[offset] = value;
    }
    ConfigBytes::new(bytes).unwrap()
}

fn run(offset: usize, before: &[u8], after: &[u8], volatile: bool) -> DiffRun {
    DiffRun {
        offset,
        before: before.to_vec(),
        after: after.to_vec(),
        volatile,
    }
}

#[test]
fn identical_bytes_have_no_diff() {
    let a = with(&[(5, 9)]);
    assert_eq!(diff(&a, &a.clone(), &VolatileSet::none()), vec![]);
}

#[test]
fn one_changed_byte_is_one_run() {
    let before = with(&[]);
    let after = with(&[(100, 0x42)]);
    assert_eq!(
        diff(&before, &after, &VolatileSet::none()),
        vec![run(100, &[0], &[0x42], false)]
    );
}

#[test]
fn adjacent_changes_group_into_one_run() {
    let before = with(&[]);
    let after = with(&[(10, 1), (11, 2), (12, 3)]);
    assert_eq!(
        diff(&before, &after, &VolatileSet::none()),
        vec![run(10, &[0, 0, 0], &[1, 2, 3], false)]
    );
}

#[test]
fn a_gap_of_one_unchanged_byte_makes_two_runs() {
    let before = with(&[]);
    let after = with(&[(10, 1), (12, 3)]);
    assert_eq!(
        diff(&before, &after, &VolatileSet::none()),
        vec![run(10, &[0], &[1], false), run(12, &[0], &[3], false)]
    );
}

#[test]
fn the_first_and_last_byte_are_compared() {
    let before = with(&[]);
    let after = with(&[(0, 1), (CONFIG_LEN - 1, 2)]);
    assert_eq!(
        diff(&before, &after, &VolatileSet::none()),
        vec![
            run(0, &[0], &[1], false),
            run(CONFIG_LEN - 1, &[0], &[2], false)
        ]
    );
}

#[test]
fn positions_that_differ_between_untouched_snapshots_are_volatile() {
    // Two reads of an untouched device differ at 50, so 50 is not a setting.
    let first = with(&[]);
    let second = with(&[(50, 7)]);
    let volatile = VolatileSet::from_untouched_pair(&first, &second);

    let before = with(&[]);
    let after = with(&[(50, 9), (100, 1)]);
    assert_eq!(
        diff(&before, &after, &volatile),
        vec![run(50, &[0], &[9], true), run(100, &[0], &[1], false)]
    );
}

#[test]
fn adjacent_bytes_with_different_volatility_split_into_two_runs() {
    let volatile = VolatileSet::from_untouched_pair(&with(&[]), &with(&[(50, 7)]));

    let before = with(&[]);
    let after = with(&[(49, 1), (50, 2)]);
    assert_eq!(
        diff(&before, &after, &volatile),
        vec![run(49, &[0], &[1], false), run(50, &[0], &[2], true)]
    );
}

#[test]
fn an_empty_volatile_set_marks_nothing() {
    assert!(!VolatileSet::none().contains(0));
    assert!(!VolatileSet::none().contains(CONFIG_LEN - 1));
}

proptest! {
    // Patching "before" with the runs must give "after", for any pair.
    #[test]
    fn applying_the_runs_to_before_gives_after(
        before in proptest::collection::vec(any::<u8>(), CONFIG_LEN),
        flips in proptest::collection::vec((0..CONFIG_LEN, any::<u8>()), 0..40),
    ) {
        let mut after_bytes = before.clone();
        for (offset, value) in flips {
            after_bytes[offset] = value;
        }
        let before = ConfigBytes::new(before).unwrap();
        let after = ConfigBytes::new(after_bytes).unwrap();

        let mut patched = before.as_slice().to_vec();
        for r in diff(&before, &after, &VolatileSet::none()) {
            prop_assert_eq!(r.before.len(), r.after.len());
            prop_assert_eq!(&patched[r.offset..r.offset + r.before.len()], &r.before[..]);
            patched[r.offset..r.offset + r.after.len()].copy_from_slice(&r.after);
        }
        prop_assert_eq!(patched, after.as_slice());
    }

    // Swapping the arguments swaps before and after in every run.
    #[test]
    fn diff_is_symmetric(
        a in proptest::collection::vec(any::<u8>(), CONFIG_LEN),
        b in proptest::collection::vec(any::<u8>(), CONFIG_LEN),
    ) {
        let a = ConfigBytes::new(a).unwrap();
        let b = ConfigBytes::new(b).unwrap();
        let forward = diff(&a, &b, &VolatileSet::none());
        let backward = diff(&b, &a, &VolatileSet::none());
        prop_assert_eq!(forward.len(), backward.len());
        for (f, r) in forward.iter().zip(backward.iter()) {
            prop_assert_eq!(f.offset, r.offset);
            prop_assert_eq!(&f.before, &r.after);
            prop_assert_eq!(&f.after, &r.before);
        }
    }
}

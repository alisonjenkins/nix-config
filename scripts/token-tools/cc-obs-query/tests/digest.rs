#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::fs;

use common::{cli, digest_rules, fixture, s, serve, write_pack, Fake, TOOL_PACK};
use serde_json::{json, Value};

const UNTIL: &str = "2026-10-09";

fn baseline(fake: &Fake, pack: &str) -> common::Run {
    cli(
        fake,
        &[
            "digest",
            "--baseline",
            "--pack",
            pack,
            "--since",
            "7d",
            "--until",
            UNTIL,
        ],
    )
}

fn valid_digest(fake: &Fake, pack: &str) -> Value {
    let run = baseline(fake, pack);
    assert_eq!(run.code, 0, "{}", run.err);
    run.json()
}

fn write_args<'a>(file: &'a str, pack: &'a str) -> Vec<&'a str> {
    vec!["digest", "--write", file, "--pack", pack, "--until", UNTIL]
}

/// Mutate a baseline digest and run `--write`; returns the run.
fn write_mutated(
    rules: Vec<(&'static str, String)>,
    pack_yaml: &str,
    mutate: impl FnOnce(&mut Value),
) -> common::Run {
    let dir = tempfile::tempdir().unwrap();
    let pack = write_pack(dir.path(), pack_yaml);
    let fake = serve(rules);
    let mut digest = valid_digest(&fake, s(&pack));
    mutate(&mut digest);
    let file = dir.path().join("in.json");
    fs::write(&file, digest.to_string()).unwrap();
    cli(&fake, &write_args(s(&file), s(&pack)))
}

fn rejects(mutate: impl FnOnce(&mut Value), needle: &str) {
    let run = write_mutated(
        digest_rules(fixture("loki_tool_results.json")),
        TOOL_PACK,
        mutate,
    );
    assert_ne!(run.code, 0, "accepted: {}", run.out);
    let err = run.err_json();
    assert!(
        err["error"].as_str().unwrap().contains(needle),
        "{needle} not in {err}"
    );
}

#[test]
fn digest_write_rejects_non_string_free_text_fields() {
    type Case = (&'static str, Box<dyn Fn(&mut Value)>);
    let cases: Vec<Case> = vec![
        (
            "questions[0].unavailable",
            Box::new(|d| d["questions"][0]["unavailable"] = json!({"note": "p".repeat(150)})),
        ),
        (
            "rows[0].pattern",
            Box::new(|d| d["questions"][0]["rows"][0]["pattern"] = json!(["a prose sentence"])),
        ),
        (
            "rows[0].regrowth_of",
            Box::new(|d| d["questions"][0]["rows"][0]["regrowth_of"] = json!({"x": "y z"})),
        ),
        (
            "rows[0].evidence",
            Box::new(|d| d["questions"][0]["rows"][0]["evidence"] = json!({"x": "y z"})),
        ),
        (
            "stack.gaps[0]",
            Box::new(|d| d["stack"]["gaps"] = json!([{"x": "p".repeat(150)}])),
        ),
        (
            "prior_decisions[0].id",
            Box::new(|d| {
                d["prior_decisions"] = json!([{"id": {"x": "a b"}, "status": "acted"}]);
            }),
        ),
        (
            "prior_decisions[0].status",
            Box::new(|d| d["prior_decisions"] = json!([{"id": "0001", "status": ["a b"]}])),
        ),
        (
            "prior_decisions[0].verdict",
            Box::new(|d| {
                d["prior_decisions"] =
                    json!([{"id": "0001", "status": "acted", "verdict": {"x": "a b"}}]);
            }),
        ),
    ];
    for (path, mutate) in cases {
        rejects(mutate, path);
    }
}

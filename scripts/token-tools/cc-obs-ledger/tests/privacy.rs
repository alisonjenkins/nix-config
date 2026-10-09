#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

use cc_obs_ledger::otlp::{session_payloads, turn_payloads, Payload, Resource};
use cc_obs_ledger::transcript::{parse, ToolHasher};

const FIXTURE: &str = include_str!("fixtures/transcript.jsonl");

fn everything_sent(resource: &Resource) -> (Vec<Payload>, String) {
    let parsed = parse(FIXTURE, &ToolHasher::new(b"k".to_vec()));
    let mut payloads = turn_payloads(resource, &parsed);
    payloads.extend(session_payloads(resource, &parsed, None));
    let text = payloads
        .iter()
        .map(|p| p.body.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    (payloads, text)
}

#[test]
fn no_transcript_text_or_tool_input_leaves_the_machine() {
    let (_, text) = everything_sent(&Resource::new("ali-desktop", &[]));
    for secret in [
        "CANARY-7f3a",
        "thinking aloud",
        "file body",
        "prompt text",
        "/work/proj/",
    ] {
        assert!(!text.contains(secret), "payloads leak {secret:?}");
    }
}

#[test]
fn the_payloads_do_carry_the_figures_they_exist_for() {
    let (payloads, text) = everything_sent(&Resource::new("ali-desktop", &[]));
    assert!(!payloads.is_empty());
    for expected in [
        "cc_obs_ledger.tool_call",
        "input_hash",
        "result_bytes",
        "cc_obs_ledger_context_tokens",
        "cc_obs_ledger_cache_hit_ratio",
        "sess-1",
        "Read",
    ] {
        assert!(text.contains(expected), "payloads lack {expected:?}");
    }
}

#[test]
fn resource_attributes_from_the_environment_are_added_to_every_payload() {
    let resource = Resource::from_env_string("ali-desktop", "review.run=1, team=a b");
    let (payloads, _) = everything_sent(&resource);
    for payload in &payloads {
        let attrs = payload
            .body
            .pointer("/resourceMetrics/0/resource/attributes")
            .or_else(|| payload.body.pointer("/resourceLogs/0/resource/attributes"))
            .unwrap()
            .to_string();
        assert!(attrs.contains("review.run"), "{attrs}");
        assert!(attrs.contains("ali-desktop"), "{attrs}");
        assert!(attrs.contains("a b"), "{attrs}");
    }
}

#[test]
fn a_malformed_environment_pair_is_ignored_not_fatal() {
    let resource = Resource::from_env_string("h", "noequals,ok=1,=bad");
    let names: Vec<_> = resource.attrs.iter().map(|(k, _)| k.as_str()).collect();
    assert!(names.contains(&"ok"));
    assert!(!names.contains(&"noequals"));
    assert!(!names.contains(&""));
}

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing,
    clippy::arithmetic_side_effects
)]

mod common;

use std::io::{Read, Write};
use std::net::TcpStream;

use common::serve;

const EMPTY_VECTOR: &str = r#"{"status":"success","data":{"resultType":"vector","result":[]}}"#;

fn encode(text: &str) -> String {
    text.bytes()
        .map(|b| match b {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// Raw HTTP reply of the fake backend to an instant query.
fn reply_to(promql: &str) -> String {
    let fake = serve(vec![("up", EMPTY_VECTOR.to_owned())]);
    let host = fake.base.trim_start_matches("http://").to_owned();
    let mut stream = TcpStream::connect(&host).unwrap();
    write!(
        stream,
        "GET /prom/api/v1/query?query={} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n",
        encode(promql)
    )
    .unwrap();
    let mut out = String::new();
    stream.read_to_string(&mut out).unwrap();
    out
}

#[test]
fn an_offset_after_a_closing_paren_gets_a_400() {
    let reply = reply_to("last_over_time(up[90d]) offset 1d");
    assert!(reply.starts_with("HTTP/1.1 400"), "{reply}");
    assert!(reply.contains("\"errorType\":\"bad_data\""), "{reply}");
    assert!(
        reply.contains("offset modifier must be preceded"),
        "{reply}"
    );
}

#[test]
fn unbalanced_parentheses_and_brackets_get_a_400() {
    for bad in ["sum(up", "up[90d", "up)"] {
        let reply = reply_to(bad);
        assert!(reply.starts_with("HTTP/1.1 400"), "{bad}: {reply}");
    }
}

#[test]
fn an_offset_inside_the_range_is_served() {
    let reply = reply_to("last_over_time(up[90d] offset 1d)");
    assert!(reply.starts_with("HTTP/1.1 200"), "{reply}");
}

#[test]
fn brackets_inside_a_quoted_label_value_are_not_counted() {
    let reply = reply_to(r#"up{job="a(b"}"#);
    assert!(reply.starts_with("HTTP/1.1 200"), "{reply}");
}

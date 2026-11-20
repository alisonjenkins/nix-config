//! Finds the GitHub Actions a repository's workflows and composite actions
//! use. The files are parsed as YAML, so quoted keys, block scalars and flow
//! mappings are all seen; a line-based search would miss them.

use yaml_rust2::parser::{Event, Parser};

/// One `uses:` reference to a remote action.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionUse {
    pub file: String,
    pub line: usize,
    /// `owner/repo`, lowercase, without any sub-path.
    pub repo: String,
    /// What follows `@`, or empty when there is none.
    pub reference: String,
}

impl ActionUse {
    pub fn key(&self) -> String {
        format!("action:{}", self.repo)
    }

    /// A full 40-character commit SHA, the only reference that cannot move.
    pub fn is_pinned(&self) -> bool {
        self.reference.len() == 40 && self.reference.bytes().all(|b| b.is_ascii_hexdigit())
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Scan {
    pub remote: Vec<ActionUse>,
    /// Local actions (`./path`), relative to the repository root.
    pub local: Vec<String>,
}

enum Frame {
    Mapping { expecting_key: bool, key: Option<String> },
    Sequence,
}

/// Marks the value slot of the enclosing mapping as consumed.
fn value_done(stack: &mut [Frame]) {
    if let Some(Frame::Mapping { expecting_key, key }) = stack.last_mut() {
        if !*expecting_key {
            *expecting_key = true;
            *key = None;
        }
    }
}

/// Every `uses:` value anywhere in the file. Container actions
/// (`docker://...`) are skipped.
pub fn scan(file: &str, text: &str) -> Result<Scan, String> {
    let mut out = Scan::default();
    let mut parser = Parser::new_from_str(text);
    let mut stack: Vec<Frame> = Vec::new();
    loop {
        let (event, mark) = parser.next_token().map_err(|e| format!("{file}: not valid YAML: {e}"))?;
        match event {
            Event::StreamEnd => break,
            Event::MappingStart(..) => stack.push(Frame::Mapping { expecting_key: true, key: None }),
            Event::SequenceStart(..) => stack.push(Frame::Sequence),
            Event::MappingEnd | Event::SequenceEnd => {
                stack.pop();
                value_done(&mut stack);
            }
            Event::Alias(_) => {
                if let Some(Frame::Mapping { expecting_key: false, key: Some(k) }) = stack.last() {
                    if k == "uses" {
                        return Err(format!(
                            "{file}:{}: `uses:` is a YAML alias; write the action reference out so it can be checked",
                            mark.line()
                        ));
                    }
                }
                value_done(&mut stack);
            }
            Event::Scalar(value, ..) => {
                let is_uses = match stack.last_mut() {
                    Some(Frame::Mapping { expecting_key: expecting @ true, key }) => {
                        *expecting = false;
                        *key = Some(value.clone());
                        continue;
                    }
                    Some(Frame::Mapping { expecting_key: false, key }) => key.as_deref() == Some("uses"),
                    _ => false,
                };
                value_done(&mut stack);
                if is_uses {
                    record(&mut out, file, mark.line(), value.trim());
                }
            }
            _ => {}
        }
    }
    Ok(out)
}

fn record(out: &mut Scan, file: &str, line: usize, value: &str) {
    if value.is_empty() || value.starts_with("docker://") {
        return;
    }
    if let Some(local) = value.strip_prefix("./") {
        out.local.push(local.trim_end_matches('/').to_string());
        return;
    }
    let (path, reference) = value.split_once('@').unwrap_or((value, ""));
    let mut segs = path.split('/');
    let (Some(owner), Some(repo)) = (segs.next(), segs.next()) else { return };
    out.remote.push(ActionUse {
        file: file.to_string(),
        line,
        repo: format!("{owner}/{repo}").to_lowercase(),
        reference: reference.to_string(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    const WF: &str = r#"
jobs:
  a:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - name: x
        uses: "GitHub/CodeQL-Action/init@v3"
      - uses: ./.github/actions/setup-host-nix
      - uses: docker://alpine:3
      - uses: fluxcd/flux2/action@main
      - uses: someone/thing
      # uses: commented/out@v1
      - run: 'echo "uses: not/a-step@v1"'
      - 'uses': quoted/key@v1
      - uses: >-
          folded/scalar@v2
      - {name: flow, uses: flow/mapping@v3}
      - with:
          uses: not-a-step-key/but-still-scanned@v4
  reusable:
    uses: org/repo/.github/workflows/x.yaml@v5
"#;

    #[test]
    fn finds_every_uses_value() {
        let got = scan("wf.yaml", WF).unwrap();
        let summary: Vec<(usize, &str, &str, bool)> =
            got.remote.iter().map(|u| (u.line, u.repo.as_str(), u.reference.as_str(), u.is_pinned())).collect();
        assert_eq!(
            summary,
            vec![
                (5, "actions/checkout", "3d3c42e5aac5ba805825da76410c181273ba90b1", true),
                (7, "github/codeql-action", "v3", false),
                (10, "fluxcd/flux2", "main", false),
                (11, "someone/thing", "", false),
                (14, "quoted/key", "v1", false),
                (16, "folded/scalar", "v2", false),
                (17, "flow/mapping", "v3", false),
                (19, "not-a-step-key/but-still-scanned", "v4", false),
                (21, "org/repo", "v5", false),
            ]
        );
        assert_eq!(got.remote[2].key(), "action:fluxcd/flux2");
        assert_eq!(got.local, vec![".github/actions/setup-host-nix"]);
    }

    #[test]
    fn keys_after_nested_values_are_still_keys() {
        let text = "a:\n  b: [1, 2]\n  c: {d: e}\n  uses: x/y@z\nuses: p/q@r\n";
        let got = scan("f", text).unwrap();
        let repos: Vec<&str> = got.remote.iter().map(|u| u.repo.as_str()).collect();
        assert_eq!(repos, vec!["x/y", "p/q"]);
        // A scalar in a sequence is never a key, including after a mapping
        // in that sequence has closed.
        let got = scan("f", "- uses\n- x/y@z\n").unwrap();
        assert!(got.remote.is_empty());
        let got = scan("f", "- {k: v}\n- uses\n- x/y@z\n").unwrap();
        assert!(got.remote.is_empty());
        // A key named uses whose value is a mapping is not a reference.
        let got = scan("f", "uses:\n  a: b/c@d\nnext: 1\n").unwrap();
        assert!(got.remote.is_empty());
    }

    #[test]
    fn aliases_and_bad_yaml_are_errors() {
        let err = scan("wf.yaml", "x: &a actions/checkout@v1\nsteps:\n  - uses: *a\n").unwrap_err();
        assert_eq!(err, "wf.yaml:3: `uses:` is a YAML alias; write the action reference out so it can be checked");
        assert!(scan("f", "a: *b\n").is_err());
        let ok = scan("f", "a: &x 1\nb: *x\nuses: c/d@e\n").unwrap();
        assert_eq!(ok.remote.len(), 1);
        assert!(scan("wf.yaml", "a: [\n").unwrap_err().starts_with("wf.yaml: not valid YAML"));
    }

    #[test]
    fn local_paths_are_normalised() {
        let got = scan("f", "uses: ./tools/act/\n").unwrap();
        assert_eq!(got.local, vec!["tools/act"]);
        assert!(scan("f", "uses: ''\n").unwrap() == Scan::default());
        assert!(scan("f", "uses: lonely\n").unwrap().remote.is_empty());
    }

    #[test]
    fn pinned_needs_exactly_40_hex() {
        let mk = |r: &str| ActionUse { file: String::new(), line: 1, repo: "a/b".into(), reference: r.into() };
        assert!(mk("0123456789abcdef0123456789abcdef01234567").is_pinned());
        assert!(!mk("0123456789abcdef0123456789abcdef0123456").is_pinned());
        assert!(!mk("0123456789abcdef0123456789abcdef012345678").is_pinned());
        assert!(!mk("g123456789abcdef0123456789abcdef01234567").is_pinned());
    }
}

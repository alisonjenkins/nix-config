//! Finds the GitHub Actions a repository's workflows and composite actions use.

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

/// Extracts remote `uses:` references from one YAML file. Local actions
/// (`./...`) and container actions (`docker://...`) are skipped.
pub fn scan(file: &str, text: &str) -> Vec<ActionUse> {
    let mut out = Vec::new();
    for (i, raw) in text.lines().enumerate() {
        let line = raw.trim_start();
        let line = line.strip_prefix("- ").map(str::trim_start).unwrap_or(line);
        let Some(rest) = line.strip_prefix("uses:") else { continue };
        let value = rest.split(" #").next().unwrap_or(rest).trim();
        let value = value.trim_matches(|c| c == '"' || c == '\'');
        if value.is_empty() || value.starts_with("./") || value.starts_with("docker://") {
            continue;
        }
        let (path, reference) = match value.split_once('@') {
            Some((p, r)) => (p, r),
            None => (value, ""),
        };
        let mut segs = path.split('/');
        let (Some(owner), Some(repo)) = (segs.next(), segs.next()) else { continue };
        out.push(ActionUse {
            file: file.to_string(),
            line: i + 1,
            repo: format!("{owner}/{repo}").to_lowercase(),
            reference: reference.to_string(),
        });
    }
    out
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
      - run: echo "uses: not/a-step@v1"
"#;

    #[test]
    fn finds_remote_actions() {
        let got = scan("wf.yaml", WF);
        let summary: Vec<(usize, &str, &str, bool)> =
            got.iter().map(|u| (u.line, u.repo.as_str(), u.reference.as_str(), u.is_pinned())).collect();
        assert_eq!(
            summary,
            vec![
                (5, "actions/checkout", "3d3c42e5aac5ba805825da76410c181273ba90b1", true),
                (7, "github/codeql-action", "v3", false),
                (10, "fluxcd/flux2", "main", false),
                (11, "someone/thing", "", false),
            ]
        );
        assert_eq!(got[2].key(), "action:fluxcd/flux2");
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

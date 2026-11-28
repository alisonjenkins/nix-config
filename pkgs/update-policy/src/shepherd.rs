//! Decides what to do about the open nightly flake-update PRs, so that the
//! nightly job does not have to sit on the self-hosted runner waiting for its
//! PR to merge.
//!
//! The input is the JSON `gh pr list --json
//! number,headRefName,isDraft,createdAt,mergeStateStatus,statusCheckRollup`
//! prints. The output is one line per decision, which the
//! `update-shepherd.yaml` workflow acts on:
//!
//! ```text
//! rebase <number>             the PR is behind main; update its branch
//! stuck <number> <reason>     a human needs to look (the workflow opens an issue)
//! wait <number> <detail>      nothing to do yet
//! ```
//!
//! The decision is pure: the same PR list and time always give the same
//! lines, so every case is unit tested here instead of in YAML.

use serde_json::Value;
use std::fmt;

use crate::date::parse_utc_timestamp;

/// Branches the nightly job pushes (`update.yaml`).
pub const NIGHTLY_PREFIX: &str = "flake-update-";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Check {
    pub name: String,
    /// Upper-case GitHub state: a check run's conclusion (or its status while
    /// it has none), or a commit status's state.
    pub state: String,
}

impl Check {
    fn failed(&self) -> bool {
        matches!(
            self.state.as_str(),
            "FAILURE" | "CANCELLED" | "TIMED_OUT" | "ACTION_REQUIRED" | "STARTUP_FAILURE" | "STALE" | "ERROR"
        )
    }

    fn finished_ok(&self) -> bool {
        matches!(self.state.as_str(), "SUCCESS" | "NEUTRAL" | "SKIPPED")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pr {
    pub number: u64,
    pub branch: String,
    pub draft: bool,
    /// Unix seconds.
    pub created: i64,
    /// `mergeStateStatus`: BEHIND, BLOCKED, CLEAN, DIRTY, HAS_HOOKS, UNKNOWN,
    /// UNSTABLE.
    pub merge_state: String,
    pub checks: Vec<Check>,
}

pub fn parse_prs(text: &str) -> Result<Vec<Pr>, String> {
    let v: Value = serde_json::from_str(text).map_err(|e| format!("not JSON: {e}"))?;
    let items = v.as_array().ok_or("expected a JSON array of pull requests")?;
    items.iter().enumerate().map(|(i, item)| parse_pr(item).map_err(|e| format!("pull request [{i}]: {e}"))).collect()
}

fn field<'a>(item: &'a Value, name: &str) -> Result<&'a Value, String> {
    item.get(name).ok_or_else(|| format!("missing `{name}`"))
}

fn string(item: &Value, name: &str) -> Result<String, String> {
    field(item, name)?.as_str().map(str::to_owned).ok_or_else(|| format!("`{name}` is not a string"))
}

fn parse_pr(item: &Value) -> Result<Pr, String> {
    let number = field(item, "number")?.as_u64().ok_or("`number` is not a positive integer")?;
    let created_text = string(item, "createdAt")?;
    let created =
        parse_utc_timestamp(&created_text).ok_or_else(|| format!("`createdAt` {created_text:?} is not a UTC timestamp"))?;
    let checks = match item.get("statusCheckRollup") {
        None | Some(Value::Null) => Vec::new(),
        Some(Value::Array(list)) => list.iter().map(parse_check).collect::<Result<_, _>>()?,
        Some(_) => return Err("`statusCheckRollup` is not an array".into()),
    };
    Ok(Pr {
        number,
        branch: string(item, "headRefName")?,
        draft: item.get("isDraft").and_then(Value::as_bool).unwrap_or(false),
        created,
        merge_state: string(item, "mergeStateStatus")?.to_ascii_uppercase(),
        checks,
    })
}

fn parse_check(item: &Value) -> Result<Check, String> {
    let text = |k: &str| item.get(k).and_then(Value::as_str).filter(|s| !s.is_empty());
    // A CheckRun has name/status/conclusion; a StatusContext has context/state.
    let name = text("name").or_else(|| text("context")).ok_or("a status check has neither `name` nor `context`")?;
    let state = text("conclusion").or_else(|| text("state")).or_else(|| text("status")).unwrap_or("PENDING");
    Ok(Check { name: name.to_owned(), state: state.to_ascii_uppercase() })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Rebase(u64),
    Stuck(u64, String),
    Wait(u64, String),
}

/// Each decision must stay one line for the shell consumer, whatever a check
/// name contains.
fn one_line(text: &str) -> String {
    text.replace('\r', "\\r").replace('\n', "\\n")
}

impl fmt::Display for Decision {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Decision::Rebase(n) => write!(f, "rebase {n}"),
            Decision::Stuck(n, why) => write!(f, "stuck {n} {}", one_line(why)),
            Decision::Wait(n, why) => write!(f, "wait {n} {}", one_line(why)),
        }
    }
}

fn hours(secs: i64) -> String {
    format!("{:.1}h", secs as f64 / 3_600.0)
}

/// A daily time-of-day window in UTC, `HH:MM-HH:MM`. It may wrap past
/// midnight (`23:30-04:30`). A rebase re-runs the PR's checks on the home
/// self-hosted runner, so rebases are kept to the hours when power is cheap.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Window {
    start: i64,
    end: i64,
}

impl Window {
    pub fn parse(s: &str) -> Option<Window> {
        let (a, b) = s.split_once('-')?;
        let start = minutes(a)?;
        let end = minutes(b)?;
        (start != end).then_some(Window { start, end })
    }

    pub fn contains(self, unix_seconds: i64) -> bool {
        let m = unix_seconds.rem_euclid(86_400) / 60;
        if self.start < self.end {
            self.start <= m && m < self.end
        } else {
            m >= self.start || m < self.end
        }
    }
}

impl fmt::Display for Window {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:02}:{:02}-{:02}:{:02} UTC", self.start / 60, self.start % 60, self.end / 60, self.end % 60)
    }
}

fn minutes(hhmm: &str) -> Option<i64> {
    let (h, m) = hhmm.split_once(':')?;
    if h.len() != 2 || m.len() != 2 || !h.bytes().chain(m.bytes()).all(|b| b.is_ascii_digit()) {
        return None;
    }
    let (h, m): (i64, i64) = (h.parse().ok()?, m.parse().ok()?);
    (h < 24 && m < 60).then_some(h * 60 + m)
}

/// What to do about each open nightly PR, oldest first. `stuck_after` is how
/// long (seconds) a PR may stay open before a human is told, however healthy
/// it looks. With a `rebase_window`, a PR that is behind main outside the
/// window waits for it instead of being rebased.
pub fn decide(prs: &[Pr], now: i64, stuck_after: i64, rebase_window: Option<Window>) -> Vec<Decision> {
    let mut nightly: Vec<&Pr> = prs.iter().filter(|p| p.branch.starts_with(NIGHTLY_PREFIX)).collect();
    nightly.sort_by_key(|p| (p.created, p.number));
    let newest = nightly.last().map(|p| p.number);
    let mut out = Vec::new();
    for pr in &nightly {
        let n = pr.number;
        let age = now - pr.created;
        if Some(n) != newest {
            out.push(Decision::Stuck(
                n,
                format!("superseded by #{} but still open; the nightly job could not close it", newest.unwrap_or(0)),
            ));
            continue;
        }
        if pr.draft {
            out.push(Decision::Stuck(n, "is a draft, so auto-merge will not merge it".into()));
            continue;
        }
        let failed: Vec<String> =
            pr.checks.iter().filter(|c| c.failed()).map(|c| format!("{} {}", c.name, c.state.to_ascii_lowercase())).collect();
        if !failed.is_empty() {
            // Rebasing would only re-run a check that already failed on this
            // lock; tomorrow's nightly supersedes the PR instead.
            out.push(Decision::Stuck(n, format!("check failed: {}", failed.join(", "))));
            continue;
        }
        let mut rebased = false;
        match pr.merge_state.as_str() {
            "DIRTY" => {
                out.push(Decision::Stuck(n, "conflicts with main; tomorrow's nightly will replace it".into()));
                continue;
            }
            "BEHIND" if rebase_window.is_none_or(|w| w.contains(now)) => {
                out.push(Decision::Rebase(n));
                rebased = true;
            }
            _ => {}
        }
        let pending: Vec<&str> =
            pr.checks.iter().filter(|c| !c.failed() && !c.finished_ok()).map(|c| c.name.as_str()).collect();
        let mut detail = format!(
            "open {}, merge state {}, {}",
            hours(age),
            pr.merge_state.to_ascii_lowercase(),
            if pending.is_empty() { "no checks pending".to_owned() } else { format!("pending: {}", pending.join(", ")) }
        );
        if pr.merge_state == "BEHIND" && !rebased {
            if let Some(w) = rebase_window {
                detail.push_str(&format!(", rebase waits for {w}"));
            }
        }
        if age >= stuck_after {
            out.push(Decision::Stuck(n, format!("not merged after {} ({detail})", hours(stuck_after))));
        } else if !rebased {
            out.push(Decision::Wait(n, detail));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const H: i64 = 3_600;
    const NOW: i64 = 1_795_400_000;

    fn pr(number: u64, age: i64, merge_state: &str, checks: &[(&str, &str)]) -> Pr {
        Pr {
            number,
            branch: format!("{NIGHTLY_PREFIX}{number}-1"),
            draft: false,
            created: NOW - age,
            merge_state: merge_state.into(),
            checks: checks.iter().map(|(n, s)| Check { name: (*n).into(), state: (*s).into() }).collect(),
        }
    }

    fn lines(prs: &[Pr]) -> Vec<String> {
        decide(prs, NOW, 6 * H, None).iter().map(ToString::to_string).collect()
    }

    #[test]
    fn healthy_pr_waits() {
        assert_eq!(
            lines(&[pr(1, H / 2, "BLOCKED", &[("flake-check", "IN_PROGRESS"), ("CodeRabbit", "SKIPPED")])]),
            ["wait 1 open 0.5h, merge state blocked, pending: flake-check"]
        );
        assert_eq!(lines(&[pr(1, H, "CLEAN", &[("flake-check", "SUCCESS")])]), ["wait 1 open 1.0h, merge state clean, no checks pending"]);
    }

    #[test]
    fn behind_is_rebased_last_nights_case() {
        // #1070: flake-check passed, then main moved.
        assert_eq!(lines(&[pr(1070, H, "BEHIND", &[("flake-check", "SUCCESS"), ("repo-claims", "SUCCESS")])]), ["rebase 1070"]);
    }

    #[test]
    fn behind_and_old_is_rebased_and_reported() {
        assert_eq!(
            lines(&[pr(7, 6 * H, "BEHIND", &[("flake-check", "SUCCESS")])]),
            ["rebase 7", "stuck 7 not merged after 6.0h (open 6.0h, merge state behind, no checks pending)"]
        );
    }

    #[test]
    fn exactly_at_the_limit_is_stuck_and_just_under_is_not() {
        assert!(lines(&[pr(1, 6 * H, "BLOCKED", &[])])[0].starts_with("stuck 1 not merged"));
        assert!(lines(&[pr(1, 6 * H - 1, "BLOCKED", &[])])[0].starts_with("wait 1"));
    }

    #[test]
    fn failed_checks_are_reported_not_rebased() {
        for state in ["FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE", "ERROR"] {
            assert_eq!(
                lines(&[pr(3, H, "BEHIND", &[("flake-check", state), ("repo-claims", "SUCCESS")])]),
                [format!("stuck 3 check failed: flake-check {}", state.to_ascii_lowercase())],
            );
        }
        assert_eq!(
            lines(&[pr(3, H, "BLOCKED", &[("a", "FAILURE"), ("b", "TIMED_OUT")])]),
            ["stuck 3 check failed: a failure, b timed_out"]
        );
    }

    #[test]
    fn line_breaks_in_check_names_stay_on_one_line() {
        let out = lines(&[pr(3, H, "BLOCKED", &[("lint\nunit", "FAILURE")])]);
        assert_eq!(out, ["stuck 3 check failed: lint\\nunit failure"]);
        let out = lines(&[pr(3, H, "BLOCKED", &[("a\r\nb", "QUEUED")])]);
        assert_eq!(out, ["wait 3 open 1.0h, merge state blocked, pending: a\\r\\nb"]);
        assert!(out.iter().all(|l| !l.contains('\n') && !l.contains('\r')));
    }

    fn w(s: &str) -> Window {
        Window::parse(s).unwrap()
    }

    #[test]
    fn behind_outside_the_window_waits_and_inside_is_rebased() {
        // NOW is 2026-11-23T02:13:20Z.
        let prs = [pr(1, H, "BEHIND", &[("flake-check", "SUCCESS")])];
        let at = |now: i64, win: &str| decide(&prs, now, 6 * H, Some(w(win))).iter().map(ToString::to_string).collect::<Vec<_>>();
        assert_eq!(
            at(NOW, "05:00-06:00"),
            ["wait 1 open 1.0h, merge state behind, no checks pending, rebase waits for 05:00-06:00 UTC"]
        );
        assert_eq!(at(NOW, "02:00-03:00"), ["rebase 1"]);
        assert_eq!(at(NOW, "02:13-02:14"), ["rebase 1"]);
        assert!(at(NOW, "02:14-03:00")[0].starts_with("wait 1"));
        assert_eq!(at(NOW, "23:30-02:14"), ["rebase 1"]);
        let old = [pr(1, 7 * H, "BEHIND", &[])];
        assert_eq!(
            decide(&old, NOW, 6 * H, Some(w("05:00-06:00"))).iter().map(ToString::to_string).collect::<Vec<_>>(),
            ["stuck 1 not merged after 6.0h (open 7.0h, merge state behind, no checks pending, rebase waits for 05:00-06:00 UTC)"]
        );
    }

    #[test]
    fn the_window_does_not_change_other_states() {
        let prs = [pr(1, H, "BLOCKED", &[])];
        assert_eq!(
            decide(&prs, NOW, 6 * H, Some(w("00:30-04:30"))),
            decide(&prs, NOW, 6 * H, None)
        );
    }

    #[test]
    fn window_contains() {
        let day = 1_795_132_800; // 2026-11-20T00:00:00Z
        let at = |h: i64, m: i64| day + h * H + m * 60;
        let night = w("00:30-04:30");
        assert!(!night.contains(at(0, 29)));
        assert!(night.contains(at(0, 30)));
        assert!(night.contains(at(4, 29)));
        assert!(!night.contains(at(4, 30)));
        assert!(!night.contains(at(12, 0)));
        let wrap = w("23:30-04:30");
        assert!(wrap.contains(at(23, 30)));
        assert!(wrap.contains(at(0, 0)));
        assert!(wrap.contains(at(4, 29)));
        assert!(!wrap.contains(at(4, 30)));
        assert!(!wrap.contains(at(23, 29)));
        assert!(w("00:00-00:01").contains(-86_400));
    }

    #[test]
    fn window_parse_and_display() {
        assert_eq!(w("00:30-04:30").to_string(), "00:30-04:30 UTC");
        assert_eq!(w("23:59-00:00").to_string(), "23:59-00:00 UTC");
        for bad in ["", "00:30", "00:30-", "0:30-04:30", "00:30-04:3", "24:00-01:00", "00:60-02:00", "01:00-01:00",
                    "aa:bb-01:00", "00:30-04:30-05:00", "+1:30-04:30", "00:30-04:+3"] {
            assert_eq!(Window::parse(bad), None, "{bad}");
        }
    }

    #[test]
    fn conflicts_are_reported() {
        assert_eq!(lines(&[pr(4, H, "DIRTY", &[])]), ["stuck 4 conflicts with main; tomorrow's nightly will replace it"]);
    }

    #[test]
    fn drafts_are_reported() {
        let mut p = pr(5, H, "CLEAN", &[]);
        p.draft = true;
        assert_eq!(lines(&[p]), ["stuck 5 is a draft, so auto-merge will not merge it"]);
    }

    #[test]
    fn older_nightlies_are_superseded_and_only_the_newest_is_acted_on() {
        let prs = [pr(9, H, "BEHIND", &[]), pr(8, 30 * H, "BEHIND", &[("flake-check", "FAILURE")])];
        assert_eq!(lines(&prs), ["stuck 8 superseded by #9 but still open; the nightly job could not close it", "rebase 9"]);
    }

    #[test]
    fn same_creation_time_orders_by_number() {
        let prs = [pr(11, H, "CLEAN", &[]), pr(10, H, "CLEAN", &[])];
        assert!(lines(&prs)[0].starts_with("stuck 10 superseded by #11"));
    }

    #[test]
    fn other_branches_are_ignored() {
        let mut review = pr(12, 100 * H, "DIRTY", &[]);
        review.branch = "flake-review-1-1".into();
        assert!(lines(&[review]).is_empty());
        assert!(lines(&[]).is_empty());
    }

    #[test]
    fn parses_gh_output() {
        let text = r#"[{"number": 1070, "headRefName": "flake-update-45280843759-1", "isDraft": false,
            "createdAt": "2026-11-23T22:39:57Z", "mergeStateStatus": "BEHIND",
            "statusCheckRollup": [
              {"__typename": "CheckRun", "name": "flake-check", "status": "COMPLETED", "conclusion": "SUCCESS"},
              {"__typename": "CheckRun", "name": "repo-claims", "status": "IN_PROGRESS", "conclusion": ""},
              {"__typename": "StatusContext", "context": "CodeRabbit", "state": "pending"}
            ]},
            {"number": 2, "headRefName": "x", "createdAt": "2026-11-23T00:00:00Z", "mergeStateStatus": "clean",
             "statusCheckRollup": null}]"#;
        let prs = parse_prs(text).unwrap();
        assert_eq!(prs.len(), 2);
        assert_eq!(prs[0].number, 1070);
        assert_eq!(prs[0].created, parse_utc_timestamp("2026-11-23T22:39:57Z").unwrap());
        assert_eq!(
            prs[0].checks,
            [
                Check { name: "flake-check".into(), state: "SUCCESS".into() },
                Check { name: "repo-claims".into(), state: "IN_PROGRESS".into() },
                Check { name: "CodeRabbit".into(), state: "PENDING".into() },
            ]
        );
        assert!(!prs[0].draft);
        assert_eq!(prs[1].merge_state, "CLEAN");
        assert!(prs[1].checks.is_empty());
    }

    #[test]
    fn a_check_with_no_state_is_pending() {
        let prs = parse_prs(r#"[{"number": 1, "headRefName": "flake-update-1", "createdAt": "2026-11-23T00:00:00Z",
            "mergeStateStatus": "BLOCKED", "statusCheckRollup": [{"name": "flake-check"}]}]"#)
        .unwrap();
        assert_eq!(prs[0].checks[0].state, "PENDING");
    }

    #[test]
    fn parse_errors_name_the_problem() {
        let err = |t: &str| parse_prs(t).unwrap_err();
        assert!(err("nope").starts_with("not JSON"));
        assert_eq!(err("{}"), "expected a JSON array of pull requests");
        assert_eq!(err("[{}]"), "pull request [0]: missing `number`");
        assert_eq!(err(r#"[{"number": -1}]"#), "pull request [0]: `number` is not a positive integer");
        let base = r#""number": 1, "headRefName": "b", "mergeStateStatus": "CLEAN""#;
        assert_eq!(
            err(&format!(r#"[{{{base}, "createdAt": "yesterday"}}]"#)),
            "pull request [0]: `createdAt` \"yesterday\" is not a UTC timestamp"
        );
        let base = format!(r#"{base}, "createdAt": "2026-11-23T00:00:00Z""#);
        assert_eq!(
            err(&format!(r#"[{{{base}, "statusCheckRollup": {{}}}}]"#)),
            "pull request [0]: `statusCheckRollup` is not an array"
        );
        assert_eq!(
            err(&format!(r#"[{{{base}, "statusCheckRollup": [{{"state": "SUCCESS"}}]}}]"#)),
            "pull request [0]: a status check has neither `name` nor `context`"
        );
        assert_eq!(
            err(r#"[{"number": 1, "headRefName": 3, "createdAt": "2026-11-23T00:00:00Z", "mergeStateStatus": "CLEAN"}]"#),
            "pull request [0]: `headRefName` is not a string"
        );
    }
}

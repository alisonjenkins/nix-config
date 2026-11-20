//! `update-policy bump`: moves each direct flake input to the newest upstream
//! commit that has been visible for at least its tier's cooldown.
//!
//! Age is measured from when this tool first saw a commit at the head of the
//! input's branch, recorded in `pins/flake-seen.json`. Commit dates are not
//! used: anyone can set them, so a backdated commit would skip the cooldown.

use crate::date::Date;
use crate::sources::Sources;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fmt;

/// How many observations to keep per input. At one run a night this is
/// about two months, far longer than any cooldown.
pub const HISTORY: usize = 60;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirectInput {
    pub name: String,
    pub owner: String,
    pub repo: String,
    /// Branch or tag from flake.nix; `None` means the default branch.
    pub reference: Option<String>,
    /// A `rev` written in flake.nix: a deliberate pin, never bumped here.
    pub pinned: bool,
    pub locked_rev: String,
}

impl DirectInput {
    pub fn key(&self) -> String {
        format!("github:{}/{}", self.owner, self.repo).to_lowercase()
    }

    /// Where the input comes from. History is reset if this changes.
    pub fn source(&self) -> String {
        match &self.reference {
            Some(r) => format!("{}@{r}", self.key()),
            None => self.key(),
        }
    }

    /// A nixpkgs channel branch, already gated by Hydra.
    pub fn is_channel(&self) -> bool {
        self.key() == "github:nixos/nixpkgs"
            && self
                .reference
                .as_deref()
                .is_some_and(|r| r.starts_with("nixos-") || r.starts_with("nixpkgs-"))
    }

    pub fn url_at(&self, rev: &str) -> String {
        format!("github:{}/{}/{rev}", self.owner, self.repo)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Skipped {
    pub name: String,
    pub reason: String,
}

/// Direct inputs of the root flake. Inputs this tool cannot move (not on
/// GitHub, or `follows` another input) are returned as skipped with a reason.
pub fn direct_inputs(lock_text: &str) -> Result<(Vec<DirectInput>, Vec<Skipped>), String> {
    let lock: Value = serde_json::from_str(lock_text).map_err(|e| format!("flake.lock is not valid JSON: {e}"))?;
    let nodes = lock.get("nodes").and_then(Value::as_object).ok_or("flake.lock has no `nodes`")?;
    let root_name = lock.get("root").and_then(Value::as_str).ok_or("flake.lock has no `root`")?;
    let root = nodes.get(root_name).ok_or_else(|| format!("flake.lock root `{root_name}` is missing"))?;
    let mut inputs = Vec::new();
    let mut skipped = Vec::new();
    let Some(edges) = root.get("inputs").and_then(Value::as_object) else {
        return Ok((inputs, skipped));
    };
    for (name, target) in edges {
        let Some(node_name) = target.as_str() else {
            skipped.push(Skipped { name: name.clone(), reason: "follows another input".into() });
            continue;
        };
        let node = &nodes[node_name];
        let get = |section: &str, k: &str| node.get(section).and_then(|s| s.get(k)).and_then(Value::as_str);
        match get("original", "type") {
            Some("github") => {}
            other => {
                skipped.push(Skipped {
                    name: name.clone(),
                    reason: format!(
                        "source type `{}` is not supported yet; only github inputs are bumped",
                        other.unwrap_or("none")
                    ),
                });
                continue;
            }
        }
        let (Some(owner), Some(repo), Some(locked_rev)) =
            (get("original", "owner"), get("original", "repo"), get("locked", "rev"))
        else {
            return Err(format!("flake.lock node `{node_name}` is missing owner, repo or locked rev"));
        };
        inputs.push(DirectInput {
            name: name.clone(),
            owner: owner.to_string(),
            repo: repo.to_string(),
            reference: get("original", "ref").map(str::to_string),
            pinned: get("original", "rev").is_some(),
            locked_rev: locked_rev.to_string(),
        });
    }
    Ok((inputs, skipped))
}

/// Picks the commit a ref points at from `git ls-remote <url> <ref>` output.
/// For an annotated tag the peeled commit (`^{}`) wins.
pub fn parse_ls_remote(output: &str, reference: Option<&str>) -> Option<String> {
    let lines: Vec<(&str, &str)> = output
        .lines()
        .filter_map(|l| l.split_once('\t'))
        .filter(|(sha, _)| sha.len() == 40 && sha.bytes().all(|b| b.is_ascii_hexdigit()))
        .collect();
    let find = |name: &str| lines.iter().find(|(_, r)| *r == name).map(|(s, _)| s.to_string());
    match reference {
        None => find("HEAD"),
        Some(r) => find(&format!("refs/tags/{r}^{{}}"))
            .or_else(|| find(&format!("refs/heads/{r}")))
            .or_else(|| find(&format!("refs/tags/{r}")))
            .or_else(|| find(r)),
    }
}

/// Reads each input's upstream head with `git ls-remote`, which needs no
/// API token and is not subject to the REST API's rate limits.
pub fn fetch_heads(inputs: &[DirectInput]) -> Heads {
    let mut heads = Heads::new();
    for input in inputs.iter().filter(|i| !i.pinned) {
        let url = format!("https://github.com/{}/{}", input.owner, input.repo);
        let pattern = input.reference.clone().unwrap_or_else(|| "HEAD".into());
        let result = std::process::Command::new("git")
            .args(["ls-remote", &url, &pattern])
            .env("GIT_TERMINAL_PROMPT", "0")
            .output()
            .map_err(|e| format!("could not run git: {e}"))
            .and_then(|out| {
                if !out.status.success() {
                    return Err(format!(
                        "`git ls-remote {url} {pattern}` failed: {}",
                        String::from_utf8_lossy(&out.stderr).trim()
                    ));
                }
                parse_ls_remote(&String::from_utf8_lossy(&out.stdout), input.reference.as_deref())
                    .ok_or_else(|| format!("`{pattern}` was not found in {url}"))
            });
        heads.insert(input.name.clone(), result);
    }
    heads
}

/// Reads `{"input": "rev", ...}`, for tests and dry runs without network.
pub fn parse_heads(text: &str) -> Result<Heads, String> {
    let map: BTreeMap<String, String> =
        serde_json::from_str(text).map_err(|e| format!("heads file must be a JSON object of input name to rev: {e}"))?;
    Ok(map.into_iter().map(|(k, v)| (k, Ok(v))).collect())
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct SeenFile {
    pub schema: u64,
    #[serde(rename = "_doc", default, skip_serializing_if = "Option::is_none")]
    pub doc: Option<String>,
    pub inputs: BTreeMap<String, SeenInput>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct SeenInput {
    pub source: String,
    pub seen: Vec<Seen>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Seen {
    pub rev: String,
    pub first_seen: String,
}

pub const SEEN_DOC: &str = "Written by `update-policy bump` (pkgs/update-policy). When each upstream commit was first seen at the head of a flake input's branch; the update policy's cooldown is measured from this, not from commit dates, which can be set to anything. Do not edit by hand.";

impl SeenFile {
    pub fn parse(text: &str) -> Result<SeenFile, String> {
        let f: SeenFile = serde_json::from_str(text).map_err(|e| format!("not a valid seen file: {e}"))?;
        if f.schema != 1 {
            return Err(format!("seen file schema {} is not supported (expected 1)", f.schema));
        }
        Ok(f)
    }

    pub fn to_json(&self) -> String {
        let mut out = SeenFile { schema: 1, doc: Some(SEEN_DOC.into()), inputs: self.inputs.clone() };
        out.inputs.retain(|_, v| !v.seen.is_empty());
        serde_json::to_string_pretty(&out).expect("seen file serialises") + "\n"
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Group {
    /// The tier auto-merges.
    Auto,
    /// The tier needs a human: a separate PR.
    Manual,
}

impl fmt::Display for Group {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Group::Auto => "auto",
            Group::Manual => "manual",
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    Update { to: String, first_seen: Date },
    UpToDate,
    /// Upstream has moved, but nothing newer than the lock is old enough.
    /// `next` is the oldest commit newer than the lock: the first to qualify.
    Waiting { next: String, ready_on: Date },
    Skip(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decision {
    pub input: DirectInput,
    pub tier: Option<String>,
    pub cooldown_days: u32,
    pub group: Group,
    pub action: Action,
}

/// The upstream head of each input, or why it could not be read.
pub type Heads = BTreeMap<String, Result<String, String>>;

/// Records today's heads in `seen` and decides what each input moves to.
pub fn plan(inputs: &[DirectInput], heads: &Heads, seen: &mut SeenFile, sources: &Sources, today: Date) -> Vec<Decision> {
    let today_s = today.to_string();
    let mut out = Vec::new();
    for input in inputs {
        let entry = sources.resolve(&input.key());
        let tier = entry.map(|e| e.tier.clone());
        let tier_def = tier.as_ref().and_then(|t| sources.tiers.get(t));
        let cooldown_days = match tier_def {
            Some(t) if input.is_channel() => t.channel_cooldown_days.unwrap_or(t.cooldown_days),
            Some(t) => t.cooldown_days,
            None => 0,
        };
        let group = if tier_def.is_some_and(|t| t.automerge) { Group::Auto } else { Group::Manual };
        let decide = |action| Decision { input: input.clone(), tier: tier.clone(), cooldown_days, group, action };

        if input.pinned {
            out.push(decide(Action::Skip("pinned to a rev in flake.nix (see pins/registry.json)".into())));
            continue;
        }
        if tier_def.is_none() {
            out.push(decide(Action::Skip(format!(
                "`{}` has no trust tier in pins/sources.json; run `update-policy check`",
                input.key()
            ))));
            continue;
        }
        let head = match heads.get(&input.name) {
            Some(Ok(h)) => h.clone(),
            Some(Err(e)) => {
                out.push(decide(Action::Skip(format!("could not read upstream: {e}"))));
                continue;
            }
            None => {
                out.push(decide(Action::Skip("no upstream head was looked up".into())));
                continue;
            }
        };

        let record = seen.inputs.entry(input.name.clone()).or_default();
        if record.source != input.source() {
            // flake.nix now points somewhere else: old observations do not apply.
            *record = SeenInput { source: input.source(), seen: Vec::new() };
        }
        if record.seen.last().map(|s| s.rev.as_str()) != Some(head.as_str()) {
            record.seen.retain(|s| s.rev != head);
            record.seen.push(Seen { rev: head.clone(), first_seen: today_s.clone() });
        }
        let excess = record.seen.len().saturating_sub(HISTORY);
        record.seen.drain(..excess);

        if head == input.locked_rev {
            out.push(decide(Action::UpToDate));
            continue;
        }
        // Newest observation old enough, searching back from the head. Stop
        // at the locked rev: anything before it is older than what we have.
        let mut chosen = None;
        for s in record.seen.iter().rev() {
            if s.rev == input.locked_rev {
                break;
            }
            let Some(first) = Date::parse(&s.first_seen) else { continue };
            if first.days_until(today) >= i64::from(cooldown_days) {
                chosen = Some((s.rev.clone(), first));
                break;
            }
        }
        let action = match chosen {
            Some((to, first_seen)) => Action::Update { to, first_seen },
            None => {
                // The oldest observation after the lock qualifies first.
                let next = record
                    .seen
                    .iter()
                    .rev()
                    .take_while(|s| s.rev != input.locked_rev)
                    .last()
                    .expect("the head was just recorded and differs from the lock");
                let first = Date::parse(&next.first_seen).unwrap_or(today);
                Action::Waiting { next: next.rev.clone(), ready_on: first.plus_days(cooldown_days) }
            }
        };
        out.push(decide(action));
    }
    out
}

fn short(rev: &str) -> &str {
    &rev[..rev.len().min(8)]
}

/// Markdown for the PR body: what moved, what is waiting, and why.
pub fn summary(decisions: &[Decision], skipped: &[Skipped], group: Option<Group>, today: Date) -> String {
    let in_group = |d: &&Decision| group.is_none_or(|g| d.group == g);
    let mut s = String::new();
    let updates: Vec<&Decision> = decisions.iter().filter(in_group).filter(|d| matches!(d.action, Action::Update { .. })).collect();
    let waiting: Vec<&Decision> = decisions.iter().filter(in_group).filter(|d| matches!(d.action, Action::Waiting { .. })).collect();
    let skips: Vec<&Decision> = decisions.iter().filter(in_group).filter(|d| matches!(d.action, Action::Skip(_))).collect();

    s.push_str(&format!("Flake inputs bumped by `update-policy bump` on {today} (docs/update-policy.md).\n\n"));
    if updates.is_empty() {
        s.push_str("No input is due an update.\n");
    } else {
        s.push_str("| Input | Tier | From | To | First seen | Cooldown |\n| --- | --- | --- | --- | --- | --- |\n");
        for d in &updates {
            if let Action::Update { to, first_seen } = &d.action {
                s.push_str(&format!(
                    "| `{}` | {} | `{}` | `{}` | {} ({} days ago) | {} days |\n",
                    d.input.name,
                    d.tier.as_deref().unwrap_or("?"),
                    short(&d.input.locked_rev),
                    short(to),
                    first_seen,
                    first_seen.days_until(today),
                    d.cooldown_days
                ));
            }
        }
    }
    if !waiting.is_empty() {
        s.push_str("\nWaiting out their cooldown:\n\n");
        for d in &waiting {
            if let Action::Waiting { next, ready_on } = &d.action {
                s.push_str(&format!(
                    "- `{}` ({}): `{}` is eligible on {ready_on}\n",
                    d.input.name,
                    d.tier.as_deref().unwrap_or("?"),
                    short(next)
                ));
            }
        }
    }
    if !skips.is_empty() || !skipped.is_empty() {
        s.push_str("\nNot bumped:\n\n");
        for d in &skips {
            if let Action::Skip(why) = &d.action {
                s.push_str(&format!("- `{}`: {why}\n", d.input.name));
            }
        }
        if group.is_none() {
            for k in skipped {
                s.push_str(&format!("- `{}`: {}\n", k.name, k.reason));
            }
        }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    const SOURCES: &str = r#"{"schema": 1,
      "tiers": {
        "own": {"cooldown_days": 0, "automerge": true, "description": "o"},
        "core": {"cooldown_days": 3, "automerge": true, "channel_cooldown_days": 0, "description": "c"},
        "established": {"cooldown_days": 7, "automerge": true, "description": "e"},
        "sensitive": {"cooldown_days": 7, "automerge": false, "description": "s"}
      },
      "sources": [
        {"match": "github:nixos/nixpkgs", "tier": "core"},
        {"match": "github:nix-community/*", "tier": "established"},
        {"match": "github:nix-community/lanzaboote", "tier": "sensitive"},
        {"match": "github:alisonjenkins/*", "tier": "own"}
      ]}"#;

    fn sources() -> Sources {
        Sources::parse(SOURCES).unwrap()
    }
    fn d(s: &str) -> Date {
        Date::parse(s).unwrap()
    }
    fn rev(c: char) -> String {
        std::iter::repeat_n(c, 40).collect()
    }
    fn input(name: &str, owner: &str, repo: &str, reference: Option<&str>, locked: char) -> DirectInput {
        DirectInput {
            name: name.into(),
            owner: owner.into(),
            repo: repo.into(),
            reference: reference.map(str::to_string),
            pinned: false,
            locked_rev: rev(locked),
        }
    }
    fn heads(pairs: &[(&str, char)]) -> Heads {
        pairs.iter().map(|(n, c)| (n.to_string(), Ok(rev(*c)))).collect()
    }
    fn seen_with(name: &str, source: &str, obs: &[(char, &str)]) -> SeenFile {
        let mut f = SeenFile { schema: 1, doc: None, inputs: BTreeMap::new() };
        f.inputs.insert(
            name.into(),
            SeenInput {
                source: source.into(),
                seen: obs.iter().map(|(c, date)| Seen { rev: rev(*c), first_seen: date.to_string() }).collect(),
            },
        );
        f
    }

    #[test]
    fn new_head_waits_for_the_cooldown() {
        let disko = input("disko", "nix-community", "disko", None, 'a');
        let mut seen = SeenFile::default();
        let got = plan(&[disko.clone()], &heads(&[("disko", 'b')]), &mut seen, &sources(), d("2026-11-20"));
        assert_eq!(got[0].action, Action::Waiting { next: rev('b'), ready_on: d("2026-11-27") });
        assert_eq!(got[0].cooldown_days, 7);
        assert_eq!(got[0].group, Group::Auto);
        assert_eq!(seen.inputs["disko"].seen, vec![Seen { rev: rev('b'), first_seen: "2026-11-20".into() }]);
        assert_eq!(seen.inputs["disko"].source, "github:nix-community/disko");

        // Six days later it is still waiting, and the record is unchanged.
        let got = plan(&[disko.clone()], &heads(&[("disko", 'b')]), &mut seen, &sources(), d("2026-11-26"));
        assert!(matches!(got[0].action, Action::Waiting { .. }));
        assert_eq!(seen.inputs["disko"].seen.len(), 1);

        // Seven days after it was first seen it moves.
        let got = plan(&[disko], &heads(&[("disko", 'b')]), &mut seen, &sources(), d("2026-11-27"));
        assert_eq!(got[0].action, Action::Update { to: rev('b'), first_seen: d("2026-11-20") });
    }

    #[test]
    fn takes_the_newest_aged_commit_not_the_head() {
        let disko = input("disko", "nix-community", "disko", None, 'a');
        let mut seen = seen_with("disko", "github:nix-community/disko", &[('b', "2026-11-01"), ('c', "2026-11-10"), ('d', "2026-11-19")]);
        let got = plan(&[disko], &heads(&[("disko", 'e')]), &mut seen, &sources(), d("2026-11-20"));
        assert_eq!(got[0].action, Action::Update { to: rev('c'), first_seen: d("2026-11-10") });
        let revs: Vec<char> = seen.inputs["disko"].seen.iter().map(|s| s.rev.chars().next().unwrap()).collect();
        assert_eq!(revs, vec!['b', 'c', 'd', 'e']);
    }

    #[test]
    fn never_moves_backwards_past_the_lock() {
        // The lock is already at `c`; `b` is older and aged, but not newer.
        let disko = input("disko", "nix-community", "disko", None, 'c');
        let mut seen = seen_with("disko", "github:nix-community/disko", &[('b', "2026-11-01"), ('c', "2026-11-02"), ('d', "2026-11-19")]);
        let got = plan(&[disko], &heads(&[("disko", 'd')]), &mut seen, &sources(), d("2026-11-20"));
        assert_eq!(got[0].action, Action::Waiting { next: rev('d'), ready_on: d("2026-11-26") });
    }

    #[test]
    fn waiting_reports_the_first_commit_to_qualify() {
        let disko = input("disko", "nix-community", "disko", None, 'a');
        let mut seen = seen_with("disko", "github:nix-community/disko", &[('a', "2026-11-01"), ('b', "2026-11-15"), ('c', "2026-11-18")]);
        let got = plan(&[disko], &heads(&[("disko", 'd')]), &mut seen, &sources(), d("2026-11-20"));
        assert_eq!(got[0].action, Action::Waiting { next: rev('b'), ready_on: d("2026-11-22") });
    }

    #[test]
    fn channels_and_own_have_no_cooldown() {
        let unstable = input("nixpkgs_unstable", "nixos", "nixpkgs", Some("nixos-unstable"), 'a');
        let master = input("nixpkgs_master", "nixos", "nixpkgs", None, 'a');
        let mine = input("ali-neovim", "alisonjenkins", "neovim-nix-flake", None, 'a');
        assert!(unstable.is_channel());
        assert!(input("x", "NixOS", "nixpkgs", Some("nixpkgs-25.11-darwin"), 'a').is_channel());
        assert!(!master.is_channel());
        assert!(!input("x", "nixos", "nixpkgs", Some("release-26.05"), 'a').is_channel());
        assert!(!input("x", "nixos", "nixos-hardware", Some("nixos-unstable"), 'a').is_channel());
        let mut seen = SeenFile::default();
        let got = plan(
            &[unstable, master, mine],
            &heads(&[("nixpkgs_unstable", 'b'), ("nixpkgs_master", 'b'), ("ali-neovim", 'b')]),
            &mut seen,
            &sources(),
            d("2026-11-20"),
        );
        assert_eq!(got[0].action, Action::Update { to: rev('b'), first_seen: d("2026-11-20") });
        assert_eq!(got[0].cooldown_days, 0);
        assert_eq!(got[1].action, Action::Waiting { next: rev('b'), ready_on: d("2026-11-23") });
        assert_eq!(got[1].cooldown_days, 3);
        assert_eq!(got[2].action, Action::Update { to: rev('b'), first_seen: d("2026-11-20") });
    }

    #[test]
    fn sensitive_goes_to_the_manual_group() {
        let lz = input("lanzaboote", "nix-community", "lanzaboote", Some("master"), 'a');
        let mut seen = seen_with("lanzaboote", "github:nix-community/lanzaboote@master", &[('b', "2026-11-01")]);
        let got = plan(&[lz], &heads(&[("lanzaboote", 'b')]), &mut seen, &sources(), d("2026-11-20"));
        assert_eq!(got[0].group, Group::Manual);
        assert_eq!(got[0].tier.as_deref(), Some("sensitive"));
        assert!(matches!(got[0].action, Action::Update { .. }));
    }

    #[test]
    fn up_to_date_pinned_untiered_and_unreachable() {
        let ok = input("disko", "nix-community", "disko", None, 'a');
        let mut pinned = input("rea", "nixos", "nixpkgs", None, 'a');
        pinned.pinned = true;
        let untiered = input("x", "who", "what", None, 'a');
        let broken = input("impermanence", "nix-community", "impermanence", None, 'a');
        let missing = input("haumea", "nix-community", "haumea", None, 'a');
        let mut h = heads(&[("disko", 'a'), ("rea", 'b'), ("x", 'b')]);
        h.insert("impermanence".into(), Err("connection reset".into()));
        let mut seen = SeenFile::default();
        let got = plan(&[ok, pinned, untiered, broken, missing], &h, &mut seen, &sources(), d("2026-11-20"));
        assert_eq!(got[0].action, Action::UpToDate);
        assert_eq!(got[1].action, Action::Skip("pinned to a rev in flake.nix (see pins/registry.json)".into()));
        assert_eq!(
            got[2].action,
            Action::Skip("`github:who/what` has no trust tier in pins/sources.json; run `update-policy check`".into())
        );
        assert_eq!(got[2].group, Group::Manual);
        assert_eq!(got[3].action, Action::Skip("could not read upstream: connection reset".into()));
        assert_eq!(got[4].action, Action::Skip("no upstream head was looked up".into()));
        // Only reachable, tiered, unpinned inputs are recorded.
        assert_eq!(seen.inputs.keys().collect::<Vec<_>>(), vec!["disko"]);
    }

    #[test]
    fn a_changed_source_resets_history() {
        let hm = input("home-manager", "nix-community", "home-manager", Some("release-26.11"), 'a');
        let mut seen = seen_with("home-manager", "github:nix-community/home-manager@release-26.05", &[('b', "2026-10-01")]);
        let got = plan(&[hm], &heads(&[("home-manager", 'b')]), &mut seen, &sources(), d("2026-11-20"));
        assert!(matches!(got[0].action, Action::Waiting { .. }), "{got:?}");
        assert_eq!(seen.inputs["home-manager"].source, "github:nix-community/home-manager@release-26.11");
        assert_eq!(seen.inputs["home-manager"].seen[0].first_seen, "2026-11-20");
    }

    #[test]
    fn a_head_that_returns_keeps_its_first_seen_date_only_if_still_last() {
        // b seen, then c, then upstream force-pushes back to b: b is new again.
        let disko = input("disko", "nix-community", "disko", None, 'a');
        let mut seen = seen_with("disko", "github:nix-community/disko", &[('b', "2026-11-01"), ('c', "2026-11-05")]);
        plan(&[disko], &heads(&[("disko", 'b')]), &mut seen, &sources(), d("2026-11-20"));
        let obs: Vec<(char, &str)> =
            seen.inputs["disko"].seen.iter().map(|s| (s.rev.chars().next().unwrap(), s.first_seen.as_str())).collect();
        assert_eq!(obs, vec![('c', "2026-11-05"), ('b', "2026-11-20")]);
    }

    #[test]
    fn history_is_capped() {
        let disko = input("disko", "nix-community", "disko", None, 'a');
        let mut seen = SeenFile::default();
        let start = d("2026-01-01");
        for i in 0..(HISTORY + 5) {
            let head = format!("{:040x}", i + 1);
            let mut h = Heads::new();
            h.insert("disko".into(), Ok(head));
            plan(&[disko.clone()], &h, &mut seen, &sources(), start.plus_days(i as u32));
        }
        let s = &seen.inputs["disko"].seen;
        assert_eq!(s.len(), HISTORY);
        assert_eq!(s[0].rev, format!("{:040x}", 6));
    }

    #[test]
    fn reads_direct_inputs_from_the_lock() {
        let lock = r#"{"version": 7, "root": "root", "nodes": {
          "root": {"inputs": {"nixpkgs": "nixpkgs", "hm": "hm", "pinned": "pinned", "f": ["nixpkgs"], "t": "t"}},
          "nixpkgs": {"locked": {"rev": "aaaa"}, "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable"}},
          "hm": {"locked": {"rev": "bbbb"}, "original": {"type": "github", "owner": "nix-community", "repo": "home-manager"}},
          "pinned": {"locked": {"rev": "cccc"}, "original": {"type": "github", "owner": "x", "repo": "y", "rev": "cccc"}},
          "t": {"locked": {}, "original": {"type": "tarball", "url": "https://x"}}
        }}"#;
        let (inputs, skipped) = direct_inputs(lock).unwrap();
        assert_eq!(inputs.len(), 3);
        assert_eq!(inputs[1].name, "nixpkgs");
        assert_eq!(inputs[1].reference.as_deref(), Some("nixos-unstable"));
        assert_eq!(inputs[1].source(), "github:nixos/nixpkgs@nixos-unstable");
        assert_eq!(inputs[1].url_at("abc"), "github:NixOS/nixpkgs/abc");
        assert!(inputs[2].pinned);
        assert!(!inputs[0].pinned);
        assert_eq!(
            skipped,
            vec![
                Skipped { name: "f".into(), reason: "follows another input".into() },
                Skipped { name: "t".into(), reason: "source type `tarball` is not supported yet; only github inputs are bumped".into() },
            ]
        );
        assert!(direct_inputs("{").unwrap_err().contains("not valid JSON"));
        assert!(direct_inputs(r#"{"root": "root", "nodes": {}}"#).unwrap_err().contains("root `root` is missing"));
        let bad = r#"{"root": "root", "nodes": {"root": {"inputs": {"a": "a"}}, "a": {"original": {"type": "github"}}}}"#;
        assert!(direct_inputs(bad).unwrap_err().contains("missing owner, repo or locked rev"));
        let none = r#"{"root": "root", "nodes": {"root": {}}}"#;
        assert_eq!(direct_inputs(none).unwrap(), (vec![], vec![]));
    }

    #[test]
    fn ls_remote_parsing() {
        let a = rev('a');
        let b = rev('b');
        let c = rev('c');
        let out = format!("{a}\tHEAD\n{b}\trefs/heads/main\n{a}\trefs/tags/v1\n{c}\trefs/tags/v1^{{}}\nnot-a-sha\trefs/heads/x\n");
        assert_eq!(parse_ls_remote(&out, None), Some(a.clone()));
        assert_eq!(parse_ls_remote(&out, Some("main")), Some(b.clone()));
        assert_eq!(parse_ls_remote(&out, Some("v1")), Some(c));
        assert_eq!(parse_ls_remote(&format!("{a}\trefs/tags/v2\n"), Some("v2")), Some(a.clone()));
        assert_eq!(parse_ls_remote(&format!("{b}\trefs/heads/main\n{a}\trefs/tags/main\n"), Some("main")), Some(b.clone()));
        assert_eq!(parse_ls_remote(&format!("{a}\tweird\n"), Some("weird")), Some(a));
        assert_eq!(parse_ls_remote(&out, Some("x")), None);
        assert_eq!(parse_ls_remote("", None), None);
        let not_hex: String = std::iter::repeat_n('z', 40).collect();
        assert_eq!(parse_ls_remote(&format!("{not_hex}\tHEAD\n"), None), None);
        assert_eq!(parse_ls_remote("abc123\tHEAD\n", None), None);
    }

    #[test]
    fn seen_file_round_trip() {
        let f = seen_with("disko", "github:nix-community/disko", &[('b', "2026-11-01")]);
        let mut empty = f.clone();
        empty.inputs.insert("gone".into(), SeenInput { source: "x".into(), seen: vec![] });
        let text = empty.to_json();
        assert!(text.ends_with("}\n"));
        assert!(text.contains("Do not edit by hand"));
        let back = SeenFile::parse(&text).unwrap();
        assert_eq!(back.inputs, f.inputs);
        assert!(SeenFile::parse(r#"{"schema": 2, "inputs": {}}"#).unwrap_err().contains("schema 2"));
        assert!(SeenFile::parse("[]").unwrap_err().contains("not a valid seen file"));
    }

    #[test]
    fn summary_lists_moves_waits_and_skips() {
        let mk = |name: &str, tier: &str, group, action| Decision {
            input: input(name, "o", "r", None, 'a'),
            tier: Some(tier.into()),
            cooldown_days: 7,
            group,
            action,
        };
        let decisions = vec![
            mk("disko", "established", Group::Auto, Action::Update { to: rev('b'), first_seen: d("2026-11-10") }),
            mk("hm", "established", Group::Auto, Action::Waiting { next: rev('c'), ready_on: d("2026-11-25") }),
            mk("lz", "sensitive", Group::Manual, Action::Update { to: rev('d'), first_seen: d("2026-11-01") }),
            mk("x", "established", Group::Auto, Action::Skip("could not read upstream: boom".into())),
            mk("y", "established", Group::Auto, Action::UpToDate),
        ];
        let skipped = vec![Skipped { name: "f".into(), reason: "follows another input".into() }];
        let auto = summary(&decisions, &skipped, Some(Group::Auto), d("2026-11-20"));
        assert_eq!(
            auto,
            "Flake inputs bumped by `update-policy bump` on 2026-11-20 (docs/update-policy.md).\n\n\
             | Input | Tier | From | To | First seen | Cooldown |\n| --- | --- | --- | --- | --- | --- |\n\
             | `disko` | established | `aaaaaaaa` | `bbbbbbbb` | 2026-11-10 (10 days ago) | 7 days |\n\
             \nWaiting out their cooldown:\n\n- `hm` (established): `cccccccc` is eligible on 2026-11-25\n\
             \nNot bumped:\n\n- `x`: could not read upstream: boom\n"
        );
        let manual = summary(&decisions, &skipped, Some(Group::Manual), d("2026-11-20"));
        assert!(manual.contains("| `lz` | sensitive |"));
        assert!(!manual.contains("disko"));
        assert!(!manual.contains("follows"));
        let all = summary(&decisions, &skipped, None, d("2026-11-20"));
        assert!(all.contains("- `f`: follows another input"));
        let only_lock_skips = summary(&[], &skipped, None, d("2026-11-20"));
        assert!(only_lock_skips.ends_with("\nNot bumped:\n\n- `f`: follows another input\n"), "{only_lock_skips}");
        let none = summary(&[], &[], None, d("2026-11-20"));
        assert!(none.ends_with("No input is due an update.\n"));
    }

    #[test]
    fn heads_file() {
        let h = parse_heads(r#"{"disko": "abc"}"#).unwrap();
        assert_eq!(h["disko"], Ok("abc".to_string()));
        assert!(parse_heads("[1]").unwrap_err().contains("JSON object of input name to rev"));
    }

    #[test]
    fn group_display() {
        assert_eq!(Group::Auto.to_string(), "auto");
        assert_eq!(Group::Manual.to_string(), "manual");
    }
}

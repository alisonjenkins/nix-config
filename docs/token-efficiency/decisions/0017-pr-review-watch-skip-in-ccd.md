---
id: "0017"
host: Alisons-MacBook-Pro
date: 2026-11-11T12:20:00Z
finding: top-skills-dashboard-2026-11-11#1
decision: configure
reason: "git skill's pr-review-responses.md spends ~40% of its content (the 'Watching for a review' section, ~900 of 2079 words) on a manual polling mechanism that the Claude Desktop app's own ccd_pr tooling (bind_pr/get_status/set_monitor, 'Auto-fix') already supersedes, and this session's own environment instructions already forbid self-polling for PR review in this app; that section is read for nothing in every ccd_pr-enabled session that opens a PR"
metric: { question: not-pack-tracked, key: top-skills-dashboard:git, baseline: 0.56, unit: usd/use }
acted_on: null
outcome: null
outcome_review: null
---
The user's "Top skills" usage dashboard (last 30 days) showed `git` as the single most
expensive skill by cost-per-use ($0.56, 20 uses) and `programming` close behind ($0.47,
19 uses). Checking the skill files themselves: `programming/SKILL.md` (901 words) and
`git/SKILL.md` (526 words) are both dense routing tables, not padded prose — trimming
them would cost real guidance for negligible savings, so skill-definition bloat is not
the driver of these numbers; the cost is overwhelmingly the real work done under each
skill (diffs, debugging, PR review), not the skill file load.

One genuine exception: `home/skills/git/pr-review-responses.md` is the single heaviest
file in the git skill (2079 words, 3x `git/SKILL.md` itself), and `git/SKILL.md`'s
routing table says it "starts automatically on PR open" — so every PR opened in this
session (5 of them, this review alone) triggers reading it. Its "Watching for a review"
section (lines 19-129, roughly 900 words) describes a manual watch-script/ScheduleWakeup
polling mechanism, but in a Claude Desktop (`ccd_pr`-enabled) session that mechanism is
already superseded by the app's own PR monitoring, and the session's own environment
instructions explicitly forbid self-polling (`ScheduleWakeup`, Monitor, `gh` polling) for
exactly this. Added a guard note at the top of that section directing a `ccd_pr`-enabled
session straight to "Reading the threads," skipping the inapplicable ~900 words. The
rest of the file (reading/triaging/replying/resolving threads) is unaffected and still
applies everywhere.

This takes effect for future sessions once committed; it does not change any already-
spent tokens, and its savings are a few hundred words per PR-open event in ccd_pr
sessions specifically, not a large absolute figure. `metric` uses the dashboard's own
`git` skill cost-per-use ($0.56) as the closest available reference point, since this
finding came from that dashboard rather than a `cc-obs-query` pack question.

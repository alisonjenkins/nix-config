{
  # Headline rules only. The full workflow — commit-message format, splitting a
  # change, PR handling, worktrees — lives in the `git` skill, which is the
  # single source of truth. Keep these three lines here anyway: they are
  # safety-critical and must hold even when the skill is not loaded.
  gitStrategy = ''
    # Git Strategy (user mandate)

    - Atomic commits: each commit does exactly one granular thing; reverting it
      alone must leave the project compilable (assuming it compiled before).
      Never bundle unrelated changes into one commit.
    - Never squash — it destroys per-change revertability.
    - Merging PRs/branches: prefer rebase-and-merge (`gh pr merge --rebase`),
      else a merge commit (`gh pr merge --merge`); never `--squash`.
    - Invoke the `git` skill before committing, opening a PR, or merging: it
      carries the message format, the splitting rules, and the PR workflow.
  '';

  modelRouting = ''
    # Model Routing (user mandate)

    - Delegate mechanical stretches to a sub-agent (Agent tool) instead of
      grinding them in the main loop: any run of ~5+ bulk calls of the same
      shape — gh/GraphQL queries, web searches, log trawls. Prefer running
      these in the background (run_in_background) so the main loop is not
      blocked waiting on them.
    - Default the sub-agent model to "haiku"; step up to "sonnet" only when
      the task needs judgement, multi-step reasoning, or code changes. The
      main loop stays on the big model, reserved for voice, scope, and
      judgement.
    - Fast local search keeps inline reading cheap: the built-in Grep tool
      already uses ripgrep and works on every machine — make it the default for
      content search. At the shell, use `rg` (content) and `fd` (file/dir
      names) when present, but do not assume they are installed or at any fixed
      path: probe with `command -v` first, fall back to `grep -r` / `find`, and
      note `fd` may be packaged as `fdfind` on Debian/Ubuntu.
    - Invoke the `delegation` skill before spawning a sub-agent: it carries
      the model-tier decision test, when NOT to delegate at all, Explore vs
      general-purpose, and how to write a self-contained prompt.
    - Never delegate: user-facing judgement, irreversible actions, or work
      whose context cannot be compressed into a prompt.
  '';

  workStyle = ''
    # Working Principles (user mandate)

    - Restate the task in one sentence before starting anything that is more
      than a single mechanical edit: what is wrong today, and for whom. If the
      request named a solution rather than a problem ("add caching", "make it
      faster", "clean this up"), or the sentence only works with a guess in it,
      invoke the `requirements` skill before writing code — not to interrogate
      the user, but to decide what to assume out loud and what genuinely
      blocks.
    - Before writing, changing, or fixing code — including a one-line fix —
      invoke the `programming` skill and read its language file for whatever
      you are editing. Same for `testing` before touching tests and `review`
      before judging a diff. Debugging counts as changing code.
    - Times: ISO8601 UTC (e.g. 2026-06-10T14:03:22Z) in all files, logs, and
      reports.
    - UTF-8 everywhere; prefer formats both humans and machines can read
      (Markdown tables, JSON, CSV) over free-form dumps.
    - External systems: make interactions idempotent — check current state
      before mutating; safe to re-run.
    - Tenacity: retry transient failures with backoff before giving up; when a
      subtask is unrecoverable, degrade gracefully — deliver the rest and
      report the gap.
    - Infrastructure as code first: propose the change in the IaC repo and let
      CI/CD apply it. Direct mutation of live infrastructure (consoles, ad-hoc
      kubectl/aws edits) is sometimes acceptable for personal infra, but
      ALWAYS ask the user for permission first — never mutate live infra
      unprompted. Per-tool guidance: the `infra` skill.

    # Communication (user mandate)

    - Work autonomously with best judgement, but keep the user in the loop:
      surface load-bearing decisions as they are made.
    - Flag uncertainty and assumptions explicitly — never present a guess as
      fact.
    - Calm and factual; no speculation about people or motives.
    - Ask only when genuinely blocked; otherwise decide, act, and report the
      decision.
  '';
}

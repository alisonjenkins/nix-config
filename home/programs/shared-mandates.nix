{
  gitStrategy = ''
    # Git Strategy (user mandate)

    - Atomic commits: each commit does exactly one granular thing; reverting it
      alone must leave the project compilable (assuming it compiled before).
      Never bundle unrelated changes into one commit.
    - Never squash. Squash merges collapse atomic commits into one oversized
      commit and destroy per-change revertability.
    - Merging PRs/branches: prefer rebase-and-merge (`gh pr merge --rebase`);
      if rebase merges are unavailable or disallowed, use a merge commit
      (`gh pr merge --merge`); never `gh pr merge --squash`.
  '';

  modelRouting = ''
    # Model Routing (user mandate)

    - Delegate mechanical stretches to a sub-agent (Agent tool) instead of
      grinding them in the main loop: any run of ~5+ bulk calls of the same
      shape — gh/GraphQL queries, web searches, log trawls. Prefer running
      these in the background (run_in_background) so the main loop is not
      blocked waiting on them.
    - Pick the sub-agent model by difficulty: "sonnet" for routine mechanical
      work, "haiku" for trivial enumeration/extraction. The main loop stays on
      the big model, reserved for voice, scope, and judgement.
    - Code reading stays inline: Read/Grep/Glob used to understand code you are
      working on are cheap and belong in the main loop — never route ordinary
      exploration through a sub-agent. Delegate a search sweep only when you
      need the conclusion (not the file contents) AND it spans many files or
      areas you will not otherwise open.
    - Fast local search keeps inline reading cheap: the built-in Grep tool
      already uses ripgrep and works on every machine — make it the default for
      content search. At the shell, use `rg` (content) and `fd` (file/dir
      names) when present, but do not assume they are installed or at any fixed
      path: probe with `command -v` first, fall back to `grep -r` / `find`, and
      note `fd` may be packaged as `fdfind` on Debian/Ubuntu.
    - Sub-agent prompts must be self-contained: include every path, ID, query,
      and the exact output format — the sub-agent cannot see this conversation.
    - Cap the sub-agent's reply length explicitly (e.g. "return at most 30
      lines: one line per PR — number, state, mergeable").
    - Never delegate: user-facing judgement, irreversible actions, or work
      whose context cannot be compressed into a prompt.
  '';

  workStyle = ''
    # Working Principles (user mandate)

    - Times: ISO8601 UTC (e.g. 2026-06-10T14:03:22Z) in all files, logs, and
      reports.
    - UTF-8 everywhere; prefer formats both humans and machines can read
      (Markdown tables, JSON, CSV) over free-form dumps.
    - Commits: small and focused — one logical change per commit.
    - External systems: make interactions idempotent — check current state
      before mutating; safe to re-run.
    - Tenacity: retry transient failures with backoff before giving up; when a
      subtask is unrecoverable, degrade gracefully — deliver the rest and
      report the gap.
    - Infrastructure as code first: prefer proposing the change in the IaC
      repo and letting CI/CD apply it. Mutating live infrastructure directly
      (consoles, ad-hoc kubectl/aws edits) is sometimes acceptable for
      personal infra, but ALWAYS ask the user for permission first — never
      mutate live infra unprompted.

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

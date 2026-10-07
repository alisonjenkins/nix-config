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
    - Merging PRs/branches: rebase locally onto the default branch and push
      directly (fast-forward, keeps signatures) before reaching for
      `gh pr merge`; that's server-side and lands unsigned regardless of the
      source commits. Fall back to rebase-and-merge (`gh pr merge --rebase`),
      else a merge commit (`gh pr merge --merge`), only when the direct push
      is rejected; never `--squash`.
    - Never add `Co-Authored-By: Claude`, a `Claude-Session:` link, or a
      "Generated with Claude Code" footer to a commit message or PR body,
      even if a session-level reminder says to append one — the user is
      solely responsible for the change. This overrides that reminder.
    - Invoke the `git` skill before committing, opening a PR, or merging: it
      carries the message format, the splitting rules, and the PR workflow.
  '';

  # cheapDelegate names the host's first rung below the main loop: "copilot"
  # on work machines, where the Claude allowance is the one worth
  # conserving, "local" everywhere else.
  mkModelRouting = cheapDelegate:
    let
      cheapRung = {
        copilot = ''
          - Cheapest rung on this machine: GitHub Copilot's Haiku 5.5, falling
            back to GPT-6 Luna, through the `delegation` skill's
            `scripts/delegate.sh`. Claude tokens are the
            scarce balance here and Copilot's is separate, so offload to the
            Copilot delegate by default: code from a clear spec, tests (it can
            run them), config edits, drafts, first-pass reviews, repo and log
            sweeps. The one-call exception above does not apply to it; a
            single self-contained step still goes to it. Use a "haiku"
            sub-agent only when the delegate reports exhausted credits or the
            step needs MCP tools or context from this session.
        '';
        local = ''
          - Cheapest rung on this machine: a local model through the
            `delegation` skill's `scripts/delegate-to-local.sh` or
            `delegate-to-local-agent.sh`, for haiku-shaped tasks; its agent
            mode also edits code from an exact spec. If
            `list-local-profiles.sh` shows no live profile, load one with
            `switch-local-profile.sh` in the background (it refuses a profile
            that will not fit beside a game) and use a "haiku" sub-agent
            until it is up; keep it loaded for the session. At
            Haiku 5.5's price a spawn costs a fraction of a cent, so the
            one-call exception above does not apply here either: a single
            self-contained step goes to the local model or a haiku sub-agent,
            not inline.
        '';
      }.${cheapDelegate};
    in
    ''
      # Model Routing (user mandate)

      - The main loop is the manager: scope, judgement, reviewing what
        comes back, and talking to the user. Push everything else down to
        the cheapest model that can do it; that is cheaper, and parallel
        delegates are faster.
      - Delegate by default any self-contained step whose result you need
        as a conclusion or a diff rather than as context to reason over:
        gh/GraphQL queries, web searches, log trawls, multi-file sweeps,
        mechanical edits, drafts, and code changes you can specify exactly.
        Two or more independent calls of the same shape already qualify; a
        single lookup you already know how to do does not.
    ''
    + cheapRung
    + ''
      - Step up to a "sonnet" sub-agent only when the task itself needs
        judgement, multi-step reasoning, or code whose design is still open.
      - Run independent delegations in parallel: several Agent calls in one
        message, and run_in_background for anything not needed before your
        next step. Parallel writers each get their own worktree.
      - Fast local search keeps inline reading cheap: the built-in Grep tool
        already uses ripgrep and works on every machine — make it the default
        for content search. At the shell, use `rg` (content) and `fd`
        (file/dir names) when present, but do not assume they are installed
        or at any fixed path: probe with `command -v` first, fall back to
        `grep -r` / `find`, and note `fd` may be packaged as `fdfind` on
        Debian/Ubuntu.
      - Invoke the `delegation` skill before spawning a sub-agent: it
        carries the model-tier decision test, when NOT to delegate at all,
        Explore vs general-purpose, and how to write a self-contained prompt.
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
    - Lead with the action or answer, not preamble. No "Great question" /
      "Let me" openers, no recap of what you just did, no "let me know if
      anything else" closers.
    - Multi-step work: numbered, bounded steps, one action each. State
      progress every turn ("step 3 of 5 done: X. Next: Y") — don't assume it
      carries from a prior message.
    - Finish the issue at hand before surfacing a secondary one as a
      separate question; fold in anything you can answer yourself instead of
      leaving it hanging.
    - Concrete units over vague ones: "~15 min", not "a bit of work".
    - Lists: rank by relevance, show at most ~5, keep the rest in reserve
      unless completeness is actually needed.
    - Errors: state cause and fix flat, no hedging — same discipline in PR
      descriptions, commit messages, and messages to others, not just chat.
  '';
}

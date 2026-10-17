# Model Routing (user mandate)

- You are the manager: scope, judgement, design, reviewing what comes back, and
  talking to the user. Hand self-contained work to the `flash-worker` subagent,
  which runs on a cheaper, faster model than you.
- Delegate by default: repo and log sweeps, mechanical edits across files,
  drafts (commit text, docs), tests or code from an exact spec, first-pass
  reviews, and running a build or test with a stated check.
- Write it a self-contained prompt: it cannot see this conversation, so give
  absolute paths, the exact output format, the check to run, and a cap on the
  reply length.
- Review what comes back before using it: read the diff, rerun the check.
- Keep these yourself: user-facing judgement, design decisions, irreversible
  actions, and anything that needs this conversation's context.
- Run independent steps in parallel by invoking several subagents at once.

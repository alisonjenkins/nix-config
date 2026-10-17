# 0048. Route agy's work to Flash through a pinned subagent, and enforce it with an orchestrator

- Status: Accepted
- Date: 2026-10-17

## Context

When Claude credits run out, `agy` becomes the main agent, and its default model
is `Gemini 4 Argon (Medium)` (no `--model` run resolved to it; `settings.json`
has no model key). Argon is the strongest model `agy` offers and has its own
weekly limit, so routine work should go to Flash, as Claude hands work to Haiku.

Facts found on 2026-10-17 (agy 1.2.9, headless):

- A custom agent is a markdown file with frontmatter in
  `~/.gemini/config/agents/<name>.md`. `model` takes `inherit`, `flash` or `pro`;
  `subagent: true` lets the main agent call it with `invoke_subagent`; `tools`
  lists what it may use.
- `model: flash` runs the subagent on the Flash tier. The subagent's conversation
  record in `~/.gemini/antigravity-cli/conversations/` contained
  `gemini-3.8-flash-tiered` 11 and 28 times; the main agent's contained none, and
  its session logged `Propagating selected model override ... "Gemini 4 Argon
  (Medium)"`.
- An unregistered tool name stops the agent from starting: `unknown component:
  tool "command_status" not found in registry` (it had been replaced by
  `manage_task`). `agy` then fell back to a built-in `self` subagent on Flash, so
  the failure was visible only in the reply. The names that work: `view_file`,
  `list_dir`, `grep_search`, `write_to_file`, `replace_file_content`,
  `run_command`, `invoke_subagent`.
- A subagent's `list_dir` was rejected with `must be an absolute path`.
- Routing text alone did not delegate. With the routing rule loaded (confirmed in
  the conversation record), the default agent did a four-file lookup and then a
  multi-file `TODO` to `DONE` edit itself, creating no subagent conversation.
- A main agent with no edit or command tools did delegate. Run as
  `agy --agent orchestrator` (`tools`: `view_file`, `list_dir`, `grep_search`,
  `invoke_subagent`; `mainAgent: true`, `subagent: false`, `model: inherit`), the
  same edit went to `flash-worker`, which changed both files, while the
  orchestrator's own conversation had no Flash markers.

## Decision

`modules.antigravityCli` (`home/modules/antigravity-cli`) also writes:

- `~/.gemini/config/agents/flash-worker.md`: `model: flash`, `subagent: true`,
  `mainAgent: false`, read, edit and `run_command` tools, and an instruction to
  pass absolute paths and to run the named check.
- `~/.gemini/config/agents/orchestrator.md`: the main agent that cannot edit or
  run commands, selected with `agy --agent orchestrator` or the `/agents` panel.
- A Model Routing section appended to `~/.gemini/config/AGENTS.md`
  (`model-routing.md`), which tells the default agent to hand self-contained work
  to `flash-worker`. This is advice for the default agent.

## Alternatives rejected

- **Routing text alone.** It was loaded and ignored on the tasks above.
- **Setting Flash as the default model.** It removes Argon for the work that needs
  it; the orchestrator keeps Argon for judgement.
- **Making the orchestrator the default agent.** No settings key for the default
  agent is documented, and a main agent that cannot edit is wrong for small tasks.

## Consequences

- Enforcement is opt-in: the default `agy` session is still Argon doing its own
  work, with the routing text as advice. Starting it as `agy --agent orchestrator`
  (or an alias) is what forces delegation.
- The orchestrator cannot do a small edit itself; each one costs a subagent call.
- Subagents in headless runs have their approvals soft-denied unless
  `--dangerously-skip-permissions` is set; interactive sessions prompt.
- A tool name that stops being registered silently disables the agent. After an
  `agy` upgrade, run a delegation once and read the reply for `not found in
  registry`.

## Evidence

- Delegation with the pinned worker: `agy -p "Use the flash-worker subagent ..."
  --dangerously-skip-permissions` edited `notes.txt` and created `done.txt`; the
  first run (with `command_status`) reported the registry error, the second did
  not.
- Default agent, routing rule loaded: no new conversation beyond the main one for
  both tasks. Orchestrator: two new conversations, the worker's with 28
  `gemini-3.8-flash-tiered` markers and the main one with 0.

## Revisit when

`agy` documents a default-agent setting, or a `model` value that names a specific
model (the field takes only a tier today), or the default agent starts delegating
unprompted.

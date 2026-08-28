# Frontmatter

## Portability rule

The [agentskills.io](https://agentskills.io) spec allows exactly six fields:

    name  description  license  compatibility  metadata  allowed-tools

Everything else is a Claude Code extension. Shared skills in this repo, the
families under `home/skills/`, are linked into both
Claude Code and opencode, so they use **spec fields only**. That constraint is
what keeps them usable outside Claude Code. Claude-Code-only behaviour belongs
in settings (`skillOverrides`) or in a skill that is already Claude-Code
specific, such as a project skill under `.claude/skills/`.

Uploading a skill with a non-spec field to claude.ai or the Skills API fails
with `Unexpected key(s) in SKILL.md frontmatter`.

The one tolerated exception on a shared skill is `argument-hint`: it is
cosmetic, other runtimes ignore unknown keys, and nothing about the skill's
behaviour depends on it. Never put a *behavioural* extension on a shared
skill, such as `paths`, `context`, `disable-model-invocation`, or
`user-invocable`: those change what the skill does, so a runtime that ignores
them runs it differently.

## Fields worth knowing

| Field | Effect |
|---|---|
| `description` | The matching surface. Capped at 1,536 chars combined with `when_to_use`. |
| `when_to_use` | Extra trigger phrases, appended to the description. CC-only. |
| `paths` | Glob list. Limits **automatic activation** to sessions working with matching files. It does not remove the entry from the listing. CC-only. |
| `disable-model-invocation` | Only you can invoke it. Use for anything with side effects: deploy, commit, send. Also blocks preloading into subagents. CC-only. |
| `user-invocable: false` | Only the model can invoke it. Background knowledge you should not have to type. CC-only. |
| `allowed-tools` | Tools pre-approved for the invoking turn. Spec field. |
| `context: fork` | Runs the skill in a subagent; its body never enters the main context. Needs an actionable task, not guidelines. CC-only. |
| `argument-hint` / `arguments` | Autocomplete hint and `$name` substitution. CC-only. |
| `model` / `effort` | Override for the turn the skill is active. CC-only. |

## Subagents

A subagent receives **no skill listing**. It sees only: its own system prompt,
the task message, the instructions-file hierarchy, git status, and the full
content of skills named in its `skills:` frontmatter list. So:

- Guidance a subagent must have goes in its `skills:` list, since a
  description it cannot see will never fire.
- For an ad-hoc subagent with no definition of its own, the **parent injects**:
  name the skill in the delegation prompt. A subagent can invoke a skill by
  exact name even though none are listed to it, and the parent knows what the
  task needs, so it sends only the relevant one rather than preloading
  everything. This is the cheaper half of the same idea as `skills:`.
- `disable-model-invocation: true` skills **cannot** be preloaded this way.
- `Explore` and `Plan` skip the instructions hierarchy entirely, which is why
  they are cheap for read-only sweeps.

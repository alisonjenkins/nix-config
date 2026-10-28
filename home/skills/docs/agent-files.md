# Agent instruction files and human docs

## The rule

Give every fact one owner file; every other file links to it or imports it and never restates it.

| Content | Owner | Others |
|---|---|---|
| What it is, quickstart, contribution basics | README.md and docs/ | Agent files link to it |
| Build, test and lint commands, code style, repo layout, always-do rules | AGENTS.md | CLAUDE.md imports it |
| Claude-only behaviour (plan mode, hooks, skills) | CLAUDE.md below the import | Nothing else carries it |
| Why a decision was made | An ADR | Agent files link to the ADR |
| Detail for one subsystem | A doc in docs/ or a path-scoped rule | The agent file keeps a one-line pointer |

## What each file is for

The agents.md standard says "README.md files are for humans: quick starts, project descriptions, and contribution guidelines." AGENTS.md holds the extra context coding agents need (build and test commands, code style, security, deploy steps). Keep READMEs concise for human contributors.

"The closest AGENTS.md to the edited file wins; explicit user chat prompts override everything."

## How Claude Code picks a file

By default it reads AGENTS.md only when no CLAUDE.md exists in the working directory or above. A CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md counts; ~/.claude/CLAUDE.md, a managed CLAUDE.md and .claude/rules/ files do not.

With both AGENTS.md and CLAUDE.md present it reads CLAUDE.md only, unless CLAUDE.md imports AGENTS.md. Reading AGENTS.md directly needs Claude Code v2.1.277 or later (confirmed in the changelog: 2.1.277 "Added AGENTS.md support"). AGENTS.md support also works on Bedrock, Vertex AI, Foundry, gateways and with telemetry disabled since 2.1.281.

The "Project instructions" setting in /config configures this with default value `claude-md-or-agents-md`; `claude-md-and-agents-md` loads both, each directory's CLAUDE.md first and its AGENTS.md after.

## Keeping one file

Maintain one file using one of two methods.

Import (preferred):

```markdown
@AGENTS.md

## Claude Code

- Claude-only rules go here
```

Symlink (only when you need no Claude-specific content):

```bash
ln -s AGENTS.md CLAUDE.md
```

Symlink caveats from the docs: Claude's Edit and Write tools refuse to write through a symlink and direct the edit to the target; on Windows a committed symlink checks out as a plain one-line text file unless core.symlinks is enabled, so use the import there.

## Size and placement

Target under 200 lines per CLAUDE.md; longer files cost context and reduce adherence. Imports organise a long file but do not reduce its context cost.

Move instructions that matter for part of the codebase into path-scoped rules (.claude/rules/) or a subdirectory file, which load only when Claude works there. Write concrete, checkable rules ("Run the test command before committing") rather than vague ones.

## What agent files must not contain

Do not include a copy of README prose such as the pitch or install steps. Do not include contribution rules that humans also follow (link CONTRIBUTING.md) or decision history (link the ADR).

Keep a one-line pointer to the doc that owns the detail.

## Other tools

| Tool | Instruction files | Reads AGENTS.md | Import syntax |
|---|---|---|---|
| Cursor | .cursor/rules/*.mdc (plain .md ignored; whether .cursorrules is still read is unverified) | Yes, root and subdirectories, nearest wins | none (a @path mention is read on demand) |
| GitHub Copilot | .github/copilot-instructions.md; .github/instructions/NAME.instructions.md with applyTo globs | Yes, anywhere in the repo, nearest wins; also a root CLAUDE.md or GEMINI.md | none |
| Gemini CLI | GEMINI.md, scanned up from the workspace | Only if context.fileName lists AGENTS.md | @file.md imports |
| OpenAI Codex CLI | AGENTS.override.md then AGENTS.md per directory from the Git root to the cwd | Yes, natively (32 KiB default cap, project_doc_max_bytes) | none |
| Windsurf (Devin Desktop) | .devin/rules preferred, .windsurf/rules legacy fallback, legacy .windsurfrules | Yes, AGENTS.md in any directory processed by rules engine (root always-on, subdirectory auto-glob) | none |
| Aider | CONVENTIONS.md loaded with --read or the read: config key | not documented (search of Aider repo found no AGENTS.md support) | none |

The import pattern is Claude-specific; every other tool below either reads AGENTS.md natively or has its own file.

## Catching drift

Run a link check over both sets of files in CI if present (see structure.md). In Claude Code, the /doctor prompt-audit command (confirmed in the changelog: 2.1.283 "Added /doctor prompt-audit") audits CLAUDE.md, CLAUDE.local.md, AGENTS.md and the .claude files for stale references and contradictions.

No published tool checks agent files against human docs for drift.

## Sources and confidence

| Source | URL |
|---|---|
| agents.md | https://agents.md/ |
| Claude Code memory | https://code.claude.com/docs/en/memory#agents-md |
| Cursor rules | https://cursor.com/docs/context/rules |
| GitHub Copilot repository instructions | https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions |
| Gemini CLI GEMINI.md | https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/gemini-md.md |
| OpenAI Codex CLI AGENTS.md | https://learn.chatgpt.com/docs/agent-configuration/agents-md |
| Devin Desktop (formerly Windsurf) cascade memories | https://docs.devin.ai/desktop/cascade/memories |
| Aider conventions | https://aider.chat/docs/usage/conventions.html |

Confidence: checked by running the tool or reading source on 2026-10-28. Remaining unverified: whether Cursor still reads .cursorrules; behaviour is version-dependent.

# Conventions

## Naming

- The **directory name** is the command you type. Frontmatter `name` is only a
  display label for personal and project skills (for plugin skills it sets the
  last command segment).
- Lowercase, hyphenated, no prefix scheme. `git`, not `my-git-workflow`.
- Check for collisions before choosing: bundled commands (`/skills`, `/doctor`,
  `/code-review`, `/init`, `/run`) win arguments you did not intend. A personal
  skill overrides a bundled skill of the same name, occasionally wanted and
  usually not.

## Writing the description

The description is the *only* part of a skill always in context, and the
entire basis on which the model decides to load it. Treat it as a matching
surface, not a summary.

- **Key use case first.** Text is truncated at 1,536 characters, and under
  budget pressure descriptions are dropped least-used-first, so front-load.
- **Include the words a user would say**, including tool names (`kubectl`,
  `gh`, `cargo`) and file extensions.
- For a family parent, include trigger vocabulary for **every child**.
- State the negative case when the skill is easily confused with a neighbour:
  "not for source code" is worth its characters.
- **Lead with the verb, not the noun.** Descriptions of *what the skill
  contains* ("general code-writing conventions", "how to review code") do not
  fire; descriptions of *what the user is doing* ("use when fixing, debugging
  or changing code") do. Measured: the `git` family fired unprompted on
  "commit this" because its description said "use when committing", while
  `programming` sat unused through an entire Nix debugging session because it
  said "use when writing or refactoring code, or when unsure of the idiom,"
  and the model was neither writing nor unsure.
- **Cover the broken case.** Most code work arrives as "this is broken, fix
  it", not "write me a feature". Naming only the greenfield verbs excludes the
  common path.
- Aim for 250–450 characters. `programming` is 448 and covers five languages;
  a leaf rarely needs more than 200.

## Parent or leaf?

Make a **family** when:
- Several variants share most of their guidance (languages, cloud tools,
  document formats), or
- Several existing skills share trigger vocabulary and would otherwise each
  pay for a full description in the listing.

Keep it a **leaf** when it has a distinct trigger and no siblings:
`process-todo` and `mcp-builder` are correctly standalone.

## These files run on machines you are not sitting at

A shared skill is deployed to every machine the user works from: different
distributions, package managers, macOS as well as Linux. Guidance that assumes
otherwise breaks where you cannot see it.

- Never hardcode an absolute tool path. What sits at
  `/run/current-system/sw/bin/<tool>` on one machine is elsewhere or absent on
  the next.
- Never assume a tool is installed. Prefer the portable built-in; for shell
  tools, probe with `command -v` and give the fallback. Call out naming
  quirks: `fd` is packaged as `fdfind` on Debian and Ubuntu, and macOS ships
  BSD rather than GNU userland.
- Keep wording tool- and path-agnostic in anything shared. Machine-specific
  detail belongs in that machine's own configuration or in memory, not here.

## Match the form to the failure

Plain prose holds up until the model is under pressure to skip it. Pick the
form by what actually gets violated, not by habit:

| Failure mode | Form that holds |
|---|---|
| A rule gets rationalized away under pressure | A flat prohibition plus a table of excuse → why it doesn't count |
| Output arrives in the wrong shape | A positive template of the right shape, not a description of the wrong one |
| A required element gets silently dropped | A REQUIRED-field checklist, not a paragraph that mentions it once |
| Behaviour should depend on a condition | State the condition as an observable predicate, not "when appropriate" |

If a rule must hold 100% of the time, a skill is the wrong place for it —
only moving the check into a hook removes the chance to rationalize past it.

## Match specificity to fragility

A fragile, mechanical sequence (a migration, a deploy, a multi-step git dance
with an easy-to-lose invariant like commit signing) wants a literal script or
an exact command, not room to improvise. An open-ended task (a review, a
design call) wants heuristics and judgement, not a rigid script that won't
fit the actual case. Pick per task, not once per skill.

Don't leave dated "before/after" advice in a body — a model with no sense of
when it was written reads it as current fact. Delete superseded guidance, or
say plainly it's superseded and why; never leave it presented as live.

## Body

- Keep `SKILL.md` under 500 lines; move detail into sibling files and link
  them from the body, saying what each contains.
- Write instructions, not prose about instructions. The reader is executing.
- Reference sibling files by relative path; reference other skills by name
  (`testing`) rather than restating their content.
- Never duplicate what another skill owns. A pointer that costs one line beats
  a paragraph that will drift out of sync.

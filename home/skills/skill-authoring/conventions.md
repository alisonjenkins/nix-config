# Conventions

## Naming

- The **directory name** is the command you type. Frontmatter `name` is only a
  display label for personal and project skills (for plugin skills it sets the
  last command segment).
- Lowercase, hyphenated, no prefix scheme. `git`, not `my-git-workflow`.
- Check for collisions before choosing: bundled commands (`/skills`, `/doctor`,
  `/code-review`, `/init`, `/run`) win arguments you did not intend. A personal
  skill overrides a bundled skill of the same name, which is occasionally what
  you want and usually not.

## Writing the description

The description is the *only* part of a skill that is always in context, and
it is the entire basis on which the model decides to load the skill. Treat it
as a matching surface, not a summary.

- **Key use case first.** Text is truncated at 1,536 characters, and under
  budget pressure descriptions are dropped least-used-first, so front-load.
- **Include the words a user would actually say**, including the tool names
  (`kubectl`, `gh`, `cargo`) and the file extensions.
- For a family parent, include trigger vocabulary for **every child**.
- State the negative case when the skill is easily confused with a neighbour:
  "not for source code" is worth its characters.
- **Lead with the verb, not the noun.** Descriptions that describe *what the
  skill contains* ("general code-writing conventions", "how to review code")
  do not fire; descriptions that name *what the user is doing* ("use when
  fixing, debugging or changing code") do. Measured: the `git` family fired
  unprompted on "commit this" because its description said "use when
  committing", while `programming` sat unused through an entire Nix debugging
  session because it said "use when writing or refactoring code, or when
  unsure of the idiom," and the model was neither writing nor unsure.
- **Cover the broken case.** Most code work arrives as "this is broken, fix
  it", not "write me a feature". A description that only names the greenfield
  verbs excludes the common path.
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
distributions, different package managers, macOS as well as Linux. Guidance
that silently assumes otherwise breaks where you cannot see it.

- Never hardcode an absolute tool path. What sits at
  `/run/current-system/sw/bin/<tool>` on one machine is elsewhere or absent on
  the next.
- Never assume a tool is installed. Prefer the portable built-in; for shell
  tools, probe with `command -v` and give the fallback. Call out naming quirks
  where they exist: `fd` is packaged as `fdfind` on Debian and Ubuntu, and
  macOS ships BSD rather than GNU userland.
- Keep wording tool- and path-agnostic in anything shared. Machine-specific
  detail belongs in that machine's own configuration or in memory, not here.

## Body

- Keep `SKILL.md` under 500 lines; move detail into sibling files and link
  them from the body so the model knows what each contains.
- Write instructions, not prose about instructions. The reader is executing.
- Reference sibling files by relative path; reference other skills by name
  (`superpowers:writing-skills`) rather than restating their content.
- Never duplicate what another skill owns. A pointer that costs one line beats
  a paragraph that will drift out of sync.

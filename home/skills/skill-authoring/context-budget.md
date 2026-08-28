# What a skill costs

## The three levels

1. **Frontmatter**: `name` + `description`, in context for every main-loop
   session, always. This is the only cost you pay for a skill you never use.
2. **`SKILL.md` body**: loaded when the skill is invoked.
3. **Bundled files**: loaded only when the body points at one and the model
   follows the pointer. Scripts are executed, never loaded.

Designing a skill is mostly deciding what belongs at which level. Anything a
reader needs *before* deciding to use the skill goes in level 1. Anything
needed in every use goes in level 2. Everything else goes in level 3.

## The listing budget

The listing holds every skill **name** always; descriptions are trimmed to fit
a budget of 1% of the model's context window. On overflow, Claude Code drops
descriptions starting with the least-used skills, so a rarely-used skill
quietly stops matching, and the failure looks like "the skill won't trigger".

- `/context` shows the listing size after trimming; `/doctor` names the biggest
  contributors; `--debug` logs an overflow warning.
- `skillListingBudgetFraction` (or `SLASH_COMMAND_TOOL_CHAR_BUDGET`) raises it;
  `skillListingMaxDescChars` changes the 1,536-char per-entry cap.
- A 1M-token model has ample headroom. A 200k model does not, so design for
  the smaller one if the skills are meant to be portable.

## Making a skill cost less

In descending order of effect:

1. **Fold siblings into a family.** One description replaces N.
2. **`skillOverrides: "name-only"`** on the leaves of a family: settings-side,
   so it works on skills you do not own and cannot edit. They stay invocable
   and stay in the `/` menu; only the description leaves the listing.
3. **Trim the description.** Keyword-first, drop the prose.
4. **`"off"`** for something you genuinely never use. Reversible, and unlike
   deleting it, the skill is still there when you change your mind.
5. **`context: fork`** for a heavy one-shot task, so even the body never lands
   in the main context.

`paths:` is *not* on this list: it gates automatic activation, not listing
cost.

---
name: writing
description: Use when drafting or editing prose a person will read. A PR comment or review reply, a commit body, a README, a design doc, a report, a release note, a message to a colleague. Also when asked to tighten text, cut the fluff, de-slop it, make it stop sounding AI-generated, or make it easier to read. Carries the accessibility baseline of writing for a dyslexic reader with ADHD, the plain-speech rules, the punctuation and formatting house style, the AI tells to strip, and the voice checks that keep edited text from reading sterile.
---

# Writing

## What this covers

Written deliverables. Anything that outlives the turn it was produced in, or
that a third party reads.

It does not govern the chat register. If the user has set a terse or stylised
mode for replies, that mode wins for replies. A document drafted during that
session still follows this skill.

## Two failure modes

Text fails in one of two directions, and fixing one direction usually pushes
the text into the other. Check for both.

1. **Slop.** Puffery, AI vocabulary, hedging, filler, the rule of three,
   bolded labels that restate the line. Reads generated.
2. **Sterile.** Every pattern removed, nothing left. No opinion, uniform
   sentence length, no specifics. Reads generated for the opposite reason.

## Write for a dyslexic reader with ADHD

Assume the reader is dyslexic and has ADHD. This is the default audience, not
an accommodation added on request. It costs nothing for anyone else, and it
rules out most of what makes technical writing hard to get through.

- **Front-load the point.** First sentence of a section says the conclusion.
  Reasoning follows it. A reader who stops after one line still got the answer.
- **Short paragraphs.** Three or four lines. A wall of text is where attention
  is lost, and where a dyslexic reader loses their place on the return sweep.
- **Break it up.** Headings, lists and tables give the eye somewhere to land
  and make the structure scannable without reading every word.
- **Subject and verb near the start of the sentence.** A chain of subordinate
  clauses before the main point forces a re-read.
- **Use the same word for the same thing every time.** Synonym cycling makes
  the reader stop and check whether two words mean two things.
- **Expand an acronym on first use**, then use it consistently.
- **Bold the anchors, not decoration.** A few words in bold help someone
  skimming find the load-bearing part. Bold on everything helps nobody.

The plain-speech rules below serve the same reader. Concrete words, active
voice and one idea per sentence are all easier to decode than the alternative.

## Plain speech

- **Say what it does, not how it feels.** "the database stays close at hand"
  names a feeling. "`.toSQL()` returns the exact string sent to the database"
  names a mechanism. If a sentence cannot be restated as a concrete
  instruction, fact, or number, cut it.
- **The portability test.** If a sentence could appear unchanged in another
  project's docs, it says nothing about this one. Cut it.
- **Active voice.** Name the actor. "queries are validated" becomes "the
  compiler validates queries". Passive is fine only when the actor is genuinely
  unknown.
- **One idea per sentence.** If the reader has to backtrack to parse it, split
  it or drop clauses.
- **Cut adverbs or fix the verb.** "runs quickly" becomes "is fast", or better,
  the number. An adverb propping up a weak verb means the verb is wrong.
- **Prefer the plain word.** utilize becomes use, leverage becomes use,
  facilitate becomes help, numerous becomes many, in the event that becomes if.
- **Name sources or delete the claim.** "Experts believe" and "reports suggest"
  are not attributions.

## Voice

Removing tells is half the job. The other half:

- **Have an opinion.** React to the facts. A neutral list of pros and cons
  tells the reader nothing about what you would do.
- **Vary rhythm.** Short sentences. Then longer ones that take their time. A
  uniform line length is itself a tell.
- **Acknowledge complexity.** "Fast, but it breaks under concurrent writes"
  beats "fast".
- **Use "I" when it fits.** First person is not unprofessional.
- **Be specific.** Not "this is concerning" but the thing that concerns you and
  why.

## Punctuation and formatting

- **No em dashes.** House rule. Use a period or a comma. Do not substitute
  parentheses, en dashes, or a hyphen standing in for a dash. If a thought
  needs separation, end the sentence.
- **Colons before a list or an example only.** Not as a mid-sentence
  connector.
- **Straight quotes**, not curly.
- **Sentence case headings.** No decorative emoji in headings or bullets.
- **Bold sparingly.** Not on every proper noun. A bold lead-in that names an
  item and is followed by genuinely new detail is fine. A bold label that
  restates the line that follows it is a tell, so write that as prose.

## Self-audit

Before handing text over, ask the question directly: what about this is
obviously AI generated? Fix what the answer names. Then check the text still
has a point of view.

## Routing

| Doing | Read |
|---|---|
| Scanning a draft against the full checklist of AI tells | [ai-tells.md](ai-tells.md) |

Related: `review` for phrasing a review finding, `git/commit-messages.md` for
commit subject and body format. Both defer to this skill for the prose itself.

Derived from the `unslop` skill in
[cursor/plugins](https://github.com/cursor/plugins), rewritten for this skill
set rather than vendored.

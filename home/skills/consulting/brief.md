# Writing a consult brief

The consultant has no conversation history, no memory of what you tried, and no
view of your reasoning. It has this document and whatever it chooses to read.
Everything you leave out, it will either guess at or waste turns rediscovering.

Write these six sections, in this order.

## Question

One sentence, decidable, answerable by someone who has never seen this session.

    Should the retry live in the client wrapper or in the caller?

Not `what should I do about the retries?`: that is a topic, not a question.
If you cannot state it in one sentence, you do not yet know what you are asking,
and that is worth another minute of thinking rather than a consult.

## Goal

What is being built and why: the requirement, not the ticket title. One or two
sentences. This is what lets the consultant tell you the question is wrong,
which is frequently the most valuable answer it can give.

## Tried

Every attempt and its actual outcome, in order. For each: what you changed, and
what happened.

- Quote the **shortest decisive line** of any error, verbatim. Not a summary of
  it, and not the whole log.
- Include attempts that seemed to work and then did not.
- Say how you verified each one. "It did not work" is ambiguous between the fix
  being wrong and the verification being wrong, and the consultant cannot tell
  which without this.

## Known

Files you have read, with line references, and what each showed. Name the
things you checked and found *fine* as well as the ones you found suspicious:
that is what stops the consultant re-treading your path.

Be explicit that this is your reading of them. The consultant should check the
files itself, and it needs to know which claims are yours rather than the code's.

## Constraints

- What must not change, and why.
- What has been ruled out, and on what evidence: flag anything ruled out on
  reasoning rather than on a test, because that is where the answer usually is.
- Repo mandates that bind the answer: the language and its conventions, the
  commit discipline, infrastructure-as-code rules, anything the user has
  already decided.

## Wanted

What a good answer looks like, and how long it may be.

    Return a decision and why, at most 40 lines. No code. I will implement it.
    If my framing is wrong, say that instead of answering the question.

## Naming skills

The consultant gets **no skill listing** and cannot discover a skill on its own,
though it can invoke one by exact name. Name the ones this problem needs, such
as `invoke the debugging skill and read its false-signals.md`, following the
same rule that already applies to any subagent prompt.

## The test

Before sending: could a competent engineer who has never seen this repository
act on this brief? If not, the gap you feel is the section you skipped.

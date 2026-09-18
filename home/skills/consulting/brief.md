# Writing a consult brief

The consultant has no conversation history, no memory of what you tried, and no
view of your reasoning. It has this document and whatever it chooses to read.
Anything you leave out, it guesses at or wastes turns rediscovering.

Write these six sections, in this order.

## Question

One sentence, decidable, answerable by someone who has never seen this session.

    Should the retry live in the client wrapper or in the caller?

Not `what should I do about the retries?`: that is a topic, not a question.
If you cannot state it in one sentence, you do not yet know what you are asking;
spend another minute thinking rather than a consult.

## Goal

What is being built and why: the requirement, not the ticket title. One or two
sentences. This lets the consultant tell you the question is wrong, often the
most valuable answer it can give.

## Tried

Every attempt and its actual outcome, in order: what you changed, what
happened.

- Quote the **shortest decisive line** of any error, verbatim. Not a summary,
  not the whole log.
- Include attempts that seemed to work and then did not.
- Say how you verified each one. "It did not work" is ambiguous between a wrong
  fix and a wrong verification, and the consultant cannot tell which without
  this.

## Known

Files you have read, with line references, and what each showed. Name what you
checked and found *fine* as well as what looked suspicious: that stops the
consultant re-treading your path.

Be explicit that this is your reading. The consultant should check the files
itself, and needs to know which claims are yours rather than the code's.

## Constraints

- What must not change, and why.
- What has been ruled out, and on what evidence: flag anything ruled out by
  reasoning rather than a test, because that is where the answer usually is.
- Repo mandates that bind the answer: the language and its conventions, the
  commit discipline, infrastructure-as-code rules, anything the user has
  already decided.

## Wanted

What a good answer looks like, and how long it may be.

    Return a decision and why, at most 40 lines. No code. I will implement it.
    If my framing is wrong, say that instead of answering the question.

## Naming skills

Name the skills this problem needs in the brief, e.g. `invoke the debugging
skill and read its false-signals.md` — see the `delegation` skill for why.

## The test

Before sending: could a competent engineer who has never seen this repository
act on this brief? If not, the gap is the section you skipped.

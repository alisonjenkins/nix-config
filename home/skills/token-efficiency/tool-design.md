# Designing a token-efficient tool

Start from one finding. A design answers: what does the model do today that costs too
much, and what is the smallest thing that does it for less?

## A design states

- **The task**, in the model's words: what it asks for and what it needs back.
- **Output size**: expected tokens per call, and the hard cap. A number, not "small".
- **What is filtered or summarised before the model sees it**, and how the model asks for
  more.
- **Calls per typical task.** The best design is often one call that replaces five.
- **Delivery mechanism and why** (see below).
- **How success is measured** with the stack: which `cc-obs-query` figure should move, over
  which period, and the baseline.

## Checklist (fail any item, fix it)

1. Output is bounded and the bound is the default; the model opts in to more.
2. Filtering and ranking happen in the tool, not in the model's context.
3. Default output is concise: names and numbers, no prose, no repeated headers; a
   `--detail` option gives the rest.
4. Fixed cost is small: a short tool description or schema, no examples that restate it.
5. The typical task needs few calls; list the calls.
6. Errors say what was wrong and the exact fix (a valid example, the flag to use), so the
   model corrects itself in one more call.
7. It is read-only unless the finding says otherwise, and anything that changes state asks.
8. It runs on every machine it is used from: no absolute paths, no assumed tools (probe
   with `command -v`).
9. A measurement plan exists, with a baseline figure from the stack.
10. The estimate is written down so a later review can compare it with the real output.

## Delivery mechanism (provisional)

The question is open until the experiment in spec 007 (FR-038) has run. What exists:

- Idle cost is small for both under Claude Code's tool deferral, so per-call output size
  matters more than the protocol.
- Published comparisons are vendor- or single-author-run on other workloads (GitHub,
  browsers); the large gaps came from big schemas and unfiltered output, not the protocol.
- Working hypothesis for read-only analytics used by one person: a command-line tool taught
  by a short skill, with concise default output and pipe-friendly flags. Choose a protocol
  server instead when the tool must serve other users or share a login across machines.

Replace this section with the experiment's decision (the ADR number and the figures).

## After it is built

A later review compares the real output size with the estimate. Record the gap on the
decision record; a design that was off by more than 2x teaches something for the next one.

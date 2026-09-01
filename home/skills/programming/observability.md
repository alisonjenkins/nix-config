# Observability-driven development

The goal is that a failure or a wrong result can be explained by reading the
output the program already produced, not by re-running it under a debugger,
adding print statements, or guessing from the code what must have happened.
Instrumentation is not a nice-to-have added after something breaks; it is
written alongside the logic it observes, in the same commit.

## What earns a log line

Log at a **decision point** or a **boundary**, not on every line:

- Every branch that changes what the program does next (which path was taken,
  and the value that drove the decision).
- Every crossing of a process, network, or trust boundary: a request in, a
  request out, a queue message consumed, a file read, a subprocess spawned —
  with enough of the payload identity (an ID, a size, a key) to correlate it
  with the other side.
- Every retry, fallback, or degraded-mode path taken. If the code has a
  fallback, silently succeeding on the fallback path is exactly the kind of
  behaviour that later requires guessing; log that it happened and why.
- Every error, at the point it is first observed, with the state that produced
  it — not just re-logged again at each level it is propagated through.

Do not log inside a tight loop's steady-state iteration, a getter, or
anything called per-frame/per-row at volume; log the aggregate (count,
duration, outcome) when the loop finishes instead. Noise that buries the
one line that mattered is a cost, not a safety margin.

## What a log line must carry

A log line that says a thing happened without saying *which* thing, on *what*
input, is a line that will send the next reader back to guessing. Every log
line needs:

- **Structured fields, not an interpolated sentence.** `event="order_failed"
  order_id=order_id reason=reason`, not `f"Order {order_id} failed: {reason}"`.
  A field can be grepped, filtered, and aggregated; text embedded in a message
  can only be read.
- **The identifiers needed to correlate it** with the request, job, or
  transaction it belongs to (a request ID, trace ID, or equivalent) threaded
  through from entry to exit — see Correlation below.
- **Enough context to explain the *why*, not just the *what*.** "Validation
  failed" is useless; "validation failed: field=email reason=missing_at_sign
  value_len=12" reconstructs the failure without rerunning anything.

## Correlation

A single request, job, or unit of work that touches more than one function,
thread, task, or process needs one identifier that appears in every log line
it produces, so the lines can be reassembled into one story after the fact.
Generate it at the entry point (the top of the request handler, the start of
the job), and pass it through explicitly or via the language's ambient-context
mechanism (see the per-language file). Never invent a new identifier partway
through a single unit of work; that breaks the correlation it exists to
provide.

## Levels

Pick the level by who needs to act on it, not by how the author feels about
the code:

| Level | Means | Example |
|---|---|---|
| `error` | This unit of work failed; something needs to look at it | Request 500s, job fails, unhandled exception reached the boundary |
| `warn` | Degraded, retried, or fell back; work still completed | Retried a flaky call, fell back to a cache, used a default |
| `info` | Notable state transition, on the happy path | Server started, request completed, job finished |
| `debug` | Detail useful when tracing one specific run, not on by default | Intermediate values, cache hit/miss, branch taken |

`error` and `warn` are not compiled or filtered out in production; do not put
anything there that a human is not expected to look at, or the level stops
meaning anything and gets ignored wholesale.

## Never let logging replace error handling

A log line is not a substitute for `defensive.md`'s "crash early" or for
propagating an error with context — it is the record that lets someone
reconstruct what happened *after* the error was already handled correctly.
Logging a failure and continuing as if it did not happen is the "limp on"
anti-pattern with extra steps.

## Traces and metrics

Where the language/runtime has a tracing library (see per-language file),
prefer a structured span around a unit of work over a pair of manual
start/end log lines: the span carries duration, nesting, and status for free,
and composes across an async boundary or a call into another service without
extra bookkeeping. Reach for a counter or histogram metric instead of a log
line when what matters is a rate or a distribution over time (requests/sec,
latency, queue depth) rather than a specific occurrence — a metric answers
"how often" cheaply where grepping logs does not.

## Before shipping a feature

If you cannot answer "what did the program actually do, using only its
output" for the change you just wrote, without adding a print statement or
attaching a debugger, the feature is not done — the observability is part of
the feature, not a follow-up.

# Keeping decisions reversible

## There are no final decisions

Every architectural choice you make will be wrong eventually: the database,
the cloud vendor, the framework, the message format. Design so that being wrong
costs a module rather than a rewrite.

Practically: the thing you might replace sits behind an interface you own, and
its types do not leak past that interface. The moment a vendor's types appear
in your domain code, the decision has become permanent.

## Forgo following fads

A technology's popularity is not evidence that it fits this problem. Ask what
it costs to remove before asking what it does. New dependency, new runtime, new
build step, new failure mode: each needs a reason specific to the problem in
front of you.

The counterpart is equally true: refusing something because it is new is also
not analysis.

## Tracer bullets and prototypes are different things

They get confused constantly, and the confusion is expensive.

|  | Tracer bullet | Prototype |
|---|---|---|
| Purpose | Find out if the pieces connect | Find out one specific answer |
| Scope | Thin, but end to end and real | One dimension, everything else faked |
| Afterwards | **Kept and grown** | **Thrown away, always** |
| Quality bar | Production, just minimal | Whatever answers the question |

If you build a prototype and then ship it, you shipped scaffolding. If you
build a tracer bullet to throwaway quality, you now have a throwaway system
that people are depending on. Decide which one you are building, say so, and
hold the line.

## Configuration: where it stops paying

Make it configurable when the value legitimately differs between environments,
deployments or users, or when changing it must not require a rebuild.

Do **not** make it configurable to avoid a decision. Every knob is a
combination that someone must test and someone must document, and unused knobs
rot into wrong defaults. A named constant with a one-line justification beats a
config key nobody ever sets.

## Policy is metadata

Encode the *rule*, not the current answer to the rule. "Retry while the error
is retryable and the deadline has not passed" survives; "retry three times"
becomes a magic number that someone doubles in an incident and never reverts.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt), tips 18-21, 55, 79. Full tip list: https://pragprog.com/tips/

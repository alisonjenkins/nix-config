# Property-based testing

## When it beats examples

Example-based tests check the cases you thought of. Property-based tests
generate cases you did not, and shrink any failure to the smallest input that
still reproduces it — which is usually the bug stated in its clearest form.

Reach for it when:

- the input space is large or structured (parsers, serialisers, path handling,
  date arithmetic, anything taking arbitrary text or bytes);
- there is a rule that must hold for *all* inputs, not just the three in the
  ticket;
- you are fixing a boundary bug and suspect there are siblings — off-by-one,
  empty, exactly-one, maximum, negative zero, non-ASCII.

Keep example tests too. They document intent and pin the specific regression;
properties cover the space between them.

## Choosing a property

The hard part is not the library, it is naming a rule that is true for every
input. Four shapes cover most real cases:

- **Round-trip.** `decode(encode(x)) == x`. The highest value per line of test
  code you will ever write. Applies to serialisation, escaping, compression,
  URL and path handling.
- **Invariant.** Something true of the output regardless of input: the result
  is sorted; length is preserved; the total is unchanged; no field is null.
- **Oracle.** Compare against a slower, obviously-correct implementation, or
  against the old implementation you are replacing. Ideal for optimisations
  and rewrites, where "same answer as before" *is* the specification.
- **Idempotence.** `f(f(x)) == f(x)`. Normalisation, deduplication, and
  anything that touches an external system — which the `programming` skill
  already requires to be idempotent, so this tests a rule you already hold.

If no property comes to mind, that is a finding about the code: a function
whose contract cannot be stated over all inputs usually has an unclear
contract.

## Practical notes

- **Constrain the generator to the real domain.** A property that fails on an
  input the system can never receive is noise; encode the precondition in the
  generator, not in a skipped assertion.
- **Reproduce the failure before fixing it.** Every library prints the failing
  seed or case — pin it as a plain example test so the regression stays covered
  after the generator moves on.
- **Watch the runtime.** Properties run hundreds of cases; a slow function
  under a property is a slow test suite. Lower the case count for expensive
  properties rather than deleting them.

Libraries: Rust `proptest` or `quickcheck`; Python `hypothesis`; TypeScript /
JavaScript `fast-check`.

## Test your tests: saboteurs

A green suite is only evidence if it can go red. Deliberately break the code —
invert a condition, drop a line, return a constant — and confirm a test fails.
If nothing does, the test was decorative.

This is the positive control the `debugging` skill argues for, applied to your
own harness. Do it whenever you write a test for something you cannot easily
run, and whenever a suite has been green for a suspiciously long time through
real changes. Mutation-testing tools automate it, but doing it by hand on the
one function you care about takes a minute and catches the same class of
problem.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt) — tips 71, 92. Full tip list: https://pragprog.com/tips/

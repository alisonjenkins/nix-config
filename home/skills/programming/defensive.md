# Defensive programming

You cannot write perfect software. The goal is not code that never fails; it
is code that fails where the fault is, immediately, with enough information to
identify it.

## Contracts

State what a function requires and what it guarantees, in whatever form the
language supports: types first, then a runtime check, then a doc comment as
the last resort.

- **Preconditions** are the caller's responsibility. A violated precondition is
  a bug in the caller, and the function should not try to be helpful about it.
- **Postconditions** are yours. If you promise a sorted, non-empty result, the
  caller is entitled to skip re-checking.
- **Invariants** hold across every public entry point, not just the happy path.

Prefer making an illegal state unrepresentable over checking for it: a type
that cannot hold an empty list beats an assertion that it is not empty. Reach
for this whenever the language's type system supports it: a newtype that can
only be constructed from validated input, a sum type with no "impossible"
variant, a non-empty-list type. Parse untrusted input into that type once at
the boundary and pass the typed value inward; do not re-validate downstream.

**Give distinct domain concepts distinct types, even when the underlying
representation is identical.** A function that takes `customer_id: String`
and `order_id: String` will happily accept them swapped, because it is the
same type, so nothing catches it until the wrong row gets returned or updated
at runtime.
Wrap each in its own type (`CustomerId(String)`, `OrderId(String)`) so the
function signature becomes `fn f(customer_id: CustomerId, order_id: OrderId)`
and passing them in the wrong order is a compile error, not a bug someone
finds in production. This applies to any pair of same-shaped values that mean
different things: two kinds of ID, a validated vs. unvalidated string, a
quantity in cents vs. a quantity in dollars, meters vs. feet. Mandatory
wherever the language supports zero- or near-zero-cost wrapper types: see the
per-language file for the concrete mechanism (Rust newtypes, TypeScript
branded types, Python `NewType`). This is a mechanical instruction; the
design-level version of the same rule, recognising when two values are
secretly different concepts in the first place, is the `design` skill's
[data-and-state.md](../design/data-and-state.md).

## Guard rails

Where a language lets you turn a whole class of runtime failure into a
build-time or lint-time one, turn it on project-wide, not opt-in per file.
This is a mandate, not a suggestion: a lint that is merely enabled but not set
to deny/error is advisory and gets ignored under deadline pressure exactly
when it matters most. Concrete settings live in the per-language file (e.g.
`languages/rust.md`'s clippy deny list for panic-class lints); the principle
here is general: prefer "the compiler/linter refuses to build this" over
"we wrote a test that would probably have caught this."

## Crash early

A program that dies at the point of the fault is far easier to debug than one
that limps on and produces a wrong answer three layers later. When you discover
something that should be impossible, stop. Do not paper over it with a default
value, an empty collection, or a swallowed exception.

"Limp on" is a legitimate choice only where the failure is expected and
recovery is defined, and then it is error handling, not damage control.

## Assertions vs error handling

They are not interchangeable, and mixing them up is how assertions get a bad
name.

| | Assertion | Error handling |
|---|---|---|
| Guards against | Something that **cannot** happen | Something that **can** happen |
| Cause when it fires | A bug in this program | The world being the world |
| Examples | An index past a length you just computed; a match arm the type system should exclude | Malformed input, a network timeout, a missing file |
| May be compiled out | Yes | **Never** |

Never use an assertion for anything that can occur in normal operation: user
input, I/O, anything that crossed a process boundary. And never put a
side effect inside an assertion, because in a build where assertions are
stripped that side effect disappears.

## Finish what you start

Whatever allocates the resource releases it, in the same scope. Use the
language's construct for this: RAII, `defer`, `with`, `try-with-resources`,
`Drop`, rather than a matching call at the end of a long function, which the
first early return will skip.

Where nesting is involved, deallocate in the reverse order of allocation, and
where two pieces of code allocate the same set of resources, allocate them in
the same order everywhere. That last rule is what prevents deadlock.

## Act locally, and take small steps

- **Act locally.** Keep the effect of a change inside the smallest scope that
  can hold it. A variable in the tightest block, a helper private to its
  module, a mutation confined to the object that owns the data.
- **Take small steps.** Make one change, then check: compile, test, run,
  before making the next. Large unverified stretches are how you end up with
  five changes and one failure and no idea which caused it.
- **Don't outrun your headlights.** Do not take a design decision whose payoff
  depends on predicting more than one step ahead. Requirements, platforms and
  your own understanding all change faster than the prediction survives.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt), tips 36-43. Full tip list: https://pragprog.com/tips/

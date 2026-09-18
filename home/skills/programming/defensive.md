# Defensive programming

You cannot write perfect software. The goal is code that fails where the fault
is, immediately, with enough information to identify it.

## Contracts

State what a function requires and guarantees, in whatever form the language
supports: types first, then a runtime check, then a doc comment as last resort.

- **Preconditions** are the caller's responsibility. A violated precondition is
  a bug in the caller; the function should not try to be helpful about it.
- **Postconditions** are yours. If you promise a sorted, non-empty result, the
  caller is entitled to skip re-checking.
- **Invariants** hold across every public entry point, not just the happy path.

Prefer making an illegal state unrepresentable over checking for it: a type
that cannot hold an empty list beats an assertion that it is not empty. Use
this wherever the type system allows: a newtype constructible only from
validated input, a sum type with no "impossible" variant, a non-empty-list
type. Parse untrusted input into that type once at the boundary and pass the
typed value inward; do not re-validate downstream.

**Give distinct domain concepts distinct types, even when the representation
is identical.** A function taking `customer_id: String` and `order_id: String`
accepts them swapped, and nothing catches it until the wrong row is returned or
updated at runtime. Wrap each in its own type (`CustomerId(String)`,
`OrderId(String)`) so the signature becomes
`fn f(customer_id: CustomerId, order_id: OrderId)` and the wrong order is a
compile error. This applies to any pair of same-shaped values that mean
different things: two kinds of ID, a validated vs. unvalidated string, cents
vs. dollars, meters vs. feet.
Mandatory wherever the language has zero- or near-zero-cost wrapper types; the
per-language file has the mechanism (Rust newtypes, TypeScript branded types,
Python `NewType`). This is the mechanical instruction; the design-level rule,
recognising when two values are secretly different concepts, is the `design`
skill's [data-and-state.md](../design/data-and-state.md).

## Guard rails

Where a language can turn a whole class of runtime failure into a build-time
or lint-time one, turn it on project-wide, not opt-in per file. This is a
mandate: a lint enabled but not set to deny/error is advisory and gets ignored
under deadline pressure, exactly when it matters. Concrete settings live in
the per-language file (e.g. `languages/rust.md`'s clippy deny list for
panic-class lints). The principle: prefer "the compiler/linter refuses to
build this" over "we wrote a test that would probably have caught this."

## Crash early

A program that dies at the fault is far easier to debug than one that limps on
and produces a wrong answer three layers later. When you discover something
that should be impossible, stop. Do not paper over it with a default value, an
empty collection, or a swallowed exception.

"Limp on" is legitimate only where the failure is expected and recovery is
defined; then it is error handling, not damage control.

## Assertions vs error handling

Not interchangeable; mixing them up is how assertions get a bad name.

| | Assertion | Error handling |
|---|---|---|
| Guards against | Something that **cannot** happen | Something that **can** happen |
| Cause when it fires | A bug in this program | The world being the world |
| Examples | An index past a length you just computed; a match arm the type system should exclude | Malformed input, a network timeout, a missing file |
| May be compiled out | Yes | **Never** |

Never use an assertion for anything that can occur in normal operation: user
input, I/O, anything that crossed a process boundary. Never put a side effect
inside an assertion; a build that strips assertions loses the side effect.

## Finish what you start

Whatever allocates the resource releases it, in the same scope. Use the
language's construct: RAII, `defer`, `with`, `try-with-resources`, `Drop`,
not a matching call at the end of a long function, which the first early
return skips.

Deallocate in reverse order of allocation, and where two pieces of code
allocate the same set of resources, allocate them in the same order
everywhere. That last rule prevents deadlock.

## Act locally, and take small steps

- **Act locally.** Keep a change's effect in the smallest scope that can hold
  it: a variable in the tightest block, a helper private to its module, a
  mutation confined to the object that owns the data.
- **Take small steps.** One change, then compile, test, run, before the next.
  Large unverified stretches end with five changes, one failure, and no idea
  which caused it.
- **Don't outrun your headlights.** Do not take a design decision whose payoff
  depends on predicting more than one step ahead. Requirements, platforms and
  your own understanding change faster than the prediction survives.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt), tips 36-43. Full tip list: https://pragprog.com/tips/

# Coupling

## Tell, don't ask

Do not pull an object's state out, decide something about it, and push a result
back. Ask the thing that owns the state to do the work.

    # asking
    if order.status == "paid" and order.balance() <= 0:
        order.status = "closed"

    # telling
    order.close_if_settled()

The asking version encodes an invariant about `Order` in a caller that is not
`Order`. When the invariant changes, the caller breaks silently — and so does
every other caller that made the same assumption.

## Don't chain method calls

Any call of the form `a.b().c().d()` couples you to the type of every
intermediate. One layer of indirection is normal; two is a smell; three means
you are navigating someone else's object graph.

The rule of thumb: **talk only to your immediate neighbours** — your own
fields, your parameters, and things you just created.

Honest exceptions, which are not violations:
- Fluent builders and chained iterators / streams, where every call returns the
  same type by design (`items.iter().filter(..).map(..).collect()`).
- Chains inside a single module over its own private types — no external
  coupling is being created.

## Inheritance is a cost, not a discount

Inheriting buys code reuse and pays for it in permanent coupling to a base
class you do not control. Before reaching for it, check whether one of these
fits instead:

- **Delegation — has-a beats is-a.** If you only wanted the behaviour, hold an
  instance and call it. The relationship stays replaceable.
- **Interfaces / traits / protocols for polymorphism.** Express "these things
  can all be used the same way" as a contract, not as a shared ancestor.
- **Mixins / traits with default methods for shared functionality.** Share the
  implementation without claiming a type relationship that is not true.

Deep hierarchies are the failure mode. Any time you find yourself editing a
base class to accommodate one subclass, the hierarchy is wrong.

## Judging a proposed boundary

Ask what crosses it. A boundary that passes plain data is cheap to keep; one
that passes objects the other side must then interrogate is a boundary in name
only. If the caller has to know the callee's internal states to use it, there
is no boundary.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt) — tips 44-47, 51-54. Full tip list: https://pragprog.com/tips/

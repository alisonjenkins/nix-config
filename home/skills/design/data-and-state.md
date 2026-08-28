# Data and state

## Programs are about data

Code is the means; the data and its transformations are the thing. When a
design will not come into focus, stop drawing boxes for objects and write down
the data instead: what comes in, what shape it must end up in, and the steps
between.

Once it is written as a sequence of transformations, the function boundaries
are usually obvious, each step is independently testable, and there is nothing
to mock.

## Give distinct concepts distinct types

A `customer_id` and an `order_id` that are both a bare `String` are the same
type as far as the compiler is concerned, so nothing stops them being passed in
the wrong order, and the mistake surfaces at runtime, in someone else's
incident, instead of at the call site. Two kinds of ID, a validated vs.
unvalidated string, a quantity in cents vs. dollars: whenever two values share
a representation but mean different things, that is a modelling gap, not a
detail to fix later. Wrap each in its own type so a mismatched call is a
compile/type error. This is the design-level statement of the same rule the
`programming` skill's `defensive.md` covers mechanically: see it for the
concrete construct per language (Rust newtypes, TypeScript branded types,
Python `NewType`).

## Don't hoard state, pass it around

State stored so that a later call can find it is an implicit contract between
two points in time. It breaks under concurrency, under reordering, and under
any refactor that changes call order.

Prefer passing what a function needs into it. A function whose result depends
only on its arguments can be read, tested and moved in isolation; one that
depends on accumulated state can only be understood by replaying history.

## Avoid global data

Every global is a hidden parameter to every function that touches it,
including the ones you did not write. Globals defeat isolation in tests,
serialise your options under concurrency, and make the blast radius of a change
unbounded.

Singletons and module-level mutable caches are globals. Naming them something
else changes nothing.

## If it is important enough to be global, wrap it in an API

Some things genuinely are process-wide: configuration, a connection pool, a
logger, a feature-flag source. Do not expose the variable; expose a small
interface that owns it.

The payoff is concrete: the value can be swapped in a test, its access can be
made thread-safe in one place, and its representation can change without a
repo-wide search. If you cannot name the interface, you do not yet know what
the global is for.

## Configuration is external data, not code

Anything that varies between environments, deployments, or users is data.
Values that would otherwise be edited-and-redeployed belong in configuration,
but see [reversibility.md](reversibility.md) for where that stops paying,
because configuration that nobody ever changes is just a harder-to-read
constant.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt), tips 47-50, 55. Full tip list: https://pragprog.com/tips/

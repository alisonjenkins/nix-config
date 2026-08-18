# Concurrency

## Shared state is incorrect state

Any state reachable by two threads, tasks or processes at once is wrong by
default, and stays wrong until something explicitly serialises access to it.
This includes the cases people talk themselves out of: a counter, a lazily
initialised cache, a "read-mostly" map, a file two units both append to.

The dangerous property is that unsynchronised access usually works. It works
in development, it works under test, and it fails at load, which is exactly
when the failure is most expensive.

## Prefer not sharing over sharing carefully

In descending order of preference:

1. **Do not share.** Give each worker its own data; combine the results at the
   end. Immutable values can be shared freely because there is nothing to race.
2. **Pass messages.** Channels, queues, actors — one owner per piece of state,
   and everyone else asks it to act. The ownership rule then holds by
   construction rather than by everyone remembering the convention.
3. **Lock.** Correct, and the easiest to get subtly wrong: a lock forgotten on
   one path, a lock held across an `await` or an I/O call, two locks taken in
   different orders in different functions.

If you do lock: acquire in a consistent global order, hold for the shortest
possible span, and never call out to code you do not control while holding one.

## Analyse the workflow before adding concurrency

Concurrency pays only where there is genuine waiting or genuine parallelism to
exploit. Map what actually depends on what first — the dependency graph is what
determines the possible speed-up, not the number of tasks you can spawn.

Concurrency added without that analysis buys contention, a harder debugging
story, and no throughput.

## Non-determinism is a design property, not bad luck

**Random, intermittent, or load-dependent failures are concurrency issues until
proven otherwise.** A test that passes alone and fails in the suite, a bug that
only appears on the fast machine, a "flaky" integration — these are almost never
flakiness. They are a race that is being reported honestly.

Do not retry past it. Find the shared state.

The `debugging` skill's `false-signals.md` covers this from the other side:
what to distrust when the symptom will not reproduce.

## Source

Adapted from The Pragmatic Programmer, 20th Anniversary Edition
(Thomas & Hunt) — tips 56-59. Full tip list: https://pragprog.com/tips/

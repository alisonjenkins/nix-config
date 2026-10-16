# What testing is for, and what makes a test worth having

`SKILL.md` carries the short form. Read this when judging a test, deciding how
much setup is too much, or choosing what a test should assert.

## What testing is for

**Not finding bugs.** Testing catches bugs; it is *for* design feedback. Hard
to test means something structural: too many collaborators, hidden state, work
fused to I/O. Fix the code, not the test. Elaborate setup is a design finding.
The `design` skill covers what to do about it.

Three consequences:

- **A test is the first user of your code.** Write the call site you wish
  existed, then make it exist. An API that is awkward from a test is awkward
  from everywhere.
- **Design to test.** Testability is a design constraint, not a retrofit.
  Injecting the clock, the RNG and the I/O boundary costs nothing up front and
  is expensive to add later.
- **Find bugs once.** Any bug a human had to find gets a test that would have
  caught it, before the fix lands. Finding it twice means the first fix bought
  nothing.

## What makes a test worth having

- **It fails when the behaviour breaks, and only then.** A test that also
  fails on unrelated refactors is a maintenance tax, not a safety net.
- **It tests behaviour at a boundary you actually promise**, not internal
  structure. Asserting on a private helper freezes an implementation detail.
- **The failure message identifies the bug.** If you have to attach a debugger
  to understand a red test, the assertion is too coarse.
- **It is deterministic.** No wall-clock, no network, no ordering dependence
  between test cases. Inject the clock and the RNG.
- **It covers states, not lines.** Line coverage of two booleans can hit 100%
  while three of their four combinations are never exercised. Ask which states
  and boundaries the test visits (empty, one, many, maximum, error), not what
  percentage the tool reports.

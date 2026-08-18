# Testing TypeScript / JavaScript

## Practice
- Vitest or Jest, whichever the project already uses. Do not add a second
  runner.
- Test the module's exported contract. Rendering internals and private helpers
  are not the promise.
- For UI, Testing Library queries by role and accessible name — those assert
  the thing a user (and a screen reader) can actually reach.
- Async assertions use the runner's `await expect(...).resolves/rejects`; a
  bare floating promise in a test silently passes.
- Fake timers for debounce/throttle logic; never `sleep` in a test.

## Traps
- Snapshot tests rot into rubber stamps. Use them for genuinely stable output
  only, and review the diff rather than running `-u` reflexively.
- Mocking the network at the `fetch` level hides serialisation bugs; prefer a
  local test server (`msw` or a real one) when the wire format matters.

# TypeScript / JavaScript

## Toolchain
- Node and package manager come from the flake devshell. Lockfile is committed
  and authoritative; never regenerate it as a side effect of another change.
- `tsc --noEmit` clean is the bar, alongside the project's linter.
- Profiling/benchmarking/zero-copy tools: see `../performance.md`'s tool
  table first.
- Guard rail: enable `noUncheckedIndexedAccess` in `tsconfig.json`. Without it,
  `arr[i]`/`obj[key]` types as the value type, not `T | undefined`: the
  equivalent of Rust's unchecked indexing panic, except here it's a silent
  `undefined` that crashes three calls later instead of at the access site.

## Idioms
- `strict: true`. No `any` — use `unknown` plus a narrowing check when the
  shape is genuinely dynamic.
- Discriminated unions instead of optional-field soup for state that has modes.
- `type CustomerId = string & { readonly __brand: "CustomerId" }`, not a bare
  `string`; mandatory per `defensive.md`'s "distinct domain concepts" rule.
  Construct only via a dedicated constructor function.
- Parse external data at the boundary (zod or an explicit validator) and pass
  typed values inward. Do not cast untrusted JSON with `as`.
- `async`/`await` throughout; a floating promise is a bug — await it or
  explicitly `void` it with a comment.
- Prefer named exports; default exports make renames invisible in diffs.
- Structured logging (`pino` server-side; the project's existing logger
  otherwise) with fields as an object, not a template string:
  `logger.error({ orderId, reason }, "order failed")`. `console.log` is a
  debugging leftover, not shippable instrumentation: no levels, no structure.
  See `../observability.md` for what belongs in a log line and at what level.

## Browser / UI
- No CDN or external-host assets in artifacts or embedded pages — inline CSS
  and JS, embed images as data URIs.
- Respect both colour schemes: define the full palette on `:root` and override
  only tokens in the dark block.

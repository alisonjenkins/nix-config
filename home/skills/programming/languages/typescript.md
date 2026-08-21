# TypeScript / JavaScript

## Toolchain
- Node and package manager come from the flake devshell. Lockfile is committed
  and authoritative; never regenerate it as a side effect of another change.
- `tsc --noEmit` clean is the bar, alongside the project's linter.
- Guard rail: enable `noUncheckedIndexedAccess` in `tsconfig.json`. Without it,
  `arr[i]`/`obj[key]` types as the value type, not `T | undefined` — the
  equivalent of Rust's unchecked indexing panic, except here it's a silent
  `undefined` that surfaces as a crash three calls later instead of at the
  access site.

## Idioms
- `strict: true`. No `any` — use `unknown` plus a narrowing check when the
  shape is genuinely dynamic.
- Discriminated unions instead of optional-field soup for state that has modes.
- Branded types for identifiers/values that must not be mixed up despite
  sharing a primitive type: `type CustomerId = string & { readonly __brand:
  "CustomerId" }`, with a constructor function as the only way to produce one.
  `f(customerId: CustomerId, orderId: OrderId)` then rejects a swapped call at
  compile time — plain `string`/`string` would not. Mandatory at any function
  boundary taking two or more same-typed values that mean different things —
  see `defensive.md`'s "distinct domain concepts" rule.
- Parse external data at the boundary (zod or an explicit validator) and pass
  typed values inward. Do not cast untrusted JSON with `as`.
- `async`/`await` throughout; a floating promise is a bug — await it or
  explicitly `void` it with a comment.
- Prefer named exports; default exports make renames invisible in diffs.

## Browser / UI
- No CDN or external-host assets in artifacts or embedded pages — inline CSS
  and JS, embed images as data URIs.
- Respect both colour schemes: define the full palette on `:root` and override
  only tokens in the dark block.

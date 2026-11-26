---
description: cargo-mutants with cap_lints drops lld from .cargo/config.toml; the fix must keep the linker choice out of rustflags.
max_turns: 4
allowed_tools: [Skill]
---
`cargo mutants` links use about four times the memory of `cargo test` in this Rust repo, and the box starts swapping. The config is below. Why does this happen, and what should I change? Keep `cap_lints` on: our crate denies warnings. Answer in a few lines, no tool runs.

`mutants.toml`:

```toml
cap_lints = true
```

`.cargo/config.toml`:

```toml
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "link-arg=-fuse-ld=lld"]
```

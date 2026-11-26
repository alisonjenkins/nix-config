---
type: llm
---
The reply says cargo-mutants sets `CARGO_ENCODED_RUSTFLAGS` (or an environment rustflags override) because of `cap_lints`, and that this replaces the rustflags from `.cargo/config.toml`, so `-fuse-ld=lld` is dropped and a different (default, e.g. ld.bfd) linker is used.

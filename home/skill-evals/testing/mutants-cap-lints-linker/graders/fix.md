---
type: llm
---
The reply's main fix keeps `cap_lints` on and selects lld without config rustflags, for example a wrapper script set as `target.<triple>.linker` that passes `-fuse-ld=lld`. Suggesting only "turn cap_lints off" fails.

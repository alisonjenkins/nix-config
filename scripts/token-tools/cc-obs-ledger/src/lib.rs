//! Hook tool that fills the gaps in Claude Code's own telemetry: per-turn context
//! size, cache hit ratio, fixed-context split and keyed hashes of tool inputs.
//! It reads token counts and sizes only and never sends transcript text.

pub mod census;
pub mod config;
pub mod error;
pub mod notice;
pub mod otlp;
pub mod ship;
pub mod transcript;

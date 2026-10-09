//! Read-only, bounded queries over the local observability stack. The library holds
//! the backend clients and the commands; the `cc-obs-query` binary is a thin CLI.
pub mod backend;
pub mod bounds;
pub mod cli;
pub mod commands;
pub mod error;
pub mod pack;
pub mod window;

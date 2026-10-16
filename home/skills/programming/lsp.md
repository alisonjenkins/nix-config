# Language servers (LSP)

Ask the language server before you grep for anything that is about meaning,
not text. It knows scopes, types and imports; grep does not.

## When to use it

| Question | Operation |
|---|---|
| Where is this defined? | `goToDefinition` |
| Who uses / calls this? | `findReferences`, `incomingCalls` |
| What type is this, what does it do? | `hover` |
| What is in this file? | `documentSymbol` (cheaper than reading it) |
| Where is something called X? | `workspaceSymbol` with a `query` |
| What does this call? | `outgoingCalls` |

- Do this **before** changing a signature, renaming, or deleting something:
  list the references first.
- Use grep for text: strings, config keys, comments, other languages, and to
  cross-check an empty LSP answer.
- Claude Code: the `LSP` tool may be deferred. Load it with
  `ToolSearch select:LSP` if it is not callable.
- Diagnostics can arrive after LSP calls and edits. Read them and fix what
  you caused; do not step over them.

## An empty answer is not "no"

`null`, "No hover information" or "0 items" has three causes. Rule them out
in order before you conclude anything:

1. **Cold start.** The first request for a workspace starts a server. Retry
   after 10-30 s. An idle server can also be slow (7.9 s observed on one that
   had sat unused for a day).
2. **Wrong or missing workspace.** The server only analyses what it loaded.
   `documentSymbol` is syntax-only and works anyway, so it proves nothing
   about this. If `documentSymbol` answers but `hover` and
   `goToDefinition` are empty, suspect the workspace.
3. **Genuinely nothing there.** Only now.

Control: run `hover` on a symbol you can see is defined in the same file. If
that is empty too, the server is not analysing this code, and an empty
`findReferences` means nothing.

## Workspace root traps

- **rust-analyzer** loads a Cargo workspace from the session's working
  directory. A crate that is not at that root (seen with
  `scripts/<tool>/Cargo.toml` in a repo with no root `Cargo.toml`) was never
  loaded: `documentSymbol` worked, `hover`/`definition` were empty. The same
  server answered once the root was the crate. Start the session in the
  crate. Setting `rust-analyzer.linkedProjects` should also work but is
  untried. Otherwise fall back to grep and say that you did.
- **nixd** answered `goToDefinition` for local bindings straight away. Hover
  on a nixpkgs `lib` function came back empty; the cause is unconfirmed
  (probably it needs an evaluation), so treat that as unknown, not as a fault.

## lspmux (shared servers)

If `lspmux` is in use here (`pgrep -a lspmux`), sessions and editors share
servers. From `lspmux status`, an instance appears to be keyed by **server
binary + workspace root** (inferred, not read from its source). So:

- Another worktree is another instance, and another cold start.
- A server upgrade (new store path) gets its own instance; old ones were seen
  lingering.
- `lspmux status` lists instances (`pid`, `server`, `path`, `last used`,
  clients). Find the binary with `command -v lspmux`.
- The server process is shared with live sessions. **Never kill or restart
  it, or an instance, without asking.** Clients lose their LSP.

## Probing a server by hand

When the tool gives nothing and you must know whether the server works: speak
LSP over stdio to `lspmux client --server-path <server binary>` with the
working directory set to the workspace root. Send `initialize` (with
`rootUri`), `initialized`, `textDocument/didOpen`, then `documentSymbol` and
`hover`; poll `hover` for up to ~90 s (rust-analyzer needs ~10 s after
loading). Answer server-to-client requests with `null`. Do **not** send
`shutdown`/`exit`: that is for a server you own. Terminate the client
instead.

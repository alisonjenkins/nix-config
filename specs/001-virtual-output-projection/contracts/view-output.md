# Contract: `view-output`

## IPC request (niri-ipc)

```rust
Request::ViewOutput { name: Option<String> }
Response::ViewOutput(ViewOutputState)

enum ViewOutputState {
    Viewing { viewer: String, source: String },
    Stopped { viewer: String, source: String },
    NotViewing,
}
```

| Call | Precondition | Reply | Effect |
|---|---|---|---|
| `name: Some(v)` | `v` is a virtual output that is on | `Viewing { viewer, source: v }` | The focused physical output views `v`, and `v` becomes the active monitor |
| `name: Some(v)` | Already viewing another output | `Viewing { viewer, source: v }` | Switches to `v` |
| `name: Some(v)` | `v` unknown | `Err("no output named 'v'")` | None |
| `name: Some(v)` | `v` is physical | `Err("output 'v' is not a virtual output")` | None |
| `name: Some(v)` | `v` is off | `Err("virtual output 'v' is off")` | None |
| `name: Some(v)` | No physical output exists | `Err("no physical output to view 'v' on")` | None |
| `name: None` | Viewing | `Stopped { viewer, source }` | The viewer shows its own workspaces and becomes active |
| `name: None` | Not viewing | `NotViewing` | None |

"The focused physical output" is the active monitor if it is physical. Otherwise it is the
physical output the pointer is on. If neither applies, it is the first physical output.

## CLI (`niri msg`)

```
niri msg view-output [NAME]
```

- Success prints one line: `Viewing steam on DP-2`, `Stopped viewing steam on DP-2`, or
  `Not viewing any output`.
- Errors print the error message and exit with a non-zero status, like other `niri msg`
  errors.
- `niri msg --json view-output [NAME]` prints the `Response` as JSON.

## Bind action (niri-config KDL)

```kdl
binds {
    Mod+V { view-output "steam"; }   // enter or switch
    Mod+Shift+V { view-output; }    // leave
}
```

- `Action::ViewOutput { name: Option<String> }` behaves exactly as the request does.
- Binds have no reply channel, so an error is logged at `warn` and shown for 2 s in the same
  label as "Viewing: <name>".

## Overview interaction (no new API)

- Clicking a workspace in a virtual output's column gives the same result as
  `view-output <that output>` with that workspace active.
- Drag and drop and new-workspace drops between columns go through the existing
  interactive-move and DnD paths. There are no new actions.

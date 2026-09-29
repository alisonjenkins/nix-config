# Contract: event-stream events

Two new variants of `niri_ipc::Event`, delivered by `niri msg event-stream` and the JSON event
stream (`niri msg --json event-stream`, or the socket `EventStream` request). Both follow the
existing rules: they are sent once in the initial burst to a new subscriber, then on every change.
Existing events are unchanged. Clients that deserialise `Event` strictly must accept the new
variants, as with any event addition.

## `ViewOutputChanged`

```rust
/// View mode started, stopped or switched output.
///
/// Sent on connect with the current state.
ViewOutputChanged {
    /// `Viewing { viewer, source }` while a physical output shows a virtual output,
    /// otherwise `NotViewing`. `Stopped` is never sent in this event.
    state: ViewOutputState,
},
```

JSON examples:

```json
{"ViewOutputChanged":{"state":{"Viewing":{"viewer":"DP-2","source":"steam"}}}}
{"ViewOutputChanged":{"state":"NotViewing"}}
```

Sent exactly once for each of: `view-output <name>` (IPC or bind), clicking a virtual workspace or
window in the overview, `view-output` with no name, Escape in a view entered from the overview,
the viewer becoming the active monitor again, and either output going away. Switching the viewed
source sends one `Viewing` with the new names. No event is sent when nothing changes (for example
`view-output` with no name while not viewing).

`niri msg event-stream` prints:

```text
View output: steam on DP-2
View output: none
```

## `OutputsChanged`

```rust
/// An output was connected, disconnected, turned on or turned off.
///
/// Sent on connect with the current outputs.
OutputsChanged {
    /// All outputs, keyed by connector name, as returned by the `Outputs` request.
    outputs: HashMap<String, Output>,
},
```

- Covers every output, physical and virtual.
- Sent when the set of output names changes, or when any output turns on or off (its
  `current_mode`/`logical` becomes present or absent).
- Not sent for a mode, scale, transform or position change alone.
- The payload is the full current map, so a client needs no other state to stay correct.

`niri msg event-stream` prints one line listing the outputs and their on/off state, sorted by
name:

```text
Outputs changed: DP-2 (on), steam (off)
```

## Unchanged

- The `view-output` request and its `ViewOutputState` response (including `Stopped`).
- The `Outputs` request.

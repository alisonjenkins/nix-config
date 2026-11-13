# Printing over Moonraker

The X-Max 4 runs Klipper with Moonraker on port 7125. `scripts/printer.sh` finds
the address from the `print_host` field of
`~/.config/QIDIStudio/user/default/physical_printer/*.json`. It never reads the
key or password fields.

## Before starting a print

Only when the user asked to print in this conversation.

1. `scripts/printer.sh status` and confirm the state is `standby`, `complete`,
   `cancelled` or `error`-cleared, not `printing` or `paused`.
2. Tell the user the things you cannot see and they must check: PLA is loaded in
   filament slot 1 (the start code uses the filament box), and the plate matches
   the bed type sliced for.
3. `scripts/printer.sh start FILE.gcode` uploads and starts in one call.

## After starting

- Check `status` once heating begins. It reports state, file, temperatures and
  progress. Do not poll in a loop; report and let the user ask.
- Say plainly what was checked ("heating, no plastic laid yet") and not more.
- `scripts/printer.sh cancel` stops a running job. Use it only when the user asks.

## Failure

- Connection refused or timeout: the printer is off or asleep. Say so; do not
  retry for long.
- HTTP 401 or 403: Moonraker wants a key. Stop and tell the user. Do not look up
  the key in the config.
- Upload succeeds but `print_started` is false: report it and the printer state.

# Printing over Moonraker

The X-Max 4 runs Klipper with Moonraker on port 7125. `scripts/printer.sh` finds
the address from the `print_host` field of
`~/.config/QIDIStudio/user/default/physical_printer/*.json`. It never reads the
key or password fields.

## Before starting a print

Only when the user asked to print in this conversation.

1. `scripts/printer.sh status` and confirm the state is `standby`, `complete`
   or `cancelled`, not `printing`, `paused` or `error`.
2. An idle printer is not a ready one. Ask the user to confirm, and wait for
   the answer, that:
   - the bed is clear: the last part is off, nothing is left on the plate, and
     they are not partway through clearing it;
   - the right plate is fitted, matching the bed type sliced for;
   - the sliced material is loaded in the filament box slot the slice used
     (`QIDI_SLOT`, 0 = slot 1A), in the colour they want.
   Ask even when they just said to print. Ask again for every start attempt,
   including a retry after a cancel or failure: the bed may no longer be clear.
3. `scripts/printer.sh start FILE.gcode --bed-clear` uploads and starts in one
   call. Pass the flag only after step 2.

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

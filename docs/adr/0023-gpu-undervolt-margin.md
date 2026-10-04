# 0023. Undervolt the RX 9070 XT to -40mV, not to the edge

- Status: Accepted, pending soak
- Date: 2026-10-04

## Context

LACT sets the RX 9070 XT's voltage offset and power cap from
`services.lact.settings` in `flake-modules/hosts/ali-desktop/default.nix`.
The offset was tuned toward the lowest value that passed a benchmark: -80mV
first, then -75mV, then -70mV.

The card hung its graphics ring once at each of those values:

| Date | Offset | Game |
|---|---|---|
| 2026-05 | -80mV | Forza Horizon 6 |
| 2026-08-31 | -75mV | (game session, journal rotated) |
| 2026-10-04T07:41:48Z | -70mV | Helldivers 2 |

The 2026-08-31 hang is why the offset moved from -75mV to -70mV. That 5mV
step did not hold.

The 2026-10-04 hang in `journalctl -k`. The Forza Horizon 6 hangs had the
same shape, with `msg=RESET` in place of `msg=REMOVE_QUEUE`:

```
amdgpu 0000:03:00.0: ring gfx_0.0.0 timeout, signaled seq=426174665, emitted seq=426174668
amdgpu 0000:03:00.0:  Process helldivers2.exe pid 2835190 thread thread pool wor pid 2835897
amdgpu 0000:03:00.0: Ring gfx_0.0.0 reset failed
amdgpu 0000:03:00.0: MES(1) failed to respond to msg=REMOVE_QUEUE
amdgpu 0000:03:00.0: MODE1 reset
amdgpu 0000:03:00.0: VRAM is lost due to GPU reset!
```

A hang is never contained to the game. The ring reset fails, and the kernel
then falls back to a full MODE1 reset, which wipes VRAM. Xwayland, the
browser, sunshine and every other GPU client die with it.

The undervolt was worth little. The Forza Horizon 6 benchmark measured +1.2%
average FPS at -75mV with a 374W cap, against the same RAM tuning at stock.

## Decision

Set `voltage_offset = -40` and keep `power_cap = 374.0`. That leaves 30mV
between the setting and the lowest offset known to hang. If the card hangs
again, step toward stock in this order, one change at a time:

1. Power cap to 330W, the card's default.
2. A -150MHz clock offset.
3. Voltage offset to 0.

## Alternatives rejected

- **Keep -70mV.** It hung. The config comment already said to back
  off toward 0 if it hung again.
- **-65mV or -60mV.** A 5mV step was the last fix, from -75mV to -70mV, and
  it did not hold. Hangs are rare and depend on load, so a benchmark pass
  says little about the margin. A small step would need weeks of play to
  trust.
- **Stock voltage.** It gives up the overclock completely. That is the right
  answer if -40mV still hangs, but it would also hide whether the
  undervolt was the cause.
- **Lower the power cap first.** Raising the cap on a fixed voltage margin
  lets the card boost higher into the same voltage droop. That reasoning is
  not backed by a source, so the cap stays, and voltage moves first because
  voltage has evidence behind it.

## Consequences

- The card loses some of the +1.2%. That has not been measured at -40mV.
- Nothing records whether an undervolt was live during the Forza Horizon 6
  hangs of 2026-05-22. Hangs without a fault also come from firmware, so a
  hang at -40mV does not by itself prove the voltage is still wrong.
- Any hang still costs the whole session, whatever its cause. See
  [0024](0024-amdgpu-kernel-parameters.md) for the MES firmware limit
  behind that.

## Evidence

- The three hangs above. The 2026-10-04 lines come from `journalctl -k -b 0`.
  The 2026-05 hang and the +1.2% figure come from the Forza Horizon 6 notes
  kept outside this repo.
- Live OverDrive state before the change, from
  `/sys/class/drm/card1/device/pp_od_clk_voltage`: `OD_VDDGFX_OFFSET: -70mV`,
  allowed range `-200mv 0mv`.
- The built system's `/etc/lact/config.yaml` has `voltage_offset: -40` and
  `power_cap: 374.0`.
- Players report a -150MHz clock offset fixes Helldivers 2 crashes on RX
  9070 XT cards, on Windows and Linux. These are Steam forum posts, not
  measurements:
  <https://steamcommunity.com/app/553850/discussions/1/591772149598992585/>.

## Revisit when

- Helldivers 2 or Forza Horizon 6 hangs at -40mV. Take the next step in the
  list above.
- Several weeks pass with no `ring .* timeout` in `journalctl -k`. Then
  -50mV is worth a try, with the same soak before trusting it.
- A hang happens at 0mV. Then the cause is the driver or firmware, not the
  overclock. Copy `/sys/class/drm/card1/device/devcoredump/data` within a
  few minutes of the reset, before the kernel drops it, and report it to
  <https://gitlab.freedesktop.org/drm/amd>.

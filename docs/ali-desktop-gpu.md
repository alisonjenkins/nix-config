# ali-desktop GPU: tuning and hang triage

`ali-desktop` runs an RX 9070 XT (Navi 48, `1002:7550`, GFX12, PCI
`0000:03:00.0`, DRM `card1`) next to the Raphael iGPU at `0000:1a:00.0`.
Everything here lives in `flake-modules/hosts/ali-desktop/default.nix`. Why
each setting is what it is: [0023](adr/0023-gpu-undervolt-margin.md) for the
undervolt, [0024](adr/0024-amdgpu-kernel-parameters.md) for the kernel
parameters.

## Current settings

LACT applies these at boot, from `services.lact.settings`:

| Setting | Value | Stock |
|---|---|---|
| Voltage offset | -40mV | 0 |
| Power cap | 374W | 330W (the cap's maximum is 374W) |
| Clock offset | 0 | 0 |
| Fan control | firmware | firmware |

Kernel parameters (`boot.kernelParams`, plus `amdgpu.ppfeaturemask` from
`modules.base.amdgpuPPFeatureMask`):

| Parameter | Value | Why |
|---|---|---|
| `ppfeaturemask` | `0xfff7ffff` | Kernel default plus OverDrive, so LACT can write voltage and power |
| `lockup_timeout` | `20000` | Default is 2s; llama.cpp Vulkan jobs need longer |
| `vm_fragment_size` | `9` | 2MB fragments; no extra memory cost |
| `runpm` | `0` | No runtime PM on a desktop card |
| `gpu_recovery`, `dc`, `dpm` | `1` | Same as auto; harmless |

Kernel parameters need a reboot (`just boot`). LACT settings apply on
`just switch`.

## Is it the GPU that crashed?

A GPU hang takes the whole session with it, so it can look like a niri,
Xwayland or browser crash. Check the kernel log first:

```bash
journalctl -k -b 0 | grep -E 'ring .* timeout|GPU reset|VRAM is lost|page fault'
```

| What you see | What it means |
|---|---|
| `ring gfx_0.0.0 timeout`, then `Process <name> pid` | A job from that process hung the graphics ring. The process named is the one that hung it |
| `[gfxhub] page fault` before the timeout | The game read bad memory. Usually a vkd3d-proton or game bug, not voltage. Forza Horizon 6's descriptor aliasing looked like this |
| No page fault, just the timeout | A hang without a fault. Undervolt instability looks like this, and so do firmware hangs |
| `MES(1) failed to respond to msg=REMOVE_QUEUE`, then `MODE1 reset` | The ring reset failed and the card fully reset. Expected on this firmware, see [0024](adr/0024-amdgpu-kernel-parameters.md) |
| `MES firmware reports incorrect version in ucode binary (0x1 vs 0x8b)` | Informational, logged during resume. Not the fault |
| `amdgpu: unknown parameter '<name>' ignored` at boot | A kernel parameter that does nothing. Remove it |

If the previous boot ended in the hang, use `journalctl -k -b -1`.

## After a hang

1. **Copy the devcoredump first.** The kernel keeps it for only a few
   minutes:

   ```bash
   cp /sys/class/drm/card1/device/devcoredump/data ~/amdgpu-devcoredump-$(date -u +%FT%TZ)
   ```

2. Note the game, the Proton version, and what was on screen.
3. Check the undervolt that was live:
   `cat /sys/class/drm/card1/device/pp_od_clk_voltage` shows
   `OD_VDDGFX_OFFSET`.
4. Take the next step in [0023](adr/0023-gpu-undervolt-margin.md)'s list,
   one change at a time: power cap to 330W, then a -150MHz clock offset,
   then 0mV.

A hang at 0mV with stock power means the overclock is not the cause. Report
it to <https://gitlab.freedesktop.org/drm/amd> with the devcoredump, kernel
version (`uname -r`), Mesa version and the `journalctl -k` excerpt.

## Deeper diagnostics

- `RADV_DEBUG=hang` writes `~/radv_dumps_*` when a hang happens. It waits
  for idle after every submit, so the game runs slowly; use it only to
  catch a hang that reproduces. See
  <https://docs.mesa3d.org/drivers/amd/hang-debugging.html>.
- Live clocks, power and VRAM: `amdgpu_top` is installed.
- Every module parameter, with defaults for the running kernel:
  `modinfo -p amdgpu`. Live values: `/sys/module/amdgpu/parameters/`.

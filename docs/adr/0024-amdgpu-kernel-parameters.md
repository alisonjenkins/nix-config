# 0024. Override amdgpu kernel parameters only with a measured reason

- Status: Accepted
- Date: 2026-10-04

## Context

`ali-desktop`'s `boot.kernelParams` had grown a block of `amdgpu.*`
overrides. Each one carried a comment saying what it did. Checked against
the running kernel (7.2.8-cachyos) on 2026-10-04, three of those comments
were wrong:

- **`amdgpu.gfxoff=0`** did nothing. The parameter does not exist, and the
  kernel logs it at every boot:

  ```
  amdgpu: unknown parameter 'gfxoff' ignored
  ```

  GFXOFF stayed enabled the whole time it was supposed to be off as a
  hang mitigation.
- **`amdgpu.vm_update_mode=0`** was commented "use default (auto)". It
  overrode the default. `modinfo amdgpu` says the default is 0 "except for
  large BAR(LB)", where it is 2: compute VM page tables are updated by the
  CPU. This card has a large BAR. BAR0 maps all 16 GiB of VRAM.
- **`amdgpu.lockup_timeout=20000`** was commented "default 10s". The
  default is now 2s for every queue. `modinfo` says `default: 2000`, and
  upstream lowered it in "drm/amdgpu: reduce queue timeout to 2 seconds".

`amdgpu.ppfeaturemask` came from `modules.base.amdgpuPPFeatureMask`, and the
host overrode it to `0xffffffff`, "full PowerPlay unlock". The base default
is `0xfff7ffff`: the kernel default plus OverDrive (bit 14, `0x4000`), which
is all LACT needs to set voltage and power. `0xffffffff` also set bit 19
(`GFX_DCS`), which the kernel leaves off by default.

## Decision

In `flake-modules/hosts/ali-desktop/default.nix`:

- Drop the host's `amdgpuPPFeatureMask` override, so the base `0xfff7ffff`
  applies.
- Drop `amdgpu.gfxoff=0`.
- Drop `amdgpu.vm_update_mode=0`.
- Keep `amdgpu.lockup_timeout=20000`, with its comment corrected. This host
  runs llama.cpp on Vulkan, and long Vulkan dispatches hit `DeviceLost` at
  the 2s default
  ([llama.cpp #21724](https://github.com/ggml-org/llama.cpp/issues/21724)).
- Keep `amdgpu.vm_fragment_size=9`, `amdgpu.runpm=0`,
  `amdgpu.gpu_recovery=1`, `amdgpu.dc=1` and `amdgpu.dpm=1`.

A new `amdgpu.*` override needs a measured reason in its comment, and the
comment has to match what `modinfo amdgpu` says the parameter does.

## Alternatives rejected

- **Disable GFXOFF properly**, by clearing ppfeaturemask bit 15 (`0x8000`),
  or by writing 0 to `/sys/kernel/debug/dri/N/amdgpu_gfxoff`. On Navi 48,
  turning GFXOFF off broke s2idle and left the card drawing about 250W
  ([nixpkgs #564601](https://github.com/NixOS/nixpkgs/issues/564601)). No
  source names GFXOFF as a hang cause on RDNA4, so the trade is not worth
  making.
- **Remove `lockup_timeout` and go back to 2s.** A real hang would recover
  18 seconds sooner. But recovery is a MODE1 reset that kills the session
  anyway (see Consequences), so the extra seconds of freeze cost little.
  Losing llama.cpp jobs to false timeouts costs more.
- **Remove `vm_fragment_size=9`.** 2MB fragments are used only when an
  allocation is large enough, and cost no extra memory
  ([Phoronix forum](https://www.phoronix.com/forums/forum/linux-graphics-x-org-drivers/open-source-amd-linux/977778-amdgpu-increasing-fragment-size-for-performance)).
  There is no evidence of harm or benefit, so it stays rather than becoming
  another variable while the undervolt is tested.
- **Remove `gpu_recovery`, `dc` and `dpm`.** They match what auto picks on
  this card. Removing them changes nothing at runtime, so it is churn.

## Consequences

- Any GPU hang still escalates to a MODE1 reset that wipes VRAM. The ring
  reset needs MES to remove the hung queue, and MES firmware `0x8b` fails
  that (`MES(1) failed to respond to msg=REMOVE_QUEUE`). Upstream amd-gfx
  has patches for it: the mes12 `remove_queue_after_reset` change, and a
  lower per-queue-reset version threshold. Whether kernel 7.2.8 carries
  them is unchecked. The `MES firmware reports incorrect version in ucode
  binary (0x1 vs 0x8b)` line after a reset is informational, not the fault.
- Compute VM updates go back through the CPU, the default AMD chose for
  large-BAR cards. This has not been benchmarked here.
- `GFX_DCS` is off again, matching the kernel default.

## Evidence

- `modinfo -p amdgpu` and `/sys/module/amdgpu/parameters/*` on
  2026-10-04: `lockup_timeout` "default: 2000"; `vm_update_mode` "0 = never
  (default except for large BAR(LB))... 2 = Compute only (default for LB)";
  live `ppfeaturemask=0xffffffff`.
- `/sys/bus/pci/devices/0000:03:00.0/resource`: BAR0 is 16384 MiB.
- The built system's `kernel-params` file contains
  `amdgpu.ppfeaturemask=0xfff7ffff` and no `gfxoff` or `vm_update_mode`.
- Kernel parameter reference:
  <https://docs.kernel.org/gpu/amdgpu/module-parameters.html>.

## Revisit when

- A kernel update changes a default. Re-run `modinfo -p amdgpu` against
  this list.
- A hang survives with a contained ring reset, no MODE1. That means the MES
  fix landed, and a shorter `lockup_timeout` for the GFX queue
  (`GFX,Compute,SDMA,Video` format) becomes worth it.
- s2idle or idle power is fixed for GFXOFF-off on Navi 48, and GFXOFF is
  then implicated in a hang.

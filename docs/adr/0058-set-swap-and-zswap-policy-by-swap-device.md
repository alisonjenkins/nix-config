# 0058. Set swappiness and zswap by swap device type

- Status: Accepted
- Date: 2026-10-30

## Context

[0056](0056-tune-vm-sysctls-for-zram-in-base.md) set zram sysctls in base and
let `ali-desktop` pin `vm.swappiness = 10` because it also has disk swap. Two
problems remained:

- Gaming desktops and laptops that swap to zram kept the low pin or the base
  value of 100. Distributions that tune for zram go higher: CachyOS ships 150,
  Bazzite and Pop!_OS 180, because compressing an anonymous page is cheaper
  than refaulting evicted file cache.
- zswap sits in front of the swap device as a compressed cache. In front of
  zram it is a second compressor on the same pages and keeps them out of zram
  (Arch wiki, Zram page). CachyOS kernels build zswap default-on; on
  `ali-desktop` zswap held 1.4 MB while zram held 4 KiB of data.

## Decision

1. **Gaming hosts with zram use `vm.swappiness = 150`.** The gaming block of
   `modules/desktop` sets it at `mkOverride 900`, above the base `mkDefault`
   (100). A host `mkForce` still wins (`ali-mba-linux` keeps 180). The
   `ali-desktop` pin of 10 is removed.
2. **zswap is off wherever zram is the swap.** `modules/base` sets
   `modules.kernelTuning.zswapOff = mkDefault config.zramSwap.enable`, and
   imports `modules/kernel-tuning` to do so. Both knobs live in the
   [0057](0057-manage-kernel-options-through-kernel-tuning-profiles.md) table
   and conflict with each other.
3. **Disk-swap-only hosts may enable zswap.** `home-storage-server-1` (8 GB
   RAM, zram off, 32 GB LVM swap) sets `zswapOn`. This is a trial.
4. **Servers keep their swappiness and zram size.** No measurement supports a
   change. Server guidance in the literature is low swappiness (Red Hat
   throughput-performance 10, virtual-guest 30), which the base value for
   non-zram hosts already is.

## Consequences

- Gaming hosts swap anonymous pages earlier. Watch for stutter caused by
  swap-in of pages a game still wants; revert per host with a plain
  `vm.swappiness` at higher priority.
- `modules/base` now depends on `modules/kernel-tuning`, which stays inert
  until a knob or profile is set.
- The minimum kernel for both zswap knobs (3.11) is from memory; the fleet
  runs 6.18 or newer.
- Not decided: whether Kubernetes nodes tolerate swap (kubelet `failSwapOn`
  is not set in this repo), and whether hibernation interacts with zswap on
  the storage server, which has a resume device.

## Revisit when

The storage-server trial shows worse swap-in latency, or a gaming host stutters
under memory pressure.

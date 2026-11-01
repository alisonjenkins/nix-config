# 0056. Tune swap sysctls for zram in base, per host where disk swap exists

- Status: Accepted
- Date: 2026-10-28

## Context

`modules/base` enables zram (zstd, 100% of RAM) on every host but kept
`vm.swappiness = 10` and the kernel's `vm.page-cluster = 3`. Both are tuned for
swap on a disk. With zram, swappiness 10 keeps cold anonymous pages resident
until pressure is severe, and an 8-page swap-in readahead fetches pages from
RAM-backed storage that nobody asked for. zram-generator's upstream guidance is
the opposite: swap eagerly into compressed RAM, no readahead.

The fleet had drifted into per-host copies. `ali-mba-linux` carried the full
upstream block (swappiness 180, page-cluster 0, watermark_boost_factor 0,
watermark_scale_factor 125), `home-kvm-hypervisor-1` carried 100 and 0, desktop
gaming carried page-cluster 0 and watermark_scale_factor 50, and every other zram
host (servers, non-gaming laptops, download-server-1) kept the disk defaults.

## Decision

In `modules/base`, when `zramSwap.enable` is true:

- `vm.page-cluster = 0` (`mkDefault`).
- `vm.swappiness = 100` (`mkDefault`); without zram it stays 10.

`ali-desktop` pins `vm.swappiness = 10`. It has a halved zram plus 64G of disk
swap so compile working sets overflow to disk; eager swapping would fill the
small zram early and spill sooner.

`ali-mba-linux` keeps 180 and its watermark settings, which were chosen against
observed JVM heap OOMs. The kvm host keeps its explicit 100 beside its
host-specific reasoning. The duplicated `page-cluster` lines in both are gone.

## Alternatives rejected

- **swappiness 180 fleet-wide.** The knob is global: above 100 it also makes
  file cache cheaper to keep than anonymous memory, which hurts hosts that read
  large files (Jellyfin, storage). Only mba has evidence for it.
- **`vm.watermark_scale_factor = 125` fleet-wide.** It reserves 1.25% of RAM as
  free headroom: about 3 GiB on the 251 GiB kvm host and 800 MiB on the 64G
  desktop, which deliberately lowered it to 50. It suits small, pressured
  machines only.
- **Leave the base at 10 and copy the block to hosts that want it.** That is how
  the fleet drifted.

## Consequences

Servers and non-gaming laptops (k8s, vpn, download-server-1, framework and work
laptops) move from swappiness 10 to 100. This has not been measured; nothing
showed swappiness 10 as the cause of a problem on them. `home-storage-server-1`
has no zram and is unchanged.

## Revisit when

A zram host shows heavy swap-in latency or CPU spent in zstd reclaim after
deploy, or `vm.swappiness = 100` evicts a cache-sensitive workload. Then pin the
host back to 10 beside its own reasoning.

# Plan: Migrate `/nix` on ali-desktop from btrfs to XFS

- Status: DRAFT — planning only, nothing executed
- Author: Claude (agent), for Alison Jenkins
- Date written: 2026-08-25T00:00:00Z (times below are placeholders — fill in actual UTC times when executing)
- Host: `ali-desktop`
- Scope: **only** `/nix`. `/persistence` stays on btrfs, on the same underlying `osvg-persistence` LV, unchanged.
- This document is a plan. No migration step in it has been run. No config in this repo has been changed. No filesystem has been touched. Every command below that mutates anything is explicitly flagged; the human operator runs those, not the agent (see `infra` skill: live infra changes need explicit go-ahead, and this agent cannot `sudo`).

---

## 0. Why, and why this is delicate

`/nix` and `/persistence` are currently two **subvolumes of the same btrfs filesystem** on `/dev/osvg/persistence` (293G). Moving `/nix` to XFS means:

- Splitting that shared filesystem into two independent block devices/filesystems — the store gets its own LV and its own XFS filesystem; `/persistence` keeps the existing btrfs LV as-is.
- `/nix` has `neededForBoot = true` and cannot be unmounted while NixOS is running from it — the cutover must happen from outside the running system (live USB or initrd), not by `umount`ing `/nix` on a live desktop session.
- Impermanence keeps `/` as tmpfs and relies on `/persistence` bind-mounts (roughly 20 paths: `/var/log`, `/var/lib/docker`, `/var/lib/flatpak`, `/etc/NetworkManager/system-connections`, `/var/lib/sbctl`, `/etc/luks`, etc.) surviving reboot. None of those live on `/nix`, so they are structurally unaffected — but the plan double-checks this rather than assuming it.
- Secure Boot (lanzaboote) is enabled; `/boot` is a separate vfat partition, untouched by this migration, but the bootloader/generation mechanics still need to be understood before doing anything from a live environment.

Read this whole document before running anything. Where a number must be measured first, this plan says so explicitly rather than inventing one.

---

## 1. Pre-flight verification (non-destructive; read-only)

**Goal of this phase:** confirm assumptions, gather the one missing number (uncompressed store size), and make sure a backup exists — before deciding whether any LV needs to be reclaimed or created.

### 1.1 Confirm `osvg-nixroot` and `osvg-nix` are genuinely dead

Do not treat "suspected dead/leftover" as fact. Verify independently, in this order:

```bash
# 1. Is either LV currently mounted anywhere, by any means (including bind mounts)?
findmnt --all | grep -E 'nixroot|osvg-nix\b'
mount | grep -E 'nixroot|osvg-nix\b'

# 2. Does the running NixOS config reference either device anywhere?
grep -rn "nixroot\|osvg-nix\b\|osvg/nix\b" /etc/nixos 2>/dev/null
grep -rn "nixroot\|osvg[-/]nix\b" /home/ali/git/personal/nix-config \
  --include='*.nix' -- ':!*/hosts/*/hardware-configuration.nix' 2>/dev/null || true
grep -rn "nixroot\|osvg[-/]nix\b" /home/ali/git/personal/nix-config/flake-modules/hosts/ali-desktop/

# 3. LVM metadata: creation/modification time, tags, any active/open count
sudo lvs -o lv_name,lv_time,lv_attr,lv_tags,lv_active osvg
sudo dmsetup info -c | grep -E 'nixroot|osvg-nix\b'   # open count column

# 4. Mount read-only and inspect contents WITHOUT writing anything
sudo mkdir -p /mnt/check-nixroot /mnt/check-oldnix
sudo mount -o ro /dev/osvg/nixroot /mnt/check-nixroot     # ext4 per lsblk
sudo mount -t zfs -o ro osvg-nix /mnt/check-oldnix 2>&1 || \
  sudo zpool import  # zfs_member — may need `zpool import` first; read-only, do not `zpool import -f`

ls -la /mnt/check-nixroot | head -50
du -sh /mnt/check-nixroot 2>/dev/null
ls -la /mnt/check-oldnix | head -50 2>/dev/null

# 5. Unmount again — do not leave these mounted
sudo umount /mnt/check-nixroot
sudo umount /mnt/check-oldnix 2>/dev/null || sudo zpool export osvg-nix 2>/dev/null
```

**Interpretation:**
- If `osvg-nixroot` contains what looks like an old root filesystem (e.g. `/etc/nixos`, `/var`, a `.git` in `/etc/nixos` matching an old commit, `/home` skeletons) — treat as leftover from a prior installation, not in the current boot path.
- If `osvg-nix` (zfs_member) is an old `/nix` store from a prior ZFS-based layout — same conclusion.
- **STOP AND VERIFY checkpoint 1:** Do not proceed to reclaim (`lvremove`) either LV until you can positively state, in writing, what each one is and that nothing in the current flake or current boot entries references it. If genuinely uncertain after the above, keep both LVs as-is and size the new XFS volume from freed VG space alone (see §1.3) — reclaiming them is an optimization, not a requirement, for this migration.

### 1.2 Confirm backup currency

```bash
# Confirm whatever backup mechanism is in use for this host has a recent,
# complete run covering at least /persistence (and ideally the flake repo,
# which is already in git).
# Fill in the actual mechanism here before executing — e.g.:
#   restic snapshots --host ali-desktop | tail -5
#   borg list /path/to/repo
# and confirm the newest snapshot postdates the last meaningful config change.
```

`/nix/store` itself is reproducible from the flake (git-tracked) plus the binary cache (niks3) plus upstream caches — it is not something that strictly needs its own backup, but note the recommended new-volume copy itself acts as the "backup" during migration (§4) since the old btrfs subvolume is kept until verified (§6).

**STOP AND VERIFY checkpoint 2:** Confirm a current backup of `/persistence` exists and is restorable, before any LVM/filesystem mutation in later phases. This is independent of the `/nix` migration but is good hygiene before touching the same VG.

### 1.3 VG free space accounting

```bash
sudo vgs osvg -o vg_name,vg_size,vg_free
sudo pvs -o pv_name,vg_name,pv_size,pv_free
sudo lvs -o lv_name,lv_size,lv_attr,pool_lv,data_percent osvg
```

Sum: current `vg_free` + (if confirmed dead in §1.1) the size of `osvg-nixroot` (683.6G) + `osvg-nix` (195.3G) = space available for a new LV without shrinking anything live.

**Decision rule:** if `vg_free` alone (before reclaiming anything) already covers the sized target from §2 plus headroom, skip reclaiming the two suspect LVs entirely — fewer irreversible steps. Only reclaim them if genuinely needed for space, and only after §1.1's checkpoint is satisfied. **Never shrink `osvg-root`, `osvg-persistence`, or any live-mounted LV to make room** — shrinking a live, in-use filesystem (especially btrfs, whose shrink path is comparatively fragile and slow at this size) is strictly the higher-risk path compared to allocating from already-free or reclaimed-dead space, and this plan does not need it.

---

## 2. Sizing the new XFS volume

### 2.1 The one measurement this plan depends on

The compsize run mentioned in the task ("`compsize /nix/store` run is in progress separately") is **not yet complete as of writing this plan**. Do not guess its output. When it finishes, it reports something like:

```
Type       Perc     Disk Usage   Uncompressed Referenced
TOTAL       XX%      224G         UUUG         ...
```

Record:
- `compressed_bytes` = the "Disk Usage" total from compsize (should be close to the 224.67 GiB reported by `btrfs fi usage` / `df`, since that's the compressed on-disk size).
- `uncompressed_bytes` = the "Uncompressed" total from compsize. **This is the number XFS actually needs**, since XFS has no transparent compression — every byte compsize reports as "uncompressed" is a byte XFS must store as-is.
- `compression_ratio = uncompressed_bytes / compressed_bytes` (a placeholder for the worked example below — do not use this number for real until compsize finishes).

### 2.2 Formula

```
target_uncompressed_bytes = compsize_uncompressed_total   # direct from compsize output, NOT derived from GC log

target_volume_bytes = target_uncompressed_bytes * (1 + headroom_fraction)
```

**Worked example** (placeholder ratio only — replace `RATIO` and the resulting uncompressed figure with the real compsize numbers before sizing anything):

```
compressed_bytes      = 224.67 GiB                     (measured, from GC log / df)
RATIO                 = <placeholder, e.g. 1.6>         (compsize will give the real ratio — DO NOT use 1.6 for real)
uncompressed_bytes    ≈ 224.67 GiB * RATIO = 359.5 GiB   (illustration only)

headroom_fraction     = 0.35                             (see justification below)
target_volume_bytes   ≈ 359.5 GiB * 1.35 ≈ 485 GiB        (illustration only — recompute with real numbers)
```

### 2.3 Hardlinks: why the copy does not multiply by the GC log's savings figure

The GC log's "hard linking is currently saving 201.9 GiB" describes space saved **within the store as currently laid out**, because many identical files across different store paths are hardlinked to the same inode (nix's `auto-optimise-store`). This 201.9 GiB is **already netted out of** both the compressed 224.67 GiB figure and whatever uncompressed figure compsize reports — those are on-disk/logical sizes of the *deduplicated* set of unique inodes, not a sum of every store path's nominal size.

Two very different outcomes depending on how the copy is performed:
- **Hardlinks preserved** (e.g. `rsync -H`, `cp -a`, or a tar pipe that preserves link groups): the new filesystem's used space tracks the *same* uncompressed total that compsize reports — the copy is size-neutral with respect to hardlinking. This is what §4 recommends.
- **Hardlinks broken** (each hardlinked file duplicated as an independent copy — happens by default with plain `cp -r`, or `rsync` without `-H`, or many naive "just tar it" one-liners that don't track inode numbers across the whole set): the destination would balloon by roughly the 201.9 GiB the GC log reported as currently being saved — i.e. the copy could be ~1.9x the deduplicated size or worse depending on fan-out. This is a correctness bug, not just a space problem — always verify the destination's dedup with the checks in §4.4 before trusting it, since a silently-broken hardlink copy will "work" (files are readable) while consuming far more space and, if the sync runs again or verification hashes only, going undetected.

So: `target_uncompressed_bytes` in §2.2 is already the "post-hardlink-dedup" figure. Do not add the 201.9 GiB back in — that would double-count. It's referenced here only to explain *why* the copy command in §4 must preserve hardlinks and what breaks if it doesn't.

### 2.4 Headroom recommendation

Recommend **30-40% headroom** over the measured uncompressed total (used 35% in the worked example). Justification:

- XFS itself needs working room: new store paths continue to be added during the (likely live, see §4.3) sync window, GC doesn't run continuously, and `nix-collect-garbage` needs scratch space for temporary paths during builds/substitution.
- No compression cushion anymore — under btrfs, a burst of store growth is partially absorbed by zstd; on XFS every byte of growth is a byte of headroom consumed 1:1.
- XFS AG (allocation group) fragmentation over time on a highly-hardlinked, many-small-file workload benefits from not running near-full — free-space fragmentation degrades allocation performance well before the FS is nominally full.
- This is a one-off resize-avoidance decision: XFS can only grow online, never shrink, so oversizing costs disk space (cheap on a 3.6TB NVMe with reclaimed LVs) while undersizing means either an online grow (`xfs_growfs`, easy) or, if the VG itself is out of room, a much harder problem. Bias toward oversizing.

Do not finalize an LV size until `compsize` has actually completed and you have real `uncompressed_bytes`. Recompute §2.2's worked example with real numbers as the last step of this section before moving to §3.

**STOP AND VERIFY checkpoint 3:** confirm the real compsize output, the resulting `target_volume_bytes`, and that `vg_free` (post §1 decisions) covers it, before creating any LV.

---

## 3. Creating the XFS filesystem

### 3.1 Create the new LV (sudo, human-run)

```bash
# DESTRUCTIVE only in the sense of consuming VG free space — creates a new LV, touches nothing existing.
# Replace <SIZE> with the real target_volume_bytes from §2, rounded up to a clean unit (e.g. 500G).
sudo lvcreate -L <SIZE> -n nix-xfs osvg
```

If §1.1 confirmed `osvg-nixroot` and/or `osvg-nix` are dead and their space is needed:

```bash
# DESTRUCTIVE — irreversibly destroys osvg-nixroot's ext4 filesystem and all data on it.
# Only run after checkpoint 1 in §1.1 is satisfied.
sudo lvremove osvg/nixroot

# DESTRUCTIVE — irreversibly destroys osvg-nix's zfs_member and all data on it.
# Only run after checkpoint 1 in §1.1 is satisfied.
sudo lvremove osvg/nix
```

then `lvcreate` the new LV from the reclaimed space as above.

### 3.2 `mkfs.xfs` options and justification

```bash
# DESTRUCTIVE — initializes a filesystem on the new LV, destroying anything on it (should be empty, just-created).
sudo mkfs.xfs \
  -m reflink=1,crc=1 \
  -s size=4096 \
  -d agcount=32 \
  -L nix-store \
  /dev/osvg/nix-xfs
```

Per-flag justification:

- `reflink=1`: enables copy-on-write reflinks (XFS's equivalent of btrfs CoW, on a per-file basis via `cp --reflink` / `xfs_io reflink`). Nix itself doesn't use reflinks for store dedup (it uses hardlinks via `auto-optimise-store`), but leaving reflink support off is a one-way door — it cannot be enabled later without reformatting — and it's free to enable now, useful for ad-hoc operations (e.g. `cp --reflink=auto` when inspecting/duplicating store paths) and default-on in modern `mkfs.xfs` anyway. `crc=1` (metadata checksums, self-healing metadata) is required by `reflink=1` and is the modern XFS default since v5 format — keep it.
- `-s size=4096`: sector size for the filesystem, matching the NVMe's native/physical sector size (4K on Crucial T700) for optimal alignment and write performance. **Caveat:** this is the XFS sector size, independent of the LUKS sector size discussed in §8 — LUKS is currently 512-byte sectors underneath, and XFS's 4096 logical sector size still works fine sitting on a 512-byte-sector LUKS/LVM stack (it just means XFS's own alignment assumptions are slightly decoupled from the physical device until/unless §8 is done). Do not conflate the two.
- `-d agcount=32`: more allocation groups than the default (`mkfs.xfs` picks AG count based on device size, often smaller than this for a ~500G volume) improves concurrency for parallel small-file workloads — exactly what a Nix store is (multiple builds/substitutions writing many small store paths concurrently, e.g. during `nixos-rebuild switch` or parallel substituter fetches). More AGs = more independent free-space btrees = less lock contention. 32 is a reasonable value for a few-hundred-GB volume on fast NVMe with many small files; avoid going much higher (diminishing returns, more per-AG overhead) or lower (contention under `nix-daemon`'s parallel builds).
- `-L nix-store`: filesystem label, for a stable `LABEL=` mount reference and easy identification in `lsblk`/`blkid` output — matches the convention already used elsewhere in this repo (e.g. `/media/storage1` mounts by `LABEL=storage`).
- Deliberately **not** setting `-b size=` (block size) away from the 4096 default — 4K blocks are already optimal for a mixed small/large-file workload and match the sector size chosen above.

### 3.3 Mount options — and why they differ from `/media/steam-games-1`

The existing XFS entry for `/media/steam-games-1` in `flake-modules/hosts/ali-desktop/hardware-configuration.nix` is tuned for large sequential game-asset I/O:

```nix
options = [ "noatime" "largeio" "allocsize=64m" "logbsize=256k" "nofail" ];
```

`largeio` + `allocsize=64m` tell XFS to preallocate in large (64MB) chunks and report a large preferred I/O size to applications — great for writing multi-gigabyte game asset files sequentially, terrible for a Nix store: `allocsize=64m` would massively over-allocate speculative space for the store's huge count of tiny files (many store paths are a few KB to a few MB), wasting space and doing nothing for performance since store writes are not large sequential streams.

Recommended `/nix` mount options instead:

```nix
"/nix" = {
  device = "/dev/disk/by-label/nix-store";
  fsType = "xfs";
  options = [
    "noatime"        # No access-time writes on every read — same rationale as the current btrfs entry
    "nobarrier"      # OMIT — see note below; do not add this on an NVMe without a battery/UPS-backed write cache
    "logbsize=256k"  # Larger journal buffer for write throughput — same value as steam-games-1, still appropriate: a bigger log buffer helps any XFS workload with many metadata-heavy transactions, which a Nix store (many small file creates during builds/substitution) is a canonical example of
    "nofail"
  ];
  neededForBoot = true;   # unchanged — see §5.3
};
```

Do **not** carry over `largeio`/`allocsize=64m` — they are the two options tuned specifically for `/media/steam-games-1`'s workload and are actively wrong for a store. `logbsize=256k` is fine to keep since it benefits metadata-heavy workloads generally, not just large sequential ones. `nobarrier` / `nowsync`-style options that trade durability for a small write-latency win are explicitly **not** recommended here — a Nix store's integrity matters (broken store = broken system), and modern NVMe + `crc=1` metadata makes the barrier cost low anyway; leave XFS's default write-barrier/FUA behavior alone.

### 3.4 Alignment given LVM + LUKS

- `mkfs.xfs` auto-detects the LV's underlying stripe/alignment via `sysfs` topology when possible; on a straightforward LVM linear LV (no striping) over LUKS over a single NVMe partition, there is no meaningful RAID-stripe alignment concern here (unlike on an md-RAID or hardware RAID LV).
- The LUKS2 payload offset and the LVM PE (physical extent) boundary are already aligned to reasonably large boundaries by default in modern `cryptsetup`/`lvm2` — no manual `-d su=,sw=` stripe unit/width flags are needed for this single-device, non-striped setup. Do not add them speculatively.
- The `-s size=4096` sector size chosen in §3.2 is independent of alignment and is about matching the NVMe's physical sector size for write efficiency, not RAID geometry.

---

## 4. The data sync

### 4.1 Command (hardlink-preserving)

```bash
# Read from the live btrfs subvol, write to the new XFS LV. Non-destructive to the source.
sudo mkdir -p /mnt/nix-xfs-new
sudo mount /dev/osvg/nix-xfs /mnt/nix-xfs-new   # uses fstab-equivalent options once staged; for the initial sync, explicit options are fine too

sudo rsync -aHAX --numeric-ids --info=progress2 \
  /nix/store/ /mnt/nix-xfs-new/store/
# repeat, or fold in, the rest of /nix's top-level content — /nix/var (nix-daemon DB, profiles, gcroots) —
# which is comparatively small and equally must be hardlink/xattr preserving:
sudo rsync -aHAX --numeric-ids --info=progress2 \
  /nix/var/ /mnt/nix-xfs-new/var/
```

Flag meanings that matter here specifically: `-H` preserves hardlinks (the critical one, see §2.3) — rsync tracks inode numbers within the transfer and recreates the link groups on the destination; `-A` preserves ACLs and `-X` extended attributes (Nix uses xattrs for some CA-derived-path / build metadata in newer versions, and NixOS store paths may carry ACLs in some setups — preserve them rather than assuming they're unused); `--numeric-ids` avoids uid/gid translation via name lookup, which matters here since `nixbld` build users and the general uid range must map identically, not be re-resolved by name (especially relevant since this runs as root from a live/initrd environment where `/etc/passwd` may differ from the target system's).

### 4.2 Cost at scale: 254,915 paths, heavy hardlinking

`rsync -H` has known superlinear memory/time behavior building its hardlink-tracking table as the file count grows — at ~255K store paths (likely several times that many actual files once each path's contents are counted), expect meaningfully higher CPU and RAM use during the initial scan/table-build phase than a plain `-a` copy, and the -H matching pass itself does not parallelize. Concretely:

- Budget for this to take **hours**, not minutes, plus meaningfully more resident memory than the data volume alone would suggest (the hardlink inode table is proportional to file count, not data size).
- If rsync appears to hang or thrash rather than progress (check with `pv`/`--info=progress2` output stalling, or `top` showing rsync at high RSS with low I/O), the two concrete alternatives, in order of preference if rsync struggles:
  1. **`cp -a --reflink=never`** (GNU coreutils `cp -a` preserves hardlinks natively via its own inode-tracking, and is often faster than rsync's remote-protocol-oriented hardlink logic for a local-to-local copy). Simpler, fewer tunables, but less resumable/no progress reporting and no easy "second incremental pass" story.
  2. **`tar -C /nix -cf - store var | tar -C /mnt/nix-xfs-new -xf -`** (a straight tar pipe through two local tar invocations preserves hardlinks by default and streams without building a separate large in-memory table the way rsync's `-H` does) — good if both rsync and `cp -a` are too slow/memory-hungry, at the cost of no incremental re-run capability (a second pass means starting over, not just diffing).
  3. If even that struggles, running rsync in **passes by top-level directory prefix** (e.g. per-hash-prefix subsets of `/nix/store/*`) trades one giant hardlink table for several smaller ones — more bookkeeping, but bounds peak memory. Only worth doing if the single-pass approaches demonstrably fail on this hardware; do not pre-optimize into this without first trying options 1-2.

Whichever tool is used, the acceptance criterion is the same: verify in §4.4, not by assuming the tool worked.

### 4.3 Live sync + second pass — recommended, with reasoning

Recommend: **do the bulk sync live**, then a **final short second pass (`rsync -aHAX --delete` restricted, or just a second identical `rsync -aHAX` pass) immediately before the actual cutover**, rather than requiring the machine to be fully offline for the entire multi-hour bulk copy.

Reasoning:
- The Nix store is *close to* immutable during normal desktop use — files under existing store paths are never modified in place (Nix's core invariant), only *added* (new store paths from builds/GC-then-rebuild) or *removed* (GC). A live rsync pass safely captures the vast majority of content without any correctness risk, since it's not racing against in-place mutation.
- The realistic race is: a new store path gets created *after* the bulk pass started but *before* cutover (e.g. background auto-upgrades, a `nix-shell` pulling something new, systemd timers). A GC running mid-sync is the other edge case — deleting a path rsync already indexed but hasn't copied yet is harmless (rsync just skips or errors harmlessly on a vanished source file with `--ignore-missing-args` behavior for whole-file transfers; worth adding `--ignore-missing-args` to the rsync invocations above to be safe against exactly this).
- A short second pass (should complete in minutes, not hours, since rsync's `-H`/`-a` still has to rebuild its hardlink table but the actual data delta is tiny) run right before the offline cutover step in §5 catches that delta with minimal added downtime, versus taking the whole desktop offline for the multi-hour bulk phase.
- Explicitly **do not** attempt the sync from inside the running system for the *final* cutover copy — that's still done from the live/initrd environment per §5, where `/nix` is guaranteed quiescent (nothing can write to it) and the second pass is the last word before the fstab swap.

### 4.4 Verification before trusting the copy

Run all of these before proceeding to cutover, and do not skip the hardlink check — it's the one most likely to silently pass a naive "looks fine" glance:

```bash
# Path count parity (run against the *live* /nix/store just before final cutover, and against the new copy right after the final sync pass)
find /nix/store -maxdepth 1 -mindepth 1 | wc -l
find /mnt/nix-xfs-new/store -maxdepth 1 -mindepth 1 | wc -l
# Expect these to match (== 254,915-ish, modulo any store activity between measurements)

# Total logical size comparison — should be close to the uncompressed compsize figure from §2.1,
# NOT close to the compressed 224.67 GiB btrfs figure (XFS has no compression to shrink it).
du -sh --apparent-size /mnt/nix-xfs-new/store   # apparent-size counts each hardlinked file once per link, same convention as `du` on the btrfs side normally reports for a heavily-hardlinked tree — compare like-for-like

# Hardlink count spot-check: pick several known heavily-shared store paths (e.g. common glibc/openssl
# derivations) and confirm link counts match between old and new
stat -c '%n %h' /nix/store/<some-known-hash>-glibc-*/lib/libc.so.6
stat -c '%n %h' /mnt/nix-xfs-new/store/<same-hash>-glibc-*/lib/libc.so.6
# %h (link count) should match exactly

# Content integrity — nix-native verification (run once /nix has been cut over and mounted at the real
# path, from inside the running system or a chroot into the new store)
nix store verify --all              # checks store path hashes against the Nix database
nix-store --verify --check-contents # slower, full content re-hash — worth running once, budget significant time given 254,915 paths
```

**STOP AND VERIFY checkpoint 4:** path counts match, `du --apparent-size` is in the right ballpark (near the uncompressed compsize figure, with sensible variance for store activity during the sync window), spot-checked hardlink counts match, and `nix store verify` is clean, before touching any config or doing the offline cutover in §5.

---

## 5. Cutover — the hard part

### 5.1 Why `/nix` can't just be unmounted live

`/nix` has `neededForBoot = true` and the running system's `nix-daemon`, systemd, and essentially every running process has open file descriptors and mmaps into store paths. There is no clean way to `umount /nix` on a live, booted NixOS desktop session — even read-only remount attempts will fail with "device busy," and forcing it would crash the running system uncleanly (not a graceful shutdown, so risk of leaving the *old* btrfs subvol in an inconsistent state too, which is exactly what §6's rollback plan depends on staying intact).

### 5.2 Options considered, and the recommendation

1. **Boot from a live USB / the NixOS installer ISO.** Boot the machine off external media, unlock LUKS manually (`cryptsetup open`), activate the VG (`vgchange -ay`), mount both the old btrfs `/nix` subvol and the new XFS LV read-write, run the final rsync pass (§4.3), then edit and copy the flake's `hardware-configuration.nix` change onto the real root (which needs finding first, since impermanence means the *persisted* root of the actual config lives in the git checkout wherever that's stored — likely under `/persistence` or a home directory bind-mounted from it) — or, more simply, do the source-file edit from the *already-running* desktop beforehand (see §5.4 ordering) so the live-USB step is pure data-mover + fstab-swap, minimizing what has to happen in the unfamiliar live environment.
2. **From the initrd** (e.g. break into an interactive initrd shell via a kernel boot parameter, or an emergency/rescue target). Technically avoids needing separate media, but the initrd environment on this host is minimal (only the modules listed in `hardware-configuration.nix`'s `boot.initrd.availableKernelModules`/`kernelModules` — no guarantee `rsync`, `xfsprogs`, or enough working userspace tooling is present without deliberately adding it to `boot.initrd.systemd.extraBin` or similar first). More fragile, more prep work, no real advantage over option 1 for a desktop that already has read USB media available.
3. **A temporary NixOS generation that mounts `/nix` differently and reboots into it.** Doesn't actually solve the problem — you still can't rewrite the *contents* of `/nix` while a generation depending on it is the one currently running and being switched *from*; the new generation's activation itself needs the store. This only helps for changing *mount options* on an already-correct filesystem, not for a device swap requiring a bulk data copy that must happen with the target device unmounted from the running kernel's perspective. Not applicable here.

**Recommendation: option 1, live USB / NixOS installer ISO.** It's the most standard, most reversible-feeling, best-tooled path (a full NixOS installer environment has `rsync`, `xfsprogs`, `cryptsetup`, `lvm2`, `git` all present or trivially available via `nix shell`), and keeps the fragile initrd approach off the critical path. Do the config-file edit (§5.3) from the normal running desktop *before* rebooting to the live USB, so the live-USB session's job is narrowly: mount everything, run the final sync pass, verify, reboot. That minimizes time spent operating blind in an unfamiliar environment.

### 5.3 The config change

In `/home/ali/git/personal/nix-config/flake-modules/hosts/ali-desktop/hardware-configuration.nix`, replace the `"/nix"` block:

```nix
"/nix" = {
  device = "/dev/disk/by-label/nix-store";
  fsType = "xfs";
  options = [
    "noatime"
    "logbsize=256k"
    "nofail"
  ];
  neededForBoot = true;   # unchanged — still true, /nix is still required at boot regardless of fsType
};
```

Leave the `"/persistence"` block completely untouched — it keeps `device = "/dev/osvg/persistence"`, `fsType = "btrfs"`, `subvol=persistence`, and all its current options.

Note `boot.supportedFilesystems` already includes `"xfs"` (see line 9 of the current file, alongside `"btrfs"` and `"ext4"`) — no change needed there. Confirm `xfsprogs`-equivalent kernel/initrd module support is present; NixOS's `xfs` filesystem type support doesn't need an explicit `initrd.availableKernelModules` entry the way some exotic modules do (XFS is builtin/commonly available), but do a `just build` (see §5.4 step 2) to catch any missing-module eval/build error before relying on it at boot.

**Do this edit as a normal commit on the current git branch, following the `git` skill's atomic-commit convention** — this is exactly the kind of one-thing-per-commit change (device+fsType+options for one mount point) the repo's git strategy calls for. Do not bundle it with the LUKS sector-size work in §8, which is a separate, separately-decided change.

### 5.4 Order of operations (machine stays bootable at every step)

1. **[running desktop, no sudo needed]** Edit `hardware-configuration.nix` as in §5.3. Commit it. Do **not** `just switch` yet — the new device (`/dev/disk/by-label/nix-store`) doesn't have `/nix`'s contents yet, so switching now would try to activate against an empty/wrong filesystem.
2. **[running desktop, sudo for build only, no activation]** `just build` (builds the `ali-desktop` toplevel derivation against the *edited* hardware config, without switching) — this validates the Nix expression evaluates and builds cleanly with the new fstab entry before you're committed to anything. A build failure here is cheap to fix; a build failure discovered from the live USB is not.
3. **[running desktop, sudo]** Do the live bulk rsync pass from §4.1 against the currently-mounted `/nix` (source) into the new XFS LV mounted at a scratch path (destination) — this is the multi-hour pass, done while the desktop is otherwise usable.
4. **[running desktop, sudo]** Run verification (§4.4) against this first pass to catch gross problems early, before scheduling the offline window.
5. **[human decision]** Schedule the offline window; nothing after this point should be treated as "the machine is normally usable."
6. **[live USB / NixOS installer ISO, sudo throughout — this is a separate boot]** Boot the live USB. Unlock LUKS (`cryptsetup open /dev/nvme3n1p2 luksroot`), activate the VG (`vgchange -ay osvg`), mount the *old* btrfs `/nix` subvol read-only (`mount -o subvol=nix,ro /dev/osvg/persistence /mnt/old-nix`) — read-only here is a deliberate safety net, nothing should be writing to the old store at this point — and mount the new XFS LV read-write at a scratch path.
7. **[live USB, sudo]** Run the final short second rsync pass (§4.3) to catch anything created between step 3's snapshot and now. Because source is read-only, there's no risk of the destination racing a live writer.
8. **[live USB, sudo]** Re-run the §4.4 verification checks against the final copy.
9. **[live USB, sudo]** Add the `nix-store` XFS label if not already set at `mkfs` time (`xfs_admin -L nix-store /dev/osvg/nix-xfs`, only if needed — it was already labeled in §3.2's `mkfs.xfs -L nix-store`, so this step should be a no-op check, not a new mutation).
10. **[live USB, sudo]** Unmount both the old (ro) and new mounts cleanly. Reboot normally off the internal disk (remove/deprioritize the USB media) — the already-committed, already-built config from steps 1-2 takes over and mounts `/nix` from the new XFS label per the updated `hardware-configuration.nix`.
11. **[running desktop, post-reboot]** Confirm the system booted, confirm `findmnt /nix` shows the XFS device, run `nix store verify --all` again against the live mounted store, and exercise a real workflow (`just build` for some host, or a `nix-shell` pulling something not already resident) to confirm normal operation before declaring success.

### 5.5 Impermanence interaction

Impermanence's bind-mount machinery (persistence directories under `/persistence`) is entirely orthogonal to this change — none of the persisted paths listed in `flake-modules/hosts/ali-desktop/default.nix` (`persistence."/persistence".directories = [...]`) live under `/nix`, and `/persistence` itself is untouched. The only impermanence-relevant fact is that `/` is tmpfs and rebuilt fresh every boot from the store + activation scripts — which is exactly why `/nix` being correctly mounted with `neededForBoot = true` *before* the persistence/bind-mount machinery runs matters, and why that flag is being kept unchanged rather than altered.

### 5.6 Secure Boot / lanzaboote interaction

- `/boot` (vfat, `nvme3n1p1`) is untouched by this migration — lanzaboote's signed boot stub, kernel, and initrd images live there, not on `/nix` directly (though the *source* store paths for the kernel/initrd are on `/nix/store`, the *signed artifacts* lanzaboote installs to `/boot` are copies/derivatives, not the live store itself).
- No re-signing is needed purely because the underlying filesystem type of `/nix` changed — lanzaboote signs boot artifacts at `switch`/`boot` time based on the *current* generation's kernel/initrd contents, regardless of what filesystem those store paths happen to live on. The `just build` in step 2 and any subsequent normal `just switch`/`just boot` after the migration will go through the normal lanzaboote signing path unchanged.
- **However**: the *initrd itself* need not gain new LUKS/LVM/XFS mount logic beyond what's already implied by `fileSystems."/nix"` in Nix's own generated fstab/initrd mount units — NixOS derives the initrd's early-mount logic from `fileSystems` automatically, so switching `fsType` from `"btrfs"` to `"xfs"` is exactly the kind of config-driven change this mechanism is designed to handle, and step 2's `just build` is the checkpoint that catches any surprise here (e.g. if `boot.initrd.supportedFilesystems` needs an explicit XFS entry — check current NixOS behavior; `boot.supportedFilesystems` already lists `"xfs"`, and this typically covers initrd-stage inclusion via `boot.initrd.supportedFilesystems` inheriting the same list unless separately restricted — verify this evaluates without warnings during step 2 rather than assuming).
- Do not conflate this with the LUKS sector-size question in §8 — that one *does* touch the boot-critical LUKS header and is deliberately kept as a separate, optional, separately-approved decision.

---

## 6. Rollback

### 6.1 Keep the old copy until fully verified

**Do not delete the `nix` subvolume on `/dev/osvg/persistence` (i.e. do not `btrfs subvolume delete` it, and do not shrink/reuse that space) until:**
- The system has booted successfully from the new XFS `/nix` at least once (§5.4 step 11).
- `nix store verify --all` and (once, at least) `nix-store --verify --check-contents` are clean on the new store.
- A period of genuinely normal use has passed — recommend **at least 1-2 weeks** of normal desktop use (covering a few `just switch` cycles, some GC runs, some Steam/gaming sessions that stress the store's read path) before reclaiming the old subvolume's space. This is cheap insurance: the old subvolume just sits there consuming its share of `/dev/osvg/persistence`'s 293G until reclaimed; there is no ongoing cost to leaving it besides that disk space.

### 6.2 How to revert, if needed before the old copy is removed

1. Revert the `hardware-configuration.nix` commit from §5.3 (`git revert <sha>`, following the `git` skill's convention — a clean revert commit, not a force-push or history rewrite).
2. `just build` then `just switch` (or `just boot` + reboot, if the running system is already in a bad enough state that `switch`'s activation can't complete) — this points `/nix`'s fstab entry back at `subvol=nix` on `/dev/osvg/persistence`.
3. If the running system cannot even get far enough to run `just switch` (e.g. it won't boot at all post-cutover), boot the previous generation from the bootloader menu — since the *old* generation's boot entry still points at the pre-migration store layout implicitly via its already-built closure, and the underlying btrfs subvolume with the old store contents is still physically present and untouched — this is the safety net the "keep it until verified" rule in §6.1 exists for.

### 6.3 Point of no return

The point of no return is **deleting or overwriting the old `nix` btrfs subvolume's data** (via `btrfs subvolume delete`, or via later reusing that freed space for something else). Everything before that — including having already switched to and booted from the new XFS `/nix` — remains cleanly reversible via §6.2, because the old data is still sitting there unless it's explicitly deleted or written over. There is no automatic "streaming from the old subvol" happening once cutover completes — it's simply parked, inert, until a human decides to reclaim it.

---

## 7. Post-migration

### 7.1 bees

`beesdFilesystems.persistence` is configured with `spec = "LABEL=persistence"` — bees operates on the whole btrfs filesystem it's pointed at. After this migration, `/dev/osvg/persistence` still carries that label and still contains the (now-orphaned, pending §6's reclaim window) `nix` subvolume alongside the still-live `persistence` subvolume. **No config change is needed to keep bees running** — it will simply have less to dedup once the `nix` subvolume's data is eventually removed (per §6), since that was presumably a meaningful fraction of what bees was deduplicating (store paths tend to have high cross-path content overlap, which is exactly what bees targets). Post-reclaim, expect bees' `hashTableSizeMB = 2048` to be somewhat oversized for the smaller remaining `persistence`-only dataset — revisit whether to shrink it, but this is a minor, non-urgent tuning follow-up, not a required step.

XFS has no equivalent of bees / btrfs's block-level dedup — reflink-based manual dedup on XFS (e.g. via `duperemove`, which supports XFS reflinks) is the closest analog, but Nix's own hardlink-based `auto-optimise-store` (already enabled) achieves comparable space savings for the specific case of byte-identical whole files, which is nix store's actual dedup shape (whole immutable files, not partial-block overlap) — so bees' absence on the new `/nix` is expected and not a regression for this specific workload.

### 7.2 fstrim vs discard

The current btrfs `/nix` entry uses `discard=async` (inline async TRIM). Systemd's `services.fstrim.enable = true` (already set in `modules/base/default.nix`) provides a periodic, scheduled TRIM as an alternative/complement. Recommend: **do not add `discard`/`discard=async` to the new XFS `/nix` mount options** — rely on the existing periodic `fstrim.timer` instead. Reasoning: inline discard on every delete adds latency to metadata-heavy workloads (exactly what a Nix store's GC and build-path creation/removal churn is), and XFS + periodic fstrim is the more commonly recommended combination for NVMe versus per-op inline discard; `/media/steam-games-1`'s existing XFS entry already follows this pattern (`discard` is absent there too, relying on the same systemd `fstrim.timer`), so this keeps the two XFS mounts on this host consistent.

### 7.3 I/O scheduler

NVMe devices under Linux typically default to `none`/`noop` at the block layer for `blk-mq`, which is already correct for NVMe (no scheduler reordering needed — the drive's own internal parallelism handles it better than any Linux I/O scheduler). Confirm post-migration with:

```bash
cat /sys/block/nvme3n1/queue/scheduler
```

No change expected or needed as a result of the fsType swap — the scheduler operates below the filesystem layer.

### 7.4 What to re-measure, and the baseline to capture first

**Capture this baseline BEFORE starting the migration** (i.e. now, or before §3, while `/nix` is still on btrfs), so there's something to compare the post-migration numbers against:

- `nix-collect-garbage -d` wall-clock time (on a representative amount of collectible garbage — note GC time is highly dependent on how much there is to collect, so either capture this right after a fresh accumulation of some garbage, or treat this metric as directional only).
- A representative `just build`/`nixos-rebuild build` wall-clock time for a no-op or near-no-op rebuild (isolates store read/stat overhead from actual compilation).
- Parallel small-file throughput: a synthetic test is more reliable than opportunistic timing — e.g. `fio` with a job profile mimicking many small random reads (`--rw=randread --bs=4k --numjobs=8 --iodepth=32` style) pointed at a scratch subdirectory of `/nix/store`, or simply timing `find /nix/store -type f | xargs -P8 stat` as a cheaper proxy for stat-heavy concurrent access.
- `du`/`df` space used, for a sanity check that the uncompressed size lands where §2's formula predicted.

Re-run the identical set of measurements post-migration (after the boot in §5.4 step 11) and compare. Note the expected direction isn't obviously "faster" — btrfs with zstd:3 compression can sometimes *reduce* I/O for read-heavy workloads (less data physically read off the NVMe) at the cost of CPU for decompression, while XFS reads the full uncompressed bytes every time but with lower CPU overhead and (per this plan's whole premise) presumably was chosen for reasons like snapshot/subvolume complexity, corruption history, or a specific desire to avoid btrfs on the store — capture the numbers and let them speak for themselves rather than assuming a particular outcome.

---

## 8. OPTIONAL, SEPARATE DECISION: LUKS sector size 512 → 4096

**This section is explicitly out of scope for the filesystem migration above. Do not bundle it into the same maintenance window or the same git commit as §5.3's change. It is flagged here only because the volume may already be getting reformatted, which makes it tempting to combine — resist that.**

- `cryptsetup reencrypt --sector-size 4096 /dev/nvme3n1p2` (or the equivalent invocation for this LUKS2 device) exists to change the LUKS sector size in place, without needing to destroy and recreate the container.
- It rewrites the **entire ~3.6TB LUKS payload**, not just the region backing `/nix` — because LUKS sits *below* LVM in this stack (`nvme3n1p2` → LUKS2 → VG `osvg` → all LVs), this affects `osvg-root`, `osvg-swap`, `osvg-persistence`, `osvg-steam--games--1`, and every other LV in the VG simultaneously, whether or not they're involved in the `/nix` migration at all.
- Expect this to take a very long time (multi-TB in-place re-encryption/reformat, even if `reencrypt`'s resilience journal makes it interruption-safe) and to be a materially higher-risk operation than anything in §1-§7 above, purely because of blast radius — a problem here risks the *entire* VG, not just the `/nix` LV this plan is otherwise scoped to.
- Potential benefit (4K sector alignment matching the NVMe's native sector size end-to-end through LUKS, rather than just at the XFS layer per §3.2) is real but secondary — the XFS `-s size=4096` in §3.2 already gets most of the practical alignment benefit for the new `/nix` volume specifically, without touching LUKS at all.
- **Recommendation: treat this as a separate, later decision, requiring its own explicit go-ahead from the human operator (per the `infra` skill's rule — this is a live-infrastructure mutation with a large, all-LVs blast radius, and this agent must not do it unprompted or bundle it into implicit approval for the `/nix` migration above).** If pursued, do it as its own dated plan document, its own maintenance window, with its own backup-and-rollback story appropriate to a whole-VG operation (which is a materially different risk class than a single-LV filesystem swap).

---

## Open questions for the human operator (answer before executing any phase)

1. **compsize result** — not yet available at plan-writing time. §2's sizing cannot be finalized until this lands; do not size or create the LV from a guess.
2. **§1.1 verification of `osvg-nixroot` / `osvg-nix`** — needs to actually be run and its output reviewed; this plan cannot pre-confirm dead-volume status from measurements not yet taken.
3. **Backup mechanism/currency for `/persistence`** (§1.2) — this plan doesn't know what backup tooling is in use for this host; fill in the real commands and confirm a recent run exists.
4. **Live USB media** — confirm a bootable NixOS installer USB (or equivalent) is prepared and its NixOS version is compatible with unlocking this host's LUKS2/LVM/existing partition layout, before scheduling the offline window in §5.4.
5. **Maintenance window length** — the multi-hour live bulk-sync pass (§4.1/§4.2) can happen during normal use, but the live-USB offline window (§5.4 steps 6-11: second sync pass + verification + reboot) needs a dedicated block of time; size it generously given rsync's hardlink-table cost at this file count, and confirm with the operator when that window should be.
6. **§8 LUKS sector-size change** — explicitly deferred; needs its own yes/no decision from the operator, not assumed as part of this migration.

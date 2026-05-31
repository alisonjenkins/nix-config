# 02 — Content sync (ROMs / BIOS / firmware / keys)

How ROMs, BIOS, firmware and Switch keys get onto the deck **declaratively** without
bloating the nix store or the niks3 cache.

## Why not Nix fetchers

Pure `fetchurl`/`fetchzip` is the wrong tool for a personal dump library:

1. **Store + cache bloat (disqualifying).** `fetchurl` puts bytes in `/nix/store`; this
   host's `/nix` + `/home` share one XFS LV and **main pushes to the niks3 cache** — a
   multi-GB ROM library would balloon every cache push and re-store dumps already held in B2.
2. **Private-bucket auth.** Fixed-output derivations can't cleanly carry a B2 credential
   (it leaks into the derivation + breaks reproducibility). S3 presigned URLs expire (≤7d).
   Public objects defeat the point.

`requireFile` (never downloads; user supplies the hash out-of-band) remains the right
pattern for any *single* copyrighted file you'd rather pin in the store — but for a whole
library, sync-to-disk wins.

## Model: declarative manifest → exact on-disk state

The Nix config **enumerates exactly which files should exist**; an `rclone` sync makes the
target match it **exactly** — fetch what's listed, **prune anything not listed**. B2 is just
the byte store; the Nix list is the source of truth. Add a line → file appears; remove the
line + rebuild → file is deleted on the next sync.

This is declarative *management* (config version-controlled + reproducible) with on-disk
*data* (never the store). It is a stateful sync, not a pure build — the correct trade for
large private content.

### Option schema (sketch)

```nix
options.modules.emulation.content = {
  enable        = lib.mkEnableOption "B2 manifest-driven content sync";
  remote        = lib.mkOption { type = lib.types.str; default = "b2"; };       # rclone remote
  bucket        = lib.mkOption { type = lib.types.str; };
  keySopsSecret = lib.mkOption { type = lib.types.str; };                       # B2 keyID+appKey via sops
  schedule      = lib.mkOption { type = lib.types.str; default = "daily"; };    # systemd timer; also on login

  sets = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        bucketPrefix = lib.mkOption { type = lib.types.str; };                  # e.g. "roms"
        dest         = lib.mkOption { type = lib.types.str; };                  # HOME-relative, e.g. "~/Emulation/roms"
        perms        = lib.mkOption { type = lib.types.str; default = "0755"; };# "0700" for keys/firmware
        files        = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; }; # EXPLICIT allowlist
        symlinkInto  = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; }; # per-emulator targets
      };
    });
    default = {};
  };
};
```

### Example

```nix
modules.emulation.content = {
  enable = true; bucket = "ali-emulation"; keySopsSecret = "backblaze/emulation";
  sets = {
    roms = {
      bucketPrefix = "roms"; dest = "~/Emulation/roms";
      files = [ "snes/Chrono Trigger (USA).sfc" "n64/GoldenEye 007 (USA).z64" ];
    };
    bios = {
      bucketPrefix = "bios"; dest = "~/Emulation/bios";
      files = [ "scph5501.bin" "scph7001.bin" "dc_boot.bin" ];
    };
    switch-keys = {
      bucketPrefix = "switch/keys"; dest = "~/Emulation/bios/switch"; perms = "0700";
      files = [ "prod.keys" "title.keys" ];
      symlinkInto = [ "~/.local/share/citron/keys" "~/.config/Ryujinx/system" ];
    };
    switch-firmware = {
      bucketPrefix = "switch/firmware"; dest = "~/Emulation/bios/switch/firmware"; perms = "0700";
      files = [ /* the .nca set */ ];
      symlinkInto = [ "~/.local/share/citron/nand/system/Contents/registered" ];
    };
  };
};
```

## Enforcement: "exactly this, nothing else"

Per set, Nix renders a small **manifest** file (the `files` list — text, fine in the store;
the ROMs never enter it). The sync service then:

1. **Fetch only listed files:** `rclone copy b2:<bucket>/<prefix> <dest> --files-from <manifest>`
   (incremental — skips unchanged via size/checksum).
2. **Prune unlisted:** reconcile `<dest>` against the manifest — delete any file in `<dest>`
   not in `files`. Use `rclone sync --files-from … --delete-excluded` **or** an explicit
   prune pass (walk `<dest>` minus manifest) — prefer the explicit prune for predictability;
   verify the exact `rclone` flag semantics on the packaged version at implementation time.

Target dir = pure function of `files`. **Prune is scoped strictly to each set's `dest`**
(never touches saves/configs/other dirs) so it can't eat unrelated data.

Optional integrity: pin a per-file `sha256`/B2-SHA1 and run `rclone --checksum`.

## Mechanics

- **Creds (no secret in store):** `sops-nix` template renders the B2 creds to an env file
  owned by the user, mode `0400`:
  ```
  RCLONE_CONFIG_B2_TYPE=b2
  RCLONE_CONFIG_B2_ACCOUNT=<keyID>
  RCLONE_CONFIG_B2_KEY=<appKey>
  ```
  rclone reads `RCLONE_CONFIG_B2_*` from env → no `rclone.conf`, no creds in `/nix/store`.
  (Native B2 app key is simplest; the S3-compatible key also works via `type = s3`.)
- **Units:** one `emulation-sync-<set>` systemd **user** service (runs as the user so `~`
  resolves), `EnvironmentFile` = the sops env file, `ExecStart` = the fetch+prune.
  `schedule` timer + `wantedBy = graphical-session.target` (sync on login) + a `rom-sync`
  wrapper for on-demand. **Not** in the activation script (no network-blocking rebuilds) —
  so a removed item is pruned on the next sync run, not instantly at `just switch`
  (a best-effort activation trigger could be added if instant pruning is wanted).

## BIOS / firmware / keys placement

BIOS files live where each emulator looks. Centralize to `~/Emulation/bios` (EmuDeck
convention) and create `home.activation` symlinks into each emulator's expected dir:

| Content | Synced to | Symlinked into |
|---|---|---|
| PS1 `scph*.bin` etc. | `~/Emulation/bios` | RetroArch system dir (`~/.config/retroarch/system`; swanstation reads there) |
| PS2 `bios/*` | `~/Emulation/bios` | `~/.config/PCSX2/bios` |
| Saturn/Dreamcast (`dc_boot.bin`…) | `~/Emulation/bios` | RetroArch system dir |
| **Switch `prod.keys`/`title.keys`** | `~/Emulation/bios/switch` (0700) | citron/eden keys dir + `~/.config/Ryujinx/system` |
| **Switch firmware `.nca`** | `~/Emulation/bios/switch/firmware` (0700) | `…/nand/system/Contents/registered/`, Ryujinx `bis/...` |

Switch keys/firmware ride the same rclone sets (own dumps, private bucket, 0700 dest). One
B2 key gates everything; nothing copyrighted touches the store.

## Legal note (put in the module docs)

ROMs, BIOS, `prod.keys`, and firmware are the **user's legal responsibility — own-console /
own-disc dumps only.** The module ships no copyrighted bytes; it only stores a manifest of
filenames + B2 object paths.

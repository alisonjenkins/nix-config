# Kobo sync (`modules.koboSync`)

Pulls highlights, pen marks and stylus notebooks from a Kobo Libra Colour
into the Obsidian vault over Wi-Fi. No USB cable and no kobo.com account
are needed in normal use.

Code: `home/modules/kobo-sync`, `pkgs/kollate`. Enabled on `ali-desktop`.

## How it works

```
Kobo (Nickel + Cobalt's OpenSSH)          desktop (systemd user timer, 5 min)
/mnt/onboard/.kobo/KoboReader.sqlite  ──ssh+tar──►  ~/.local/state/kobo-sync/mirror
/mnt/onboard/.kobo/markups                          │
/mnt/onboard/My Notebooks/*.nebo                    ▼
                                        kollate-cli import / transcribe / export
                                                    │
                                                    ▼
                                    ~/obsidian/3. Resources/Kobo/
```

Each run of `kobo-sync`:

1. Lists the synced files on the Kobo (`stat` over SSH). A Kobo that is
   asleep or off Wi-Fi logs `event=kobo_unreachable` and exits 0. A changed
   host key (`event=host_key_changed`) or a rejected key
   (`event=auth_failed`) exits 1, so the unit fails at once.
2. Hashes that listing. Same as last run: log `event=unchanged`, stop.
3. Streams the files with `tar` over SSH into a staging dir. The firmware
   may not ship `rsync`, so `tar` is used on the Kobo side. A Kobo that
   sleeps mid-copy logs `event=kobo_lost_mid_copy`, exits 0 and retries
   next run.
4. Runs `PRAGMA integrity_check` on the copied database. A torn copy
   (Nickel writing mid-copy) fails the run; the next run retries.
5. `rsync --delete` from staging into the mirror.
6. `kollate-cli import <mirror>`, into `~/.local/share/kollate/library.db`.
7. Sets Kollate's `on_device_delete` setting to `trash`. A highlight
   deleted on the Kobo moves to Kollate's Trash, and Trash is never exported.
8. `kollate-cli transcribe` (handwriting to text, local model). A failure
   here only logs `event=transcribe_failed`; export still runs.
9. `kollate-cli export obsidian <exportFolder>`.

A second, daily timer (`kobo-sync-stale`) sends a desktop notification when
the last good contact is more than `staleAfterDays` (3) days old.

Tests: `home/modules/kobo-sync/tests` (pytest, fake `ssh` and
`kollate-cli`), run by the `kobo-sync-tests` prek hook.

Logs: `journalctl --user -u kobo-sync`. Force a full run:
`KOBO_SYNC_FORCE=1 kobo-sync`.

## One-time setup

1. **Kobo, over USB.** Install [Cobalt](https://github.com/BandarLabs/Cobalt).
   Its installer turns on the firmware's OpenSSH, authorises
   `~/.ssh/kobo_cobalt` for root and turns off password login.
2. **Network.** Give the Kobo a DHCP reservation and the DNS name `kobo`,
   or set `modules.koboSync.host` to its IP.
3. **Check SSH.** `ssh -i ~/.ssh/kobo_cobalt root@kobo true`.
4. **Handwriting model.** Add one with `kollate-cli models add <files>`
   (Qwen3-VL 2B, 2.7 GB, needs AVX2). Without a model, transcribe fails
   and everything else still syncs.
5. **Kobo setting (optional).** `kobo session --wifi-always-on on` keeps
   Wi-Fi up while the Kobo is awake.

## Options

| Option | Default |
|---|---|
| `host` | `kobo` |
| `sshKey` | `~/.ssh/kobo_cobalt` |
| `exportFolder` | `~/obsidian/3. Resources/Kobo` |
| `interval` | `5min` |
| `staleAfterDays` | `3` |
| `transcribe.enable` | `true` |
| `transcribe.cpu` | `false` (Vulkan) |

## Known limits

- **Only while awake.** Wi-Fi goes down on every suspend. Reading for a few
  minutes is enough for the next run to catch it.
- **Firmware updates.** May undo Cobalt's SSH changes on the root
  filesystem. The unit then fails with `auth_failed` (re-run Cobalt setup)
  or `host_key_changed` (check the Kobo, then delete its line in
  `~/.local/state/kobo-sync/known_hosts`).
- **Young dependencies.** Cobalt started 2026-07-29. Kollate has one
  developer (v0.7.1, 2026-10-05). Both are pinned by version.
- **CLI only.** `pkgs/kollate` builds `kollate-cli` without the GTK app.

## Not yet verified on a real Kobo

1. `kollate-cli import` accepts the mirror directory as a mount point
   (its code looks for `.kobo/KoboReader.sqlite` under the path).
2. The synced paths are all Kollate needs: compare `kollate-cli inspect`
   on the mirror with `inspect` on the USB mount.
3. `transcribe` covers notebook pages, not only margin markups.
4. Cobalt's SSH survives a reboot and stays key-only.
5. Writing `on_device_delete` straight into Kollate's `setting` table keeps
   working across Kollate upgrades.

## Rejected alternatives

- **A Cobalt app that pushes from the Kobo.** Cobalt apps cannot open
  sockets or read files outside their own folder, so they cannot read
  `KoboReader.sqlite`.
- **kobo.com notebook scraping.** Needs a browser session cookie and passes
  a bot check; fragile.
- **Plato.** Replaces Nickel while running.

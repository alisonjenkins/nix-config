# Pending / unfinished work

Moved out of CLAUDE.md so it stays out of every subagent's startup context.
Still git-tracked here (cross-machine).

## niks3 cache push on desktops/laptops

`modules/niks3-cache-push` + GHA parallel-push workflow implemented. `secrets/niks3-token.enc.yaml`
now exists (key `niks3_token`). Per-host status:

- **ali-desktop** — ✅ **enabled 2026-07-01** (`modules.niks3CachePush` + `sops.secrets.niks3-token` live).
  Verified pushing to `api.nixcache.org`. Two gotchas hit on the way, watch for them on the laptops:
  1. **Impermanence host key path.** These hosts hardcoded `sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`,
     but on impermanence the real key is at `/persistence/etc/ssh/keys/ssh_host_ed25519_key`
     (per `services.openssh.hostKeys`). Drop the override so sops-nix defaults off `openssh.hostKeys`.
     Symptom: sops-install-secrets finds no age key → `/run/secrets` never created → niks3-hook
     errors `open /run/secrets/niks3-token: no such file or directory`.
  2. **Stale `.sops.yaml` recipient.** `server_ali-desktop` in `.sops.yaml` was derived from an old key
     path and didn't match the live host key. Verify with
     `nix-shell -p ssh-to-age --run 'ssh-to-age -i <the openssh.hostKeys .pub>'`, update the anchor,
     then `sops updatekeys secrets/niks3-token.enc.yaml`. Same class of check needed per laptop.
  After switching, the socket-activated daemon may hold a stale pre-secret process — `systemctl restart niks3-auto-upload.service`.

- **ali-work-laptop** — server age key already a niks3-token recipient in `.sops.yaml`. Just uncomment the
  `modules.niks3CachePush` + `sops.secrets.niks3-token` block in `flake-modules/hosts/ali-work-laptop/default.nix`
  (put the secret inside the host's existing `sops.secrets` block, not a sibling `sops.secrets.x =`, else
  duplicate-attr eval error). First verify its `sshKeyPaths` per gotcha #1 above.

- **ali-framework-laptop** — **not yet a recipient.** Add its server age key to `.sops.yaml` (keys anchor +
  niks3-token creation rule), `sops updatekeys secrets/niks3-token.enc.yaml`, then uncomment the host block
  in `flake-modules/hosts/ali-framework-laptop/default.nix`. It also hardcodes
  `sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]` (gotcha #1) — fix that too.

Server-side niks3 push failures (504 during GC / 503 from B2) are tracked in the `niks3-cache` memory;
mitigations merged to `home-cluster` 2026-07-01.

## emulation module follow-ups

`modules/emulation` implemented + audited (6-dimension adversarial audit; do-now + robustness findings fixed) but **disabled by default** — no host sets `modules.emulation.enable`. Follow-ups, highest value first:

1. **Activate on `ali-steam-deck`** — flip `enable = true`; set up B2 sops secret group (`<keySopsSecret>/accountId` + `/applicationKey`) + point `content.sopsFile` at an encrypted file; pin the Sinden src hash; drop `citron` from the host's `users.users.ali.packages` (module owns it). Zero integration coverage until enabled — audit #15.
2. **PS3 (folder-based) end-to-end** — content sync expands + protects trailing-slash folder entries (no data-loss), but RetroFE lists by file scan not folders; a PS3 collection needs folder-entry support + an `rpcs3 --no-gui <EBOOT.BIN>` launcher. Folders are why `catalogue.ps3` has `extensions = [ ]`.
3. **MAME controls** (audit #16) — `controls-emudeck.nix` omits MAME: its `ctrlr/default.cfg` is clean but needs a `-ctrlr default` launch flag (wire into the RetroFE mame launcher) + the right nixpkgs ctrlr search path verified. Same for PCSX2/melonDS (input embedded in monolithic settings files → can't ship read-only without clobbering paths/window-state).
4. **RetroFE hardware validation** (audit #17) — items flagged UNVERIFIED-ON-HARDWARE in `frontend-retrofe.nix` + `design/05-frontend.md` (gamescope nesting/focus, standalone bin names/flags, bundled-layout name, per-game override case-sensitivity). Reconcile the two lists when validated.

`flake check` runs `emudeck-config-paths` (bitrot guard on pinned EmuDeck configs). PS1/PS3 disc ripping → `.#ripping` dev shell.

## Steam Remote Play streaming at the client's resolution

Working as of 2026-08-26: streaming `ali-desktop` → Steam Deck at a true 1280x800,
with the ultrawide DP-2 still connected and usable. Verified in
`/media/steam-games-1/Steam/logs/streaming_log.txt`:

```
SynchronizeClientState(): setting capture size 1280x800
CGameStreamVideoStageVAAPI: Reinitializing 1280x800 ...
>>> Capture resolution set to 1280x800
```

### How it actually works (took seven attempts to find)

- Steam sizes the encoder from **its own idea of the desktop**, never from the
  PipeWire stream the portal hands it. The capture side was always correct at
  1280x800.
- **That idea comes from SDL3, not from X.** Disassembling `steamui.so` settles it:
  the routine that logs `Desktop state changed` calls `SDL_GetDisplays(NULL)`, walks
  the NULL-terminated array calling `SDL_GetDisplayBounds` on each, unions them with
  `SDL_GetRectUnion` for the desktop, and keeps the first entry as primary. No Xlib
  in that path at all. Every RandR hook in the filter was aimed at the wrong layer;
  they are kept because other Steam code paths do use them, but they do not decide
  this number. Find the call site again with radare2:
  `aa; aae; axt <addr of the format string>` — plain `aaa` will not find it, the
  reference is PC-relative off `edi`.
- The count argument is **not** consulted — `push 0` immediately before the call.
  Anything filtering `SDL_GetDisplays` has to terminate the array, not just shorten
  the count.
- `steamui.so` (`/data/src/steamUI/gamestream/gamestreamsystemlinux.cpp`, emits
  `Desktop state changed`) **`dlopen`s `libXrandr.so.2` / `libX11.so.6` and resolves
  by `dlsym`**. A handle-scoped `dlsym` searches only that object, so plain
  `LD_PRELOAD` interposition never entered its lookup path. This is why six
  correct-looking interceptions changed nothing — the hooks fired, but from SDL
  and other PLT-bound callers, never from the gamestream code.
  `pkgs/steam-display-filter` now interposes `dlsym` itself.
- Steam's capture size is the **bounding box of every monitor except the primary**,
  so the streamed output must be *non*-primary. "Set the streaming display as
  primary" — the usual advice — is backwards and provably does not work here.
- Steam **discards outputs whose physical size is 0mm x 0mm**, which is what niri
  reports for virtual outputs. The shim fakes 338mm x 211mm to get the output
  considered at all.

### Backlog, highest value first

1. **Confirm the mid-session path. NOT YET VERIFIED.** Verified working 2026-08-26:
   a Steam that comes up with the filter already armed streams at a true 1280x800
   (`capture size 1280x800`, encoder 1280x800, no re-fit). What is still unproven is
   the Deck connecting to a Steam that has been running for a while, because every
   successful run so far had the watcher arm before Steam finished starting.

   Both fixes below target that case, and neither has been exercised by it:

   - `SDL_GetDisplays(NULL)` is now filtered (the array is terminated, not just the
     count) — this is what the deciding routine calls.
   - The watcher now turns the output **off before** withdrawing the target. The
     reverse order left the output present with the filter inert, and Steam
     recomputed in that window and cached the union of both monitors (6400x1440),
     then sized the next stream to it. That is why a mid-session connect stayed
     wrong even once the display filtering was correct.

   To test: with Steam running and nothing streaming, confirm the `steam` output is
   off and no target is published, then connect the Deck without restarting Steam
   and read `SynchronizeClientState(): setting capture size`.

   Ground truth for judging any fix: with DP-2 physically detached the capture size
   is correct with no filtering at all, because nothing is left to disagree.

   A useful trick for forcing Steam to recompute on demand, without a Deck:
   `niri msg create-virtual-output --name trigger --width 1920 --height 1080
   --refresh-rate 60` then remove it. Each create/remove makes Steam re-emit
   `Desktop state changed`, which turns a multi-minute round trip into seconds.
2. **Give niri virtual outputs a real physical size.** Fix in the fork
   (`/home/ali/git/niri`, branch `rebase-feat-virtual`) rather than faking it in the
   shim: derive mm from the mode at ~96dpi. Removes the shim's main reason to exist
   and is upstreamable.
3. **Physical disconnection always worked** because it changes the source of truth —
   no unfiltered API is left to disagree. Useful as the reference behaviour when
   judging whether a fix is real: if the filtered path does not match the
   DP-2-detached path, the filter still has a gap.

### Traps worth not re-learning

- `flog` once did `fopen`/`fclose` per line; at the SDL hooks' rate (~180 lines/s)
  that stalled Steam's main loop and failed the stream launch with
  `CSteamEngine::BMainLoop appears to have stalled > 15 seconds`. The log file is
  held open and repeats collapse. Diagnostics must not cost more than the fault.
- Interposing `dlsym` makes every hook's own `dlsym(RTLD_NEXT, ...)` resolve to
  *itself* — unbounded recursion, segfault whose faulting address equals the stack
  pointer. Internal lookups go through `next_sym()`, and `RTLD_NEXT`/`RTLD_DEFAULT`
  are never redirected.
- `RTLD_NEXT` only searches the global scope, and Steam `dlopen`s libX11 without
  `RTLD_GLOBAL`, so the real function must be found by name via
  `dlopen(..., RTLD_NOLOAD)` as a fallback. Without it the hooks silently report a
  zero width.
- `pkgs/steam-display-filter/dlopen_probe.c` reproduces Steam's `dlopen`+`dlsym`
  pattern in ~30 lines, so shim changes can be checked in seconds instead of by
  launching Steam and reconnecting a Deck. Run it under two names to cover both
  halves of the process gate; see the comment at the top of the file.
- Testing this needs **two outputs present**. With DP-2 detached there is nothing to
  filter and every probe trivially "passes" — a synthetic second output
  (`niri msg create-virtual-output --name gatetest --width 5120 --height 1440
  --refresh-rate 60`) stands in, and **must be removed afterwards**
  (`niri msg remove-virtual-output gatetest`). A stray virtual output left behind
  once became the focused output when DP-2 disconnected and read as a hung machine.

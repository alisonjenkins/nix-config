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

## positional-audio-bench follow-ups

**Usage + how to swap HRTF datasets: `docs/positional-audio-bench.md`.**
`pkgs/positional-audio-bench` implemented (2026-09-14): objective localization
benchmark for `modules.desktop.pipewire.binauralSurround` — ITD/ILD/front-back
scoring via GCC-PHAT + a Woodworth (elevation-corrected) ground truth, `tune`/
`regress`/`sweep-datasets`/`live-verify` CLI, wired into `nix flake check`
(`flake-modules/positional-audio-bench.nix`, MIT KEMAR + pure defaults only).
Baseline on the defaults: mean ITD error 3.0 deg, max 15.0 deg @ 105 az/0 el,
front-back discrimination 8.6 dB.

1. ~~Alternate HRTF datasets not yet fetched.~~ **Resolved 2026-09-14**:
   checked licenses for CIPIC/SADIE II/ARI/HUTUBS — only CIPIC (UC Davis) has
   an unambiguous redistribution grant. Packaged subjects 021 (small pinna)
   and 165 (large pinna) in `pkgs/positional-audio-bench/datasets.nix` and
   ran `sweep-datasets` against ali-desktop's real config: **KEMAR (default)
   beat both CIPIC variants on every metric**, including front-back
   discrimination (8.6 dB vs 6.2/7.2 dB) — matching pinna size alone doesn't
   help, and CIPIC's older measurement setup may just be lower fidelity.
   Swapping among generic dummy-head datasets is a dead end; the next lever
   is a personalized/individually-measured HRTF, not another mannequin.
   See `docs/positional-audio-bench.md` for the full table.
2. ~~RBJ biquad math unverified against PipeWire's actual SPA filter-chain
   implementation.~~ **Resolved 2026-09-14**: diffed against
   `spa/plugins/audioconvert/biquad.c` in the pipewire source. SPA's
   `bq_lowshelf`/`bq_highshelf` use `alpha = sin(w0)/(2*Q)`, same as the
   peaking filter — not the RBJ cookbook's separate shelf-slope (`S`)
   formula. `biquad.py` already matched this exactly, so no change was
   needed; a PR review had flagged the shelf formula as suspicious purely
   from the textbook cookbook, without checking the real source, which is
   exactly the gap this item was tracking.
3. **`live-verify` (drives real `pw-cat`/`pw-record`) is untested against
   real hardware** — written against the expected `pw-cat --target`/
   `--channels` flag behavior, never run against an actual PipeWire session.
   First real run on `ali-desktop` (`just audio-bench-live ali-desktop
   <monitor-port>`) should be treated as its actual first test. Same is true
   of `perceptual-test`'s `pw-cat --playback` calls.
4. **Front-back score interpretation caveat, upgraded 2026-09-14 after an
   independent sanity-check review (Fable) caught this properly:** the
   score is *spectral cue strength*, not *fit to a specific listener*.
   Scoring two generic (non-personalized) datasets against each other, as
   the CIPIC comparison above does, is fair. Scoring a **personalized**
   candidate (e.g. from `match-subject`) this way is not — a well-matched
   personal HRTF can legitimately score *lower* while localizing better,
   because the listener's brain is listening for cues shaped like their own
   pinna, not for maximally distinct cues in the abstract. `sweep-datasets`
   on a personalization candidate only catches broken/corrupted data now;
   `perceptual-test` (added 2026-09-14: a blind forced-choice compass-
   direction test through headphones, reports front-back confusion rate) is
   the only part of the tool that can actually validate personalization.
5. **Personalization via nearest-neighbour anthropometric matching, added
   2026-09-14**: `positional-audio-bench match-subject` matches a
   listener's own pinna measurements (fossa height, pinna height, pinna
   width by default — the three HUTUBS parameters large enough to
   self-measure without the error swamping the signal) against 96 real
   HUTUBS subjects (CC BY 4.0, vendored in
   `pkgs/positional-audio-bench/src/positional_audio_bench/data/`), zero
   cost, an afternoon of measurement. Chosen over a DIY acoustic
   measurement rig (~$150-400, a weekend, open tools exist: RWTH Aachen's
   Open-HRTF, York's XR-HRTFs) or Genelec Aural ID (~€600, photo-based,
   confirmed to export a portable SOFA file — most commercial options
   don't) as the cheapest first experiment; try those if this doesn't pan
   out. Not yet run against a real person's measurements — the matcher and
   its 54-test suite are verified, but no one has gone through
   measure → match → fetch → `perceptual-test` end to end yet.

## emulation module follow-ups

`modules/emulation` implemented + audited (6-dimension adversarial audit; do-now + robustness findings fixed) but **disabled by default** — no host sets `modules.emulation.enable`. Follow-ups, highest value first:

1. **Activate on `ali-steam-deck`** — flip `enable = true`; set up B2 sops secret group (`<keySopsSecret>/accountId` + `/applicationKey`) + point `content.sopsFile` at an encrypted file; pin the Sinden src hash; drop `citron` from the host's `users.users.ali.packages` (module owns it). Zero integration coverage until enabled — audit #15.
2. **PS3 (folder-based) end-to-end** — content sync expands + protects trailing-slash folder entries (no data-loss), but RetroFE lists by file scan not folders; a PS3 collection needs folder-entry support + an `rpcs3 --no-gui <EBOOT.BIN>` launcher. Folders are why `catalogue.ps3` has `extensions = [ ]`.
3. **MAME controls** (audit #16) — `controls-emudeck.nix` omits MAME: its `ctrlr/default.cfg` is clean but needs a `-ctrlr default` launch flag (wire into the RetroFE mame launcher) + the right nixpkgs ctrlr search path verified. Same for PCSX2/melonDS (input embedded in monolithic settings files → can't ship read-only without clobbering paths/window-state).
4. **RetroFE hardware validation** (audit #17) — items flagged UNVERIFIED-ON-HARDWARE in `frontend-retrofe.nix` + `design/05-frontend.md` (gamescope nesting/focus, standalone bin names/flags, bundled-layout name, per-game override case-sensitivity). Reconcile the two lists when validated.

`flake check` runs `emudeck-config-paths` (bitrot guard on pinned EmuDeck configs). PS1/PS3 disc ripping → `.#ripping` dev shell.

## Steam Remote Play streaming at the client's resolution

**How the components fit together: `docs/steam-remote-play-streaming.md`.** This
section is the archaeology — what was tried, why it failed, and what must not be
re-learned. Read the doc first if you are trying to understand the system rather
than its history.

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

### Game-mode follow-ups (from the 2026-09-24 live test), highest value first

Game-mode streaming works end to end (docs/adr/0007): the shim launches the
game without gamescope, Steam captures `Game Vulkan`, and camera look turns
freely. These are what the live test surfaced.

1. ~~**Wrong learned client size.**~~ Done 2026-09-24 (docs/adr/0012).
   Confirmed live: `set steam to 1728x1080@60`, then
   `Capture method set to Game Vulkan NV12`, `Capture resolution set to 1728x1080`.
2. **Games render at their own configured resolution.** Without gamescope
   nothing forces the render size to match the stream (steam-command-runner
   ADR 0006 only applies under gamescope). HD2 was set to 1440x900 by hand as
   a workaround. Options: borderless-fullscreen games follow the output size,
   so sizing the output right (item 1) may be enough for them; for exclusive
   fullscreen, investigate Wine/Proton display-mode overrides. Needs a survey
   of a few games before choosing.
3. ~~**Reconnect to a running game streams the Friends List.**~~ Fixed
   2026-09-24, not yet live-tested: a stream start stages the last game again
   if its pid is still alive. Gap: a stream-mode restart in between forgets
   the game, so a reconnect after a `just switch` mid-game is not covered.
4. ~~**MangoHud missing from the stream.**~~ Done 2026-09-24:
   `custom.mangohud.firstVulkanLayer` (docs/adr/0011). Confirmed on the Mac
   client.
5. ~~**HD2 left at half width.**~~ Root-caused 2026-09-24, fixed in 5a148cae,
   not yet live-tested. stream-mode took `>>> Stopped desktop stream` as the
   end of the stream, but Steam logs it on every swap into game capture, so
   two minutes into each game-mode stream it un-fullscreened the game. Seen
   live at 09:20 as a stretched picture.
6. ~~**The shim's decision line is invisible by default.**~~ Done 2026-09-24:
   every launch writes a timestamped decision line to
   `~/.steam-command-runner-shim.log` (runner `bc720b0`), docs corrected.
7. ~~**No outputs at all when DP-2 is off.**~~ Done 2026-09-24
   (docs/adr/0013): the output stays on when it is the only one.
8. ~~**lsfg-vk layer fails to load.**~~ Not a fault, checked 2026-09-24. The
   `Failed to find 'vkGetInstanceProcAddr'` line appears only for zenity
   during SteamVR startup (`vrstartup-linux.txt`, 2026-09-20), not every app;
   the host loader loads the layer cleanly. Frame generation is off because
   the only profile (HD2 2x) has `active_in = []`, which reads as deliberate.
   Probably lsfg-vk declining unprofiled processes; not confirmed in its
   source.
9. **Steam's desktop capture dies when the output goes off under it.** Steam
   keeps a PipeWire capture of the output open after a stream stops. When
   stream-mode turned the output off (08:20:41 on 2026-09-24) it logged
   `PipeWire stream state error: no more input formats`, and every later
   stream was `Desktop Black Frame` until Steam restarted. ADR 0013 keeps the
   output on while the monitor is off, but with DP-2 on the output still goes
   off. Test whether the capture recovers when the output comes back; if
   not, keep it on until Steam releases the capture. Seen again 2026-09-24
   09:01, when a niri config reload turned the output off (now reasserted on
   `ConfigLoaded`, 484a897e). Confirmed it does not recover on its own: the
   desktop capture stayed `Black Frame` while game capture worked.
11. **X sees virtual output mode changes one change late.** Measured
   2026-09-24: after `niri msg output steam mode 1726x1080@60` then
   `1728x1080@60`, `xrandr` on `:0` reported 1728 then 1726. HD2 read the
   stale 1280x800 and sized its borderless window to it. stream-mode works
   around it by stepping through refresh+1 (4a1dea45). Suspected
   cause, not confirmed: `resize_virtual_outputs` in
   `patches/niri-virtual-outputs.patch` calls `change_current_state`, which
   sends `wl_output.done`, before `output_resized` updates the logical size,
   so xwayland-satellite applies the old size on each `done`. Fix it in the
   patch and drop the workaround.
10. **Live-confirmed 2026-09-24 09:17** (for the record, not work): after a
   restart mid-connection stream-mode adopted the Mac, the shim launched HD2
   directly, the output was 1728x1080@60, and once HD2 had focus Steam
   captured `Game Vulkan NV12`. The focus fix (841f94bd) and the reconnect
   re-staging (item 3) are not yet live-tested.

### Traps worth not re-learning

- `flog` once did `fopen`/`fclose` per line; at the SDL hooks' rate (~180 lines/s)
  that stalled Steam's main loop and failed the stream launch with
  `CSteamEngine::BMainLoop appears to have stalled > 15 seconds`. The log file is
  held open and repeats collapse. Diagnostics must not cost more than the fault.
- **Verify through the path Steam uses, or the result means nothing.** `steamui.so`
  has `DT_NEEDED libSDL3.so.0`, so its calls go through the PLT and `LD_PRELOAD`
  interposes them. A test that `dlopen`s SDL and resolves with a handle-scoped
  `dlsym` bypasses the preload and reports "unfiltered" however well the filter
  works. Six changes were confirmed working through paths Steam does not use, and
  changed nothing; the first version of the probe repeated the same mistake.
  `xdpyinfo` was another: it exercises Xinerama, which Steam never calls.
- `pkgs/steam-display-filter/sdl_probe.c` does it correctly — link it against SDL3
  and run it under two names to cover both halves of the process gate. Seconds,
  rather than launching Steam and reconnecting a Deck.
- If interposing `dlsym` ever looks necessary again: a hook's own
  `dlsym(RTLD_NEXT, ...)` then resolves to *itself*, which is unbounded recursion
  and a segfault whose faulting address equals the stack pointer. It is not needed
  for SDL and the current filter does not do it.
- Testing this needs **two outputs present**. With DP-2 detached there is nothing to
  filter and every probe trivially "passes" — a synthetic second output
  (`niri msg create-virtual-output --name gatetest --width 5120 --height 1440
  --refresh-rate 60`) stands in, and **must be removed afterwards**
  (`niri msg remove-virtual-output gatetest`). A stray virtual output left behind
  once became the focused output when DP-2 disconnected and read as a hung machine.

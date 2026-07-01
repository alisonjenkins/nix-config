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

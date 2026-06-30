# Pending / unfinished work

Moved out of CLAUDE.md so it stays out of every subagent's startup context.
Still git-tracked here (cross-machine).

## niks3 cache push on desktops/laptops

`modules/niks3-cache-push` + GHA parallel-push workflow implemented but **not enabled**. To finish:

1. Create `secrets/niks3-token.enc.yaml` via `sops secrets/niks3-token.enc.yaml`, key `niks3_token`
2. Add ali-framework-laptop server age key to `.sops.yaml` (keys section + niks3-token creation rule)
3. Uncomment `modules.niks3CachePush` + `sops.secrets.niks3-token` in:
   - `flake-modules/hosts/ali-desktop/default.nix`
   - `flake-modules/hosts/ali-framework-laptop/default.nix`
   - `flake-modules/hosts/ali-work-laptop/default.nix`

## emulation module follow-ups

`modules/emulation` implemented + audited (6-dimension adversarial audit; do-now + robustness findings fixed) but **disabled by default** — no host sets `modules.emulation.enable`. Follow-ups, highest value first:

1. **Activate on `ali-steam-deck`** — flip `enable = true`; set up B2 sops secret group (`<keySopsSecret>/accountId` + `/applicationKey`) + point `content.sopsFile` at an encrypted file; pin the Sinden src hash; drop `citron` from the host's `users.users.ali.packages` (module owns it). Zero integration coverage until enabled — audit #15.
2. **PS3 (folder-based) end-to-end** — content sync expands + protects trailing-slash folder entries (no data-loss), but RetroFE lists by file scan not folders; a PS3 collection needs folder-entry support + an `rpcs3 --no-gui <EBOOT.BIN>` launcher. Folders are why `catalogue.ps3` has `extensions = [ ]`.
3. **MAME controls** (audit #16) — `controls-emudeck.nix` omits MAME: its `ctrlr/default.cfg` is clean but needs a `-ctrlr default` launch flag (wire into the RetroFE mame launcher) + the right nixpkgs ctrlr search path verified. Same for PCSX2/melonDS (input embedded in monolithic settings files → can't ship read-only without clobbering paths/window-state).
4. **RetroFE hardware validation** (audit #17) — items flagged UNVERIFIED-ON-HARDWARE in `frontend-retrofe.nix` + `design/05-frontend.md` (gamescope nesting/focus, standalone bin names/flags, bundled-layout name, per-game override case-sensitivity). Reconcile the two lists when validated.

`flake check` runs `emudeck-config-paths` (bitrot guard on pinned EmuDeck configs). PS1/PS3 disc ripping → `.#ripping` dev shell.

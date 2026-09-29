# Quickstart: validating the Virtual Output Overview Column

## Automated (niri fork)

```bash
cd /home/ali/git/niri
nix develop -c cargo test --workspace            # everything, incl. layout proptests
nix develop -c cargo test --lib tests::projection # band, tiles, input, events (headless)
nix develop -c cargo test -p niri-ipc             # event-stream state parts
nix develop -c cargo clippy --workspace --all-targets -- -D warnings
nix develop -c cargo fmt --check
```

Expected: everything passes. The tests cover:

| Scenario | Spec |
|---|---|
| With no virtual output on, overview geometry equals upstream's (inset 0, culling on) | FR-003, SC-004 |
| With the band, DP-2's strip is centred in the remaining width; `workspace_under` never reaches the band | FR-001/002 |
| A DP-2 window scrolled towards the band is hit outside the band; a click in the band never reaches DP-2 | US1-2/3, SC-001 |
| Band width follows overview progress | FR-004 |
| Groups in config order; every workspace plus the empty last one is a tile; 1, 3 and 12 outputs give equal tile sizes | FR-005/006, SC-002 |
| Scroll clamps at both ends, centres short content, resets to the first output's active workspace on open | FR-007/008 |
| Wheel over the band scrolls only the column; wheel over DP-2 is unchanged | FR-019 |
| Click a window in a tile: view mode on its output, that workspace active, window focused, Esc returns | FR-013 |
| Click empty tile space: same without focusing; click a label, gap or band background: nothing | FR-014/015 |
| Drag DP-2 → tile, tile → DP-2, tile → tile across outputs; drop on the empty last tile creates a workspace | FR-016/017 |
| Drag near the band's bottom edge scrolls the column | FR-018 |
| Turning a source off during a drag over its tile: drag continues, no target, no crash | US3-6, FR-028 |
| Turning a source off with the column scrolled to it: group gone, scroll clamped | Edge case |
| Locked session: no band, no tiles reachable | FR-022 |
| Rendering: band above DP-2's workspaces; tiles cropped; offscreen tiles produce no elements (`egl_*`) | FR-009/011 |
| `ViewOutputChanged` once per start/stop cause, correct names; none when nothing changes | FR-023, SC-005 |
| `OutputsChanged` on connect, disconnect, on, off; not on a mode change alone | FR-024 |
| New subscriber's initial events include both | FR-025 |
| Existing view-mode, lock, hot-corner and cursor-teleport tests stay green | FR-021 |

## Build and ship (nix-config)

```bash
# Push the fork first: the niri-virtual input follows alisonjenkins/niri rebase-feat-virtual.
cd ~/git/personal/nix-config
nix flake update niri-virtual
nix build .#nixosConfigurations.ali-desktop.config.programs.niri.package
just switch   # then log out and back in: the compositor is replaced
```

## Manual (ali-desktop)

1. `niri msg output steam on`, plus two throwaway outputs:
   `niri msg create-virtual-output --name vtest1` and `--name vtest2`.
2. In another terminal: `niri msg event-stream`. Expect `Outputs changed: …` after each step 1
   command, and one `View output: none` and one `Outputs changed` line at the start.
3. Put several windows on a DP-2 workspace so it scrolls past the right edge. Press Mod+O.
   A band slides in on DP-2's right with `steam`, `vtest1`, `vtest2`, each followed by its
   workspaces at one size. DP-2's workspaces sit left of it.
4. Click a DP-2 window right next to the band: that window activates. Reopen; click band
   background and a label: nothing happens, the overview stays open.
5. Scroll the wheel over the band: only the column moves, stopping at both ends. Scroll over
   DP-2: DP-2's workspaces behave as usual.
6. Drag a DP-2 window onto a `vtest2` workspace; drag it onto `steam`'s empty last tile (a new
   `steam` workspace appears); drag it back to DP-2.
7. Click a window in a `steam` tile: DP-2 shows `steam` with "Viewing: steam — Esc to return",
   that window focused. The event stream prints `View output: steam on DP-2`. Press Esc:
   DP-2 returns and the stream prints `View output: none`.
8. `niri msg remove-virtual-output vtest1` with the overview open: its group disappears.
9. During a live Remote Play stream from ali-mba, repeat steps 3 to 7. The stream never
   blacks out or freezes (SC-006).
10. Clean up: `niri msg remove-virtual-output vtest2`, `niri msg output steam off`.

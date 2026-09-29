# Quickstart: validating Virtual Output Projection

## Automated (niri fork)

```bash
cd /home/ali/git/niri
nix develop -c cargo test --lib projection        # Projection + overview_columns unit tests
nix develop -c cargo test --lib tests::projection # headless fixture tests (US1-US3 + edges)
nix develop -c cargo test --lib                   # full suite incl. layout proptests, unchanged
nix develop -c cargo clippy --lib --tests -- -D warnings
nix develop -c cargo fmt --check
```

Expected: everything passes. The fixture tests cover:

| Scenario | Spec |
|---|---|
| Overview: `contents_under` inside the `steam` column returns its window | US1-1, FR-001/002 |
| Drag a `steam` window to a viewer workspace and the reverse | US1-2/3, FR-003 |
| Drop into a gap between workspaces creates a workspace on that column's output | US1-4 |
| Turning `steam` off or on during the overview removes or adds its column | US1-6, FR-005 |
| `view-output steam`, then a click at the viewer centre focuses the `steam` window | US2-1/2, FR-010/011 |
| A click in a letterbox bar hits nothing | US2-3 |
| Turning `steam` off during view mode ends view mode and makes the viewer active | FR-015 |
| Removing the viewer ends view mode, and `steam` is unchanged | Edge case |
| Rendering `steam` contains no projected elements | FR-018 |
| `view-output DP-1`, `view-output nope` and `view-output` on an output that is off return the typed errors | FR-019/020 |
| Guard: `global_space.output_under` is used only in the allowed places | R1 |

## Build and ship (nix-config)

```bash
# Base = the niri rev in nix-config's flake.lock (02fdd8e at the time of writing);
# the fork's history must contain it.
cd /home/ali/git/niri && git -c diff.external= diff --no-ext-diff --binary \
  "$(jq -r .nodes.niri.locked.rev <nix-config>/flake.lock)" HEAD \
  > <nix-config>/patches/niri-virtual-outputs.patch
cd <nix-config>
nix build .#nixosConfigurations.ali-desktop.config.programs.niri.package
just switch   # then log out and back in: the compositor is replaced
```

## Manual (ali-desktop)

1. `niri msg output steam on`.
2. Open something on `steam`, e.g. `niri msg action spawn -- foot` with focus on `steam`,
   or move a window there with `move-window-to-monitor`.
3. Press super+o. A `steam` column appears to the right of DP-2's workspaces and slides in
   with the zoom.
4. Drag the window from the `steam` column onto a DP-2 workspace. It lands there. Drag it
   back.
5. Drag a window into the gap between two `steam` workspaces. A new `steam` workspace
   appears.
6. Click a `steam` workspace. The overview closes and DP-2 shows `steam` letterboxed with
   "Viewing: steam" for about 2 s. Click into the window and type.
7. `niri msg view-output`. DP-2 returns to normal.
8. Error paths:
   - `niri msg view-output DP-2` gives "not a virtual output".
   - `niri msg view-output steam` while it is off gives "is off".
9. During a live Remote Play stream from ali-mba, repeat steps 3 to 7 ten times. The stream
   never blacks out or freezes (SC-005).
10. `niri msg output steam off` while viewing. DP-2 returns to normal with a notice (SC-006).

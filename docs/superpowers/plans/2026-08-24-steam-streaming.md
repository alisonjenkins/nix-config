# Steam Remote Play Host Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Steam Remote Play a reliable, tuned host path on `ali-desktop` for the Steam Deck, and leave the machine ready for a Steam Frame, without regressing Sunshine or the Quest/WiVRn path.

**Architecture:** Remove untracked configuration drift first so that behavioural probes measure a known tree. Then apply Wayland capture fixes one at a time, re-probing after each. Discovery hardening, the headless-gamescope fallback and the capture-geometry fix stay conditional on probe results rather than being applied up front. Finally, replace the build-time VR runtime choice with a runtime switcher so SteamVR and WiVRn can coexist.

**Tech Stack:** NixOS + nix-darwin flake (flake-parts + haumea), home-manager, niri (Smithay Wayland compositor), Steam via `programs.steam` with a custom FHS override, gamescope, xdg-desktop-portal-gnome, WiVRn/Monado, OpenComposite, SteamVR.

**Source spec:** `docs/superpowers/specs/2026-08-24-steam-streaming-design.md`. Read it before starting. Section references below (§6a, §6h, ...) point into it.

## Global Constraints

- Host is `ali-desktop` only. Do not change any other host's configuration.
- Session is niri. Steam runs as an XWayland client under `xwayland-satellite`.
- The machine has **no Wi-Fi hardware**. `enp16s0` is the only physical NIC.
- GPU is AMD RDNA4; Steam Remote Play encodes via VA-API on radeonsi.
- `~/.local/bin` precedes `/run/current-system/sw/bin` in `PATH` (positions 33 and 47). The gamescope shim depends on this ordering; do not change it.
- Steam is single-instance. Any task that launches a second Steam must stop the first.
- Never squash commits. One commit per granular change. Reverting a single commit alone must leave the flake evaluable.
- All timestamps written into files use ISO8601 UTC.
- Build verification for every config task: `nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"`. Do not use `just switch` inside a task unless the task says to — activation is the user's call.
- The agent cannot run `sudo` (no askpass). Any step needing root must be handed to the user with the exact command.

## A note on testing in this repo

This is declarative system configuration, not application code, so classic red-green TDD applies to only one task in this plan (Task 9's `vr-runtime` script, which is a shell program with testable behaviour). For every other task the verification cycle is:

1. Build the configuration and confirm it evaluates (`nix build …toplevel`) — this is the equivalent of "tests pass".
2. Where a task changes runtime behaviour, run the named behavioural probe and record the result.

Where a task can be made to fail first in a meaningful way, the steps say so explicitly.

---

### Task 1: Pin the gamescope shim (§6f)

`~/.local/bin/gamescope` is currently a symlink to `~/git/steam-command-runner/target/debug/steam-command-runner` — a debug build inside a working tree, sitting in the launch chain of every Steam game. Replace it with a store path from a pinned flake input, keeping the same filename and the same `PATH` precedence so interception is unchanged.

The upstream flake at `github:alisonjenkins/steam-command-runner` exposes `packages.x86_64-linux.default` (verified 2026-08-24; the flake also exposes a legacy `defaultPackage`, do not use it). The binary inside is named `steam-command-runner`. Local `main` is at `eafb913` and matches `origin/main` with a clean tree, so no work needs pushing first.

**Files:**
- Modify: `flake.nix` (inputs block, starts line 4)
- Modify: `home/machines/ali-desktop/default.nix`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `~/.local/bin/gamescope` as a store symlink. Task 2 relies on `~/.local/bin` being a home-manager-managed location.

- [ ] **Step 1: Record the current shim state so the change is falsifiable**

```bash
readlink -f ~/.local/bin/gamescope
~/.local/bin/gamescope --version 2>&1 | head -3
```

Expected: a path under `~/git/steam-command-runner/target/debug/`. Save this output — Step 7 compares against it.

- [ ] **Step 2: Add the flake input**

In `flake.nix`, inside the `inputs = {` block (line 4), add alongside the other `github:alisonjenkins/*` inputs:

```nix
    steam-command-runner = {
      url = "github:alisonjenkins/steam-command-runner";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };
```

If evaluation later complains that the input has no `nixpkgs` to follow, drop the `inputs.nixpkgs.follows` line and leave the bare `url`.

- [ ] **Step 3: Lock the new input**

```bash
nix flake lock --update-input steam-command-runner
git diff --stat flake.lock
```

Expected: `flake.lock` shows a new `steam-command-runner` node.

- [ ] **Step 4: Install the shim declaratively**

In `home/machines/ali-desktop/default.nix`, change the header to take `inputs` and add the file. The whole file becomes:

```nix
{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  home.packages = [
    pkgs.nbt-studio
  ];

  # steam-command-runner intercepts `gamescope` in the Steam launch chain to
  # apply per-game gamescope arguments while keeping the Steam overlay and stop
  # button working. It only works from ~/.local/bin, which precedes the system
  # profile in PATH; installing it via home.packages would expose it under its
  # own name and never be reached. Previously a symlink to a debug build in a
  # working tree — every game's launch chain depended on an unpinned binary.
  home.file.".local/bin/gamescope".source =
    "${inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/steam-command-runner";
}
```

- [ ] **Step 5: Build**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
```

Expected: success. If it fails with `attribute 'inputs' missing`, the home module is not receiving `inputs` via `extraSpecialArgs` — check `home-manager.extraSpecialArgs` in `flake-modules/hosts/ali-desktop/default.nix` and add `inherit inputs;` there rather than working around it in the machine file.

- [ ] **Step 6: Hand the activation to the user**

home-manager will refuse to overwrite the existing unmanaged symlink. Tell the user to run:

```bash
rm ~/.local/bin/gamescope
just switch
```

(The repo sets `home-manager.backupCommand` to `hm-backup-file`, which may handle this automatically. If it does, the `rm` is unnecessary — try `just switch` first.)

- [ ] **Step 7: Verify the shim is now store-backed**

```bash
readlink -f ~/.local/bin/gamescope
~/.local/bin/gamescope --version 2>&1 | head -3
```

Expected: a `/nix/store/...-steam-command-runner-*/bin/steam-command-runner` path, and a version banner matching Step 1's. If the version differs from Step 1, the working tree had uncommitted behaviour — stop and tell the user before continuing.

- [ ] **Step 8: Commit**

```bash
git add flake.nix flake.lock home/machines/ali-desktop/default.nix
git commit -m "feat(ali-desktop): pin the steam-command-runner gamescope shim

~/.local/bin/gamescope was a symlink to a debug build inside a working
tree, and sits in the launch chain of every Steam game. Pin it to a flake
input so the launch chain no longer depends on an unpinned binary from a
dirty checkout.

Installed via home.file rather than home.packages because the shim only
works under the name 'gamescope' from ~/.local/bin, which precedes the
system profile in PATH."
```

---

### Task 2: Adopt the Sunshine wrapper scripts (§6g)

`~/.local/bin/sunshine-gamescope` and `~/.local/bin/sunshine-steam-bp` are untracked imperative scripts, invoked by name from the Sunshine application list in `flake-modules/hosts/ali-desktop/default.nix` (lines 214, 226, 263, 275). Both hardcode `WAYLAND_DISPLAY=wayland-1`, which is a guess about socket naming, and both write debug logs to `/tmp`.

**Files:**
- Create: `home/programs/linux-only/sunshine-wrappers/default.nix`
- Modify: `home/machines/ali-desktop/default.nix` (add the import)

**Interfaces:**
- Consumes: Task 1's `~/.local/bin` being home-manager-managed.
- Produces: `sunshine-gamescope <1080p|1440p>` and `sunshine-steam-bp` on `PATH`. The Sunshine `detached` entries in the host config already call these exact names — do not rename them.

- [ ] **Step 1: Capture the current scripts verbatim**

```bash
cat ~/.local/bin/sunshine-gamescope ~/.local/bin/sunshine-steam-bp
```

Keep this output next to you. The rewrite must preserve the gamescope argument string exactly: `-W $WIDTH -H $HEIGHT -w $WIDTH -h $HEIGHT -r 120 --force-windows-fullscreen -e -- steam -gamepadui`.

- [ ] **Step 2: Write the module**

Create `home/programs/linux-only/sunshine-wrappers/default.nix`:

```nix
{ pkgs, lib, ... }:
let
  # Resolve the compositor socket rather than assuming wayland-1. Sunshine's
  # detached commands run from the Sunshine user service, which does not
  # inherit the niri session's WAYLAND_DISPLAY, so it has to be recovered.
  # The previous imperative scripts hardcoded wayland-1, which is only
  # correct by accident of startup ordering.
  resolveWayland = ''
    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      export XDG_RUNTIME_DIR
      for sock in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
        case "$sock" in
          *.lock) continue ;;
        esac
        [ -S "$sock" ] || continue
        WAYLAND_DISPLAY="$(basename "$sock")"
        export WAYLAND_DISPLAY
        break
      done
    fi
    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      echo "sunshine wrapper: no wayland socket found in $XDG_RUNTIME_DIR" >&2
      exit 1
    fi
  '';

  sunshine-gamescope = pkgs.writeShellApplication {
    name = "sunshine-gamescope";
    runtimeInputs = with pkgs; [ coreutils gamescope util-linux ];
    text = ''
      ${resolveWayland}

      case "''${1:-1080p}" in
        1080p|1080) WIDTH=1920; HEIGHT=1080 ;;
        1440p|1440) WIDTH=2560; HEIGHT=1440 ;;
        *)
          echo "sunshine-gamescope: unknown resolution '$1', using 1080p" >&2
          WIDTH=1920; HEIGHT=1080
          ;;
      esac

      # setsid detaches from Sunshine's process group so that Sunshine's own
      # exit does not tear the session down.
      exec setsid gamescope \
        -W "$WIDTH" -H "$HEIGHT" -w "$WIDTH" -h "$HEIGHT" \
        -r 120 --force-windows-fullscreen -e \
        -- steam -gamepadui
    '';
  };

  sunshine-steam-bp = pkgs.writeShellApplication {
    name = "sunshine-steam-bp";
    runtimeInputs = with pkgs; [ coreutils util-linux ];
    text = ''
      ${resolveWayland}
      exec setsid steam steam://open/bigpicture
    '';
  };
in
{
  config = lib.mkIf pkgs.stdenv.isLinux {
    home.packages = [ sunshine-gamescope sunshine-steam-bp ];
  };
}
```

Before finalising `sunshine-steam-bp`, check Step 1's captured original: if it launched Steam differently (for example `steam -bigpicture` or via `launch-steam-bigpicture`), use whatever the original actually did. Do not substitute your own guess for a working command.

- [ ] **Step 3: Import it**

In `home/machines/ali-desktop/default.nix`, add to the `imports` list:

```nix
    ../../programs/linux-only/sunshine-wrappers
```

Check the surrounding convention first: this repo forbids relative imports across flake-output boundaries, but `home/machines/*` already imports its siblings relatively (`./easyeffects`). If `home/programs/linux-only/default.nix` is the aggregator that every Linux home config pulls in, add the import there instead and drop it from the machine file — but only if the wrappers are wanted on every Linux host. They are Sunshine-specific and Sunshine only runs on `ali-desktop`, so the machine file is the correct home unless the aggregator gates on hostname.

- [ ] **Step 4: Build**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
```

Expected: success.

- [ ] **Step 5: Verify the wrappers resolve before removing the old ones**

After the user runs `just switch`:

```bash
command -v sunshine-gamescope sunshine-steam-bp
```

Expected: paths under `/nix/store` or `~/.nix-profile`, **not** `~/.local/bin`. If `~/.local/bin` still wins, the old files are shadowing the new ones — that is expected until the next step.

- [ ] **Step 6: Remove the superseded imperative scripts**

```bash
mv ~/.local/bin/sunshine-gamescope ~/.local/bin/sunshine-gamescope.superseded
mv ~/.local/bin/sunshine-steam-bp ~/.local/bin/sunshine-steam-bp.superseded
command -v sunshine-gamescope sunshine-steam-bp
```

Renamed rather than deleted, so the originals are recoverable if Task 2's Step 7 probe fails. Delete them once Step 7 passes.

- [ ] **Step 7: Probe Sunshine end to end**

From a Moonlight client, launch the "Gamescope 1080p" and "Steam Big Picture" entries. Both must behave exactly as before this task.

If either fails, restore with `mv ~/.local/bin/sunshine-gamescope.superseded ~/.local/bin/sunshine-gamescope` and diagnose before continuing. This task must not leave Sunshine regressed — it is the fallback the rest of the plan leans on.

- [ ] **Step 8: Commit**

```bash
git add home/programs/linux-only/sunshine-wrappers home/machines/ali-desktop/default.nix
git commit -m "feat(ali-desktop): bring the Sunshine wrapper scripts into home-manager

The Sunshine application list invokes sunshine-gamescope and
sunshine-steam-bp by name, but both were untracked imperative scripts in
~/.local/bin, so the host configuration depended on files no rebuild could
reproduce.

Both hardcoded WAYLAND_DISPLAY=wayland-1, which is only correct by accident
of startup ordering; the wrappers now resolve the socket from
XDG_RUNTIME_DIR. The debug logging to /tmp is dropped — the wrappers run
under the Sunshine user service, so stderr already lands in the journal."
```

---

### Task 3: Baseline probe (§7)

No configuration changes. This task establishes what is actually broken, on a tree with Tasks 1 and 2 applied, so that later tasks can be attributed. **Do not skip or shortcut this** — the whole plan's ordering exists to make this measurement meaningful.

**Files:**
- Create: `docs/superpowers/plans/2026-08-24-steam-streaming-probes.md`

**Interfaces:**
- Consumes: Tasks 1 and 2 applied and activated.
- Produces: a probe log that Tasks 4, 5, 6, 7 and 8 read to decide what to do and whether they helped.

- [ ] **Step 1: Confirm the preconditions**

```bash
grep -rn "remotePlay.openFirewall" modules/desktop/default.nix
grep -o '"EnableStreaming"[^,]*' ~/.local/share/Steam/userdata/*/config/localconfig.vdf
ip -br link | grep -v DOWN
```

Expected: `remotePlay.openFirewall = true`; `EnableStreaming "1"` for both user IDs; the interface list including `enp16s0`, `docker0`, `br-*`, `veth*`, `tailscale0`.

- [ ] **Step 2: Create the probe log**

```bash
cat > docs/superpowers/plans/2026-08-24-steam-streaming-probes.md <<'EOF'
# Steam Remote Play probe log — ali-desktop

Each entry records one probe against one tree state. Outcomes are drawn from
the fixed set in the design spec §7: `no-discovery`, `black-screen`,
`cursor-only`, `audio-only`, `works-poor`, `works`.

| UTC timestamp | Tree state | Client | Discovery | Outcome | Notes |
|---|---|---|---|---|---|
EOF
```

- [ ] **Step 3: Run the baseline probe from the Deck**

On the Deck, open Steam and look for `ali-desktop` under Remote Play.

Record two things separately — they are independent failure paths and conflating them is the mistake this step exists to prevent:

1. **Discovery**: does the host appear in the Deck's list at all?
2. **Stream**: after connecting (via the list, or by manual IP if discovery fails), what appears?

- [ ] **Step 4: If discovery fails, retry by manual IP**

On the Deck, add the host manually at `ali-desktop`'s `enp16s0` address:

```bash
ip -4 addr show enp16s0 | awk '/inet /{print $2}'
```

A successful manual-IP connect with failed discovery isolates the problem to Task 7's territory. A failed manual-IP connect means the problem is capture or firewall, not discovery.

- [ ] **Step 5: Collect host-side evidence**

```bash
journalctl --user -b --since "10 min ago" | grep -iE "pipewire|portal|screencast|remote play|streaming" | tail -40
tail -50 ~/.local/share/Steam/logs/streaming_log.txt 2>/dev/null
```

`streaming_log.txt` is Steam's own host-side streaming log and is the single most useful artefact here. If it does not exist at that path, find it with `ls ~/.local/share/Steam/logs/`.

- [ ] **Step 6: Write the row**

Append one row to the probe log with the ISO8601 UTC timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`), tree state `tasks-1-2`, client `deck`, the discovery result, the outcome keyword, and the decisive line from the logs — the shortest line that shows the failure, not a log dump.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/plans/2026-08-24-steam-streaming-probes.md
git commit -m "docs(ali-desktop): record the Steam Remote Play baseline probe"
```

- [ ] **Step 8: Branch on the result**

- Outcome `works` — Tasks 4, 5, 7 and 8 are unnecessary. Skip to Task 6 to check capture geometry, then Task 9.
- Outcome `no-discovery` **and** manual IP works — do Task 7 next, then re-probe, then continue with Task 4.
- Any of `black-screen`, `cursor-only`, `audio-only` — continue to Task 4 as written. These are the documented Wayland capture failures.
- Outcome `works-poor` — continue to Task 4; also note the observed resolution, since Task 6 may be the real cause.

---

### Task 4: Steam Wayland capture flags (§6a)

Steam's Wayland host capture is opt-in via the client's `-pipewire` flag. There is no auto-detection. The flag has to reach every launch path — CLI, the `.desktop` entry, and `steam://` handoffs — which is why it goes in the existing `steamWithRunnerUpdate` shim rather than in a desktop entry.

**Files:**
- Modify: `modules/desktop/default.nix` — the `steamWithRunnerUpdate` definition (lines 28-36) and the `gaming` options block (opens line 618)
- Modify: `flake-modules/hosts/ali-desktop/default.nix` — the `modules.desktop` settings

**Interfaces:**
- Consumes: Task 3's probe log.
- Produces: `modules.desktop.gaming.steamExtraFlags` (`listOf str`, default `[]`). Tasks 5 and 6 may add further flags to this same list on `ali-desktop`.

- [ ] **Step 1: Add the option**

In `modules/desktop/default.nix`, inside the `gaming = {` block (opens line 618), next to `shaderCacheBasePath` (line 762), add:

```nix
      steamExtraFlags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "-pipewire" ];
        description = ''
          Extra flags passed to the Steam client on every launch, injected by
          the `steam` shim so that CLI launches, the desktop entry and
          steam:// handoffs all receive them.

          Wayland hosts need "-pipewire" for Remote Play screen capture; Steam
          does not enable the PipeWire capture path automatically. Empty by
          default because the flags carry costs — "-cef-disable-gpu-compositing"
          in particular disables GPU acceleration in the Steam UI and is only
          wanted where the XWayland CEF race actually appears.
        '';
      };
```

- [ ] **Step 2: Inject the flags in the shim**

In the same file, change `steamWithRunnerUpdate` (line 28) from:

```nix
    text = ''
      PROTON_RUNNERS=${lib.escapeShellArg protonRunnerLines} update-proton-runners || true
      exec ${config.programs.steam.package}/bin/steam "$@"
    '';
```

to:

```nix
    text = ''
      PROTON_RUNNERS=${lib.escapeShellArg protonRunnerLines} update-proton-runners || true
      exec ${config.programs.steam.package}/bin/steam ${lib.escapeShellArgs gcfg.steamExtraFlags} "$@"
    '';
```

`gcfg` is already bound at the top of the file (line 10 uses `gcfg.enable`), so no new binding is needed. `lib.escapeShellArgs` on an empty list yields the empty string, so hosts that set nothing keep the exact current command line.

- [ ] **Step 3: Verify the option defaults to a no-op before setting it**

```bash
nix eval ".#nixosConfigurations.ali-desktop.config.modules.desktop.gaming.steamExtraFlags"
```

Expected: `[ ]`. This is the "test fails first" step — it confirms the option exists and that nothing has changed behaviour yet.

- [ ] **Step 4: Set the flag on ali-desktop**

In `flake-modules/hosts/ali-desktop/default.nix`, alongside the other `modules.*` settings (near `modules.locale.enable = true;`, line 192):

```nix
        # Steam's Wayland host capture for Remote Play is opt-in — the client
        # does not detect Wayland and enable the PipeWire capture path on its
        # own. Without this, Remote Play connects and carries audio and input
        # while the video stays black.
        modules.desktop.gaming.steamExtraFlags = [ "-pipewire" ];
```

- [ ] **Step 5: Build and confirm the flag lands**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
nix eval ".#nixosConfigurations.ali-desktop.config.modules.desktop.gaming.steamExtraFlags"
```

Expected: build succeeds; eval prints `[ "-pipewire" ]`.

- [ ] **Step 6: Confirm the shim actually carries it**

After `just switch`:

```bash
grep -o 'bin/steam.*' "$(readlink -f "$(command -v steam)")"
```

Expected: the line ends with `-pipewire "$@"`. If `command -v steam` resolves somewhere unexpected, check that the `hiPrio` wrapper (line 1271) is still winning.

- [ ] **Step 7: Re-probe and record**

Fully quit Steam (`steam -shutdown`) and relaunch it so the flag takes effect — Steam does not pick up new flags on a warm client. Then repeat Task 3 Steps 3-6 with tree state `task-4`.

- [ ] **Step 8: Commit**

```bash
git add modules/desktop/default.nix flake-modules/hosts/ali-desktop/default.nix docs/superpowers/plans/2026-08-24-steam-streaming-probes.md
git commit -m "feat(desktop): add gaming.steamExtraFlags and enable -pipewire on ali-desktop

Steam's Wayland host capture for Remote Play is opt-in via the client's
-pipewire flag; there is no auto-detection, so on a Wayland session Remote
Play connects and carries audio and input while the video stays black.

The flags are injected by the steam shim rather than by a desktop entry so
that CLI launches, the desktop launcher and steam:// handoffs all receive
them. The option defaults to an empty list, and escapeShellArgs on an empty
list is the empty string, so no other host's command line changes.

-cef-disable-gpu-compositing and -pipewire-dmabuf are deliberately not set:
the first costs GPU acceleration in the Steam UI, the second is a tuning
knob. Both go in this same list only if a probe demands them."
```

- [ ] **Step 9: If the probe still shows a black Steam *window* (not a black stream)**

That is the documented niri + `xwayland-satellite` CEF race, distinct from capture. Append `"-cef-disable-gpu-compositing"` to `steamExtraFlags`, rebuild, re-probe and commit separately with the reasoning. Do not add it pre-emptively.

---

### Task 5: Pin the portal ScreenCast backend (§6b)

ScreenCast currently resolves by fall-through: the `niri` portal config is `default = [ "gtk" "gnome" ]`, `gtk` has no ScreenCast implementation, so `gnome` answers. But `xdg-desktop-portal-wlr` is also in `extraPortals` and niri also speaks `wlr-screencopy`, so the resolution is ambiguous and can drift on a portal update. niri implements `org.gnome.Mutter.ScreenCast`, so `gnome` is the correct backend.

**Files:**
- Modify: `flake-modules/hosts/ali-desktop/default.nix` lines 1216-1229 (the `niri` section of `xdg.portal.config`)

**Interfaces:**
- Consumes: Task 4 applied.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Record which backend answers today**

```bash
journalctl --user -u xdg-desktop-portal -b --no-pager | grep -i "screencast\|backend\|choosing" | tail -20
```

Save the output. If it names a backend for ScreenCast, that is the current behaviour the pin must preserve. If it names `wlr` rather than `gnome`, say so before proceeding — the design assumed `gnome`, and a mismatch means §6b needs rethinking rather than applying.

- [ ] **Step 2: Add the pin**

In the `niri` section of `xdg.portal.config` (line 1216), after the `Secret` line, add:

```nix
                  # ScreenCast currently resolves only by fall-through: gtk has
                  # no implementation, so gnome answers. xdg-desktop-portal-wlr
                  # is also installed and niri also speaks wlr-screencopy, so
                  # the resolution is ambiguous and can drift on a portal
                  # update. niri implements org.gnome.Mutter.ScreenCast, so
                  # gnome is the correct backend — pin it. Steam's Remote Play
                  # capture goes through this interface.
                  "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
```

- [ ] **Step 3: Build**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
```

Expected: success. A `mkForce` conflict here means nixpkgs' `niri.nix` pins ScreenCast too — if so, wrap the value in `lib.mkForce` and note why in the comment, matching the two existing `mkForce` uses in that block.

- [ ] **Step 4: Verify after switching**

After `just switch` and `systemctl --user restart xdg-desktop-portal.service`:

```bash
journalctl --user -u xdg-desktop-portal -b --no-pager | grep -i screencast | tail -10
```

Expected: the gnome backend answering ScreenCast, and no "no backend found" errors.

- [ ] **Step 5: Re-probe and record**

Repeat Task 3 Steps 3-6 with tree state `task-5`.

- [ ] **Step 6: Commit**

```bash
git add flake-modules/hosts/ali-desktop/default.nix docs/superpowers/plans/2026-08-24-steam-streaming-probes.md
git commit -m "fix(ali-desktop): pin the niri portal ScreenCast backend to gnome

ScreenCast resolved only by fall-through — gtk has no implementation, so
gnome answered. But xdg-desktop-portal-wlr is also installed and niri also
speaks wlr-screencopy, leaving the resolution ambiguous and able to drift on
a portal update. niri implements org.gnome.Mutter.ScreenCast, so gnome is
correct; pin it rather than relying on list order.

Steam's Remote Play capture goes through this interface, so a drift here
would present as a black stream with working audio and input."
```

---

### Task 6: Resolve the capture geometry (§6h)

The portal captures a niri **output**, not a window. `programs.scopebuddy` on this host passes `-b -W 2560 -H 1440` deliberately, so a gamescope game occupies a 2560-wide borderless box on the 5120x1440 DP-2 panel with the desktop visible around it. Capturing DP-2 therefore sends a 1280x800 Deck client a frame that is half game and half desktop.

**Files:**
- Modify: `home/programs/linux-only/niri/module.nix` (window rules) — only if mitigation 2 is chosen
- Modify: `docs/superpowers/plans/2026-08-24-steam-streaming-probes.md`

**Interfaces:**
- Consumes: Tasks 4 and 5 applied, and a probe that reached the point of showing video.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Determine whether the portal offers window-scoped capture**

Start a Remote Play session from the Deck and watch what the portal picker offers on the host. Record whether the choices include a single window, or only outputs/monitors.

If window-scoped capture is offered and Steam accepts it, take mitigation 1: select the game window, confirm the client receives only the game, record it in the probe log, and skip to Step 5. No configuration change is needed.

- [ ] **Step 2: If only output capture is available, confirm the geometry problem is real**

With a gamescope game running under scopebuddy, connect from the Deck and observe. Record the outcome as `works-poor` with a note describing what fills the frame.

If the client receives a correctly cropped game anyway, Steam is doing its own scaling — record that and skip to Step 5.

- [ ] **Step 3: Apply mitigation 2 — mode switch plus a fullscreen window rule**

The mode-switch half already exists and is proven: the Sunshine entries in `flake-modules/hosts/ali-desktop/default.nix` (lines 230, 244, 254) use `niri msg output DP-2 mode 2560x1440@119.998` with an `undo` restoring `5120x1440@119.999`. Steam Remote Play has no prep-command hook equivalent, so this has to be driven by hand or by a small script the user runs before streaming.

Add a script to `home/machines/ali-desktop/default.nix`:

```nix
  home.packages = [
    pkgs.nbt-studio
    (pkgs.writeShellApplication {
      name = "stream-mode";
      runtimeInputs = [ pkgs.niri ];
      text = ''
        # Steam Remote Play captures a niri output, not a window, so the
        # streamed frame carries the whole 5120x1440 panel — half game, half
        # desktop — unless DP-2 is narrowed for the duration of the session.
        # Sunshine does this per-application via prep-cmd; Steam has no
        # equivalent hook, so it is driven by hand.
        case "''${1:-on}" in
          on)  niri msg output DP-2 mode 2560x1440@119.998 ;;
          off) niri msg output DP-2 mode 5120x1440@119.999 ;;
          *)   echo "usage: stream-mode [on|off]" >&2; exit 1 ;;
        esac
      '';
    })
  ];
```

Verify the exact mode strings against the host config before writing them — a wrong refresh rate string makes `niri msg` fail rather than fall back.

- [ ] **Step 4: Build, switch and verify**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
```

After `just switch`: run `stream-mode on`, confirm DP-2 reports 2560x1440 via `niri msg outputs`, stream from the Deck, then `stream-mode off` and confirm the panel returns to 5120x1440.

- [ ] **Step 5: Record and commit**

Append a probe row with tree state `task-6` and a note naming which mitigation applied.

```bash
git add home/machines/ali-desktop/default.nix docs/superpowers/plans/2026-08-24-steam-streaming-probes.md
git commit -m "feat(ali-desktop): add stream-mode for Remote Play capture geometry

The portal captures a niri output rather than a window, and scopebuddy
deliberately runs games in a 2560-wide borderless box on the 5120x1440
panel so the desktop stays visible around them. A Deck client therefore
receives a frame that is half game and half desktop.

Sunshine solves this per-application with prep-cmd mode switches. Steam
Remote Play has no equivalent hook, so the same mode switch is exposed as a
command to run either side of a session."
```

If mitigation 1 applied and no configuration changed, commit only the probe log.

---

### Task 7: Discovery hardening (§6c) — conditional

**Only do this task if a probe recorded `no-discovery` while a manual-IP connect succeeded.** If discovery works, skip to Task 9. Applying this speculatively adds firewall rules that nothing needs.

Steam broadcasts discovery on UDP 27036 to every accessible subnet and can bind or advertise the wrong interface. This host has `docker0`, `br-67eb35085746`, three `veth*` and `tailscale0` up. There is no Steam setting to bind discovery to one interface.

**Files:**
- Modify: `flake-modules/hosts/ali-desktop/default.nix` — the `networking` block (line 680)

**Interfaces:**
- Consumes: a probe row recording `no-discovery`.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Bisect which interface is implicated — tailscale first**

Hand to the user (needs root):

```bash
sudo tailscale down
```

Re-probe discovery from the Deck. Record the result. Then `sudo tailscale up` regardless of outcome.

- [ ] **Step 2: If tailscale was not the cause, bisect the Docker bridges**

Hand to the user:

```bash
sudo systemctl stop docker.socket docker.service
ip -br link | grep -v DOWN
```

Re-probe. Then `sudo systemctl start docker.service`.

- [ ] **Step 3: If neither is implicated, stop**

The problem is not interface selection. Record that in the probe log and move to Task 8 — a discovery failure with all extra interfaces down and manual IP working is not something this task can fix, and guessing further wastes the bisect.

- [ ] **Step 4: Add the targeted rule**

Only for the interface the bisect implicated. In the `networking` block:

```nix
          # Steam broadcasts Remote Play discovery on UDP 27036 to every
          # accessible subnet and has no setting to bind it to one interface.
          # Broadcasting onto <interface> made the host advertise an address
          # the Deck could not reach, so discovery failed while a manual-IP
          # connect worked. Confined to egress on the offending interface;
          # enp16s0 is untouched.
          firewall.extraCommands = ''
            iptables -A OUTPUT -o <interface> -p udp --dport 27036 -j DROP
          '';
```

Substitute the real interface name. If this host uses nftables rather than iptables, use `networking.nftables` equivalents — check `modules/base/default.nix` for which backend is in use before writing the rule, and match it.

- [ ] **Step 5: Build, switch, re-probe, commit**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
```

Re-probe with tree state `task-7`, then commit the config and the probe row together with a message stating which interface the bisect implicated and what evidence showed it.

---

### Task 8: Headless gamescope fallback (§6d) — conditional

**Only do this task if Tasks 4, 5 and 6 have been applied and probed, and the stream still fails.** If Remote Play works, skip to Task 9.

`gamescope --backend headless` renders offscreen and presents no Wayland surface, so niri never sees a window and tiling cannot intervene. This is the best-documented reliable pattern. Steam is single-instance, so this is a mode switch, not a parallel service.

**Files:**
- Modify: `home/machines/ali-desktop/default.nix`

**Interfaces:**
- Consumes: probe rows showing Tasks 4-6 did not fix the stream.
- Produces: a `steam-headless` command.

- [ ] **Step 1: Fix the resolution**

The Deck's native panel is 1280x800. Use that, not 1080p — encoding above the client's panel resolution wastes bitrate on a downscale. If the Frame's is known by the time this task runs, add a second entry rather than compromising between them.

- [ ] **Step 2: Add the command**

```nix
    (pkgs.writeShellApplication {
      name = "steam-headless";
      runtimeInputs = with pkgs; [ gamescope procps ];
      text = ''
        # Steam is single-instance, so the desktop client must exit first.
        if pgrep -x steam >/dev/null; then
          echo "steam-headless: shutting down the running Steam client" >&2
          steam -shutdown || true
          for _ in $(seq 1 30); do
            pgrep -x steam >/dev/null || break
            sleep 1
          done
        fi
        if pgrep -x steam >/dev/null; then
          echo "steam-headless: Steam did not exit; aborting" >&2
          exit 1
        fi

        # --backend headless presents no Wayland surface at all, so niri never
        # sees a window and the tiling layout cannot intervene in what gets
        # captured. That immunity is the point of this path.
        exec gamescope --backend headless -e -W 1280 -H 800 -- steam -gamepadui
      '';
    })
```

Note `sleep` is used inside the script, which is fine — the prohibition on foreground sleep applies to the agent's own shell, not to scripts it writes.

- [ ] **Step 3: Build**

```bash
nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"
```

- [ ] **Step 4: Probe**

After `just switch`, run `steam-headless`, then connect from the Deck. Record with tree state `task-8`.

- [ ] **Step 5: Commit**

```bash
git add home/machines/ali-desktop/default.nix docs/superpowers/plans/2026-08-24-steam-streaming-probes.md
git commit -m "feat(ali-desktop): add steam-headless for Remote Play

gamescope --backend headless renders offscreen and presents no Wayland
surface, so niri never sees a window and the tiling layout cannot affect
what is captured. That immunity is why it is the documented-reliable path
for Remote Play, and why it is worth having after the in-session capture
fixes did not settle the stream.

Steam is single-instance, so this shuts the desktop client down first
rather than racing it."
```

---

### Task 9: VR runtime switcher (§6e)

`home/modules/vr/default.nix` owns `~/.config/openxr/1/active_runtime.json` and `~/.config/openvr/openvrpaths.vrpath` as read-only store symlinks, chosen at build time by `modules.vr.enableOpenSourceVR`. A switcher cannot write those. The live state is already inconsistent as a result: OpenXR resolves to WiVRn while `openvrpaths.vrpath` lists SteamVR first.

This is the only task in the plan with a testable unit, so it is the only one written as red-green.

**Files:**
- Create: `home/modules/vr/vr-runtime.nix`
- Create: `home/modules/vr/tests/vr-runtime-test.sh`
- Modify: `home/modules/vr/default.nix`

**Interfaces:**
- Consumes: nothing from Tasks 1-8.
- Produces: `vr-runtime {wivrn,steamvr,status}` on `PATH`. Task 10 uses it.

- [ ] **Step 1: Write the failing test**

Create `home/modules/vr/tests/vr-runtime-test.sh`. It drives the script against a throwaway `HOME` so no real configuration is touched:

```bash
#!/usr/bin/env bash
set -euo pipefail

VR_RUNTIME="${1:?usage: vr-runtime-test.sh /path/to/vr-runtime}"

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export VR_RUNTIME_DRY_RUN=1   # skip systemctl calls
export VR_RUNTIME_WIVRN_JSON="$TMP/fake-wivrn/openxr_wivrn.json"
export VR_RUNTIME_STEAMVR_ROOT="$TMP/fake-steamvr"
export VR_RUNTIME_OPENCOMPOSITE_ROOT="$TMP/fake-opencomposite"
mkdir -p "$(dirname "$VR_RUNTIME_WIVRN_JSON")" "$VR_RUNTIME_STEAMVR_ROOT" "$VR_RUNTIME_OPENCOMPOSITE_ROOT"
echo '{"runtime":{"name":"Monado"}}' > "$VR_RUNTIME_WIVRN_JSON"

# 1. status on a virgin HOME must not crash and must report unset
out="$("$VR_RUNTIME" status)" || fail "status exited non-zero on a virgin HOME"
grep -qi "unset\|none" <<<"$out" || fail "status did not report an unset runtime: $out"

# 2. switching to steamvr writes both files, with SteamVR first in openvrpaths
"$VR_RUNTIME" steamvr || fail "steamvr switch exited non-zero"
grep -q "steamxr\|SteamVR" "$HOME/.config/openxr/1/active_runtime.json" \
  || fail "active_runtime.json does not point at SteamVR"
python3 -c "
import json,sys
p=json.load(open('$HOME/.config/openvr/openvrpaths.vrpath'))
rt=p['runtime']
assert 'SteamVR' in rt[0], rt
" || fail "openvrpaths.vrpath does not list SteamVR first"

# 3. switching to wivrn repoints OpenXR at the wivrn library
"$VR_RUNTIME" wivrn || fail "wivrn switch exited non-zero"
grep -q "Monado\|wivrn" "$HOME/.config/openxr/1/active_runtime.json" \
  || fail "active_runtime.json does not point at WiVRn"

# 4. the files must be writable, not store symlinks — this is the whole point
[ -w "$HOME/.config/openxr/1/active_runtime.json" ] \
  || fail "active_runtime.json is not writable; a switcher cannot work"

# 5. status reflects the last switch
out="$("$VR_RUNTIME" status)"
grep -qi "wivrn" <<<"$out" || fail "status did not report wivrn: $out"

# 6. an unknown subcommand fails loudly rather than silently doing nothing
if "$VR_RUNTIME" nonsense 2>/dev/null; then
  fail "unknown subcommand exited zero"
fi

echo "PASS: all vr-runtime assertions held"
```

- [ ] **Step 2: Run it and watch it fail**

```bash
bash home/modules/vr/tests/vr-runtime-test.sh /nonexistent/vr-runtime
```

Expected: fails immediately, because the script does not exist yet. This confirms the harness runs and can go red.

- [ ] **Step 3: Write the script**

Create `home/modules/vr/vr-runtime.nix`:

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.modules.vr;

  vr-runtime = pkgs.writeShellApplication {
    name = "vr-runtime";
    runtimeInputs = with pkgs; [ coreutils python3 systemd ];
    text = ''
      # Runtime selection between WiVRn (Monado, for the Quest over the LAN)
      # and SteamVR (for the Steam Frame, and for titles that need SteamVR
      # itself). Previously a build-time choice via
      # modules.vr.enableOpenSourceVR, which is why the live state drifted:
      # OpenXR pointed at WiVRn while openvrpaths.vrpath listed SteamVR first.
      #
      # The env overrides exist so the test harness can drive this against a
      # throwaway HOME.
      WIVRN_JSON="''${VR_RUNTIME_WIVRN_JSON:-${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json}"
      STEAMVR_ROOT="''${VR_RUNTIME_STEAMVR_ROOT:-${cfg.steamvrRoot}}"
      OPENCOMPOSITE_ROOT="''${VR_RUNTIME_OPENCOMPOSITE_ROOT:-${pkgs.opencomposite}/lib/opencomposite}"

      OPENXR_FILE="$HOME/.config/openxr/1/active_runtime.json"
      OPENVR_FILE="$HOME/.config/openvr/openvrpaths.vrpath"

      svc() {
        [ -n "''${VR_RUNTIME_DRY_RUN:-}" ] && return 0
        systemctl --user "$@" wivrn.service || true
      }

      write_openvrpaths() {
        mkdir -p "$(dirname "$OPENVR_FILE")"
        python3 - "$OPENVR_FILE" "$@" <<'PY'
import json, sys
path, *runtimes = sys.argv[1:]
json.dump({
    "config": [],
    "external_drivers": None,
    "jsonid": "vrpathreg",
    "log": [],
    "runtime": list(runtimes),
    "version": 1,
}, open(path, "w"), indent=3)
PY
      }

      case "''${1:-status}" in
        wivrn)
          mkdir -p "$(dirname "$OPENXR_FILE")"
          cp --no-preserve=mode "$WIVRN_JSON" "$OPENXR_FILE"
          # wivrn-server rewrites openvrpaths.vrpath at every startup from its
          # built-in OVR_COMPAT_SEARCH_PATH, so OpenComposite is written here
          # only as a sane resting state; wivrn owns the file while running.
          write_openvrpaths "$OPENCOMPOSITE_ROOT"
          svc start
          echo "vr-runtime: now wivrn"
          ;;
        steamvr)
          svc stop
          mkdir -p "$(dirname "$OPENXR_FILE")"
          cat > "$OPENXR_FILE" <<EOF
{
    "file_format_version": "1.0.0",
    "runtime": {
        "name": "SteamVR",
        "library_path": "$STEAMVR_ROOT/bin/linux64/vrclient.so"
    }
}
EOF
          write_openvrpaths "$STEAMVR_ROOT" "$OPENCOMPOSITE_ROOT"
          echo "vr-runtime: now steamvr"
          ;;
        status)
          if [ ! -e "$OPENXR_FILE" ]; then
            echo "vr-runtime: unset (no active_runtime.json)"
            exit 0
          fi
          name="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['runtime'].get('name','unknown'))" "$OPENXR_FILE")"
          case "$name" in
            Monado|*wivrn*|*WiVRn*) echo "vr-runtime: wivrn ($name)" ;;
            SteamVR|*Steam*)        echo "vr-runtime: steamvr ($name)" ;;
            *)                      echo "vr-runtime: unknown ($name)" ;;
          esac
          ;;
        *)
          echo "usage: vr-runtime [wivrn|steamvr|status]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.modules.vr = {
    steamvrRoot = lib.mkOption {
      type = lib.types.str;
      default = "\${HOME}/.local/share/Steam/steamapps/common/SteamVR";
      description = ''
        Filesystem path to the SteamVR installation. On ali-desktop the Steam
        library lives on a separate mount, so this is not the default location.
      '';
    };

    runtimeSwitcherPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = vr-runtime;
      description = ''
        The vr-runtime switcher derivation. Internal: exposed only so that the
        seeding activation script in ./default.nix can reference the same
        derivation this module installs, without duplicating its definition.
      '';
    };
  };

  config = lib.mkIf pkgs.stdenv.isLinux {
    home.packages = [ vr-runtime ];
  };
}
```

Verify `$STEAMVR_ROOT/bin/linux64/vrclient.so` is the right library path for the installed SteamVR before finalising — check with `ls /media/steam-games-1/Steam/steamapps/common/SteamVR/bin/linux64/`. If the OpenXR manifest SteamVR ships (`steamxr_linux64.json`) exists under that root, point `active_runtime.json` at a copy of it instead of hand-writing the JSON, which is more robust.

- [ ] **Step 4: Run the test until it passes**

Build the switcher on its own rather than through the whole system closure — it
is a `writeShellApplication`, so it builds in seconds and the test needs only
its path:

```bash
nix build --no-link --print-out-paths \
  ".#nixosConfigurations.ali-desktop.config.modules.vr.runtimeSwitcherPackage"
```

Expected: one `/nix/store/...-vr-runtime` path. Then run the test against it:

```bash
bash home/modules/vr/tests/vr-runtime-test.sh \
  "$(nix build --no-link --print-out-paths '.#nixosConfigurations.ali-desktop.config.modules.vr.runtimeSwitcherPackage')/bin/vr-runtime"
```

Expected: `PASS: all vr-runtime assertions held`.

Iterate on the script until it passes. If the attribute path does not resolve,
the option lives under home-manager rather than NixOS — try
`.#nixosConfigurations.ali-desktop.config.home-manager.users.ali.modules.vr.runtimeSwitcherPackage`
instead. Confirm which by checking whether `home/modules/vr` is imported as a
home module (it is imported at `flake-modules/hosts/ali-desktop/default.nix:89`
as `self.homeModules.vr`, so the home-manager path is the likely one).

- [ ] **Step 5: Stop home-manager owning the runtime files**

In `home/modules/vr/default.nix`, replace both `xdg.configFile` branches with an activation script that seeds the files only when absent, and import the new module:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;
in
{
  imports = [ ./vr-runtime.nix ];

  options.modules.vr = {
    enableOpenSourceVR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the open-source VR stack (WiVRn as an OpenXR runtime,
        OpenComposite as an OpenVR runtime) and seed it as the initial runtime
        selection on a machine that has never chosen one.

        This no longer *pins* the active runtime: the runtime files must be
        writable for `vr-runtime` to switch between WiVRn and SteamVR, so
        home-manager seeds them once and then leaves them alone.
      '';
    };
  };

  config = lib.mkIf pkgs.stdenv.isLinux {
    home.activation.seedVrRuntime =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e "$HOME/.config/openxr/1/active_runtime.json" ]; then
          run ${lib.getExe cfg.runtimeSwitcherPackage} \
            ${if cfg.enableOpenSourceVR then "wivrn" else "steamvr"} || true
        fi
      '';
  };
}
```

`cfg.runtimeSwitcherPackage` is the internal read-only option defined in `vr-runtime.nix` above, so both files reference one derivation rather than duplicating its definition. `lib.getExe` works because `writeShellApplication` sets `meta.mainProgram`.

- [ ] **Step 6: Hand the migration to the user**

The existing files are store symlinks that home-manager will now stop managing:

```bash
rm -f ~/.config/openxr/1/active_runtime.json ~/.config/openvr/openvrpaths.vrpath
just switch
vr-runtime status
```

Expected: `vr-runtime: wivrn (Monado)`, since `enableOpenSourceVR = true` on this host.

- [ ] **Step 7: Verify both directions against real hardware**

```bash
vr-runtime steamvr && vr-runtime status
vr-runtime wivrn && vr-runtime status
```

Then confirm the Quest still connects through WiVRn. **This is the regression gate for the whole task** — if the Quest path breaks, revert and reconsider before continuing.

- [ ] **Step 8: Commit**

```bash
git add home/modules/vr docs/superpowers/plans/2026-08-24-steam-streaming-probes.md
git commit -m "feat(vr): switch VR runtimes at runtime instead of at build time

active_runtime.json and openvrpaths.vrpath were read-only store symlinks
chosen by modules.vr.enableOpenSourceVR at build time, so nothing could
switch between WiVRn and SteamVR without a rebuild. The live state had
already drifted as a result: OpenXR resolved to WiVRn while
openvrpaths.vrpath listed SteamVR first.

home-manager now seeds the files once and leaves them writable, and
vr-runtime switches between them, stopping and starting wivrn.service to
match. enableOpenSourceVR is demoted from 'which runtime is active' to
'install the open stack and seed it as the initial choice'.

A Steam Frame streams PC VR through SteamVR, so this is a prerequisite for
using one on a machine that also serves a Quest over WiVRn."
```

---

### Task 10: Steam Frame readiness (§8)

Prepare only. No Frame-specific configuration — host-side requirements are unknown until the hardware ships.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-24-steam-streaming-design.md` (§8, recording answers as they are found)
- Modify: `PENDING.md` (repo root)

**Interfaces:**
- Consumes: Task 9's `vr-runtime`.
- Produces: nothing.

- [ ] **Step 1: Verify SteamVR runs under niri now**

```bash
vr-runtime steamvr
```

Launch SteamVR from Steam with the Quest connected through Link or a wired mode, and record whether it starts and renders.

If SteamVR fails to start under Wayland, the documented workaround is forcing it onto XWayland via `WAYLAND_DISPLAY= QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11` in SteamVR's launch options. Record whether that was needed — it is a real finding for the Frame, since the Frame path depends on SteamVR working here.

- [ ] **Step 2: Return to the working configuration**

```bash
vr-runtime wivrn
vr-runtime status
```

Do not leave the machine on SteamVR — the Quest is the headset actually in use.

- [ ] **Step 3: Clean up the stale ALVR remnant**

`~/.local/share/Steam/config/alvr_server` is left over from an ALVR install that is no longer part of this setup and can confuse SteamVR driver enumeration.

```bash
mv ~/.local/share/Steam/config/alvr_server ~/.local/share/Steam/config/alvr_server.stale
```

Renamed rather than deleted. If SteamVR behaves the same on the next launch, delete it.

- [ ] **Step 4: Record the open questions where they will be seen**

Add to `PENDING.md`:

```markdown
## Steam Frame (hardware not yet in hand)

Design: `docs/superpowers/specs/2026-08-24-steam-streaming-design.md` §8.
Answer on day one with the hardware:

- Does host streaming to the Frame require SteamVR running on the host, or
  does the Steam client stream VR without it?
- Does the bundled 6 GHz adapter have a driver outside SteamOS? Its chipset
  is not published, and `ali-desktop` has no other radio — this is the only
  wireless path to the machine.
- Confirm the topology: reporting says the **headset** creates the hotspot
  and the **PC** joins it using the bundled adapter, which is the reverse of
  the obvious assumption.
- Re-check whether Frame streaming uses the Remote Play ports already opened
  by `programs.steam.remotePlay.openFirewall`, or something else.
```

- [ ] **Step 5: Commit**

```bash
git add PENDING.md docs/superpowers/specs/2026-08-24-steam-streaming-design.md
git commit -m "docs: record the Steam Frame open questions in PENDING.md

Host-side requirements cannot be settled until the hardware ships, so the
questions are recorded where they will be seen rather than guessed at in
configuration. SteamVR was verified to run under niri via the vr-runtime
switcher, using the Quest as a stand-in, since the Frame's VR path depends
on it."
```

---

## Completion

The work is done when:

- The probe log records a `works` outcome from the Deck with a tree state naming the last applied task.
- Sunshine's "Gamescope 1080p" and "Steam Big Picture" entries still work from Moonlight.
- The Quest still connects through WiVRn, and `vr-runtime` switches both ways.
- `nix build ".#nixosConfigurations.ali-desktop.config.system.build.toplevel"` succeeds.
- Nothing in `~/.local/bin` that the host configuration depends on is untracked.

Open a PR with `gh pr create` and merge with `--rebase`. Never `--squash`.

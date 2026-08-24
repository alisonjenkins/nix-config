# Steam Remote Play host on ali-desktop — design

- Date: 2026-08-24
- Host: `ali-desktop` (niri Wayland session, AMD RDNA4, wired-only `enp16s0`)
- Clients: Steam Deck (today), Steam Frame (later, flat + VR)

## 1. Problem

Steam Remote Play from `ali-desktop` has been tried and had issues; it has not
been retested recently. The machine runs niri, where Steam is an XWayland client
under `xwayland-satellite`, and where Steam's Wayland capture path is opt-in
rather than automatic. A Steam Frame is planned, which will stream both VR and
heavy flat titles from this host. The VR side conflicts with the machine's
current VR configuration.

The work must not regress two things that already work: the Sunshine/Moonlight
stack, and the WiVRn path to the Quest.

## 2. Goals

- Steam Remote Play is a reliable, tuned host path to the Steam Deck.
- The machine is ready for a Steam Frame without speculative configuration.
- Sunshine stays available for desktop and non-Steam streaming.
- The Quest/WiVRn path keeps working.

## 3. Non-goals

- Steam Frame specific configuration. Host-side requirements are unknown until
  the hardware ships (see §8).
- Retiring Sunshine.
- Changes to any host other than `ali-desktop`.

## 4. Research findings this design rests on

Gathered 2026-08-24. Confidence markers are the researcher's.

- Steam's Wayland host capture works but is opt-in via the `-pipewire` client
  launch flag; `-pipewire-dmabuf` is an additional flag some users need. There
  is no auto-detection. [confirmed]
- The capture backend is PipeWire via the xdg-desktop-portal ScreenCast
  interface. niri implements `org.gnome.Mutter.ScreenCast`, so
  `xdg-desktop-portal-gnome` is the correct backend on niri. [confirmed]
- A June 2026 Steam stable update improved PipeWire session logic so a session
  is only active while streaming. [confirmed]
- niri + `xwayland-satellite` has a documented black-Steam-window CEF race,
  fixed with `-cef-disable-gpu-compositing`. This is a UI-rendering bug, not a
  capture bug; no source ties it to the capture path. [confirmed for the bug,
  unknown for the interaction]
- Known Wayland failure modes: black screen with working audio/input; flicker
  and stale-frame insertion specifically with `-pipewire` on KDE (open
  upstream); loss of capture permission after screen lock; cursor/input-only
  with no video. [confirmed / anecdotal per mode]
- `gamescope --backend headless -e -W <w> -H <h> -- steam -gamepadui` is the
  best-documented reliable pattern for Remote Play on Linux. [confirmed]
- Conversely, running gamescope as the *session* compositor breaks Remote Play
  capture (white or frozen image, input still working). [confirmed]
- Steam broadcasts discovery on UDP 27036 to every accessible subnet and can
  bind or advertise the wrong interface when virtual adapters are present.
  There is no Steam setting to bind discovery to one interface; the documented
  fix is disabling the extra interfaces, with manual-IP connect as fallback.
  [confirmed]
- `programs.steam.remotePlay.openFirewall` opens TCP 27036 and UDP 27031-27036.
  [confirmed]
- Steam Remote Play uses VA-API hardware encode/decode on Linux and works with
  AMD radeonsi. There is no encoder-selection UI beyond bitrate presets
  (100 Mbit / unlimited up to 250 Mbit as of June 2026). RDNA4-specific
  regressions: none found. [confirmed / unknown]

## 5. Current state on the box

Established by inspection on 2026-08-24.

- `programs.steam.remotePlay.openFirewall = true` and
  `dedicatedServer.openFirewall = true` are already set in
  `modules/desktop/default.nix`. `EnableStreaming` is `1` in both Steam user
  configs. No Steam launch flags are set anywhere.
- `xdg.portal.config.niri.default = [ "gtk" "gnome" ]` on this host, with
  `xdg-desktop-portal-gnome`, `-gtk` and `-wlr` all in `extraPortals`.
  ScreenCast currently resolves by fall-through, not by an explicit pin.
- Interfaces up: `enp16s0`, `docker0`, `br-67eb35085746`, three `veth*`,
  `tailscale0`. There is no Wi-Fi hardware in the machine at all.
- `~/.local/bin/gamescope` is a symlink to
  `~/git/steam-command-runner/target/debug/steam-command-runner` — a debug
  build in a working tree, sitting in the launch chain of every Steam game.
  `~/.local/bin` precedes `/run/current-system/sw/bin` in `PATH` (positions 33
  and 47), so the shim is live. The project has its own `flake.nix`.
- `~/.local/bin/sunshine-gamescope` and `~/.local/bin/sunshine-steam-bp` are
  untracked imperative scripts. The Sunshine application list in
  `flake-modules/hosts/ali-desktop/default.nix` invokes both by name. Both
  hardcode `WAYLAND_DISPLAY=wayland-1`.
- VR runtime state is internally inconsistent: OpenXR resolves to WiVRn via
  `~/.config/openxr/1/active_runtime.json`, while
  `~/.config/openvr/openvrpaths.vrpath` lists SteamVR *first* and OpenComposite
  second. `modules.vr.enableOpenSourceVR = true`. SteamVR is installed at
  `/media/steam-games-1/Steam/steamapps/common/SteamVR`. A stale `alvr_server`
  directory is present in the Steam config dir.

## 6. Design

### 6a. Steam Wayland capture flags

Add `modules.desktop.gaming.steamExtraFlags` (`listOf str`, default `[]`). The
existing `steamWithRunnerUpdate` shim in `modules/desktop/default.nix` injects
them before `"$@"`, so CLI launches, the `.desktop` entry and `steam://` handoffs
all get them uniformly.

`ali-desktop` sets `[ "-pipewire" ]`.

`-cef-disable-gpu-compositing` and `-pipewire-dmabuf` are deliberately **not**
defaults. The first costs GPU acceleration in the Steam UI and is only wanted if
the xwayland-satellite black-window race actually appears. The second is a
tuning knob. Both are added to the same list only if a probe demands it.

### 6b. Portal ScreenCast pinning

Add `"org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ]` to the `niri`
section of `xdg.portal.config` on `ali-desktop`.

Today ScreenCast resolves only because `gtk` has no implementation and the list
falls through to `gnome`. But `xdg-desktop-portal-wlr` is also installed and niri
also speaks `wlr-screencopy`, so the resolution is ambiguous and can drift. niri
implements Mutter's ScreenCast API, so `gnome` is the correct backend. Pin it.

### 6c. Discovery hardening — conditional

The firewall is already correct. Do **nothing** here until the baseline probe in
§7 shows discovery actually failing.

If it does fail, bisect in this order: bring `tailscale0` down and re-probe;
then bring the Docker bridges down and re-probe. Only once an interface is
implicated, add an nftables rule dropping UDP 27036 broadcast egress on every
interface except `enp16s0`. Manual-IP pairing in the Steam Link client is the
standing fallback and should be used to distinguish a discovery failure from a
capture failure during the probe.

### 6d. Headless gamescope fallback

Built only if §6a–6c do not produce a clean stream.

Shape: a user unit running
`gamescope --backend headless -e -W <w> -H <h> -- steam -gamepadui`.

Steam is single-instance, so this is a mode switch and not a service that can run
alongside the desktop Steam: entering it requires the desktop Steam to exit. The
spec records the shape; implementation is gated on need.

### 6e. VR runtime switcher

Provide `vr-runtime {wivrn,steamvr,status}`.

`home/modules/vr` currently owns `active_runtime.json` and `openvrpaths.vrpath`
as read-only `/nix/store` symlinks, which a switcher cannot write. Change:

- Seed both files from a home-manager activation script if they are absent, and
  otherwise leave them mutable.
- Install the WiVRn, OpenComposite and SteamVR paths unconditionally.
- Demote `modules.vr.enableOpenSourceVR` from "which runtime is active" to
  "install the open-source stack". Runtime selection becomes a runtime decision.
- `vr-runtime steamvr` stops the `wivrn` service and points OpenXR and OpenVR at
  SteamVR. `vr-runtime wivrn` does the inverse, starting `wivrn` and letting
  `wivrn-server` own `openvrpaths.vrpath` as it does today.

This also resolves the live inconsistency recorded in §5.

### 6f. Pin the gamescope shim

Add `steam-command-runner` as a flake input, install its package on
`ali-desktop`, and replace the debug symlink with

```nix
home.file.".local/bin/gamescope".source =
  "${steam-command-runner}/bin/steam-command-runner";
```

Same interception and same `PATH` precedence, store-pinned, with no dependency on
a dirty working tree in every game's launch chain.

### 6g. Adopt the Sunshine wrappers

Convert `sunshine-gamescope` and `sunshine-steam-bp` into
`writeShellApplication` derivations under home-manager, so the Sunshine
application list stops depending on untracked files. While converting, replace
the hardcoded `WAYLAND_DISPLAY=wayland-1` with resolution of the real socket.

### 6h. Window layout under a tiling compositor

The portal ScreenCast path in §6a captures a niri *output*, not a window. What
reaches the client is therefore whatever niri's column layout has placed on that
output — neighbouring columns and the bar included — and at the output's full
geometry.

This collides with the tuned desktop setup on this host. `programs.scopebuddy`
passes `-b -W 2560 -H 1440` deliberately, so that a gamescope game occupies a
2560-wide borderless box on the 5120x1440 DP-2 panel and the rest of the screen
stays visible. Capturing DP-2 then yields a 5120x1440 frame that is half game and
half desktop, which is wrong for a 1280x800 Deck client.

Three mitigations, in preference order:

1. Prefer a window-scoped capture if the portal offers one at selection time,
   which sidesteps output geometry entirely.
2. Otherwise, switch the DP-2 mode for the duration of the stream, exactly as
   the existing Sunshine application entries already do via
   `niri msg output DP-2 mode ...`, and pair it with a niri window rule that
   opens the streamed game fullscreen on a dedicated workspace.
3. Otherwise, fall back to §6d, where the question does not arise.

Note that gamescope's `--backend headless` in §6d creates no Wayland surface at
all — it renders offscreen, niri never sees a window, and tiling cannot
intervene. That is a substantive part of why it is the reliable path, not an
incidental detail.

Confirm at probe time which of the three applies; the answer depends on whether
the portal's window-scoped mode is offered under niri, which is untested here.

## 7. Verification protocol

Run a baseline probe **before** any change. From the Deck, start Remote Play and
record which outcome occurs: no discovery, black screen, cursor-only, audio-only,
or works-but-poor. Use manual-IP connect to separate discovery failures from
capture failures.

After the baseline, apply one change at a time and re-probe after each.

Two upstream traps are expected and should not be chased as local bugs: capture
permission is lost on screen lock, and `-pipewire` has open flicker reports.

## 8. Steam Frame readiness

Prepare only. No Frame-specific configuration is written in this cycle.

Preparation: confirm SteamVR launches and renders correctly under niri now,
using the Quest through the §6e switcher as a stand-in.

Open questions to answer on day one with the hardware:

- Does host streaming to the Frame require SteamVR running on the host, or does
  the Steam client stream VR without it?
- Does the bundled 6 GHz adapter have a driver outside SteamOS? Its chipset is
  not published. The machine has no other radio, so this is the only wireless
  path to it.
- Note the topology is the reverse of the obvious guess: the **headset** creates
  the hotspot and the **PC** joins it using the bundled adapter.

## 9. Order of work

1. §6f — pin the gamescope shim.
2. §6g — adopt the Sunshine wrappers.
3. §7 — baseline probe (steps 1 and 2 first so the probe measures a known tree).
4. §6a — `-pipewire` flag; re-probe.
5. §6b — portal pin; re-probe.
6. §6h — resolve the capture geometry question raised by the probe.
7. §6c / §6d — only if the probes still fail.
8. §6e — VR runtime switcher.
9. §8 — Frame readiness checks.

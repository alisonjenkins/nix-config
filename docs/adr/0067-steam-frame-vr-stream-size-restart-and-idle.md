# 0067. Size VR streams for a headset's virtual screen, resume them after a restart, hold off idle while streaming

- Status: Accepted, pending live test with the Steam Frame
- Date: 2026-11-28

## Context

The Steam Frame is assumed to stream PC games over the same SteamVR Link
path that [0025](0025-steam-link-vr-stream-lifecycle.md) was written for with
a Quest 2. That is unconfirmed: no Frame session's logs had been examined
when this was written. Reading stream-mode against the Quest path showed
three gaps. See "Confirmed and assumed" below for which claims rest on what.

- **Size.** A headset never reports a size to Steam, so a VR stream with
  nothing learned ran the `steam` output at `defaultWidth`x`defaultHeight`,
  the Deck's 1280x800. A flat game in the headset's 16:9 virtual screen got
  a 16:10 picture at Deck resolution.
- **Restart.** A headset announces itself with `Received streaming request`,
  not a connect line, so `connected_client` never finds it, and
  `stream_in_progress` looks only for Remote Play markers. A `just switch`
  during a VR session left the game unmanaged until SteamVR restarted.
  0025 listed this as a consequence.
- **Idle.** stasis locks at 900s and powers the monitors off at 330s. Its
  `inhibit_apps` match window app ids over niri IPC, so a running
  `steam_app_*` game holds it off, but SteamVR's menus, the Frame's library
  and a Remote Play session in Big Picture do not. A locked desktop streams
  as black.

## Decision

- A VR stream with nothing learned for its headset uses `vrDefaultWidth` x
  `vrDefaultHeight` (1920x1080), fitted inside the client's limit like any
  other size. A learned size still wins. Remote Play streams keep the old
  default. `Session.stream_size` is the one place this is decided, for
  `begin_stream`, `note_max_capture` and the reload path.
- On start, when no Remote Play stream is open and Steam is running,
  `resume_vr_stream` resumes a VR stream if `vrserver` is running, the
  streaming log's last capture was a `>>> Starting desktop stream` with no
  Remote Play session open around it, and the connections log has a
  streaming request to name the headset.
- Every stream holds `org.freedesktop.ScreenSaver.Inhibit` on the session bus
  from `begin_stream` until `end_stream`. stasis watches for that call as a
  bus monitor and keeps the hold until `UnInhibit` or until the sender
  disconnects, so the open connection is the hold. The call is sent without
  waiting for a reply, because nothing need own the name for stasis to see
  it. jeepney supplies the D-Bus client.

## Alternatives rejected

- **`systemd-inhibit --what=idle`.** stasis 1.1.0 does not read logind
  inhibitor locks at all: its login1 code only watches sleep and lock
  signals. Upstream's later releases (1.7.0) do read them, but as
  suspend-only holds ("login1 blocking idle inhibitors map to suspend-only
  holds"), so the lock and DPMS steps would still run.
- **Add SteamVR's or Steam's windows to `inhibit_apps`.** That holds idle off
  whenever they are open, not only while streaming. Steam's own window is
  open all day.
- **Hold the inhibitor while a client is connected.** A phone or a Mac stays
  connected between streams, and the Frame's Steam client may too.

## Consequences

- A VR stream's output is larger by default, which costs some encode time.
  Lower it with `vrDefaultWidth`/`vrDefaultHeight`.
- The resume guess can be wrong when SteamVR was left running after the last
  VR session and its desktop stream was the last capture. The stream then
  comes back until SteamVR exits, which is the behaviour 0025 already accepts
  for a running SteamVR.
- With no session bus, or jeepney missing, streaming carries on without the
  hold and the journal says `could not hold an idle inhibitor`.
- `respect_idle_inhibitors` in `stasis.rune.nix` is a key stasis 1.1.0's
  config migration drops (`src/config/migrate.rs`). Session-bus inhibits are
  on by default (`enable_dbus_inhibit`, `src/config/mod.rs`).

## Confirmed and assumed

Confirmed, from source or a run:

- stasis 1.1.0 (read at tag `v1.1.0`) honours `org.freedesktop.ScreenSaver`
  `Inhibit` seen as a bus monitor, clears it when the sender disconnects,
  has session-bus inhibits on by default, matches `inhibit_apps` against
  window app ids from `niri msg windows`, and ignores logind idle locks.
- The root `nixpkgs` input packages stasis 1.1.0. That ali-desktop's
  home-manager takes stasis from that input, and not an overlay, was not
  checked in an evaluated build.
- stasis' lock (900s) and DPMS (330s) timeouts and `inhibit_apps`, from
  `stasis.rune.nix`.
- `hold_idle_inhibit` sends the call with nothing owning the name
  (`dbus-monitor`, below).
- stream-mode's size, resume and teardown behaviour, from its code and tests.

Assumed, not yet seen on the Frame or on ali-desktop:

- The Frame uses the SteamVR Link path, logs `>>> Starting desktop stream`
  for a flat game, announces itself with `Received streaming request`, and
  never reports its size. All of this comes from the Quest 2 in 0025.
- The Frame's virtual screen is 16:9, and 1920x1080 is a good default for it.
- A locked desktop streams as black. This was reported by other Frame users
  and has not been observed here.
- SteamVR's menus, the Frame's library and Big Picture have no window whose
  app id matches `inhibit_apps`, and games show as `steam_app_*`.
- A restart mid-VR-session leaving the game unmanaged was read from the code,
  not observed.

## Evidence

- `stasis` 1.1.0 (the version in the root nixpkgs input,
  `pkgs/by-name/st/stasis/package.nix`): `spawn_dbus_inhibit_monitor` in
  `src/services/dbus.rs` calls `BecomeMonitor` and tracks
  `org.freedesktop.ScreenSaver` `Inhibit`/`UnInhibit` per sender, clearing
  on `NameOwnerChanged`. Nothing in that file lists logind inhibitors.
- `dbus-run-session` with `dbus-monitor`, 2026-11-28: `hold_idle_inhibit`
  sent `method call ... interface=org.freedesktop.ScreenSaver;
  member=Inhibit string "stream-mode" string "streaming to frame"` with
  nothing owning the name.
- Tests in `tests/test_stream_mode.py`:
  `test_a_vr_stream_with_nothing_learned_uses_the_vr_size`,
  `test_a_config_reload_mid_vr_stream_keeps_the_vr_size`,
  `test_a_vr_stream_fits_its_size_inside_the_clients_limit`,
  `TestResumeVrStream`, `test_a_stream_holds_off_the_lock_screen`,
  `test_ending_a_stream_releases_the_inhibitor`,
  `test_steamvr_exiting_releases_the_inhibitor`, `TestIdleInhibitMessage`.

## Revisit when

The Frame's logs show it reports a size (a `CLIENT: Video size` line), or show
that its flat streams are Remote Play sessions. Also revisit if stasis stops
honouring ScreenSaver inhibits, or if the journal shows a stream that locked
anyway.

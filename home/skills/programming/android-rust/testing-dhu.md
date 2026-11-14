# Testing with the Desktop Head Unit (DHU)

Pharos: `specs/044-android-auto/spike-0.md`. Official docs:
developer.android.com/training/cars/testing/dhu. The DHU emulates a car
screen on the desktop and talks to Android Auto on a real phone.

## adb rules

- Use **one adb binary**. Two versions on one desktop restart each other's
  server, dropping wireless connections and port forwards.
- Always `adb -s <serial> ...`.
- Never kill or restart an adb server other work shares.
- Probe: `command -v adb`; use that one for every call.

## Wireless debugging

Android 11+ needs a one-time pairing first. On the phone open Developer
options → Wireless debugging → "Pair device with pairing code":

```bash
adb pair <phone-ip>:<pairing-port>      # enter the six-digit code
adb connect <phone-ip>:<connect-port>   # the port on the Wireless debugging screen
adb devices                             # copy the serial for -s
```

The pairing and connect ports differ, and the connect port changes. Read it
from the Wireless debugging screen. Without the screen to hand, and with
mDNS discovery unsupported, scan the ephemeral range:

```bash
nmap -Pn -p 30000-60999 --open <phone-ip>
# not installed:  nix run nixpkgs#nmap -- -Pn -p 30000-60999 --open <phone-ip>
```

## Phone setup (Android Auto developer settings)

1. Open Android Auto settings, tap the version row repeatedly to enable
   developer mode.
2. In its developer settings: turn on "Unknown sources" (so a sideloaded
   app is listed).
3. Menu (three dots): "Start head unit server".
4. First connection: accept the car setup on the phone. Until accepted,
   Android Auto logs `Triggering FRX: car connection is not allowed`.

## Connect

```bash
adb -s <serial> forward tcp:5277 tcp:5277
bash "$HOME/.local/share/android-dhu/dhu"   # the launcher below; off NixOS ./desktop-head-unit
```

The DHU connects to `localhost:5277` by default, so forward that port.

Wedged head unit server: after a dropped session it can throw
`IllegalStateException: Already connected`. On the phone, stop the head
unit server from Android Auto's menu and start it again, then re-run the
DHU.

## NixOS launcher

The DHU is a prebuilt binary. On NixOS run it in an FHS env (`steam-run`)
with libc++ from nixpkgs. The host PipeWire ALSA plugin needs a newer glibc
than the FHS env has, so point ALSA at the FHS `alsa.conf` plus a small conf
that maps the plugin to the FHS copy.

`$HOME/.local/share/android-dhu/dhu`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# DHU_DIR: the extras/google/auto directory of your SDK install
d=${DHU_DIR:-$HOME/.local/share/android-dhu/extras/google/auto}
cxx=$(nix build --no-link --print-out-paths nixpkgs#llvmPackages.libcxx)
cd "$d"
export ALSA_CONFIG_PATH="/usr/share/alsa/alsa.conf:$HOME/.local/share/android-dhu/alsa-pipewire.conf"
LD_LIBRARY_PATH=$cxx/lib:$d exec steam-run ./desktop-head-unit "$@" 2> >(grep -v 'LD_PRELOAD' >&2)
```

`$HOME/.local/share/android-dhu/alsa-pipewire.conf`:

```
pcm_type.pipewire.libs.native "/usr/lib64/alsa-lib/libasound_module_pcm_pipewire.so"
ctl_type.pipewire.libs.native "/usr/lib64/alsa-lib/libasound_module_ctl_pipewire.so"
```

The DHU unpacks under `extras/google/auto` (SDK Manager "Android Auto
Desktop Head Unit Emulator"). Off NixOS, run `./desktop-head-unit` there.

## No audio

Two causes seen together on NixOS:

1. The DHU's ALSA output failed under `steam-run`. The launcher above fixes it.
2. The phone's media volume was near zero. The DHU plays at the phone's
   volume, so raise it (`adb -s <serial> shell cmd media_session volume --stream 3 --set <n>`, or the buttons).

If another media app plays through the DHU and yours does not, the fault is in your app's session or focus.

## Offline testing

Airplane mode kills the wifi that the DHU link rides on, so the session
drops. Use a debug-only switch in the app instead. Pharos
(`crates/pharos-android/src/debug.rs`) registers a receiver in code, for the
service's life, with `RECEIVER_EXPORTED` (2) because the shell is another app:

```bash
adb -s <serial> shell am broadcast -a com.alisonjenkins.pharos.auto.DEBUG_OFFLINE --ez on true
adb -s <serial> shell am broadcast -a com.alisonjenkins.pharos.auto.DEBUG_OFFLINE --ez on false
adb -s <serial> shell am broadcast -a com.alisonjenkins.pharos.auto.DEBUG_OFFLINE --el cap_bytes 1048576
```

- `--ez on true|false`: make the server unreachable, or restore it.
- `--el cap_bytes N`: set the cache cap. Use `--el` (long). `--ei` reads as
  the `-1` default and is ignored.
- Ship it as debug-only behaviour; the worst a caller can do is make the app
  act offline or shrink its cache.

## logcat

```bash
adb -s <serial> logcat -d --pid=$(adb -s <serial> shell pidof <package>)
```

- `pidof` fails if the process is dead; start the app (or bind the
  service) first.
- Every JNI entry logs a line with ids, so a grep proves each hop reached
  Rust.
- Look for `VerifyError`, `UnsatisfiedLinkError`, `ClassNotFoundException`.
  The first successful DHU run had none.
- Browsing from the car logs `onGetRoot package=com.google.android.projection.gearhead`.

## Checklist (spec task T28)

Locked-screen play, notification actions, unplug headphones, focus loss,
resume, offline, pin then browse offline.

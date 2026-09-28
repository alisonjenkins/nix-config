# Hardware video on ali-mba-linux

`ali-mba-linux` (M1 MacBook Air, t8103, NixOS on Asahi) has hardware video
**decode** configured for H.264, HEVC and VP9. There is no hardware **encode**.
Decode is experimental upstream and has not been tested on this machine yet.

Why it is set up this way is in
[ADR 0017](adr/0017-ali-mba-linux-avd-vaapi.md).

## What the hardware can do

| Block | On M1 | Linux status (2026-09) |
|---|---|---|
| AVD, Apple Video Decoder | H.264, HEVC, VP9 | Works in the Asahi kernel. Experimental VA-API layer on top |
| AV1 decode | Not on M1 | M3 and later only |
| AVE, Apple Video Encoder | Present | Not supported, and nobody is working on it |
| ProRes engine | Not on M1 | Only on M1 Pro/Max/Ultra |

Sources: the Asahi [M1 feature support page](https://asahilinux.org/docs/platform/feature-support/m1/)
and the [7.2 progress report](https://asahilinux.org/2026/08/progress-report-7-2/).

## How the pieces fit

1. **Firmware.** `avd-fw` is a small replacement firmware written by the
   Asahi developer Sofus Forstreuter. It only sets up interrupts and applies
   per-chip tuning. nixos-apple-silicon installs it through
   `hardware.asahi.avd.enable`, which defaults to on.
2. **Kernel driver.** The Asahi kernel exposes AVD as a V4L2 stateless
   (Request API) decoder. It is also posted to linux-media for upstream review.
3. **VA-API layer.** Apps do not speak V4L2 stateless. They speak VA-API.
   `libva-v4l2_request-sofus13` translates between the two.
   `hardware.asahi.avd.vaapi-support = true` installs it and sets
   `LIBVA_DRIVER_NAME=v4l2_request-sofus13` for the whole session.
4. **Apps.** mpv, Chromium and GStreamer use VA-API. Firefox cannot yet: its
   sandbox blocks this path.

## What this repo sets

Both lines are in `flake-modules/hosts/ali-mba-linux/default.nix`:

- `hardware.asahi.avd.vaapi-support = true;` turns on the VA-API layer.
- An overlay line, `avd-fw = final.master.avd-fw`, takes the firmware from
  nixpkgs master. This repo builds from nixos-26.05, which does not have
  `avd-fw`. Without the overlay the host fails to evaluate with
  `error: attribute 'avd-fw' missing`. **Drop the overlay once 26.05 has
  `avd-fw`.**

The PR check evaluates every aarch64 host, so a nixpkgs or
nixos-apple-silicon bump that breaks this fails the PR instead of landing
on main.

## Testing it

Run these on the MacBook after `just switch` and a reboot. None of them have
been run on this machine yet, so record what you see.

1. **The driver loads.** `vainfo` should name the `v4l2_request-sofus13`
   driver and list H.264, HEVC and VP9 decode profiles. An error about
   `v4l2_request-sofus13_drv_video.so` means the VA-API layer is missing;
   check `echo $LIBVA_DRIVER_NAME` in the same shell first.
2. **mpv decodes on the hardware.**
   ```bash
   mpv --hwdec=vaapi --vo=dmabuf-wayland file.mkv
   ```
   Both flags are needed. mpv's default output (`gpu-next`) does not work
   with this path yet. Watch the terminal for the line saying hardware
   decoding is in use, and compare CPU use in `htop` against `--hwdec=no`.
   Test one H.264, one HEVC and one VP9 file.
3. **Chromium.** Play something on YouTube. Known bug:
   [AsahiLinux/linux#628](https://github.com/AsahiLinux/linux/issues/628),
   green frames or stalled playback on H.264 from a memory allocation
   failure in `avd_init_job`. It was open on 2026-09-28. If you see it,
   `dmesg` should show the allocation failure.

## Known problems

| Problem | Cause | Status |
|---|---|---|
| Green frames or stalls in Chromium, H.264 | Allocation failure in the kernel driver (#628) | Open upstream |
| Firefox uses software decode | Firefox's sandbox blocks this path | Upstream, no fix yet |
| mpv hardware decode needs `--vo=dmabuf-wayland` | Interaction with mpv's `gpu-next` output | Use the flag |
| No hardware encode (OBS, screen recording, video calls) | AVE has no driver | Not being worked on |

## Contributing upstream

Asahi [bans generative-AI contributions](https://asahilinux.org/llm-policy/):
AI-drafted issues are closed, and using an AI to read m1n1 traces earns a
final warning. Write test reports, issue comments and `Tested-by:` tags
yourself.

The useful contribution from this machine is an M1 test report. The
nixos-apple-silicon module
([nix-community/nixos-apple-silicon#544](https://github.com/nix-community/nixos-apple-silicon/pull/544))
was only tested on an M2. Report results on #544 and #628, or in
`#asahi-dev` on OFTC IRC.

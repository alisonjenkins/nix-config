# 0017. Expose the M1 video decoder through VA-API, with avd-fw from master

- Status: Accepted, pending live test
- Date: 2026-09-26, commits `37bbda1c` and `64daa992` (PR #389)

## Context

The Asahi kernel drives the M1's video decoder (AVD) as a V4L2 stateless
decoder for H.264, HEVC and VP9. Apps such as mpv and Chromium reach hardware
decode through VA-API, not V4L2 stateless, so the kernel support alone
decodes nothing for them.

nixos-apple-silicon added a module for this on 2026-09-13
([#544](https://github.com/nix-community/nixos-apple-silicon/pull/544)).
`hardware.asahi.avd.enable` defaults to on and installs `pkgs.avd-fw`.
`hardware.asahi.avd.vaapi-support` defaults to off and adds
`libva-v4l2_request-sofus13`, a VA-API layer over V4L2 stateless. The author
tested it on an M2 (t8112) only.

`avd-fw` reached nixpkgs master on 2026-09-07
([NixOS/nixpkgs#560770](https://github.com/NixOS/nixpkgs/pull/560770)).
This repo builds from nixos-26.05, which does not have it. Once the flake
lock picked up #544, `ali-mba-linux` failed to evaluate on main:

```
error: attribute 'avd-fw' missing
```

Nothing noticed, because no CI job evaluated aarch64 hosts.

## Decision

In `flake-modules/hosts/ali-mba-linux/default.nix`, a host-only overlay
takes `avd-fw` from `pkgs.master`, and `hardware.asahi.avd.vaapi-support`
is on. The PR check (`.github/scripts/pr-check-x86_64-linux.sh`) now
evaluates every aarch64-linux host, so the next break of this kind fails a
PR instead of landing.

## Alternatives rejected

- **Turn `hardware.asahi.avd.enable` off.** Fixes the evaluation by removing
  the feature this machine is here to test.
- **Take `avd-fw` from `pkgs.unstable`.** This host does not load the
  unstable overlay, and adding it imports another nixpkgs. `pkgs.master` is
  already loaded here, and `avd-fw` is a small firmware blob with no
  dependency churn to worry about.
- **Put the overlay in a shared module.** `ali-mba-linux` is the only host
  that imports nixos-apple-silicon.
- **Leave `vaapi-support` off.** Then the decoder is present but unused, and
  this machine produces no M1 test report, which is the point of the exercise.

## Consequences

- `LIBVA_DRIVER_NAME` is set for the whole session. That is safe here: the
  Apple GPU driver has no VA-API driver for it to hide.
- mpv needs `--hwdec=vaapi --vo=dmabuf-wayland`. Firefox cannot use this
  path yet because of its sandbox.
- The overlay goes stale once 26.05 carries `avd-fw`. It stays harmless
  until then and afterwards, but should be removed.
- Hardware encode (AVE) is not covered and has no driver upstream.

How to test it and what to expect: [`docs/ali-mba-linux-hardware-video.md`](../ali-mba-linux-hardware-video.md).

## Evidence

- `nix build --dry-run` of the toplevel failed at main's commit `df5475bd`
  with the error above, and succeeded with the overlay. The plan then
  included `avd-fw-0.1` and `libva-v4l2_request-sofus13-1.3`.
- With the overlay removed, `just check` reports
  `FAILED: nixosConfigurations.ali-mba-linux` with the same error (PR #404).
- Not yet run on the machine: `vainfo`, mpv and Chromium decode.

## Revisit when

- nixos-26.05, or the release after it, has `avd-fw`: drop the overlay.
- On-device testing shows `vaapi-support` breaks playback here: turn it off
  and record why.
- nixos-apple-silicon makes `vaapi-support` default on: the line becomes
  redundant.

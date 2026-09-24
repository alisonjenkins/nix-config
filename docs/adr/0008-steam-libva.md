# 0008. Give Steam a newer libva, and only Steam

- Status: Accepted
- Date: 2026-08-25, commit `8451c7a1` (recorded 2026-09-24)

## Context

Remote Play streamed with no hardware encoding at all. Steam's FHS root takes
libva from the base package set, which shadows the libva that
`hardware.graphics.extraPackages32` puts in the same tree. mesa is taken from
nixpkgs master, and its radeonsi VAAPI driver exports
`__vaDriverInit_1_24`. The base set's libva 2.23 only probes down from
`__vaDriverInit_1_23`, finds no init symbol, and every hardware encoder fails.

## Decision

Steam's package is built from `pkgs.extend` with libva taken from master, in
`flake-modules/hosts/ali-desktop/default.nix`. Nothing else changes.

## Alternatives rejected

- **Override libva globally.** libva sits under ffmpeg, vlc, wine, libreoffice
  and vtk among others. Replacing it system-wide rebuilds all of them from
  source for a fault that only Steam's private FHS has.

## Consequences

When mesa and the base set's libva line up again, this override becomes
redundant but harmless.

## Evidence

`streaming_log.txt` shows the capture method; hardware encoding appears as
`VAAPI H264`.

## Revisit when

The base package set's libva understands the driver init version mesa exports.

# 0010. Keep comments out of niri's KDL, validate the built config

- Status: Accepted
- Date: 2026-09-24

## Context

niri's config is KDL, generated from Nix strings in
`home/programs/linux-only/niri/module.nix` and host files such as
`custom.niri.extraOutputs`. A comment written Nix-style (`#`) inside one of
those strings made the whole file fail to parse:

```
Error: × found `/`, expected `)` or letter
```

**niri does not tell you.** On a bad config it keeps running the last good one
and logs the error. Every niri change after that commit looked applied but was
not, including DP-2's position pin, and nothing on screen said so. It was
caught by accident, while validating an unrelated change.

## Decision

- Explanations go in Nix comments above the string, never inside it. KDL's
  comment syntax is `//`, but a Nix comment keeps the explanation next to the
  Nix that produces the line.
- After any change to niri config, validate the built file before switching:

```
nix build --no-link --print-out-paths \
  '.#nixosConfigurations.ali-desktop.config.home-manager.users.ali.xdg.configFile."niri/config.kdl".source'
niri validate -c <that path>
```

Use the `niri` binary the session runs. Virtual output support is a patch,
and stock niri rejects `virtual-output`.

## Consequences

To check the live config: `niri validate -c ~/.config/niri/config.kdl`.

## Evidence

The deployed config failed `niri validate` on 2026-09-24. The fixed one
passes.

## Revisit when

niri's config becomes typed Nix options with a generator that cannot emit
invalid KDL. A build-time `niri validate` check would also retire the manual
step.

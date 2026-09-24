# 0009. Let bubblewrap run under gamescope's capabilities

- Status: Accepted
- Date: 2026-01-17 (recorded 2026-09-24)

## Context

`programs.gamescope.capSysNice` puts `CAP_SYS_NICE` in gamescope's ambient
set, so gamescope and the game it wraps can use realtime scheduling. Every
descendant inherits it, including the bubblewrap that Steam's pressure-vessel
and umu use for their containers. bubblewrap refuses to run with capabilities
it did not expect:

```
bwrap: Unexpected capabilities but not setuid, old file caps config?
```

With the steam-command-runner shim, gamescope is outside pressure-vessel in
the launch chain, so pressure-vessel's bubblewrap starts with the capability.

## Decision

- **Steam:** a patched bubblewrap (`patches/bubblewrap-allow-caps.patch`)
  removes that check. It is added to Steam's FHS and pointed at with `BWRAP`,
  and the FHS gets `--cap-add ALL`.
- **Heroic and umu:** `umu-run` is wrapped in `overlays/default.nix` to drop
  its ambient and inheritable capabilities with `setpriv` before starting. A
  GOG or Epic title launched as `gamescope ... -- umu-run game.exe` died at
  that error before Proton started.

## Alternatives rejected

- **`capSysNice = false`.** Loses realtime scheduling for gamescope and the
  game everywhere, to fix a check in one sandbox tool.

## Consequences

- The Steam fix is a patch on bubblewrap. Check it still applies when nixpkgs
  bumps bubblewrap.
- The reasoning for the Steam half is reconstructed from the patch and the
  umu comment. The original commit, `46a01604`, has no body.

## Evidence

The error text above, and the comment on the `umu-launcher` override in
`overlays/default.nix`.

## Revisit when

bubblewrap tolerates inherited ambient capabilities, or gamescope stops
needing `CAP_SYS_NICE`.

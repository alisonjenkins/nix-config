# 0042. Run the control-centre web view as a user service on every machine

- Status: Proposed
- Date: 2026-10-13

## Context

`claude-monitor serve` is the web view of the control centre (ADR 0040). Until
now it ran only when started by hand, so the store went stale between runs.
Two facts made that matter:

- The Claude Code hooks installed by `programs.claude-monitor.enable` feed the
  store, but process death, a vanished tmux pane and a changed Claude registry
  entry are noticed only by the live refresh loop that `serve` and `watch`
  run (`src/live.rs`). With neither running, `list` and `restore` show state
  from the last time something refreshed it, which is what a reboot plan is
  built from.
- The module's `serve.enable` created a systemd user unit only. macOS had no
  equivalent, and there was no way to ask for mutual TLS.

Port 8765, the module default, is already taken on ali-desktop by
DynamoDB Local (the old `serve` also held 8800), so the default cannot be
used there.

## Decision

Enable `programs.claude-monitor.serve` for every machine through
`home/programs/claude-code/default.nix`, which `home/programs/default.nix`
imports on all home-manager profiles.

- **Linux:** the existing systemd user unit `claude-monitor-serve`.
- **macOS:** a new launchd agent `claude-monitor-serve` with `RunAtLoad` and a
  restart-on-exit policy, logging to
  `~/Library/Logs/claude-monitor-serve.log`. Both platforms build the command
  line from one shared list in `nix/hm-module.nix`, so they cannot drift.
- **Port:** 8801 (`serve.port`), not the 8765 default.
- **mTLS:** on for Linux (`serve.mtls = true`) together with
  `web.browserSetup` limited to `zen`, the browser in use. Off on macOS,
  where `web setup-browser` has no implementation (it imports into NSS
  databases), so a client certificate requirement would lock the user out.
  macOS relies on TLS 1.3 plus the single-use login code.
- **`watch` stays off.** `serve` runs the same live loop, so a second service
  would only duplicate the work.
- **Flake input:** `claude-monitor` follows the default branch. It followed
  the `008-ai-control-centre` branch while the claude-monitor pull request
  that carries this work (alisonjenkins/claude-monitor#9) was open; that
  merged on 2026-10-14 and the lock is `e549c727`.

Activation (`just switch`, `home-manager switch`) stays the user's call.

## Alternatives rejected

- **`watch` as the always-on service, `serve` on demand.** It keeps the store
  fresh without a listening socket, but then the web view needs a manual start
  every time and the user asked for it to be always available.
- **mTLS on macOS by hand-importing a certificate.** Keychain import is not
  automated, so a machine could be switched on and unreachable. Deferred
  until `setup-browser` supports it.
- **Keep the 8765 default.** Fails to bind on ali-desktop, so the service
  would restart-loop.
- **A per-host opt-in.** The point of the service is that the store is fresh
  on whichever machine the sessions run, which is every machine.

## Consequences

- A loopback listener runs on each machine, reachable only by the same user.
  TLS and mTLS do not protect against malware running as that user: the
  client key sits in the browser profile and the control socket is user-owned.
- The login URL is printed to the journal (Linux) or the log file (macOS) at
  each start and is valid for five minutes; `claude-monitor web login` asks the
  running service for a new one.
- A `serve` started by hand on 8801 blocks the service from binding. Stop it
  before the first switch.

## Evidence

- Port clash: DynamoDB Local on 8765 on ali-desktop, as reported by the
  user; not checked against a running system, and not a repo file.
- The mTLS flow and `setup-browser` import into the Zen profile
  `~/.config/zen/ali` were exercised by hand on 2026-10-13: the handshake
  failed with `SSL_ERROR_RX_CERTIFICATE_REQUIRED_ALERT` before the import and
  worked after it.
- The module changes and their evaluation checks for x86_64-linux and
  aarch64-darwin are in the claude-monitor pull request (alisonjenkins/
  claude-monitor#9).
- The macOS agent has not been run on a Mac; it is evaluated, not started.
  The claude-monitor CI builds and tests the crate on macOS (aarch64-darwin),
  including the new macOS boot-id and process start-time code, and passed
  before the merge.

## Revisit when

- `web setup-browser` can import into the macOS keychain: turn mTLS on there.
- A machine shows the service restart-looping or holding the port when idle.

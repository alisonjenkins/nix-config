---
name: deploy
description: Build then deploy hosts to remote machines via deploy-rs. Use when user
  runs /deploy, says "deploy <host>", "deploy the servers", or "roll out to all".
argument-hint: "[boot|switch] <host|group ...>"
---

# /deploy — build, then deploy-rs

Args required; no default host. Read `.claude/skills/build/SKILL.md` first — host
registry, groups, build procedure, and debug loop all come from there.

## Activation mode

Optional first arg `boot` or `switch` forces that mode for all targets. Otherwise
per-host default:

- `servers` hosts (download-server-1, home-kvm-hypervisor-1, home-storage-server-1,
  home-k8s-master-1) → **boot**: many server changes don't apply cleanly live; config
  takes effect on next reboot.
- everything else (ali-desktop, laptops, ali-steam-deck) → **switch** (live activation).

After boot-mode deploys: do NOT reboot hosts. List them under "pending reboot" in the
final report — user reboots when convenient (k8s drain, storage quiesce, etc.).

## Validate targets

A target is deployable iff it has a node in `flake-modules/deploy.nix` (currently the 9
"deploy node: yes" hosts). That file is ground truth — grep it if unsure. Reject anything
else by name with the reason:

- darwin hosts (ali-mba, Alisons-MacBook-Pro): not deploy-rs nodes — user activates on
  the Mac with `just switch`.
- home configs, dev-vm, installer-iso, home-vpn-gateway-*, home-k8s-server-1: no node.

`/deploy ali-desktop` IS sanctioned for the local machine: node is root@100.127.142.30
(tailscale), activates without local sudo. deploy-rs magic-rollback covers a bad
activation.

## Phase 1 — build everything first

Run the /build procedure for ALL targets (background builds, debug loop, 5-iteration
cap, git add for new files, no commits). Do not start any deploy until phase 1 is done —
deploying while another host's fix is in flight risks shipping broken shared modules.

## Phase 2 — deploy green hosts only

Sequential, one node at a time:

    just deploy ".#<node>" "-s"            # switch mode (live activation)
    just deploy ".#<node>" "-s" "--boot"   # boot mode (activates on next reboot)

- `-s` = `--skip-checks`: skips `nix flake check` (this flake's checks include
  ami/hetzner/emulation test VMs — far too heavy). Safe: phase 1 already built the exact
  closure, so deploy is copy + activate.
- switch mode: deploy-rs auto-rollback + magic-rollback are on by default — a deploy
  that breaks ssh rolls itself back. Boot mode: nothing changes live, so rollback
  protection doesn't apply; bad config surfaces at next reboot.
- NEVER deploy a host whose build failed. Skip it, say so.

Deploy failures:
- unreachable / ssh timeout → retry once, then mark SKIPPED-unreachable. Don't debug
  the network.
- activation failure (rolled back) → read deploy-rs output, fix config, rebuild that
  host, redeploy. Counts toward the same 5-iteration cap.

Hard rules: never `git commit`/`git push`. Never sudo. Leave fixes uncommitted.

## Final report

| host | build | deploy | mode | notes |

Then **Pending reboot**: boot-mode hosts that deployed OK — config applies on next
reboot, user reboots them.
Then **Fixes made** (file → one-liner) + reminder that changes are uncommitted.

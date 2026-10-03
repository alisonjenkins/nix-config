# Implementation Plan: Patch the Hetzner control plane without interrupting calls

**Branch**: `docs/hetzner-inplace-patching` | **Date**: 2026-10-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-hetzner-inplace-patching/spec.md`

## Summary

The control-plane machine is patched in place and rebooted while calls and chat keep running, because
everything a call needs runs on a separate, small, always-on edge machine. The edge machine is patched
only between calls.

The approach, from `research.md`:

1. Make a reboot actually apply an in-place update. Today the image's hand-built GRUB always starts
   the image's original generation, so NixOS's own GRUB is enabled and proven on a disposable server
   first.
2. Make a bad update fall back by itself: a one-shot boot of the new generation, a health check, then
   a permanent switch, and a hard reset that boots the previous generation if it never comes up.
3. Patch with deploy-rs `--boot` and a scripted reboot, with gates and a record. The control-plane
   reboot includes answering the state-volume unlock prompt, with the owner's approval and passphrase.
4. Create the edge machine in Terraform, then move the Matrix stack, the database, the ingress and the
   floating IP onto it, one step at a time in no-call windows.
5. Stop Terraform replacing servers when a new image appears.
6. Prove it with the real test: reboot the control plane during a test call.

Terms: "edge machine" and "edge node" in this plan and the tasks mean the spec's "call machine".

This feature lands after `specs/004-hetzner-encrypted-volumes/`, so the edge machine only ever holds
encrypted volumes, and it reuses that feature's no-call check.

## Technical Context

**Language/Version**: Nix for the NixOS configuration, the deploy-rs nodes and the bootloader. Bash for
the patch scripts, run through a Nix dev shell. HCL for Terraform. YAML for Flux manifests.

**Primary Dependencies**: deploy-rs (locked revision, supports `--boot`). NixOS GRUB for BIOS with a
saved default and `grub-reboot`. Tailscale for reaching the machines. The Hetzner Cloud API for the
hard reset and snapshots. Terraform with the Hetzner provider. Flux. Cilium. Envoy Gateway. CloudNativePG.

**Storage**: the master's LUKS state volume (unchanged). Encrypted Hetzner volumes for Matrix data
(from spec 004).

**Testing**: `bats` for the scripts, with stubbed tools, written first. `nix build` of the target
closure and `nix flake check`. A disposable Hetzner server from the same snapshot for every boot-path
rehearsal. `tofu plan` for Terraform. A real test call for acceptance.

**Target Platform**: Two NixOS servers on Hetzner `nbg1`, BIOS boot, one k3s cluster.

**Project Type**: Infrastructure change across three repositories (see Project Structure).

**Performance Goals**: Call machine back within 10 minutes of its patch (SC-009). Failed patch undone
within 15 minutes (SC-006). Services other than calls and chat back within 10 minutes of a control-plane reboot
(SC-008). No media freeze over 5 seconds during a control-plane reboot (SC-001).

**Constraints**: Call-machine patches on weekday daytime with no call. Extra running cost at most
€10 a month unless the owner approves more. A control-plane reboot needs the owner's passphrase.

**Scale/Scope**: Two machines, about 15 pods moved, one database, one floating IP.

Unknowns from the template are resolved in `research.md`. The unproven points are Phase A rehearsals.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result | How the plan meets it |
|---|---|---|
| I. Atomic, revertable history | Pass | One commit per task. Each repository lands through its own pull request. No squash, no AI attribution. The bootloader change is its own commit and revertible alone |
| II. Test first, evidence before done | Pass | The patch scripts have `bats` tests first. Every boot-path claim is rehearsed on a disposable server and recorded. The acceptance test is the call test |
| III. IaC, live changes by consent | Pass, with consent gates | All changes are made in the repositories and applied by deploy-rs, Flux or `tofu`. The live steps are listed below as consent gates |
| IV. Errors carry context | Pass | The scripts' lines name machine, step and inputs. Tools come from a Nix dev shell |
| V. Right altitude, single source | Pass | The no-call check is reused from spec 004. The edge node's address, taint and label each live in one place and are referenced |
| VI. Record the why | Pass | ADR 0021 is updated with the evidence and moves to Accepted in the same pull request as the first change |
| VII. Fork patches | Not applicable | No fork |

No violations, so Complexity Tracking is empty.

### Consent gates (principle III)

Each changes live state and needs the owner's explicit yes, one per step:

1. Creating the disposable rehearsal servers and volumes (they cost cents).
2. Applying the Terraform change that adds the edge server, its firewall and the lifecycle rule.
3. The first in-place deployment to the master and its first reboot, including the passphrase.
4. Each workload move onto the edge node, in a no-call window.
5. Moving the floating IP.
6. Every control-plane reboot and every call-machine reboot after that.
7. A hard reset through the Hetzner API, if a patch hangs.

## Project Structure

### Documentation (this feature)

```text
specs/003-hetzner-inplace-patching/
├── plan.md                  # This file
├── research.md              # Phase 0: decisions, evidence, unproven points
├── data-model.md            # Phase 1: machines, placement, generations, the patch state machine
├── quickstart.md            # Phase 1: how to prove each phase works
├── contracts/
│   └── patch-gates.md       # Phase 1: the gates and steps of a patch
├── checklists/
│   └── requirements.md      # spec quality checklist
├── evidence/                # the record of each rehearsal, move and patch run
└── tasks.md                 # Phase 2 (/speckit-tasks, not created here)
```

### Source code (three repositories)

```text
nix-config (this repository)
├── lib/hetzner-repart-image.nix            # stop forcing GRUB off for the running system
├── modules/hetzner/default.nix             # NixOS GRUB (BIOS): device, saved default, timeout, configurationLimit
├── lib/hetzner-node-services.nix           # a ROLE=edge branch for the floating IP binding; node label and taint
├── flake-modules/deploy.nix                # deploy-rs nodes for the master and the edge machine
├── flake-modules/hetzner-images.nix        # unchanged build, republished after the bootloader change
├── scripts/hetzner-patch/
│   ├── flake.nix                           # dev shell: deploy-rs, jq, kubectl, awscli, openssh, bats
│   ├── README.md                           # how to run each script
│   ├── check-dns.sh                        # DNS answers from both machines, and two kube-dns endpoints exist
│   ├── patch-node.sh                       # the steps and gates in contracts/patch-gates.md, incl. --first-patch
│   ├── unlock-master.sh                    # answers the state-volume prompt, with owner approval
│   ├── rollback.sh                         # previous generation, hard reset, console and rescue notes
│   └── tests/                              # bats, written first, with stubbed tools
├── docs/hetzner-patching-runbook.md        # how to patch each machine and what to do when it fails
├── docs/adr/0021-patch-hetzner-master-in-place.md   # updated with evidence, then Accepted
└── specs/003-hetzner-inplace-patching/evidence/     # baseline, bootpath, capacity, patch-runs, moves, acceptance, success-criteria

terraform (cloud-account repository, CodeCommit; the real clone is ~/git/terraform)
└── hetzner/
    ├── compute.tf                          # edge server and private-network attachment; ignore_changes = [image]; floating IP assignment
    ├── firewall.tf                         # the edge firewall
    ├── variables.tf                        # edge server type, address and fallback types
    └── outputs.tf                          # edge address and firewall id

home-cluster (GitOps, clusters/hetzner/flux-system/)
├── matrix/helmrelease.yaml                 # selectors, tolerations and pins for Synapse, MAS, haproxy, element-web, the auth service, Valkey, the SFU
├── matrix/sfu-proxy.yaml, sfu-tls-proxy.yaml, rtc-transports-workaround.yaml   # pin to the edge machine
├── matrix/postgres/cluster.yaml            # a second instance on the edge machine, then one
├── envoy-gateway-config/                   # the EnvoyProxy node selector and toleration
└── coredns-edge/                           # a second CoreDNS Deployment sharing the kube-dns label
```

**Structure Decision**: Infrastructure in three existing repositories. The Nix configuration, the patch
scripts, the decision record and the specs live here, which owns the spec-kit setup and the image. The
servers and the floating IP live in the Terraform repository. The workload pins live in `home-cluster`
because Flux applies them.

## Phases and order

Order is fixed by safety: prove the boot path first, then change the machines, then move the stack,
then prove the result. The first phase touches nothing that matters.

| Phase | Work | Gate to leave the phase | Notes |
|---|---|---|---|
| A. Prove on a disposable server | Boot a server from the current snapshot. Enable NixOS GRUB, deploy a new generation with `--boot`, reboot, and confirm it boots the new one. Rehearse the one-shot fallback with a deliberate hang and a hard reset. Rehearse the unlock script against a throwaway LUKS volume. Check memory and CPU headroom for the edge type from current usage | The boot path, the fallback and the unlock each work, or the plan switches to the fallback bootloader | no cost beyond cents |
| B. Nix changes | Bootloader module, the edge role in the node services, deploy-rs nodes, the patch scripts and their tests. Rebuild and publish the image | Scripts pass their tests. The closure builds. `nix flake check` is clean | the image only matters for new servers |
| C. Terraform and the edge machine | Add the edge server, its network attachment, firewall and placement, from the republished image. Add `ignore_changes = [image]` to both servers. Bootstrap the fresh edge server with the first `patch-node.sh` run | `tofu plan` adds only the edge resources and the lifecycle rule. After approval it applies. The edge node joins as `Ready` | one-time capacity risk: pick the fallback type if `cx23` is refused |
| D. First in-place patch of the master | Take the pre-patch snapshot. Register the running system as generation 1. Deploy the bootloader change with `--boot` in `--first-patch` mode (the Matrix stack has not moved yet). Reboot with the unlock, in a no-call window, and confirm it returns healthy. Make it permanent | The master runs a NixOS-managed generation, and the fallback works. SC-005 and SC-006 shown for the master | this is the first live reboot test, with every other service down for minutes |
| E. Move the stack | In the order of `data-model.md`: CoreDNS, Valkey, Postgres, the Matrix pods, the SFU group, the Envoy data plane. Then the floating IP | A test call works from the edge node. Edge pods have their tolerations | each step in a no-call window with the no-call check |
| F. Prove it | Reboot the master during a real test call | SC-001, SC-002 and SC-008 met. The call and chat do not drop | the real acceptance test |
| G. Close | Patch the edge node between calls, with the gate. Update the ADR and runbook | SC-004 shown. The ADR is Accepted | |

## Risks and mitigations

| Risk | Effect | Mitigation |
|---|---|---|
| `grub-install` fails or leaves the disk unbootable | A server that does not boot | Phase A on a disposable copy first. A snapshot before the first live use. Fallback bootloader that does not touch the MBR |
| The first patch has no previous generation to fall back to | The fallback has nothing to fall back to | Step 0 registers the running system as a generation, the rehearsals confirm both are in the menu, and a gate fails the patch if the entry is absent |
| The unlock cannot reach the master before Tailscale is up | The reboot stalls waiting for the passphrase | Unlock by a jump host through the edge machine or the public address, never the Tailscale name |
| The Hetzner API is unreachable when a reset is needed | No automatic recovery from a hang | A gate checks the API and token before the reboot, and the console and rescue layers remain |
| A new generation hangs at boot | No SSH, no console | One-shot boot with a saved default, and a hard reset through the API boots the old generation. Web console as a further layer |
| The unlock prompt cannot be answered by a script | A reboot needs the owner to type | Rehearse both methods. Worst case the owner answers over SSH by hand, and the procedure waits |
| `cx23` is too small or slow | The call machine struggles | Measure before and during the first test call. Stop and ask the owner |
| Capacity for the edge server is refused | The server cannot be created | `cx23`, then `cpx22`, then `cpx32` with the owner's approval. Created once only |
| A pod or agent restarts on the edge node during the outage | Calls or ingress break | No restarts there during the window, 900 second tolerations, a health check as the API returns, and a short outage |
| Envoy restarts while the controller is down | Ingress serves nothing | Never restart it during the window. Verify the data plane's behaviour in the acceptance test |
| Moving Postgres restarts the primary | A chat outage | Rehearse the changed affinity on a scratch cluster first |
| The floating IP move fails | Matrix unreachable | A no-call window, a tested rollback, and the assignment is a Terraform change that can be reversed |
| An interrupting step runs during a call | A call drops | The fail-closed no-call check, run before and again immediately before each step |
| Terraform wants to replace a server | An unplanned outage | `ignore_changes = [image]`, and read every `tofu plan` before applying |
| The k3s token cannot be rotated without a replacement | Token rotation stays blocked | Out of scope; recorded as an open question |

## Post-design Constitution Check

Re-checked against `data-model.md`, `contracts/patch-gates.md` and `research.md`. No principle is
bent. The consent gates are the way principle III is met for the live steps.

## Complexity Tracking

No violations to justify.

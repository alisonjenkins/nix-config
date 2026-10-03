# Quickstart: prove each phase of in-place patching

How to check that each phase did what it should, in order. Each scenario states what it needs, what to
run, and what a pass looks like. Commands that change live state need the owner's consent (plan,
consent gates). The read-only ones do not.

```sh
export KUBECONFIG=~/.kube/hetzner-cp.yaml
```

Times are ISO 8601 UTC. The patch scripts are in `scripts/hetzner-patch/`, and their gates are defined
in [contracts/patch-gates.md](contracts/patch-gates.md). The machines and the placement are in
[data-model.md](data-model.md).

## Phase A: prove on a disposable server

Use a throwaway server created from the current snapshot, in its own name. Delete it afterwards.

**A1. A new generation boots after `deploy --boot`**

1. Enable NixOS GRUB in a test configuration and build it.
2. `deploy --boot` to the disposable server, then reboot it.
3. Run `nixos-version` and read the kernel parameters.

Pass: the machine boots and reports the new generation, and the GRUB menu lists both the image's
original generation and the new one. Before the change it reports the image's original generation
after every reboot.

**A2. A hung generation falls back by itself**

1. Deploy a generation that is built to hang at boot (for example a unit that blocks boot).
2. Set it as a one-shot with `grub-reboot` and reboot.
3. When it does not answer, hard reset through the Hetzner API.

Pass: after the reset it boots the previous generation, and SSH works. Record the time it took.

**A3. The unlock prompt can be answered by a script**

Attach a throwaway LUKS volume to a disposable server whose `ROLE` is `server`, reboot it, and run
`unlock-master.sh --via public` with a test passphrase (the throwaway server has no Tailscale and no edge machine).

Pass: the volume opens and the state service starts, with the passphrase never printed. A wrong
passphrase makes the prompt ask again.

**A4. The edge type has headroom**

```sh
kubectl top pods -A --no-headers | sort -k4 -h -r | head -20
```

Pass: the Matrix stack plus the per-node agents fit 4 GB with at least 500 MB spare. If not, stop and
ask the owner about a larger type.

## Phase B: Nix changes

```sh
nix build .#nixosConfigurations.hetzner-karpenter-node-amd64.config.system.build.toplevel
bats scripts/hetzner-patch/tests
nix flake check
```

Pass: the closure builds, every test passes, and the flake check is clean.

## Phase C: Terraform

```sh
cd ~/git/terraform/hetzner && tofu plan
```

Pass: the plan adds only the edge server, its network attachment, its firewall and the lifecycle rule
on both servers. It shows no server create or delete for the master.

After applying: the edge node is `Ready`.

```sh
kubectl get nodes -o wide
kubectl describe node hetzner-edge-1 | grep -i -E "taints|labels"
```

## Phase D: the first in-place patch of the master

Run `patch-node.sh --machine master --approve --first-patch` in a no-call window, with the owner present. The edge machine is already bootstrapped, and the unlock goes through it (`--via edge`).

Pass: every gate passes, the master reboots, the owner's passphrase answers the prompt, and the master
returns `Ready` within 15 minutes. The run record shows `servers_created=0` and `servers_deleted=0`,
the new generation is the saved default, and Flux reconciles.

## Phase E: moving the stack

**E0. A changed Postgres affinity does not restart the primary** (before the database moves)

On a scratch CloudNativePG cluster, add a node selector to a running cluster.

Pass: record whether the primary restarted, and the interruption in seconds.

After each move, check:

```sh
kubectl get pods -n matrix -o wide
scripts/hetzner-volume-verify/check-no-call.sh
```

Pass: the moved pods are `Running` on `hetzner-edge-1`. A test message and a test call work. At the
end, the floating IP is assigned to the edge server and `https://matrix.<domain>` answers.

## Phase F: the acceptance test

1. Start a test call with at least three participants and keep it running for 15 minutes.
2. Send chat messages and join with a fourth participant during the next step.
3. Run `patch-node.sh` for the master. Answer the unlock prompt.

Pass:

- every participant stays connected, with no media freeze over 5 seconds (SC-001);
- every chat message sent during the reboot is delivered (SC-002);
- the fourth participant joins during the reboot (spec FR-003);
- the edge node's pods, its Cilium agent, its Envoy proxy and its CoreDNS copy show no restarts;
- the other services are back within 10 minutes (SC-008).

Fail: stop, record it, and decide with the owner. Do not rely on this during a real call until it
passes.

## Phase G: patching the call machine

1. With a call running, run `patch-node.sh` for the edge node.

Pass: it refuses, names the reason and changes nothing (SC-004).

2. After the call ends, run it again.

Pass: it patches, reboots unattended, and chat and calls are back within 10 minutes (SC-009). If the
final check sees a new participant just before the reboot, it aborts.

3. Deliberately make a gate fail and run a patch.

Pass: nothing changes (SC-005).

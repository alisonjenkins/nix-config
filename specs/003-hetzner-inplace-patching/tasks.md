---

description: "Task list for patching the Hetzner control plane without interrupting calls"
---

# Tasks: Patch the Hetzner control plane without interrupting calls

**Input**: Design documents from `/specs/003-hetzner-inplace-patching/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/patch-gates.md, quickstart.md. Spec 004 (`specs/004-hetzner-encrypted-volumes/`) lands first, so the edge machine only holds encrypted volumes and the no-call check exists.

**Tests**: Included. Constitution principle II requires test-first for the scripts and the Nix changes, and proof by rehearsal on a disposable server before any boot-path step on a real machine.

**Organization**: Grouped by user story. Phases 1 and 2 block every story. Story order follows dependency: US2 and US4 prove the patch mechanism, then US1 builds the edge machine and proves the call, then US3 and US5.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task).
- **[Story]**: the user story from `spec.md` (US1 to US5).
- **[CONSENT]**: changes live state or costs money. The owner must say yes to that specific step first (constitution III). Never batch consent.
- Each task is one commit where it changes a file (constitution I). Commit messages carry no AI attribution.

## Path conventions

- `nix-config:` this repository (this worktree).
- `terraform:` `~/git/terraform` (the real clone; the scratch clone is stale and MUST NOT be used).
- `home-cluster:` `~/git/home-cluster`, manifests under `clusters/hetzner/flux-system/`.

Cluster commands assume `export KUBECONFIG=~/.kube/hetzner-cp.yaml`. Times are ISO 8601 UTC. Never print a secret or the unlock passphrase, and never paste one into a task or commit.

---

## Phase 1: Setup

**Purpose**: Branches, the scripts' scaffold and the baseline.

- [ ] T001 Create one branch per repository: `nix-config:` continue on `docs/hetzner-inplace-patching` (spec 004's branch must land first, per the owner's order), `terraform:` branch `feat/hetzner-edge-node` off an up-to-date `master` in `~/git/terraform` (`git pull` first; never use the stale scratch clone), `home-cluster:` worktree `.claude/worktrees/edge-node` on `feat/hetzner-edge-node` off `origin/main`.
- [ ] T002 [P] Scaffold `nix-config:scripts/hetzner-patch/flake.nix` with a `devShells.default` providing `deploy-rs`, `hcloud`, `kubectl`, `jq`, `awscli2`, `openssh`, `bats`, `shellcheck` and `coreutils`, plus `README.md` pointing at `specs/003-hetzner-inplace-patching/contracts/patch-gates.md`. Tools resolve from Nix, never `PATH` (constitution IV).
- [ ] T003 [P] In `terraform:hetzner/` run `tofu init` and `tofu plan` (read-only, with the token variables supplied by the owner from the password manager) and record that the baseline plan is empty in `nix-config:specs/003-hetzner-inplace-patching/evidence/baseline.md`. Note the current `hcloud_server.cp` image and that `data.hcloud_image.k8s_node` uses `most_recent = true`.
- [ ] T004 [P] Create `nix-config:specs/003-hetzner-inplace-patching/evidence/README.md` listing the evidence files this feature produces: `baseline.md`, `bootpath.md`, `capacity.md`, `patch-runs.md`, `moves.md`, `acceptance.md`.

---

## Phase 2: Foundational (blocks all user stories)

**Purpose**: Prove the boot path, the fallback and the unlock on a disposable server, write the Nix changes and the patch scripts test first, then create the edge machine and bootstrap it first. The first grub-install on a real machine happens on the fresh edge server, never first on the master. Nothing in phases 3 to 7 starts before this passes.

- [ ] T005 [CONSENT] Create the disposable rehearsal server for the boot path: a `cx23` named `rehearse-patch-1` in `nbg1`, from the current `purpose=k8s-node` snapshot, with SSH key `platform-admin` and no cluster join (no `K3S_TOKEN`, no Tailscale key), through the Hetzner API with the `hcloud` CLI. Record its ID and the hourly cost in `evidence/bootpath.md`. It is deleted in the cleanup task.
- [ ] T006 Write a flake check first, in `nix-config:flake-modules/hetzner-tests.nix`, that evaluates the `hetzner-karpenter-node-amd64` configuration and asserts `boot.loader.grub.enable` is true, `boot.loader.grub.default` is `"saved"`, `boot.loader.grub.device` is set, `boot.loader.timeout` is 10 and `boot.loader.grub.configurationLimit` is at most 4, and that `system.build.hetznerImage` still evaluates. Run it and confirm it fails.
- [ ] T007 Implement the bootloader change until `T006` passes. In `nix-config:modules/hetzner/default.nix` set `boot.loader.grub` (BIOS, `device` the system disk as proven in `T008`, `default = "saved"`, `configurationLimit = 3`, `timeout = 10`). In `nix-config:lib/hetzner-repart-image.nix` remove the `lib.mkForce false` on `boot.loader.grub.enable` and keep systemd-boot forced off. Confirm the image still builds (`nix build .#hetzner-karpenter-node-amd64-image`) and `nix flake check` is clean. The image's own static GRUB stays for its first boot.
- [ ] T008 [CONSENT] Boot-path rehearsal A1 on the disposable server (quickstart A1). Build a test generation of the new configuration and deploy it with `deploy --boot` using an ad-hoc target (`--hostname <ip>`). Reboot, then run `nixos-version` and read `/proc/cmdline`. Record whether the running image's original system is registered as a profile generation before the deploy (`ls -l /nix/var/nix/profiles/system*`) and, if not, that registering it first (`nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/current-system)`) works; whether `grub-install` succeeded, which `/boot` layout resulted, that the GRUB menu afterwards lists both the original generation and the new one, how much of the 256 MB ESP the generations use, and that the machine boots the new generation. Before the change it always reports the image's original generation. If `grub-install` fails or leaves the machine unbootable, stop and switch to the fallback bootloader in `research.md` section 2.
- [ ] T009 [CONSENT] Fallback rehearsal A2 on the disposable server (quickstart A2). Deploy a generation built to hang at boot (a unit that blocks multi-user target), set it as a one-shot with `grub-reboot`, reboot, and when SSH never answers, hard reset with the Hetzner API (`hcloud server reset`). Confirm it boots the previous generation (the image's original one, which must be a menu entry) by itself with SSH working. Record the elapsed time and whether `grubenv` on the ESP's FAT is writable by GRUB.
- [ ] T010 Write `nix-config:scripts/hetzner-patch/tests/unlock-master.bats` first, with a stubbed SSH and a stubbed prompt: the script waits until a prompt is pending and does not answer before an approval flag is given; it connects only by the edge jump host or the public address and fails if asked to use a Tailscale name; it reads the passphrase from the password manager command at that moment and never prints it, logs it or puts it on a command line; a wrong passphrase makes it retry at most twice then stop and report; the exit code is non-zero on failure. Confirm every test fails.
- [ ] T011 Implement `nix-config:scripts/hetzner-patch/unlock-master.sh` until `T010` passes. Answer the pending `systemd-ask-password` over SSH with the method proven in `T012`. The master is not on the tailnet until it is unlocked (Tailscale's state lives on the LUKS volume), so the script connects with `--via edge` (a jump host through the edge machine over the private network, the default) or `--via public` (the master's public address from the allow-listed admin address), never by its Tailscale name. Tailscale is used only for the steps before and after the unlock. Errors name the operation and its inputs. `shellcheck` clean.
- [ ] T012 [CONSENT] Unlock rehearsal A3 (quickstart A3). Create a 10 GB volume `rehearse-luks`, LUKS-format it with a throwaway test passphrase, attach it to a second disposable `cx23` whose user data sets `ROLE=server`, reboot it, and run `unlock-master.sh --via public` with the test passphrase (the rehearsal server has no Tailscale and no edge machine). Try the tty-agent method (`systemd-tty-ask-password-agent --query`) and the reply-file method (`systemd-reply-password`); record which works non-interactively. Confirm a wrong passphrase re-prompts and the passphrase never appears in output. Record in `evidence/bootpath.md`.
- [ ] T013 [P] Measure the edge machine's headroom (quickstart A4, read-only). Record `kubectl top` per pod for the Matrix stack and the per-node agents (Cilium, Tetragon, CSI, node exporter, Kyverno and Kubescape agents if they run on every node), then total them against a `cx23`'s 4 GB. Write the result and the fallback types in `evidence/capacity.md`. If less than 500 MB is spare, stop and ask the owner about a larger type (spec FR-011).
- [ ] T014 Add a test first, in `nix-config:flake-modules/hetzner-tests.nix` (the existing VM test exercises the real unit scripts), that the floating-IP binding unit runs for `ROLE=edge` as well as `ROLE=server` and skips for `ROLE=agent`. Confirm it fails.
- [ ] T015 In `nix-config:lib/hetzner-node-services.nix` change the `floating-ip-bind` unit so it binds for `ROLE=server` and `ROLE=edge` and still skips otherwise, until `T014` passes. The unit reads `FLOATING_IP` from `/etc/karpenter-node.conf`.
- [ ] T016 Add a test first, in `nix-config:flake-modules/hetzner-tests.nix`, that the agent bootstrap passes `NODE_LABELS` and `NODE_TAINTS` from `/etc/karpenter-node.conf` to `k3s agent` as `--node-label` and `--node-taint`, and passes nothing extra when they are unset. Confirm it fails.
- [ ] T017 In `nix-config:lib/hetzner-node-services.nix` extend `k3s-agent-bootstrap` to accept `NODE_LABELS` and `NODE_TAINTS` (comma separated) from the node config, until `T016` passes. The existing hard-coded labels stay.
- [ ] T018 In `nix-config:flake-modules/deploy.nix` add two deploy-rs nodes, `hetzner-k8s-master-1` and `hetzner-edge-1`, each with `hostname` the Tailscale MagicDNS name, `sshUser = "ali"`, a `system` profile with `user = "root"` and `path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations."hetzner-karpenter-node-amd64"`, and `autoRollback` and `magicRollback` left on. Run `nix flake check` (the cheap deploy schema check) and confirm it passes.
- [ ] T019 Write `nix-config:scripts/hetzner-patch/tests/patch-node.bats` first, with stubbed `ssh`, `deploy`, `kubectl`, `hcloud` and `check-no-call.sh`. One test per rule in `contracts/patch-gates.md`: each gate fails closed and changes nothing; the steps run in order (record counts, `deploy --boot`, boot entry check, one-shot, reboot, wait, permanent only after healthy); an unhealthy machine triggers the hard reset and records `rolled-back`; no `server create` or `server delete` call is ever made; the call machine path refuses on `calls>0` and re-checks immediately before the reboot; the control-plane path refuses without the owner approval flag; a `--first-patch` mode skips only the "Edge serving" and "Edge protected" gates (the Matrix stack has not moved yet), is refused unless `--approve` and a no-call check pass, and still requires the edge machine `Ready`; step 0 registers the running system as a profile generation when `/nix/var/nix/profiles/system` is missing or does not include it, and the gate "previous generation in the bootloader menu" fails the patch if the entry is absent after the install; the Hetzner API gate fails when the API does not answer a read-only call or `HCLOUD_TOKEN` is not set; the run record has ISO 8601 UTC times and `servers_created=0` and `servers_deleted=0`. Confirm every test fails.
- [ ] T020 Implement `nix-config:scripts/hetzner-patch/patch-node.sh` (`--machine master|edge`, `--approve`, `--announced-at`, `--hold-after-gates`) until `T019` passes. It implements step 0 (register the running system as generation 1 if needed), the `--first-patch` mode and the Hetzner API gate. The health wait covers the storage plugin's registration and the volume remount, not only SSH. It calls `scripts/hetzner-volume-verify/check-no-call.sh` from spec 004 and does not duplicate it (constitution V). For the master it calls `unlock-master.sh`. It writes the run record to `nix-config:specs/003-hetzner-inplace-patching/evidence/patch-runs.md`. `shellcheck` clean.
- [ ] T021 [P] Write `nix-config:scripts/hetzner-patch/tests/rollback.bats` first: before the reboot it selects the previous generation; after a hung boot it hard resets through the Hetzner API and confirms the previous generation is running; it prints the web-console and rescue-mode steps when both fail; it never creates a server. Confirm it fails.
- [ ] T022 Implement `nix-config:scripts/hetzner-patch/rollback.sh` until `T021` passes, and call it from `patch-node.sh` on an unhealthy result.
- [ ] T023 [P] Write `nix-config:docs/hetzner-patching-runbook.md`: how to patch each machine, the consent steps, the recovery layers in order (previous generation before the reboot, a hard reset after a hung boot, the Hetzner web console and GRUB menu, rescue mode, and a restore from the pre-patch snapshot as the last resort, which needs capacity), and what never to do.
- [ ] T024 [CONSENT] Republish the node image so any future server comes from the grub-enabled configuration: merge `T007`, `T015` and `T017`, then trigger `Publish Hetzner image` by hand. The new image hash is new, so the dedup lets it through. Confirm a new snapshot appears with the hash label and no upload server or key is left behind.
- [ ] T025 In `terraform:hetzner/variables.tf` add `edge_server_type` (default `cx23`), `edge_private_ip` (a free address in the platform subnet next to `cp_private_ip`), and a validation that allows only `cx23`, `cpx22` and `cpx32`, with a comment that `cpx22` and `cpx32` need the owner's approval recorded in `evidence/capacity.md` first (spec FR-011). Add `edge_tailscale_auth_key` for the OAuth client secret (sensitive; the same secret the workers use).
- [ ] T026 [P] In `terraform:hetzner/firewall.tf` add `hcloud_firewall.edge` with 443/tcp, 30881/tcp, 30001/tcp, 30002/udp from anywhere (as the master's Matrix rules) and SSH from `var.ssh_allowed_ips` only. Copy the rule descriptions from the live master firewall and read them first from the Hetzner API, since the repository copy may be behind.
- [ ] T027 In `terraform:hetzner/compute.tf` add `hcloud_server.edge` named `hetzner-edge-1`: type `var.edge_server_type`, the same `local.cp_image`, the spread `hcloud_placement_group.cp`, `firewall_ids = [hcloud_firewall.edge.id]`, `ssh_keys = [hcloud_ssh_key.admin.id]`, `lifecycle { ignore_changes = [image] }`, and user data that writes `/etc/karpenter-node.conf` with `ROLE=agent`, `SERVER_ENDPOINT` (the master's private address), `K3S_TOKEN`, `TAILSCALE_AUTH_KEY` (an OAuth client secret) with `TAILSCALE_ADVERTISE_TAGS=tag:hetzner,tag:k8s`, `FLOATING_IP`, `NODE_LABELS=node-role=edge` and `NODE_TAINTS=workload=edge:NoSchedule`. Add `hcloud_server_network.edge` at `var.edge_private_ip`. Leave `hcloud_floating_ip_assignment.ingress` on the master for now.
- [ ] T028 [P] In `terraform:hetzner/outputs.tf` add outputs `edge_private_ipv4`, `edge_public_ipv4` and `edge_firewall_id`.
- [ ] T029 [CONSENT] Show the owner the `tofu plan`: it must add only the edge server, its network attachment, its firewall and the lifecycle rule on both servers, with no change to the master. After approval, `tofu apply`. If Hetzner refuses `cx23` for lack of capacity, stop and ask before using `cpx22` or `cpx32` (one-time capacity risk). Record the type and cost in `evidence/capacity.md`.
- [ ] T030 Confirm the edge machine joined: `kubectl get nodes -o wide` shows `hetzner-edge-1` `Ready`, with label `node-role=edge` and taint `workload=edge:NoSchedule` (quickstart C), and its per-node agents (Cilium, CSI, Tetragon, node exporter) are running. Check that `hcloud-csi-node` registered with CSINode before any volume moves.
- [ ] T031 [CONSENT] Bring the edge machine onto the NixOS-managed GRUB, on a fresh server with no data: run `patch-node.sh --machine edge` for it. It reboots unattended. Confirm it returns `Ready` and the new generation is the saved default. Record it in `evidence/patch-runs.md`.
- [ ] T032 Check the edge firewall opens the Matrix ports before anything moves: from outside the cluster test TCP 443, 30881 and 30001 and UDP 30002 against the edge machine's public address with a throwaway listener, and record each result in `evidence/moves.md`.
- [ ] T033 [CONSENT] Delete every disposable rehearsal server and volume (`rehearse-patch-1`, the LUKS rehearsal server and `rehearse-luks`) and confirm `hcloud server list` and `hcloud volume list` show only the master and its state volume. Record the total cost in `evidence/bootpath.md`.

---

## Phase 3: User Story 2 - Routine patching never needs spare capacity from Hetzner (Priority: P1)

**Goal**: Patch and reboot the control-plane machine in place, with no server created or deleted.

**Independent test**: Quickstart D. The run record shows `servers_created=0` and `servers_deleted=0`, and the action log holds only reboot, reset and snapshot actions.

- [ ] T034 [US2] In `terraform:hetzner/compute.tf` add `lifecycle { ignore_changes = [image] }` to `hcloud_server.cp`, and nothing else (the owner's ruling: `user_data` stays tracked). Run `tofu plan` and confirm it shows no change. Explain in a comment only why: a new snapshot must not replace the server.
- [ ] T035 [US2] [CONSENT] Show the owner the `tofu plan` for `T034` (it must be empty) and, after approval, `tofu apply`. Confirm a later `purpose=k8s-node` snapshot no longer produces a plan.
- [ ] T036 [US2] [CONSENT] Take the pre-patch snapshot of `hetzner-k8s-master-1` through the Hetzner API with the label `purpose=pre-patch`, and record its ID, size and monthly cost (about €2.30 at 160 GB) in `evidence/patch-runs.md`. It is the last-resort recovery and is deleted after the patch process has proven itself.
- [ ] T037 [US2] [CONSENT] First in-place patch of the master. Preconditions: `T008`, `T009` and `T012` passed, the edge machine is `Ready` and bootstrapped (`T031`), `T036` exists, no call is active, and the owner is present with the passphrase. Run `patch-node.sh --machine master --approve --first-patch` for a harmless new generation (the edge machine is already bootstrapped, `T031`; the Matrix stack has not moved yet, so this one patch skips the edge-serving gates). Step 0 registers the running system as a generation first, so the previous generation exists in the menu. The unlock uses `--via edge`. It installs the NixOS-managed GRUB (running `grub-install` on the live disk for the first time), sets the one-shot, reboots, answers the unlock prompt with the owner's approval, waits for health and makes the generation permanent. Record every step and the elapsed times in `evidence/patch-runs.md`.
- [ ] T038 [US2] Prove no server was created or deleted (spec FR-004, SC-003). List Hetzner servers before and after (`hcloud server list -o json`) and compare IDs, and read the project's action log for the patch window to confirm it holds only reboot, reset and snapshot actions. Record both in `evidence/patch-runs.md`.
- [ ] T039 [US2] [CONSENT] Second in-place patch of the master, a plain change that needs no reboot: deploy it with `deploy` (a switch with magic rollback) and confirm the unit changes, k3s restart time and that pods did not restart. This shows routine non-kernel changes need no replacement and no reboot. Record the API outage length in `evidence/patch-runs.md`.

---

## Phase 4: User Story 4 - Every step is gated and can be undone (Priority: P2)

**Goal**: A failed gate changes nothing, and a bad generation falls back within 15 minutes.

**Independent test**: Quickstart G3 and A2 through the script.

- [ ] T040 [US4] [CONSENT] Gate drill on a disposable server (quickstart G3): make one gate fail on purpose (for example no pre-patch snapshot) and run `patch-node.sh`. Confirm it aborts before `deploy --boot`, changes nothing, and names the failed gate. Repeat for two more gates. Record each in `evidence/patch-runs.md` (SC-005).
- [ ] T041 [US4] [CONSENT] Undo drill on a disposable server (quickstart A2 through the script): deploy a deliberately broken generation with `patch-node.sh`, let the health wait time out, and confirm `rollback.sh` hard resets and the previous generation is running within 15 minutes. Record the time (SC-006).
- [ ] T042 [US4] [CONSENT] Rescue-mode rehearsal on a disposable server: boot Hetzner rescue mode, mount the root and ESP partitions, list the generations and the `grub.cfg` entries, edit the default, and reboot into the chosen generation. Write the exact steps into `docs/hetzner-patching-runbook.md` (the layer that needs no new server).
- [ ] T043 [US4] Check that every run record in `evidence/patch-runs.md` lists each step, its result and its time in ISO 8601 UTC, and records `servers_created=0` and `servers_deleted=0` (spec FR-010). Fix the script and its test if a field is missing.

---

## Phase 5: User Story 1 - The household keeps talking while the control plane is patched (Priority: P1)

**Goal**: Reboot the control plane during a real call without dropping the call or chat.

**Independent test**: Quickstart F, the acceptance test. This phase depends on phases 2 to 4.

- [ ] T044 [US1] Write the check first: a script `nix-config:scripts/hetzner-patch/check-dns.sh` that resolves a cluster service name from a pod on the master and from a pod on the edge node and exits non-zero if either fails or if only one `kube-dns` endpoint exists. Confirm it fails (one endpoint today).
- [ ] T045 [US1] [CONSENT] Add `home-cluster:clusters/hetzner/flux-system/coredns-edge/` (a `Deployment` named `coredns-edge` in `kube-system`, the same image and the same `k8s-app: kube-dns` label as the k3s CoreDNS, mounting the existing `coredns` ConfigMap, pinned to the edge node by selector and toleration, 900 second tolerations) and register it in `flux-system/flux-kustomizations/kustomization.yaml`. After the owner approves the merge, run `T044` until it passes. k3s does not manage this Deployment, so it is not reverted.
- [ ] T046 [US1] [CONSENT] Pin Valkey to the edge node: find the chart value for the Valkey `StatefulSet`'s `nodeSelector` and `tolerations` in `home-cluster:clusters/hetzner/flux-system/matrix/helmrelease.yaml` (or a patch if the chart has none) and set the selector `node-role=edge`, the `workload=edge` toleration and the 900 second tolerations. Run `check-no-call.sh` first (it must report 0). Valkey has no volume, so it reschedules. Record the time Valkey is unavailable in `evidence/moves.md`.
- [ ] T047 [US1] [CONSENT] Rehearse the database move on a scratch CloudNativePG cluster in namespace `scratch-migrate` (quickstart A5): add `spec.affinity.nodeSelector` to a running two-instance cluster and record whether the existing primary restarts, then switch over to the instance on the node the selector names. Delete the namespace. If the primary restarts, change the plan to move the database with a replica cluster and record it in `research.md`.
- [ ] T048 [US1] [CONSENT] Move `shared-postgres` onto the edge node in a no-call window. In `home-cluster:clusters/hetzner/flux-system/matrix/postgres/cluster.yaml` set `spec.affinity.nodeSelector` to the edge node and `instances: 2` (the volumes are already encrypted from spec 004). Wait for zero lag, run `check-no-call.sh` (it must report 0), switch over with `kubectl cnpg promote`, run `scripts/hetzner-volume-verify/verify.sh --database` against the new primary, take a fresh backup, then destroy the old instance and its volume as spec 004's guard requires. Record the interruption in `evidence/moves.md`.
- [ ] T049 [US1] [CONSENT] Pin the stateless Matrix pods to the edge node in a no-call window: Synapse main, matrix-authentication-service, haproxy, the RTC authorisation service and element-web in `home-cluster:clusters/hetzner/flux-system/matrix/helmrelease.yaml`, and `rtc-transports-stub` in `matrix/rtc-transports-workaround.yaml`, each with the `node-role=edge` selector, the `workload=edge` toleration and 900 second tolerations. The Synapse media volume reschedules with its pod. Run `check-no-call.sh` first. Then run the Matrix functional check from `verify.sh` and confirm sign-in, a message and a media download.
- [ ] T050 [US1] [CONSENT] Pin the SFU group to the edge node in a no-call window: in `home-cluster:clusters/hetzner/flux-system/matrix/helmrelease.yaml` change `matrixRTC.sfu.nodeSelector` from the control-plane label to `node-role=edge` and add the `workload=edge` toleration, and add the same selector and toleration to `matrix/sfu-proxy.yaml` (it forwards to its own node's IP, so it MUST share the SFU's node) and `matrix/sfu-tls-proxy.yaml` (it forwards to `127.0.0.1:7880`). Run `check-no-call.sh` first. After the merge, confirm all three run on `hetzner-edge-1` and the SFU's host ports 30001 and 30002 are bound there.
- [ ] T051 [US1] [CONSENT] Test call through the edge node, with the owner and one other participant, before ingress moves: join a call by reaching the edge machine's address directly, confirm audio and video work over the SFU on the edge node, and record the SFU's CPU and memory during the call in `evidence/capacity.md`.
- [ ] T052 [US1] [CONSENT] Move ingress and the floating IP together, in a no-call window with the owner present (a few seconds to a minute of ingress downtime): (1) in `home-cluster:clusters/hetzner/flux-system/envoy-gateway-config/gatewayclass.yaml` change the `EnvoyProxy` `eg-proxy-config` node selector from the control-plane label to `node-role=edge` with the toleration, so the hostNetwork data plane pod moves to the edge node; (2) in `terraform:hetzner/compute.tf` change `hcloud_floating_ip_assignment.ingress` to `server_id = hcloud_server.edge.id` and apply it; (3) start the `floating-ip-bind` unit on the edge machine; (4) confirm `https://matrix.<domain>`, element and the ente web app answer, and that the master no longer holds the address. Run `check-no-call.sh` first. Record the downtime in `evidence/moves.md`. If anything fails, put the assignment back and move the Envoy pod back.
- [ ] T053 [US1] Verify only: confirm every pod on `hetzner-edge-1` that is not a DaemonSet carries tolerations of 900 seconds for `node.kubernetes.io/unreachable` and `node.kubernetes.io/not-ready` (`kubectl get pods -A -o json --field-selector spec.nodeName=hetzner-edge-1 | jq`). Do not edit manifests here: a changed pod spec rolls the pod, and for the SFU that drops a call. If one is missing, add it as its own change in a no-call window with consent, after `check-no-call.sh` reports 0. Record the result in `evidence/moves.md`.
- [ ] T054 [US1] Confirm every volume attached to a pod on `hetzner-edge-1` is encrypted (spec FR-012): list the claims of pods running on the edge node, find their volumes, and run `scripts/hetzner-volume-verify/verify.sh` part 0 against each. A plain volume on the edge node stops the work until it is migrated under spec 004. Record the result in `evidence/moves.md`.
- [ ] T055 [US1] [CONSENT] Acceptance test (quickstart F): with a test call of at least three participants running for 15 minutes, and a fourth ready to join, run `patch-node.sh --machine master --approve` with the owner present for the unlock. During the reboot send chat messages and join with the fourth participant. Afterwards compare restart counts on the edge node: Matrix pods, the Cilium agent, the Envoy proxy and the CoreDNS copy must show none, and check Cilium, Envoy and CoreDNS health as the API returns. Record the longest media freeze seen, every message delivered, the join, and the time the other services came back, in `evidence/acceptance.md`. If a participant drops or a freeze exceeds 5 seconds, stop and decide with the owner before relying on this.

---

## Phase 6: User Story 3 - The call machine is only patched between calls (Priority: P2)

**Goal**: The call machine's patch refuses during a call and runs unattended between calls.

**Independent test**: Quickstart G1, G2.

- [ ] T056 [US3] Extend `nix-config:scripts/hetzner-patch/tests/patch-node.bats` first, for the call machine: with `calls=1` the script refuses with the reason and changes nothing; with `calls=0` at the first check and `calls=1` at the re-check immediately before the reboot it aborts and does not reboot; it refuses without `--announced-at` at least 10 minutes old; with the metrics endpoint unreachable it refuses (fail closed). Confirm the new tests fail, then make them pass in `patch-node.sh`.
- [ ] T057 [US3] [CONSENT] With a real call running, run `patch-node.sh --machine edge` (quickstart G1). Confirm it refuses, names the reason and changes nothing. Record it (SC-004).
- [ ] T058 [US3] [CONSENT] Race drill: run `patch-node.sh --machine edge --hold-after-gates 120`, join a call during the hold, and confirm the re-check aborts the patch with no reboot. Record it (SC-004).
- [ ] T059 [US3] [CONSENT] With no call running and the notice posted in the household chat at least 10 minutes earlier, patch the call machine for real (quickstart G2): `patch-node.sh --machine edge --announced-at <time>`. It reboots unattended, so the encrypted volumes remount: record how long the storage plugin and the remount took, since the health wait must cover them. Record the time chat and calls were back (at most 10 minutes, SC-009) and run the Matrix functional check.

---

## Phase 7: User Story 5 - The extra cost stays small (Priority: P3)

**Goal**: The extra running cost is at most €10 a month, and the small server is big enough.

**Independent test**: Add up the monthly price; measure a real call.

- [ ] T060 [P] [US5] Add up the monthly price of every server and resource this feature added (the edge server at its type's price from the Hetzner API, the pre-patch snapshot, any extra volume) and write the figure in `evidence/capacity.md`. It must be at most €10 a month, or the owner must have approved more (spec FR-011, SC-007).
- [ ] T061 [US5] During the first nightly call on the edge machine, record its CPU, memory and any swap use every minute for the whole call, and write the maximum and the average in `evidence/capacity.md`. If `cx23` is too small or too slow, stop and ask the owner (stop-and-ask rule); do not move to a larger type without approval.
- [ ] T062 [US5] [CONSENT] Once the process has proven itself, ask the owner whether to delete the pre-patch snapshot from `T036` to stop its cost, and delete it only on a yes.

---

## Phase 8: Polish and cross-cutting

- [ ] T063 Update `nix-config:docs/adr/0021-patch-hetzner-master-in-place.md` with the final evidence (the bootloader finding, the one-shot fallback, the unlock step, the acceptance result), fix any statement that turned out wrong, set the status to Accepted, and fill in "Revisit when". It lands in the first nix-config pull request (constitution VI).
- [ ] T064 [P] Replace the body of `nix-config:docs/hetzner-inplace-patching-design.md` with a short pointer to specs 003 and 004 and the ADR, so there is one source for the design.
- [ ] T065 [P] Record the open questions this feature did not close in `nix-config:docs/hetzner-patching-runbook.md`: rotating the k3s token without replacing the master, and the Cilium agent behaviour if it restarts during an outage.
- [ ] T066 Re-run every quickstart scenario that has a pass condition, tick SC-001 to SC-009 with its evidence in `nix-config:specs/003-hetzner-inplace-patching/evidence/success-criteria.md`, and clear any open item.
- [ ] T067 Open the pull requests, one per repository, with the atomic commits intact: `nix-config`, `terraform` and `home-cluster`. Each description says what changed, why, and the verification evidence. Merge by local rebase and fast-forward (constitution I).

---

## Dependencies and order

- **Phase 1 then Phase 2 then everything else.** Phase 2 blocks all stories.
- **Within Phase 2:** the order is: rehearsals, Nix changes and scripts (tests first), the image republish (T024), the edge machine (T025 to T032), then cleanup. The edge machine is bootstrapped (T031) before the master is patched. The rehearsals (T005, T008, T009, T012) need the disposable server first and must pass before any boot-path step on a real machine. The scripts' tests (T019, T010, T021) come before their code. T033 comes last.
- **US2 and US4 (phases 3 and 4)** prove the patch mechanism on the master and on a disposable server. T037 is the first live boot-path change on the master and needs the edge machine bootstrapped (T031), T008, T009, T012 and T036.
- **US1 (Phase 5)** needs phases 2 to 4. The edge server (T027) needs T015, T017 and T024, and is created in Phase 2. The moves run in the order CoreDNS (T045), Valkey (T046), Postgres (T048), the Matrix pods (T049), the SFU group (T050), then ingress and the floating IP (T052), then the volume check (T054), then the acceptance test (T055). T044 comes before T045.
- **US3 (Phase 6)** needs the edge machine and its patch (T031). **US5 (Phase 7)** needs a real nightly call on the edge machine.
- **Polish (Phase 8)** last.

## Parallel examples

- Phase 2: T013 (measure), T014, T016, T021 and T023 together.
- Phase 5: T025, T026 and T028 together, in `terraform:hetzner/`.
- Phase 8: T064 and T065 together.

## Implementation strategy

- **MVP**: Phases 1 and 2, then US2 and US4. That gives safe in-place patching of the master with gates and a fallback, which removes the capacity risk, and it is proven on a disposable server first.
- **Then** US1 for the call guarantee, which is the main goal and is only proven by the acceptance test (T055).
- **Stop rule**: if a rehearsal or a drill fails, stop and decide with the owner. The first live boot-path change is never attempted until the disposable-server rehearsals pass.

## Notes

- Total tasks: 67. Per story: US1 12, US2 6, US3 4, US4 4, US5 3. Setup 4, Foundational 29, Polish 5. 28 tasks need consent.
- One commit per task that changes a file; each repository's changes land in its own pull request.

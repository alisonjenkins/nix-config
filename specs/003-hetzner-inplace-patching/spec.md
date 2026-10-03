# Feature Specification: Patch the Hetzner control plane without interrupting calls

**Feature Branch**: `docs/hetzner-inplace-patching`

**Created**: 2026-10-03

**Status**: Draft

**Input**: User description: "Patch and reboot the Hetzner Kubernetes control-plane node without interrupting ongoing Matrix calls and chat for the household users (a 6 hour group call runs most nights). Routine patching must never depend on Hetzner having spare server capacity, every step must have a go/no-go check and a way back, and the machine that hosts calls and chat must only be patched when no call is active. The call stack must therefore run on a separate always-on node from the control plane, costing as little as possible. Success is shown by rebooting the control plane during a real test call without the call or chat dropping."

## Context

The Hetzner cluster has one control-plane machine. It also runs the household's Matrix chat,
voice and video calls, the public entry point, and several other services. Today a change to
that machine means replacing the server. A replacement deletes the old server first, needs
Hetzner to have capacity for a new one, and restarts every service, including any call in
progress.

Two events show the risk. The original server type sold out in the chosen location in June
2026 and the machine had to change type. And the household's group call runs about 6 hours
most nights, so any restart of the machine that hosts it is a real outage.

Background, the evidence for each fact, and what is still unproven are in
`docs/hetzner-inplace-patching-design.md` and
`docs/adr/0021-patch-hetzner-master-in-place.md`. This feature is the requirements; the plan
holds the technical choices.

Related: `specs/004-hetzner-encrypted-volumes/` covers encrypting the Matrix data. The call
machine in this feature must only ever hold encrypted data volumes, so that feature lands
first, before the call machine is created (owner's decision, 2026-10-03).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The household keeps talking while the control plane is patched (Priority: P1)

The operator patches and reboots the control-plane machine while the household is in a group
call. Nobody in the call is disconnected, nobody notices a freeze, and chat keeps working.
Someone who wants to join mid-reboot can.

**Why this priority**: This is the point of the whole feature. If a patch still interrupts the
nightly call, nothing else here matters.

**Independent Test**: Start a call with at least three participants and keep it running for 15
minutes. Reboot the control-plane machine with the normal patch procedure. Watch every
participant for disconnects or freezes, send chat messages during the reboot, and try to
join with a fourth participant.

**Acceptance Scenarios**:

1. **Given** a call with three or more participants is running, **When** the control-plane
   machine is patched and rebooted, **Then** every participant stays connected and nobody
   sees media freeze for more than 5 seconds.
2. **Given** the same call, **When** participants send chat messages during the reboot,
   **Then** every message is delivered and none is lost.
3. **Given** the same call, **When** a new participant joins during the reboot, **Then** they
   join successfully.
4. **Given** the control-plane machine has finished rebooting, **When** the operator checks,
   **Then** the call and chat state is unchanged and the machine reports healthy.

---

### User Story 2 - Routine patching never needs spare capacity from Hetzner (Priority: P1)

The operator patches the control-plane machine and the call machine without creating or
deleting a server. A shortage of the chosen server type at Hetzner cannot block a patch.

**Why this priority**: The control-plane machine could not be rebuilt when its original type
sold out. A patch process that needs a new server inherits that risk.

**Independent Test**: Run a routine patch and compare the Hetzner project's server list and
audit log before and after. The server count and server IDs are identical, and no create or
delete call was made.

**Acceptance Scenarios**:

1. **Given** a routine patch, **When** it completes, **Then** no server was created or deleted
   and every server keeps its identity and address.
2. **Given** Hetzner reports no capacity for the machine's server type, **When** the operator
   runs a routine patch, **Then** it completes normally.

---

### User Story 3 - The call machine is only patched between calls (Priority: P2)

The machine that hosts calls and chat can be patched too, but only when nobody is in a call.
The procedure checks, and if anyone is in a call it refuses and says so.

**Why this priority**: Rebooting the call machine drops a call, and no live move is possible.
The household needs a guarantee that a patch cannot hit a call by accident.

**Independent Test**: Start a call, run the call-machine patch, and confirm it refuses without
changing anything. End the call and run it again; it completes. Start a call in the seconds
between the check and the reboot and confirm the procedure notices and aborts.

**Acceptance Scenarios**:

1. **Given** at least one participant is in a call, **When** the operator runs the
   call-machine patch, **Then** it refuses, names the reason, and changes nothing.
2. **Given** no one is in a call, **When** the operator runs it, **Then** it patches and
   reboots, and chat and calls are available again within 10 minutes.
3. **Given** the check passed but a participant joins before the reboot, **When** the
   procedure re-checks immediately before rebooting, **Then** it aborts without rebooting.

---

### User Story 4 - Every step is gated and can be undone (Priority: P2)

Before it reboots anything, the procedure checks that the household's chat and calls are
healthy on the call machine and that a way back exists. If any check fails, nothing changes.
If a patched machine does not come back healthy, the operator has a documented way back to the
previous version.

**Why this priority**: The control plane is a single machine. A bad patch must not leave the
operator without a way to recover.

**Independent Test**: Break one gate on purpose (stop a chat component on the call machine)
and run a patch; it aborts before the reboot. Apply a deliberately broken update to a
disposable copy of the machine and confirm it comes back on the previous version.

**Acceptance Scenarios**:

1. **Given** any check fails, **When** the operator runs a patch, **Then** it aborts before
   any reboot and reports which check failed.
2. **Given** a patched machine does not return healthy, **When** the operator follows the
   recovery steps, **Then** the previous working version is running within 15 minutes.
3. **Given** a patch finishes or aborts, **When** the operator looks at the record, **Then**
   it lists each step, its result and its time, in UTC.

---

### User Story 5 - The extra cost stays small (Priority: P3)

The separation costs as little as possible: one small additional server, and no standing
duplicate copies of services.

**Why this priority**: The household pays for this personally.

**Independent Test**: Add up the monthly price of every server the feature adds, from the
cloud provider's price list.

**Acceptance Scenarios**:

1. **Given** the feature is in place, **When** the operator adds up the new running costs,
   **Then** they are at most €10 a month.
2. **Given** measurements show the small server cannot hold the call stack, **When** the
   operator reviews the result, **Then** a larger server is used only after the owner
   approves the higher cost.

---

### Edge Cases

- The control-plane machine does not come back after a reboot. The operator follows the
  recovery steps. A snapshot taken before the first patch is the last resort.
- A call starts during a call-machine patch window, after the first check. The final check
  before the reboot catches it.
- The call machine is unreachable when the checks run. The procedure aborts and changes
  nothing.
- A participant's own network drops during a patch. That is not a failure of the feature, but
  the rehearsal must tell it apart from a server-side drop.
- Storage is slow to attach after a reboot. The call machine's data stays attached during a
  control-plane reboot, so calls and chat are unaffected, but the procedure's health checks
  allow for the delay on the machine that rebooted.
- Hetzner's server capacity runs out while the call machine is being created for the first
  time. That is a one-time setup risk and is outside routine patching.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Patching and rebooting the control-plane machine MUST NOT disconnect any
  participant of a call that is already running.
- **FR-002**: Chat MUST stay available and lose no messages while the control-plane machine
  reboots.
- **FR-003**: A new participant MUST be able to join a call while the control-plane machine
  reboots.
- **FR-004**: A routine patch of either machine MUST NOT create or delete a server.
- **FR-005**: The call machine MUST be patched only when no participant is in a call, and the
  procedure MUST refuse, with a reason, when anyone is.
- **FR-006**: The procedure MUST re-check for active calls immediately before rebooting the
  call machine.
- **FR-007**: Before any reboot, the procedure MUST verify the go/no-go checks (call machine
  healthy, a way back exists) and MUST change nothing if one fails.
- **FR-008**: Every patch MUST be reversible to the previous working version, with documented
  recovery steps for a machine that does not return healthy.
- **FR-009**: The chat server and its database, the voice and video media server and its
  proxies, the shared cache it uses, and the public entry point with its fixed address MUST
  run on a machine other than the control plane.
- **FR-010**: The procedure MUST record each step, its result and its time in UTC.
- **FR-011**: The additional running cost MUST be at most €10 a month unless the owner
  approves more.
- **FR-012**: The call machine MUST hold only encrypted data volumes (see
  `specs/004-hetzner-encrypted-volumes/`).
- **FR-013**: The acceptance test (a control-plane reboot during a real test call) MUST be
  run and its result recorded before this feature is relied on.

### Key Entities

- **Control-plane machine**: Runs the cluster's management functions and the household's other
  services. Patched at any time, including during a call.
- **Call machine**: Runs everything chat and calls need, plus the public entry point. Patched
  only between calls.
- **Patch run**: One execution of the procedure on one machine, with its checks, steps and
  outcome.
- **Check (gate)**: A condition that must hold before a reboot, such as "no participant in a
  call" or "chat components healthy".
- **Previous version**: The last working system version, kept so a patch can be undone.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a rehearsal with at least three participants for 15 minutes, rebooting the
  control-plane machine leaves 100% of participants connected, with no media freeze longer
  than 5 seconds.
- **SC-002**: Every chat message sent during that reboot is delivered; none is lost.
- **SC-003**: A routine patch of either machine performs zero server creations and zero
  deletions.
- **SC-004**: The call-machine patch refuses in 100% of test attempts while anyone is in a
  call, including a call that starts just before the reboot.
- **SC-005**: When a check is made to fail on purpose, no reboot happens in 100% of attempts.
- **SC-006**: In a rehearsal, a machine that fails to return healthy is back on its previous
  version within 15 minutes.
- **SC-007**: The additional running cost is at most €10 a month.
- **SC-008**: Services other than calls and chat are back within 10 minutes of a
  control-plane reboot.
- **SC-009**: After a call-machine patch, chat and calls are available again within 10 minutes of
  the reboot.

## Assumptions

- The household is a handful of people. The 6 hour nightly call and its chat are what must not
  be interrupted.
- The call machine is patched on weekday daytime, when the household is not in a call. The
  procedure still checks for an active call each time (FR-005, FR-006).
- A call may freeze for up to 5 seconds during a control-plane reboot and still count as not
  dropped (owner's decision, 2026-10-03).
- If the small server proves too small, the work stops and the owner decides on the cost (owner's
  decision, 2026-10-03). Nothing larger is pre-approved.
- A reboot of the control-plane machine needs the owner to supply the passphrase that unlocks its
  state volume, because the machine unlocks it at every boot through a prompt answered over SSH.
  So a control-plane reboot is never unattended, and the owner approves each one. The call machine
  holds no such volume and reboots unattended.
- A bad new version must be undoable without a second reboot decision: the machine is set to try
  the new version once and to fall back to the previous one if it does not come up healthy.
- While the control-plane machine reboots, the other services it hosts are down for a few
  minutes. This is accepted. Examples are photo storage, monitoring and streaming.
- A call cannot move live between machines. A call stays up through a control-plane reboot
  only because its machine does not reboot. This is why the call machine is patched only
  between calls.
- A highly available control plane is out of scope; its cost is not justified.
- The call machine is one small always-on server. Whether the smallest type is large and fast
  enough is unproven and is measured in the rehearsal. If it is not, the owner decides on a
  larger one (see FR-011).
- Patching in place on the current machine image, including its boot setup, is unproven and
  is tested on a disposable server first.
- Whether a running call survives the control-plane API being unavailable is unproven and is
  what the acceptance test shows.
- Dependencies: the existing infrastructure-as-code repositories for the cloud servers and the
  cluster, the node image build, and the deployment tooling already used in this repository.
- Constitution III applies: changes are made in code and applied through the normal path, and
  any live change to the running cluster needs the owner's explicit permission.

# Feature Specification: Agent Secret Broker

**Feature Branch**: `010-agent-secret-broker`

**Created**: 2026-11-17

**Status**: Draft

**Input**: User description: "Is there a decent way to allow LLMs to use secrets in 1Password that can allow you to unlock the vault allowing them access to specific secrets even if you are remote?" Follow-up: "yes please, package it in the nix-config", "create a spec for this too", "make it using speckit".

## Clarifications

### Session 2026-11-17

- Q: Unlock the user's own vault remotely, or give agents a separate, narrower identity? → A: A separate identity. The 1Password desktop app's unlock prompt appears only on the machine itself, so it cannot be answered from a phone. Agents instead get a read-only identity limited to one dedicated vault, and a human approval step sits in front of it.
- Q: Does this overlap spec 009 (agent control plane), User Story 3 (answer permission prompts remotely)? → A: Related but separate. Spec 009 answers an agent's tool-permission prompts. This feature decides whether a secret is released at all, and applies to any agent, including ones claude-monitor does not supervise. The two may share a notification channel later; neither depends on the other.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent uses a secret without ever seeing it (Priority: P1)

An agent needs a credential to do its job, for example an API token to call a service. Instead of the value, the agent is given a reference that names the secret. It asks the broker to run a command with that secret supplied. The broker resolves the reference, runs the command with the value available only to that command, and returns the command's output with any copy of the value masked. The value never appears in the agent's conversation, its transcript, or the broker's own log.

**Why this priority**: This is the core safety property. Without it, any secret the agent touches ends up in a transcript, a log or a model provider's context. It is useful on its own: it already beats pasting tokens into a session.

**Independent Test**: Put a canary secret (a random, unique value) in the agents' vault. Have an agent run a command that uses it and also tries to print it. Search the agent's transcript, the broker's output and its log for the canary value. It must appear nowhere. The command must still have succeeded with the real value.

**Acceptance Scenarios**:

1. **Given** a reference to a secret in the agents' vault, **When** an agent asks the broker to run a command with it, **Then** the command receives the real value and the agent receives the command's output with every occurrence of the value masked.
2. **Given** a reference to a secret outside the agents' vault, **When** an agent asks for it, **Then** the broker refuses, says the secret is not available to agents, and releases nothing.
3. **Given** a reference that does not exist, **When** an agent asks for it, **Then** the broker refuses with "not found" and does not say whether a similarly named secret exists elsewhere.
4. **Given** a command that prints the value in a transformed form (encoded, reversed, split), **When** it runs, **Then** the broker cannot promise to mask it; this residual risk is documented and the approval step (Story 2) is the control for it.

---

### User Story 2 - Approve a secret request from the phone while away (Priority: P1)

The user is away from their desk. An agent on one of their machines needs a secret. The user's phone shows a notification. It names the machine, the agent session, the secret, and the command that will receive it. The user taps Approve or Deny. On Approve, the command runs and the agent continues. On Deny, or if the user does nothing before the timeout, the request fails and nothing is released.

**Why this priority**: This is the "even if I'm remote" part of the request. With Story 1, it gives a complete, safe first release.

**Independent Test**: Start a request from an agent session on a test machine. Approve it from a phone on mobile data, not the home network. Confirm the command runs. Repeat with Deny, then with no answer, and confirm both fail closed. Tap Approve twice on one request and confirm the command ran once.

**Acceptance Scenarios**:

1. **Given** a pending request, **When** the user approves it from their phone, **Then** the command runs once and the agent receives its masked output.
2. **Given** a pending request, **When** the user denies it, **Then** the agent receives a refusal that says it was denied, and nothing is released.
3. **Given** a pending request, **When** the timeout passes with no answer, **Then** the request fails as timed out, and a later Approve on that notification changes nothing and says it expired.
4. **Given** the notification shows the command text, **When** that text contains control characters, very long strings or text crafted to look like a different command, **Then** the notification shows it literally, truncated at a stated length with a marker, so the user can see it was cut.
5. **Given** the notification channel is unreachable, **When** a request needs approval, **Then** the request fails closed with a message naming the channel as the cause.
6. **Given** two requests pending at once, **When** the user answers one, **Then** only that request is affected.

---

### User Story 3 - Standing rules for low-risk secrets (Priority: P2)

Asking for every use of every secret would train the user to tap Approve without reading. So the user can mark a secret as auto-approved, optionally only for a named command and only on named machines. They can mark another as always-ask, and another as never-for-agents. Deny rules win over allow rules.

**Why this priority**: It keeps approvals rare enough to mean something. The feature still works without it; every request simply asks.

**Independent Test**: Configure one auto-approved secret, one always-ask secret and one denied secret. Request each. Confirm the first runs with no notification, the second notifies, and the third is refused without notifying. Confirm each outcome is logged with the rule that decided it.

**Acceptance Scenarios**:

1. **Given** a secret with an auto-approve rule matching this machine and command, **When** an agent requests it, **Then** the command runs with no notification and the log records the rule that approved it.
2. **Given** a secret with an auto-approve rule for a different command, **When** an agent requests it for another command, **Then** the request falls back to asking the user.
3. **Given** a secret matching both an allow rule and a deny rule, **When** an agent requests it, **Then** it is refused.
4. **Given** an approval with a time window (for example "approve this secret for this session for 30 minutes"), **When** the same session requests it again within the window, **Then** it runs without a new notification; after the window it asks again.

---

### User Story 4 - Agents cannot go around the broker (Priority: P2)

The broker only helps if it is the sole way in. An agent must not be able to read the credential the broker uses, call the password manager's own tools directly, or read a secret's value from the broker's files.

**Why this priority**: Without it, Stories 1–3 are advisory. It ranks below them because a cooperative agent already uses the broker, and this story defends against a misbehaving one.

**Independent Test**: From an agent session, try to read the broker's credential file, run the password manager's command-line tool directly, and read the broker's state and log files. Each attempt must be blocked or yield nothing secret.

**Acceptance Scenarios**:

1. **Given** an agent session, **When** it tries to read the broker's credential, **Then** the read fails because the agent's user cannot access it.
2. **Given** an agent session, **When** it tries to run the password manager's own tool directly, **Then** the attempt is blocked with a message pointing to the broker.
3. **Given** the broker's log, **When** anyone reads it, **Then** it holds references and decisions only, never values.

---

### User Story 5 - Review what was released (Priority: P3)

Afterwards, the user wants to know what each agent got. They open the audit record and see each request: when, which machine and session, which secret, which command, who or which rule decided, and how it ended.

**Why this priority**: Accountability and tuning of the rules in Story 3. It is not needed for the first safe release.

**Independent Test**: Make five requests with mixed outcomes. Read the audit record and confirm all five are there, in order, with every field filled and times in ISO 8601 UTC.

**Acceptance Scenarios**:

1. **Given** any request, **When** it ends, **Then** one audit record exists for it with time requested, time decided, machine, session, secret reference, command, decision, decider, and outcome.
2. **Given** the password manager keeps its own access report, **When** the user compares it with the broker's records, **Then** every secret read the password manager reports has a matching approved broker record.

---

### User Story 6 - Turn it on per machine from the configuration repository (Priority: P3)

The user enables the broker on a machine by switching it on in that machine's configuration and rebuilding. The broker's credential comes from the repository's existing encrypted secrets. Machines that do not enable it are unchanged.

**Why this priority**: The user asked for it packaged this way. It is how the other stories are delivered, so it ranks last only as a story, not as work.

**Independent Test**: Enable the broker on one machine, rebuild, and run Story 1's test there. Build a machine without it enabled and confirm its configuration is unchanged.

**Acceptance Scenarios**:

1. **Given** a machine with the broker enabled and its credential present in the encrypted secrets, **When** it is rebuilt, **Then** the broker is available to agent sessions on that machine.
2. **Given** a machine with the broker enabled but no credential present, **When** it is built, **Then** the build fails with a message naming the missing secret, rather than producing a broker that fails at run time.

### Edge Cases

- The password manager service is unreachable or slow: the request fails after a stated timeout with that cause, and nothing is cached as a substitute.
- The broker's credential has been revoked or has expired: requests fail with a message that names this and the fix (rotate the credential in the encrypted secrets).
- The phone has no signal: the request times out and fails closed. No queued approval is honoured later.
- The approve link is opened by someone who is not the user (a forwarded notification, a leaked link): the approval must prove it came from the user's device, or it is ignored.
- An agent floods the broker with requests: notifications are rate-limited per session, excess requests are refused, and the user is told once that a session is flooding.
- The command run by the broker hangs: it is stopped at a stated limit, and the output so far is returned, masked.
- The secret value is very short or common (for example "1234"): masking would mangle unrelated output. Such values are flagged at configuration time.
- The machine sleeps or reboots while a request is pending: the request is treated as failed; nothing resumes on wake.
- A secret is rotated in the vault while an approval window is open: the next use gets the new value.

## Requirements *(mandatory)*

### Functional Requirements

**Release and masking**

- **FR-001**: The broker MUST accept a request naming a secret reference and a command, and MUST make the secret's value available only to that command's process.
- **FR-002**: The broker MUST return the command's output and exit status to the requester, with every literal occurrence of each released value replaced by a fixed mask.
- **FR-003**: The broker MUST NOT write a secret value to any log, state file, notification or error message.
- **FR-004**: The broker MUST only resolve secrets in the vault or vaults designated for agents, and MUST refuse any other reference without revealing whether it exists.
- **FR-005**: The broker's credential MUST be read-only and limited to the designated vaults.

**Approval**

- **FR-006**: Unless a rule in FR-011 decides it, every request MUST wait for the user's explicit approval before any value is released.
- **FR-007**: The approval prompt MUST reach the user's phone when the user is away from home, and MUST show the machine, the agent session, the secret reference and the command, rendered literally and truncated at a stated length with a visible marker.
- **FR-008**: An approval MUST be bound to one request, MUST be usable once, and MUST expire with the request.
- **FR-009**: An approval MUST be accepted only if it is shown to come from the user. Knowledge of the request's identifier alone MUST NOT be enough. [NEEDS CLARIFICATION: Which channel carries approvals: a public push relay with an unguessable topic, a self-hosted push service on the home cluster, or a chat bot? This decides what "shown to come from the user" can mean and whether new infrastructure is in scope.]
- **FR-010**: A request with no answer MUST fail closed after a timeout (default 120 seconds, configurable per machine).

**Rules**

- **FR-011**: The user MUST be able to declare, per secret, one of: auto-approve, ask every time, or never release to agents. An auto-approve rule MAY be narrowed to named commands and named machines.
- **FR-012**: Deny rules MUST take precedence over allow rules. A secret with no rule MUST ask.
- **FR-013**: When approving, the user MAY grant a time window for one secret and one session. [NEEDS CLARIFICATION: Should time-window grants be in the first release, and what is the longest window allowed? Windows cut notification fatigue but widen what a hijacked session can take.]
- **FR-014**: Rules MUST live in the configuration repository, so each change to them is reviewed and recorded.

**Bypass prevention**

- **FR-015**: The broker's credential MUST be readable only by the broker, not by the user account agents run as.
- **FR-016**: Agent sessions MUST be blocked from calling the password manager's own tools directly, with a message pointing to the broker.
- **FR-017**: Requests MUST be rate-limited per session (default: at most 5 pending and 20 per hour), with excess requests refused and the user told once.

**Audit**

- **FR-018**: The broker MUST record every request with: time requested, time decided, time finished (ISO 8601 UTC), machine, session, secret reference, command, decision, decider (the user or the rule that matched), and outcome.
- **FR-019**: Audit records MUST be append-only from the agent's point of view.

**Packaging**

- **FR-020**: The broker MUST be enabled per machine from the configuration repository. Machines that do not enable it MUST be unchanged.
- **FR-021**: The broker's credential MUST come from the repository's encrypted secrets. A machine that enables the broker without the credential MUST fail to build with a message naming the missing secret.
- **FR-022**: The broker MUST work from any agent that can run a command, with Claude Code as the first supported agent. [NEEDS CLARIFICATION: Must cloud agent sessions (which run outside the user's machines) be able to request secrets in the first release? That needs the broker reachable from the internet, not only from the local machine.]

### Key Entities

- **Secret reference**: A name that identifies one secret field in a designated vault. It is safe to show to agents and in notifications.
- **Access request**: One ask to run one command with one or more secrets. It has a requester (machine and session), the command, the references, a state (pending, approved, denied, timed out, refused, finished) and its timestamps.
- **Rule**: The per-secret policy: auto-approve (optionally narrowed to commands and machines), ask, or never.
- **Grant**: An approved time window for one secret and one session, with an expiry.
- **Decision**: Who or what settled a request: the user (with the device it came from) or a named rule.
- **Audit record**: The permanent record of one request, from creation to outcome. It never holds a value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the canary test, the canary value appears 0 times across the agent transcript, the broker output, the broker log and the audit record, over 20 runs that include deliberate attempts to print it.
- **SC-002**: From a phone on mobile data, the user can approve a request and see the agent continue within 30 seconds of the request being made, in 9 of 10 attempts.
- **SC-003**: 100% of requests that are denied, unanswered or blocked by a failed channel release nothing; the user's phone receives at most one notification per request.
- **SC-004**: With rules configured for the user's routine secrets, the user receives at most 5 approval prompts in a typical working day.
- **SC-005**: Every secret read in the password manager's own access report over one week has a matching approved broker record.
- **SC-006**: Each of the bypass attempts in Story 4 fails in 100% of tries.
- **SC-007**: Enabling the broker on a new machine takes one configuration change and one rebuild, plus one secret added to the encrypted secrets.

## Assumptions

- The user creates the agents' vault and its read-only service identity in 1Password by hand. That is a change to a live account, outside this repository, and needs the user's own action.
- 1Password service accounts can be limited to chosen vaults and to read-only access, and they cannot reach the user's Private vault. This was true when written; the plan must check it against current 1Password documentation.
- Masking catches only literal copies of a value. An approved command can still leak a value in a changed form. The approval step and the rules are the control for this, and the broker limits harm rather than preventing it.
- The first machines are the user's Linux workstations (ali-desktop and ali-framework-laptop). macOS hosts are a later slice.
- Agents run as the user's own account. The broker therefore runs as a separate account or under a separate service identity, so its credential is not readable by agents.
- Secrets the agents need are low-power, narrow credentials (scoped tokens, read-only keys) put into the agents' vault for this purpose. Master credentials stay in other vaults.
- Times are recorded in ISO 8601 UTC.
- Spec 009's remote permission prompts are not required for this feature.

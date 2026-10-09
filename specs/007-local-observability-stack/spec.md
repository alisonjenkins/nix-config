# Feature Specification: Local Observability Stack

**Feature Branch**: `007-local-observability-stack`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "I want to setup loki, tempo and grafana declaratively using Nix on both MacOS and Linux using containers. The aim to be to have tracing for Claude Code and the new memory and skills store that we have" (follow-up: "let's setup prometheus too")

## Clarifications

### Session 2026-10-09

- Q: How does the scheduled review run? → A: Fully automatic, in two tiers: a low-cost model pulls and condenses the data, a stronger model analyses it and drafts findings, unattended on schedule. The owner still decides on every finding.
- Q: Whose data does a review cover? → A: Per host. Each host's stack and review cover only that host; decision records are shared through the repository and name the host they came from.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bring up the stack from config on either OS (Priority: P1)

The owner enables one option in their Nix configuration on a Linux machine or a macOS machine, switches, and gets a working local logs + traces + metrics + dashboards stack running in containers. No manual container commands, no hand-edited config files. The same option set works on both operating systems.

**Why this priority**: Nothing else has value until the stack exists and is reproducible on both platforms.

**Independent Test**: On one Linux host and one macOS host, enable the option, switch, open the dashboard UI, and see the log, trace and metric data sources reported healthy.

**Acceptance Scenarios**:

1. **Given** a host with the option off, **When** the owner enables it and switches, **Then** the log store, trace store, metric store and dashboard UI are running and the dashboard lists all three stores as healthy data sources without manual setup.
2. **Given** the stack is running, **When** the owner disables the option and switches, **Then** the services stop and no stack containers remain running.
3. **Given** a machine reboot or login, **When** the system comes back, **Then** the stack is running again without manual action.
4. **Given** the same configuration on Linux and macOS, **When** each is switched, **Then** both end in the same observable state (same ports, same data sources, same dashboards).

---

### User Story 2 - See Claude Code sessions as traces and logs (Priority: P1)

The owner runs Claude Code as usual. Each session's activity (prompts, model calls, tool calls, their durations, token and cost figures, errors) arrives in the stack as traces and logs, and can be browsed in the dashboard UI without extra steps per session.

**Why this priority**: This is the stated aim: visibility into Claude Code behaviour.

**Independent Test**: Run one short Claude Code session that calls at least one tool, then find that session's trace in the dashboard within one minute, with tool calls shown as timed steps.

**Acceptance Scenarios**:

1. **Given** the stack is running and Claude Code telemetry is wired by the same configuration, **When** a session runs a prompt that uses tools, **Then** a trace for that prompt appears with a step per model call and per tool call, each with duration.
2. **Given** a finished session, **When** the owner searches logs by session identifier, **Then** all events for that session are returned in time order.
3. **Given** Claude Code has run for several sessions, **When** the owner charts token usage, cost, tool-call counts and error counts over time, **Then** the metric store returns those series, split by model and by tool.
4. **Given** the stack is stopped, **When** Claude Code runs, **Then** Claude Code works normally with no visible error or noticeable delay.

---

### User Story 3 - Find where tokens are spent and what to optimise (Priority: P1)

The purpose of the whole stack is to cut token use and cost. The owner can see, over any period, where tokens go: by session, project, model, tool, skill, MCP server, sub-agent, injected memory and fixed context (system prompt, instructions files, tool schemas), plus cache hit rate and context size per turn. The owner can rank these by cost and spot the biggest repeat offenders, such as a tool whose output is large and rarely used, a skill loaded and ignored, or a sequence of calls that a single purpose-built tool could replace. Each finding is concrete enough to decide "build a tool for this".

**Why this priority**: This is the reason the feature exists. Traces and dashboards without cost attribution only describe behaviour; they do not tell the owner what to change.

**Independent Test**: After a week of normal use, open the cost view, list the top 5 token consumers by category, and for each one see enough detail (counts, sizes, examples) to write a one-paragraph proposal for a tool or config change that would reduce it.

**Acceptance Scenarios**:

1. **Given** a week of sessions, **When** the owner opens the cost view, **Then** total tokens and estimated cost are broken down by session, project, model, tool, skill, MCP server and sub-agent, and the breakdowns add up to the total.
2. **Given** a tool, **When** the owner inspects it, **Then** they see call count, average and maximum result size, share of total tokens, and how often its output was followed by a repeat or near-identical call.
3. **Given** a session, **When** the owner inspects it, **Then** they see context size per turn, cache hit rate, and the share of tokens that are fixed context sent every turn versus new content.
4. **Given** injected memories and skill sections, **When** the owner inspects recall, **Then** they see tokens injected per prompt and how often injected items were then used or ignored, so the cost of recall can be weighed against its benefit.
5. **Given** a candidate change (new tool, trimmed skill, pruned server), **When** it has been in use for a period, **Then** the owner can compare the same figures before and after.

---

### User Story 4 - Run a regular review that turns data into decisions (Priority: P1)

Collecting data is not the goal; acting on it is. The owner follows a defined, repeatable review workflow: on a set cadence (and on demand), the stack's data is analysed against a fixed list of questions ("which tools return the most tokens per use", "which skills are loaded and unused", "which sessions had the worst cache hit rate", "which injected memories were ignored"). The analysis produces a short ranked list of findings, each with evidence. The owner then decides for each finding: build a tool, change configuration, or dismiss with a reason. Decisions are recorded, acted on, and re-checked in a later review to confirm they worked. Claude can run the analysis and draft the findings; the owner makes the decisions.

**Why this priority**: Without this, the stack becomes a data swamp: lots of signals, no decisions. It is what makes story 3 produce outcomes.

**Independent Test**: Run one review end to end on a week of data: the analysis completes, produces a ranked findings list with evidence, the owner records at least one decision per finding, and a follow-up review shows the status of earlier decisions.

**Acceptance Scenarios**:

1. **Given** a period of collected data, **When** the owner starts a review, **Then** a findings list is produced within 10 minutes, ranked by estimated tokens or cost saved, each with evidence (counts, sizes, example sessions) and a suggested action.
2. **Given** a finding, **When** the owner decides, **Then** the decision (build, configure, dismiss), its reason and date are recorded in a durable, version-controlled record that outlives raw data retention.
3. **Given** an earlier decision that was acted on, **When** the next review runs, **Then** it reports the before/after change for the affected figures and marks the decision as effective, ineffective or inconclusive.
4. **Given** a dismissed finding, **When** the same pattern appears again, **Then** it is shown as previously dismissed with the reason, and is not re-raised as new unless it has grown materially.
5. **Given** a signal that no review question uses, **When** the review runs, **Then** it is listed as unused so the owner can drop it or give it a question.
6. **Given** no new data or an unreachable stack, **When** a review is started, **Then** it reports that clearly and produces no findings rather than stale ones.
7. **Given** the weekly schedule, **When** it fires with no one at the keyboard, **Then** a low-cost model runs the review questions against the stack and writes a compact, size-bounded data digest, a stronger model reads only that digest and drafts the ranked findings, and the findings are waiting for the owner at the next session.
8. **Given** a scheduled run that failed or was missed (machine off, stack down), **When** the owner next looks, **Then** the failure and its cause are visible, and the next run covers the missed period.

---

### User Story 5 - See memory and skill store activity (Priority: P2)

The owner can see what the memory and skills retrieval store does: each recall request, which memories and skill sections matched and at what similarity score, what was injected, how long it took, and failures (for example the embedding server being down). These show up in the same dashboard, linkable to the Claude Code prompt that triggered them.

**Why this priority**: Second stated aim. It depends on the stack (story 1) and is most useful alongside story 2.

**Independent Test**: Submit a prompt that triggers recall; find the recall entry in the dashboard with matched items, scores and latency, and navigate from it to the surrounding Claude Code trace.

**Acceptance Scenarios**:

1. **Given** the stack and memory recall are enabled, **When** a prompt triggers recall, **Then** a recall record appears with the query time, number of candidates, matches above threshold with their scores, and total latency.
2. **Given** recall returns nothing or fails, **When** the owner looks at the dashboard, **Then** the empty or failed outcome is visible with its cause, not absent.
3. **Given** a recall record and a Claude Code trace from the same prompt, **When** the owner follows the link between them, **Then** both resolve to the same prompt.
4. **Given** recall has run for several days, **When** the owner charts recall request rate, hit rate, latency and failure count over time, **Then** the metric store returns those series.

---

### User Story 6 - Ready-made dashboards and persistent history (Priority: P3)

The owner opens the dashboard UI and finds provisioned dashboards for Claude Code (sessions, tool latency, token and cost trends, error rate), for token cost attribution (story 3) and for recall (hit rate, score distribution, latency). Data survives restarts and is pruned automatically after a bounded retention period.

**Why this priority**: Makes the data usable at a glance; the raw explorer already works without it.

**Independent Test**: After a day of normal use, open each dashboard and see populated panels; restart the stack and confirm earlier data is still queryable; confirm disk use stays under the configured bound.

**Acceptance Scenarios**:

1. **Given** a fresh switch, **When** the owner opens the dashboard UI, **Then** the Claude Code, token cost and recall dashboards already exist.
2. **Given** data older than the retention period, **When** retention runs, **Then** that data is removed and newer data remains.
3. **Given** a stack restart, **When** the owner queries yesterday's session, **Then** it is still there.

---

### User Story 7 - A skill guides the review and the design of token-efficient tools (Priority: P2)

The owner (and Claude acting for them) has a skill that carries the know-how for two jobs: reviewing the collected metrics, logs and traces for token waste, and designing the tool that fixes a finding so it is token efficient. When a review starts, or the owner says "design a tool for this finding", the skill loads and walks through the method: which questions to ask, how to read each view, how to rank findings, how to turn a finding into a tool design (what the tool returns, how small its output is, whether it is a server or a command-line tool per the experiment), and how to measure the result.

**Why this priority**: The review (story 4) and tool building depend on repeatable judgement. Without a written method each review re-derives it, which wastes tokens and gives inconsistent results. It is P2 because the review can run once by hand before the skill exists, and the skill is best written from that first run.

**Independent Test**: Start a fresh session with no prior context, ask for a review of last week's data, and get a findings list that follows the skill's method; then ask for a design of a tool for the top finding and get a design that meets the skill's token-efficiency checklist.

**Acceptance Scenarios**:

1. **Given** a fresh session, **When** the owner asks for a review of recent token spend, **Then** the skill loads on its own and the session follows its question list and ranking method.
2. **Given** a finding, **When** the owner asks for a tool design, **Then** the design states expected output size, what is filtered or summarised before it reaches the model, how many calls a typical task needs, the delivery mechanism and why, and how success will be measured with the stack.
3. **Given** a proposed design that fails the token-efficiency checklist (for example unbounded output, or a schema larger than the task it serves), **When** the skill reviews it, **Then** it names the failing item and a fix.
4. **Given** a tool built from such a design, **When** a later review runs, **Then** the skill's method compares its real token cost against the design's estimate and records the gap.
5. **Given** the skill is installed, **When** it sits idle, **Then** its idle context cost is no more than a short description line of at most 100 tokens.

---

### Edge Cases

- Container runtime not installed or not running (macOS especially): switch must fail or warn with a clear message naming the missing runtime, not leave a half-working stack.
- Port already in use on the host: the failure names the port and the owner can change it by option.
- Telemetry contains prompt text or file contents: sensitive content capture is off by default and enabling it is an explicit option.
- Stack is reachable only from the local machine by default; exposure to other hosts is opt-in.
- Image pulls offline or registry unreachable: already-pulled versions keep running; pinned versions make upgrades deliberate.
- Disk fills: retention bounds growth; the guard reports the exceeded disk budget (metric, dashboard, session-start notice, desktop notification) and never stops ingestion.
- Multiple Claude Code sessions in parallel: traces stay separate per session.
- Host sleeps or suspends: services resume without manual action and without corrupting stored data.
- A figure needed for attribution is not available from Claude Code: the cost view shows it as unavailable and lists the gap, never as zero.
- Decision records and review output hold aggregates and short evidence references, not prompt text or file contents, so they are safe to keep in the repository.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The stack (log store, trace store, metric store, dashboard UI) MUST be fully defined in the Nix configuration, including service config, data sources and dashboards, with no manual post-install steps.
- **FR-002**: The stack MUST run in containers on both Linux (NixOS hosts and non-NixOS hosts with user-level config only) and macOS, driven by one shared option set.
- **FR-003**: Container images MUST be pinned to explicit versions so that a given configuration revision produces the same stack.
- **FR-004**: The stack MUST be off by default and enabled per host by one option.
- **FR-005**: Data sources for logs, traces and metrics MUST be provisioned automatically, and navigation MUST work between a trace and its logs, and from a trace to related metrics.
- **FR-006**: The system MUST route Claude Code's telemetry (traces, logs and metrics) to the stack when enabled, configured by the same Nix option, and MUST NOT require per-session setup.
- **FR-007**: Claude Code MUST continue to function normally when the stack is down or disabled.
- **FR-008**: The memory/skills retrieval store MUST emit a record per recall request containing: request time, candidate count, matches with scores, injected items, latency, and outcome (success, empty, error with cause).
- **FR-009**: Recall records MUST be correlatable with the Claude Code trace of the prompt that triggered them.
- **FR-010**: The memory/skills retrieval store MUST also expose counters and latency figures (request rate, hit rate, failure count, latency) as metrics.
- **FR-011**: The metric store MUST also record the health of the stack's own components, so the owner can see when a store is down or dropping data.
- **FR-012**: Prompt text, file contents and other potentially sensitive payloads MUST NOT be captured unless explicitly enabled by option.
- **FR-013**: All stack endpoints MUST listen on the local machine only by default; wider exposure MUST be an explicit option.
- **FR-014**: Ports and retention period MUST be configurable by option, with defaults that do not collide with other services in this repository.
- **FR-015**: Stored data MUST persist across restarts and reboots, and MUST be pruned automatically after the retention period.
- **FR-016**: The stack MUST start automatically at boot/login and restart on failure.
- **FR-017**: Provisioned dashboards MUST exist for Claude Code activity, token cost attribution and recall activity.
- **FR-018**: Failure to start (missing container runtime, port conflict) MUST produce an error naming the cause and the fix.
- **FR-019**: The feature MUST be verifiable by an automated check that evaluates the configuration for both OS families without needing the containers to run.
- **FR-020**: The system MUST record, per model call, input, output, cache-read and cache-write token counts, and attribute them to session, project, model and sub-agent.
- **FR-021**: The system MUST attribute tokens to tools (result size per call), skills (when loaded), MCP servers (tool schemas and results), injected memories and fixed context, so each category can be totalled and ranked.
- **FR-022**: The system MUST show estimated cost per category using list prices that the owner can update by option, and MUST label figures as estimates.
- **FR-023**: The system MUST show context size per turn and cache hit rate per session.
- **FR-024**: The system MUST surface repeat patterns that suggest a missing tool: identical or near-identical tool calls within a session, large tool results followed by narrowing queries, and long sequences of small calls that always occur together. Detection MUST work without storing tool input content: a keyed one-way hash and a size per call are enough.
- **FR-025**: The owner MUST be able to compare any cost figure across two time ranges, to judge the effect of a change.
- **FR-026**: The token and cost views MUST be reproducible from retained data alone, with no reliance on a separate billing export.
- **FR-027**: The system MUST define a review workflow with a fixed, versioned list of review questions, each tied to specific signals and to the decision it informs.
- **FR-028**: A review MUST be runnable on demand and on a schedule, and MUST output a ranked findings list with evidence and a suggested action per finding.
- **FR-029**: Whenever Claude analyses the stored data, in a review or on request, the tools it uses MUST return bounded summaries and rankings and never raw logs or traces by default, so the analysis itself stays cheap in tokens.
- **FR-030**: The review MUST work in two tiers: a low-cost model pulls the data and condenses it into a size-bounded digest, and a stronger model analyses only the digest (plus drill-downs it explicitly requests) to draft findings. If the low-cost tier fails or hits its spend ceiling, a mechanical, model-free digest MUST be used instead and marked as such.
- **FR-031**: The scheduled review MUST run unattended with no prompt from the owner, MUST have a configurable token or spend ceiling per run that stops it when reached, and MUST leave its findings where the next session can find them.
- **FR-032**: The model used for each tier MUST be configurable by option.
- **FR-033**: Each finding MUST end in a recorded decision (build, configure, dismiss) with reason and date, stored in a durable, version-controlled record that persists beyond the 30-day data retention.
- **FR-034**: The review MUST compare each acted-on decision's affected figures before and after, and report the outcome in the next review.
- **FR-035**: The review MUST suppress re-raising dismissed findings unless they have grown materially, and MUST show the earlier reason.
- **FR-036**: The review MUST list collected signals that no review question uses, so unused collection can be removed.
- **FR-037**: The review's own cost (tokens spent running it) MUST be reported, and MUST be small relative to the savings it identifies.
- **FR-038**: Before the review runner and the skill are finalised (the query logic may exist first, as one library both options wrap), the way Claude reaches the review tools (as a tool server speaking the Model Context Protocol, or as a command-line tool described by a skill) MUST be chosen by a recorded experiment, not by assumption. The experiment MUST run the same set of representative review tasks through each option and compare: fixed context cost per session when idle, tokens per task end to end (including schema or instruction loading, calls and results), number of turns, task success rate, and ease of use on both Linux and macOS.
- **FR-039**: The experiment's result and reasoning MUST be recorded as a decision record. If the options are within 10% on tokens per task, the one with the lower fixed context cost and simpler maintenance wins.
- **FR-040**: A skill MUST exist that guides (a) reviewing the stack's data for token waste and (b) designing a token-efficient tool for a finding. It MUST contain the review question list, the ranking method, how to read each data view, and a token-efficiency design checklist.
- **FR-041**: The design checklist MUST cover at least: bounded and summarised output, filtering before the model sees data, minimal fixed schema or instruction size, calls per typical task, error messages that let the model self-correct, and a measurement plan using the stack.
- **FR-042**: The skill MUST load only when relevant (review or tool-design requests) and MUST keep its idle cost to a short description of at most 100 tokens; detail MUST sit in files read on demand.
- **FR-043**: The skill MUST be portable across the owner's machines: it MUST NOT assume particular tools are installed or hard-code paths, and MUST work on Linux and macOS.
- **FR-044**: The skill MUST be updated from the results of reviews and of the delivery-mechanism experiment (FR-038), so its guidance reflects measured results, not assumptions.
- **FR-045**: The chosen mechanism MUST also be what the stack's own telemetry measures (the owner's usage of it appears in the cost views), so the choice can be re-checked later with real data.

### Key Entities

- **Telemetry Stack**: The set of log store, trace store, metric store and dashboard UI, with its ports, retention, data location and enable switch.
- **Claude Code Session**: One run of Claude Code, containing prompts; each prompt has model calls and tool calls with durations, token and cost figures, outcomes.
- **Token Account**: Token counts (input, output, cache read, cache write) for one model call, with the session, project, model, sub-agent and category (tool, skill, MCP server, memory, fixed context) they are attributed to, and an estimated cost.
- **Optimisation Candidate**: A ranked finding (category, share of cost, evidence, examples) from which the owner decides to build a tool or change configuration; has a before/after comparison once acted on.
- **Review Question**: A fixed question the review asks of the data (for example, which tools return the most tokens per use), tied to the signals it needs and the kind of decision it informs.
- **Review**: One run of the workflow over a period: the findings it produced, its own cost, and the status of earlier decisions.
- **Decision Record**: The owner's durable decision on a finding (build, configure, dismiss), with host, reason, date, affected figures and, later, the measured outcome.
- **Recall Record**: One memory/skill retrieval request: query time, candidates, matches with scores, injected items, latency, outcome; links to its prompt.
- **Data Source**: A provisioned connection from the dashboard UI to the log store, trace store or metric store.
- **Dashboard**: A provisioned view over sessions, token cost or recall records.
- **Retention Policy**: How long data is kept before automatic removal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a clean host, enabling the option and switching yields a working stack in under 10 minutes, including first image pulls, with zero manual steps, on both Linux and macOS.
- **SC-002**: 100% of Claude Code prompts run while the stack is up appear as traces within 1 minute of completion.
- **SC-003**: 100% of recall requests while the stack is up have a visible record, including empty and failed ones.
- **SC-004**: From a recall record, the owner reaches the matching Claude Code trace in at most 2 clicks.
- **SC-005**: Claude Code prompt latency with the stack enabled is within 5% of latency with it disabled, and unchanged when the stack is down.
- **SC-006**: After one week of use, the owner can name the top 5 token consumers by category and, for each, state a concrete tool or config change, using only the dashboard, in under 30 minutes.
- **SC-007**: Per-category token figures sum to within 5% of the per-session totals reported by Claude Code.
- **SC-008**: Within 8 weeks of use, at least 3 optimisation candidates have been acted on, and each has a before/after comparison showing the effect on tokens or cost.
- **SC-009**: A full review completes in under 10 minutes of owner attention, and its own token cost, scheduled runs included, is under 1% of the spend it analyses.
- **SC-010**: After 8 weeks, 100% of findings from reviews have a recorded decision, and no review question is left without a signal or a signal without a question, other than ones listed for removal.
- **SC-011**: A recorded comparison of both delivery options exists, covering at least 5 representative review tasks and 3 runs each, with token totals per option, before the review runner and the skill are finalised.
- **SC-012**: A fresh session with no prior context, given only "review last week's token spend", produces a findings list that follows the skill's method in at least 4 of 5 trials.
- **SC-013**: Tool designs produced with the skill state an output size estimate, and for built tools the measured output size is within 2x of the estimate in at least 80% of cases.
- **SC-014**: Disk use is held to the configured disk budget (default 20 GB) over 60 days of daily use (two full retention periods), or the budget being exceeded is reported; exceeding it never stops ingestion.
- **SC-015**: Both configurations evaluate cleanly in the automated check, and a reboot returns the stack to a working state with no manual action, on both OS families.

## Assumptions

- The owner is the only user; the stack is single-tenant, local, and not a shared team service.
- "Memory and skills store" means the existing embedding-based memory and skill recall (spec 006, `modules.memoryRecall`); it needs new instrumentation to emit recall records.
- Claude Code's built-in telemetry export is the source of session traces and logs; no custom wrapper around Claude Code is needed. Where it does not expose a figure needed for attribution (for example per-tool result size or per-category split), a hook or transcript reader supplies it. Which figures are missing is a planning finding.
- The goal of the feature is to lower token use and cost by finding where to build better tools for Claude. Building those tools is out of scope here; each becomes its own feature.
- Open research question (answered during planning, not guessed here): which is cheaper in tokens for the review tools, a server speaking the Model Context Protocol or a command-line tool with a skill that teaches its use. Existing evidence in this repository points both ways: the MCP aggregation gateway already cut idle context by hiding downstream tool names, while skills load their body only when used. The experiment (FR-038) settles it for this workload; other workloads may differ. The experiment runs as soon as the query library exists and before the review runner is built, because the answer shapes how the review calls the tools.
- The skill is written after the first manual review and the delivery-mechanism experiment, so it captures what worked. A first draft of the method may precede them but is marked provisional.
- The skill is shared across the owner's machines, so it lives with the owner's other shared skills; where it lives is a planning decision.
- Review cadence defaults to weekly; the owner can run one on demand. Decision records live in the repository (alongside existing decision records), so they are version-controlled and survive raw data expiry.
- Findings are advisory. The system never changes configuration or builds tools on its own; the owner decides. Only the analysis is unattended.
- Each host with the option on runs its own scheduled review over its own data. Decision records are shared through the repository and name the host. Combining data across hosts is out of scope for v1.
- Raw data is kept 30 days; the review's findings and decisions are the long-term record, so the review cadence must be shorter than the retention.
- Cost is shown in tokens and as an estimate at list API prices. If usage is on a flat-rate plan, the estimate still ranks categories correctly but is not a bill.
- A trace collector component sits between emitters and the stores if required for routing; it is part of the stack, not a separate feature.
- Container runtime on Linux is the one already used in this repository or a rootless equivalent; on macOS a runtime is provided by the existing setup. Exact choice is a planning decision.
- Metrics are in scope (added after the first draft). Claude Code's built-in OpenTelemetry metrics and recall metrics land in the metric store; the stack's own health is scraped. Alerting stays out of scope, so no alert manager in v1.
- Retention default is 30 days for logs, traces and metrics alike, with a 20 GB total disk budget shared across all stores, reported when exceeded and never stopping ingestion; both are configurable.
- Authentication on the dashboard UI is unnecessary while it is bound to localhost only.
- Remote access over Tailscale or similar, alerting, and multi-host aggregation are out of scope for v1.
- Hosts in scope: any host that opts in; initial verification on `ali-desktop` (Linux) and the macOS work host (flake `ali-work-laptop-macos`, hostname `Alisons-MacBook-Pro`).

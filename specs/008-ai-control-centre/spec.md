# Feature Specification: AI Control Centre

**Feature Branch**: `008-ai-control-centre`

**Created**: 2026-10-12

**Status**: Draft

**Input**: User description: "I created a tool called claude-monitor that allows me to list the claude sessions that I have with their status but I need to take things to the next level. I tend to work on many things in parallel as I have ADHD. However I tend to lose track of what Claude Code / Copilot / Other AI agents are working on as I tend to do this over the course of days. Additionally these agents tend to be working on large projects and I lose track of where we are at within those projects. I need your help to create a kind of overview system that allows me to keep track of where things are at and what things are doing. I would also like it to keep track of them even if the sessions are killed. They are often spawned in worktrees and in the case of at least claude code to be able to resume you need to be in the worktree. I sometimes need to reboot the machine and because there are so many sessions across so many worktrees I will often forget to resume the work on them. We need to keep track of them all and be able to respawn them."

## Clarifications

### Session 2026-10-12

- Q: Shape of the terminal tool? → A: One program that is both an interactive view and a command line tool, built as a reusable library with the program as a thin consumer of it (to make testing and re-use, including the cortexiphan merge, easier).
- Q: What happens to finished sessions? → A: They stay visible and respawnable (never hidden by the system). When the user marks a finished session done, it moves to a Done section for review; the overview has one and every project has its own.
- Q: Where does the user use the overview? → A: Both a terminal view and a web view are required in the first release.
- Q: How are task description and "where we left off" produced? → A: Verbatim from the session by default (opening request, latest agent message); a model-written summary is available on demand only, run on the user's machine and stored once made.
- Q: Where does project progress come from? → A: The agent's own todo list, spec-kit `tasks.md` files, and any Markdown checklist in the repository; the source is always named and ambiguity is resolved by the user.
- Q: Which agents are supported in the first release? → A: Claude Code and Copilot, both fully (state and resume), plus a documented way to add more.
- Q: What happens after a reboot? → A: After login the user is shown the interrupted sessions and respawns them with one action; nothing starts without the user, and the user can opt out of individual sessions in that list.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One-glance overview of all AI work (Priority: P1)

The user runs many AI agent sessions at once, across several repositories and worktrees, over days. They open one view and see every piece of AI-driven work in one list: which agent (Claude Code, Copilot, others), which repository and worktree, what it is working on in plain words, whether it is working, waiting for them, idle or finished, and how long since it last did anything. Work that needs the user (waiting on a permission or a reply) is visibly separated from work that is progressing on its own.

**Why this priority**: The core pain is losing track. Without a trustworthy single view nothing else (history, resume) has a place to live. It is also useful on its own, as an upgrade of the existing session list.

**Independent Test**: Start three agent sessions in three different worktrees, leave them in different states, open the overview, and confirm each appears once with correct agent, location, state, a readable description of its task and time since last activity.

**Acceptance Scenarios**:

1. **Given** sessions from two different agent kinds running in three worktrees, **When** the user opens the overview, **Then** all three appear in one list, each labelled with agent kind, repository, worktree/branch, state and last-activity age.
2. **Given** one session is waiting for the user's input and another is busy, **When** the user views the overview, **Then** the waiting one is distinguished and listed so it is noticed first.
3. **Given** a session whose state changes (busy to waiting), **When** the user looks at the overview again, **Then** the new state shows without any manual refresh step beyond reopening or the view's own live update.

---

### User Story 2 - Work survives dead sessions (Priority: P1)

When a session is closed, killed, crashes, or the machine reboots, its record stays. The overview keeps listing it as "not running" together with everything known about it: where it ran, what it was doing, when it last did anything, and how it ended if known. Nothing the user was working on silently disappears from view.

**Why this priority**: The user explicitly reboots and loses sessions, and forgets them. Persistence is the precondition for resuming and equal in importance to the overview.

**Independent Test**: Start sessions, kill them (including a hard kill and a reboot), reopen the overview, and confirm every session is still listed as not running with its location and last-known task intact.

**Acceptance Scenarios**:

1. **Given** a running session, **When** its process is killed abruptly, **Then** the overview lists it as not running (not as running, and not removed) with its last known state and task.
2. **Given** several sessions were running before a reboot, **When** the user opens the overview after boot, **Then** all of them are listed as not running and flagged as "interrupted" rather than "finished".
3. **Given** a session ended cleanly, **When** the user views the overview, **Then** it is marked finished, listed in the finished group, and kept out of the "needs resuming" group, but is not hidden.
4. **Given** a finished session whose work turned out not to be done, **When** the user respawns it, **Then** it starts like an interrupted one (recorded worktree, conversation resumed where supported) and returns to the active group.

---

### User Story 3 - Respawn sessions where they were (Priority: P1)

For any not-running session the user can respawn it in one action. The agent is relaunched resuming the original conversation, in the correct worktree directory, even when that requires the working directory to match. The user can do this for one session or select several, or all interrupted ones at once, for example straight after a reboot.

**Why this priority**: Resuming is the stated end goal ("be able to respawn them"). Claude Code can only resume from the worktree it was started in, so correct placement is the whole difficulty.

**Independent Test**: After a reboot (or killing sessions), select one not-running Claude Code session in a worktree and respawn it; confirm the agent opens in that worktree with the prior conversation resumed. Then respawn all interrupted sessions in one action and confirm each lands in its own worktree.

**Acceptance Scenarios**:

1. **Given** a not-running Claude Code session recorded in worktree W, **When** the user respawns it, **Then** a new terminal-hosted agent starts in W with the original conversation resumed.
2. **Given** five interrupted sessions, **When** the user chooses "respawn all interrupted", **Then** all five start, each in its own worktree, and the overview shows them as running again without duplicates.
3. **Given** a session whose worktree no longer exists, **When** the user tries to respawn it, **Then** the action fails with a message naming the missing path and offering alternatives (recreate it if its branch still exists, or open the repository's main checkout), and no session is started in the wrong place.
4. **Given** the machine has just rebooted and the user logs in, **When** login completes, **Then** the user is shown the interrupted sessions, can deselect some, and respawns the rest with one action; no session starts before that action, and deselected ones stay listed as interrupted.
5. **Given** an agent kind that cannot resume a conversation, **When** the user respawns it, **Then** it starts fresh in the right directory and the user is told that prior conversation was not restored.

---

### User Story 4 - Know where large projects stand (Priority: P2)

Agents often work on large, multi-step projects. For each session or project the user can see where it is in the larger effort: the goal, the steps done, the step in progress, and what remains, taken from the plan or task list the agent is already working from (for example a spec's task list or an agent's own todo list). A sentence-long "where we left off" summary is shown so the user can re-enter the work after days away.

**Why this priority**: The second stated pain (losing the thread within big projects). It depends on the overview and persistence existing, and is valuable but not needed for a usable MVP.

**Independent Test**: For a session working through a task list with 10 items, 4 done, confirm the overview shows "4 of 10", names the current item, and gives a "where we left off" summary that survives the session being killed.

**Acceptance Scenarios**:

1. **Given** a session driving a task list with known progress, **When** the user views its detail, **Then** goal, completed count, current step and remaining steps are shown.
2. **Given** a session with no discoverable plan, **When** the user views it, **Then** it still shows its task description and last activity and does not show a fabricated progress figure.
3. **Given** the session is dead, **When** the user views its detail days later, **Then** the last known progress and "where we left off" summary are still shown.

---

### User Story 5 - Group, annotate and tidy (Priority: P3)

The user can group sessions under a named project or topic, add a short note ("blocked on review", "come back after deploy"), mark a session as parked or dismissed, and hide dismissed work from the default view without deleting its history. Finished work stays visible (in its own group below active work) because "finished" only means the session ended cleanly, not that the work was done. They can search or filter by repository, agent, state, project or text.

**Why this priority**: Makes the overview scale to dozens of sessions over weeks, but the earlier stories deliver value without it.

**Independent Test**: Group three sessions under one project, add a note to one, dismiss another, mark a finished one done, and confirm the default view shows the group, the note, the done one in the project's Done section, hides the dismissed one, and that a filter brings the dismissed one back.

**Acceptance Scenarios**:

1. **Given** three sessions in different worktrees of one repository, **When** the user groups them, **Then** the overview shows them under one named project with a combined state summary.
2. **Given** a finished session in project P and another finished session in no project, **When** the user marks both as done, **Then** the first appears in P's own Done section and the second in the overview's Done section, neither appears in any finished group, and both stay fully reviewable.
3. **Given** a done session, **When** the user unmarks it, or respawns it because the work was not complete, **Then** it leaves the Done section (to the finished group, or to the active group when respawned).
4. **Given** a dismissed session, **When** the user views the default list, **Then** it is hidden, and **When** they filter to include dismissed, **Then** it appears with its history intact.

---

### User Story 6 - Ready to merge into cortexiphan (Priority: P2)

The user is building cortexiphan (their graph-based life-management tool, in `~/git/personal/cortexiphan`) and will eventually merge this system into it. Until then, the control centre is the tool the user uses day to day to run the AI agents that build cortexiphan and their other projects. Everything the control centre tracks (sessions, projects, plans and their steps, notes, who or what did the work) maps onto concepts cortexiphan already has (projects, tasks, repository links, memories, attribution), so moving the data across later is a conversion, not a re-entry. Where a control-centre project corresponds to a cortexiphan project or task, the user can link them and see the link from the control centre.

**Why this priority**: It fixes the shape of the data and the vocabulary from the start and avoids a second, incompatible model of projects and tasks. The overview is useful without it, hence P2.

**Independent Test**: Take a control-centre project tracking work on cortexiphan itself, export it in the form cortexiphan can ingest, import it into a cortexiphan instance, and confirm the project, its steps with statuses, its repository/worktree links and the attribution of the work arrive without manual re-entry. Re-export and re-import and confirm nothing is duplicated.

**Acceptance Scenarios**:

1. **Given** a control-centre project with steps and linked sessions, **When** the user exports it for cortexiphan, **Then** the export contains the project, each step with its status, the repository and branch links, and who or what made each change.
2. **Given** a control-centre project linked to a cortexiphan project, **When** the user views it, **Then** the link and the other side's current status are visible, and a disagreement between the two is shown rather than silently overwritten.
3. **Given** cortexiphan is not running or not reachable, **When** the user uses the control centre, **Then** every feature in stories 1 to 5 works unchanged.
4. **Given** the user is running agent sessions on cortexiphan's own spec tasks, **When** they open the control centre, **Then** those sessions and the progress through cortexiphan's task lists show like any other project.

---

### Edge Cases

- The same project exists in both systems and they disagree on a step's status: the user sees the conflict and chooses; nothing is silently overwritten.
- Cortexiphan's model changes while it is still in early design: the control centre's own records stay valid, and only the export/link layer needs updating.
- A session is started outside the usual worktree locations or by another tool: it is still discovered and listed, or the user is told how to register it.
- Two records could refer to the same conversation (resumed or forked session): the overview shows one logical entry and does not double count or hide a genuinely separate fork.
- The machine reboots with sessions mid-task: the last recorded state is "interrupted", never "finished".
- A worktree is deleted, moved or its branch merged after the session ended: the record stays, flagged as having no valid location, and is never silently dropped.
- The user respawns a session that is actually still running: no second copy is started; the user is pointed at the running one.
- The recorded information is missing or corrupt for one session: that entry is shown as degraded, the rest of the overview still works.
- Very large numbers of old sessions (hundreds): the default view stays readable and fast. Finished sessions remain listed and respawnable, grouped below active work, most recent first, with the older ones collapsed under a count that expands on request; nothing finished is hidden unless the user dismisses it.
- A session ended cleanly but the work was not actually done: the user respawns it from the finished group exactly as they would an interrupted one.
- Sessions containing sensitive content: the overview shows task summaries only to the local user and does not copy conversation content off the machine.
- An agent kind has no way to report its state: it is listed with the information that can be determined, marked "state unknown".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST present every known AI agent session, running or not, in a single overview showing agent kind, repository, worktree/branch, state, task description and time since last activity.
- **FR-002**: The system MUST distinguish at least these states: working, waiting for the user, idle, finished, interrupted (ended unexpectedly or by reboot), and unknown.
- **FR-003**: The system MUST visibly prioritise sessions that are waiting on the user over those progressing on their own.
- **FR-004**: The system MUST fully support both Claude Code and Copilot sessions in the first release (discovery, state, persistence, respawn with conversation resume where the agent offers it), and MUST allow further agent kinds to be added, through a documented way of describing an agent kind, without changing how the overview, persistence and respawn work for existing kinds.
- **FR-005**: The system MUST keep a durable record of each session that survives the session ending for any reason, including process kill, crash, terminal close, and machine reboot.
- **FR-006**: The record for a session MUST retain what is needed to respawn it: agent kind, the identifier needed to resume its conversation, the working directory, repository and branch.
- **FR-007**: The system MUST keep the last known state, task description and progress for dead sessions and show them identically to live ones, apart from the running indicator.
- **FR-008**: The system MUST detect that a recorded session is no longer running without the user having to report it, and MUST mark sessions that vanished without a clean finish as interrupted.
- **FR-009**: Users MUST be able to respawn a not-running session in one action, which starts the agent in the recorded working directory and resumes the original conversation where the agent kind supports it.
- **FR-010**: Users MUST be able to respawn multiple selected sessions, and all interrupted sessions, in one action.
- **FR-011**: Respawned sessions MUST appear in a place the user can reach (a terminal they can attach to), and MUST be linked to the original record rather than creating an unrelated duplicate.
- **FR-012**: The system MUST refuse to respawn into a wrong or missing directory, and MUST report the specific problem (missing path, branch gone, session already running) with the available alternatives.
- **FR-013**: The system MUST NOT start a second copy of a session that is already running.
- **FR-014**: When an agent kind cannot resume a conversation, the system MUST start it fresh in the correct directory and clearly state that history was not restored.
- **FR-015**: The system MUST show, per session, project progress where a plan or task list can be discovered: goal, steps done, current step, steps remaining. Discoverable sources in the first release are the agent's own todo list, spec-kit `tasks.md` files, and any Markdown checklist in the session's repository (for example `PENDING.md` or `todo.md`).
- **FR-015a**: Every progress figure MUST name its source (which todo list or file). When more than one candidate source exists for a session and none is clearly the one being worked from, the system MUST NOT guess: it MUST list the candidates and let the user pick one, and remember the choice.
- **FR-016**: The system MUST NOT display progress figures that it cannot derive from a real plan or task list.
- **FR-017**: The system MUST show a short "where we left off" summary per session that remains available after the session ends. By default this and the task description are taken verbatim from the session (its opening request and its most recent agent message), with no model call.
- **FR-017a**: Users MUST be able to request a short model-written summary for a session or a project on demand. It MUST be generated by a model running on the user's machine (consistent with FR-020), stored once made, shown as model-written, and never replace the verbatim text. The system MUST NOT generate such summaries automatically.
- **FR-018**: Users MUST be able to group sessions under a named project, attach a free-text note to a session, and mark sessions as parked or dismissed.
- **FR-019**: The system MUST hide only dismissed sessions from the default view, without deleting their history, and MUST let users filter by repository, agent kind, state, project and text. Finished sessions MUST remain visible in the default view and MUST NOT be hidden by age or by the system.
- **FR-019b**: Users MUST be able to mark a finished session as done. Done sessions MUST move out of the finished group into a Done section where they stay visible for review, with their description, left-off text, progress, notes and history intact. The overview MUST have a Done section for sessions in no project, and every project MUST have its own Done section showing only that project's done sessions. Marking done is a user action only; the system MUST NOT mark anything done by itself.
- **FR-019c**: Users MUST be able to unmark a done session, which returns it to the finished group. Respawning a done session MUST also unmark it and return the resumed work to the active group. Done sessions MUST be included in filters and text search, and MUST NOT be hidden by dismissal rules (dismissing is a separate, explicit action).
- **FR-019a**: Finished sessions MUST be respawnable by the same actions and with the same checks as interrupted ones (FR-009 to FR-014), singly or as a multi-selection. They MUST NOT be pre-selected in, or counted as interrupted by, the post-login list (FR-032 to FR-034), but the user MUST be able to add them to that selection.
- **FR-020**: The system MUST keep all session data on the user's machine and MUST NOT transmit session content to any external service.
- **FR-021**: The system MUST remain usable when some records are corrupt or some data sources are unavailable, showing degraded entries instead of failing the whole overview.
- **FR-022**: The system MUST build on, and remain compatible with, the user's existing claude-monitor session listing, so that what that tool shows today is not lost.
- **FR-023**: The system MUST model projects, steps, repository links and notes with the same meanings and statuses as cortexiphan's projects, tasks, repository references and memories, so records convert to cortexiphan without loss of meaning.
- **FR-024**: The system MUST record, for every change to a project, step or note, who or what made it (the user, a named agent kind, or an automated source), in a form cortexiphan's attribution rules can accept.
- **FR-025**: The system MUST offer a way to export its projects, steps, links and attribution in a documented, stable, human-readable form that cortexiphan can ingest, and MUST be able to re-export without creating duplicates on re-import.
- **FR-026**: Users MUST be able to link a control-centre project or step to a cortexiphan project or task, and see that link from the control centre.
- **FR-027**: The system MUST function fully with no cortexiphan instance present or reachable; cortexiphan integration is additive and MUST NOT be a precondition for any other requirement.
- **FR-028**: When linked records disagree, the system MUST show the disagreement and let the user choose, and MUST NOT silently overwrite either side.
- **FR-029**: The system MUST support tracking work on cortexiphan itself (its worktrees, its spec task lists) as ordinary projects, with no special-casing needed to do so.
- **FR-030**: The system MUST provide both a terminal view and a web view in the first release. Both MUST show the same data and offer every action in stories 1 to 5 (overview, respawn, progress, grouping, notes, filters), so the user can pick either at any time.
- **FR-035**: The terminal tool MUST be both an interactive full-screen view and a non-interactive command line tool in one program: every action available in the interactive view MUST also be available as a command with machine-readable (JSON) output and meaningful exit codes, so the user and scripts can do everything without the interactive view.
- **FR-031**: The web view MUST be reachable only by the local user on the machine it runs on (consistent with FR-020), and MUST show live state within the same freshness limit as the terminal view (SC-005).
- **FR-032**: After the user logs in following a reboot, the system MUST surface the list of interrupted sessions (a notification or terminal banner that leads to it) without the user having to open the overview first.
- **FR-033**: In that list the user MUST be able to deselect individual sessions, then respawn the rest with one action. Deselected sessions MUST stay listed as interrupted and MUST NOT be respawned or dismissed.
- **FR-034**: The system MUST NOT start any agent session after boot without an explicit user action.

### Key Entities

- **Session**: One AI agent conversation. Attributes: agent kind, conversation identifier, working directory, repository, branch, start time, last activity time, state, end reason, task description, "where we left off" summary, link to its project and to the session it was respawned from.
- **Project**: A user-named grouping of related sessions (for example one large feature across several worktrees). Attributes: name, notes, combined state summary, optional plan reference.
- **Plan / Progress**: The ordered steps an agent is working through, with each step's status, as discovered from the agent's own task list or a project plan document. Belongs to a session or a project.
- **Worktree Location**: Repository, path, branch, and whether the path currently exists; the thing a respawn depends on.
- **Note / Marker**: A user-written note, or a parked, dismissed or done flag attached to a session or project. "Done" is the user's statement that the work is complete; it is separate from the system-derived "finished" state (the session ended cleanly) and is the only thing that moves a session into a Done section.
- **Respawn Request**: A user's request to restart one or more sessions, its outcome per session, and the new session it produced.
- **Cortexiphan Link**: A pairing between a control-centre project, step or note and the corresponding cortexiphan project, task or memory, with the last time each side was seen to agree.
- **Attribution**: Who or what (user, agent kind, automated source) made a given change, kept on projects, steps and notes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a machine reboot, the user can see every session that was active before it, and start all of them again in their correct worktrees, in under 1 minute and no more than 3 user actions.
- **SC-002**: The user can answer "what is each of my AI agents doing and which need me?" for 20 concurrent sessions within 10 seconds of opening the overview.
- **SC-003**: 100% of sessions that were running when they were killed or the machine rebooted remain listed afterwards; none vanish.
- **SC-004**: At least 95% of respawns of Claude Code sessions whose worktree still exists resume the original conversation in the correct directory on the first attempt. The same holds for Copilot sessions to the extent Copilot can resume a conversation; otherwise 100% start fresh in the correct directory with the "history not restored" notice (FR-014).
- **SC-005**: A session's state in the overview is no more than 10 seconds behind reality while it is running, and a killed session is shown as not running within 30 seconds.
- **SC-006**: After 3 days away, the user can state the goal, current step and next step of a large project from the overview alone, without opening the session, in at least 90% of tried cases.
- **SC-007**: Opening the overview with 500 historical sessions takes under 2 seconds and the default view shows active and interrupted work first, with finished sessions below (recent ones listed, older ones collapsed under a count) and dismissed ones hidden.
- **SC-008**: Adding a second agent kind requires no change to how users view, persist or respawn existing sessions.
- **SC-009**: A project with 20 steps and its linked sessions can be exported and imported into cortexiphan with 100% of steps, statuses and repository links preserved and zero manual re-entry; re-importing creates zero duplicates.
- **SC-010**: With cortexiphan completely absent, all of stories 1 to 5 pass their independent tests unchanged.
- **SC-012**: A user can mark a finished session done, find it in the right project's Done section, and reopen it by respawning, each in at most 2 actions; 0 sessions move into a Done section without a user action.
- **SC-011**: Every story 1 to 5 acceptance scenario passes in both the terminal view and the web view, and a change made in one appears in the other within 10 seconds.

## Assumptions

- The sole user is the repository owner on their own machines; multi-user access, remote sharing and cloud sync are out of scope for this feature.
- Sessions run on a single machine at a time; showing sessions from several machines in one view is out of scope for the first release.
- Claude Code and Copilot are both fully supported in the first release (see Clarifications). Agent kinds beyond those two follow the same model and may initially have limited state or resume information (see FR-014 and the "state unknown" edge case).
- Copilot is supported with state (verified 2026-10-12 on Copilot CLI 1.0.93, spikes R3 and R6). Hooks report when a session starts (lazily, on its first prompt), waits for permission, stops and ends. A session resumes from any directory, using the working directory Copilot recorded for it, and its process id comes from the hook's parent process. Known limits: hooks work only in folders Copilot trusts, and elsewhere the session is still listed through passive discovery with state unknown; "idle" is derived from the end of a turn, because Copilot's own idle notification was not seen; and crash or kill endings were not observed.
- The existing claude-monitor tool and its hook integration are the starting point for discovering sessions and their states; this feature extends it rather than replacing what it shows today.
- Respawned sessions are hosted in terminal sessions the user already uses for this workflow, so they can reattach.
- Progress is derived from plans and task lists agents already produce (agent todo lists, spec task lists); the system does not ask agents to write extra reports, and users are not required to enter progress by hand.
- Automatically respawning sessions at boot without the user asking is out of scope; the post-login prompt of FR-032 to FR-034 replaces it.
- Only finished sessions can be marked done; a session that is running or interrupted must first end cleanly or be dismissed. Finished sessions the user never marks done simply stay in the finished group.
- A session's Done section is that of its project at the moment of viewing: moving a session between projects moves it between Done sections.
- Retention: records are kept until the user deletes them; only dismissed items are hidden by default (finished ones stay visible) and none are purged.
- Session content stays local; only metadata and short summaries are kept in the overview's records.
- Cortexiphan (`~/git/personal/cortexiphan`) is in early design (Phase 0 implementation) and has no concept of agent sessions or worktrees yet, so the control centre keeps its own store and does not depend on cortexiphan running. The relationship for now is loose coupling: shared vocabulary, export/import and links, not a live shared database. The eventual merge brings the control-centre concepts (sessions, worktree locations, respawn) into cortexiphan as new kinds of record.
- The control centre is the user's working tool for building cortexiphan, so it is expected to be in daily use well before the merge and must be stable on its own.
- Cortexiphan's plans are spec-kit task lists, so those are one of the plan sources the progress feature reads (FR-015).
- Cortexiphan's rule that every change is attributed to a user, an LLM, or a connector is adopted here as the model for FR-024.

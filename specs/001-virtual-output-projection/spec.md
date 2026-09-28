# Feature Specification: Virtual Output Projection

**Feature Branch**: `001-virtual-output-projection`

**Created**: 2026-09-28

**Status**: Draft

**Input**: User description: "Show virtual outputs in the niri overview and let a physical monitor view and interact with them, so windows that open on a virtual output can be seen, used in place, or moved to a physical monitor."

## Context

The compositor can create **virtual outputs**: monitors with no physical screen behind them. They exist for streaming (Steam Remote Play uses one called `steam`), but they are generic and more can be created for any purpose. A window that opens on a virtual output is invisible to the person at the desk. The motivating case: a password-wallet unlock prompt opened on `steam` unseen, and every tool waiting on the wallet hung behind it.

Today the only way to reach such a window is to guess keyboard commands blind. This feature makes virtual outputs visible and usable from a physical monitor without disturbing anything streaming from them.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See and rescue windows from the overview (Priority: P1)

The desk user opens the overview on their physical monitor. Beside that monitor's own workspaces they see a column for every virtual output that is currently on, labelled with its name. Each column shows that output's workspaces and windows exactly as the overview shows any monitor's. The user drags a stray window from the virtual output's column onto one of the physical monitor's workspaces, and it moves there.

**Why this priority**: This is the core problem, invisible windows, and it delivers the rescue on its own even without the ability to interact in place.

**Independent Test**: With one virtual output on and one window on it, open the overview on the physical monitor, confirm the column and window are visible, drag the window to a physical workspace, and confirm it now lives there.

**Acceptance Scenarios**:

1. **Given** a virtual output `steam` is on and holds a window, **When** the user opens the overview on the physical monitor, **Then** a column labelled `steam` shows its workspaces with that window in it.
2. **Given** the overview is open with a `steam` column, **When** the user drags a window from the `steam` column onto a physical workspace, **Then** the window moves to that physical workspace.
3. **Given** the overview is open, **When** the user drags a window from a physical workspace into the `steam` column, **Then** the window moves to that `steam` workspace.
4. **Given** the overview is open, **When** the user drops a window into the gap between two workspaces in any column, **Then** a new workspace is created there on that column's output holding the window, exactly as the overview does for physical monitors today.
5. **Given** the overview is open, **When** the user reorders windows within a workspace or scrolls a column's workspaces, **Then** it behaves the same in a virtual output's column as in the physical monitor's.
6. **Given** a virtual output is off, **When** the overview opens, **Then** no column is shown for it.

---

### User Story 2 - Work on a virtual output in place (Priority: P2)

The desk user wants to use a window where it is, for example to answer a prompt without moving it off the stream. They run the view command naming the virtual output (or click one of its workspaces in the overview). Their physical monitor now shows that virtual output live, scaled to fit with its proportions kept. Clicking, scrolling and typing reach the windows on the virtual output, and their usual window-management commands act on it. Running the view command again returns the monitor to normal.

**Why this priority**: Rescue (P1) covers the urgent case; interacting in place is valuable when the window must stay on the virtual output, but it builds on the same visibility.

**Independent Test**: Put a window on a virtual output, enter view mode from the physical monitor, click into the window and type, confirm the input reached it, then leave view mode and confirm the physical monitor shows its own workspaces again.

**Acceptance Scenarios**:

1. **Given** virtual output `steam` is on, **When** the user runs the view command for `steam`, **Then** the focused physical monitor shows `steam`'s content live, scaled to fit with the aspect ratio kept and bars filling the rest, and a label "Viewing: steam" appears for 2 seconds.
2. **Given** view mode on `steam`, **When** the user clicks on a window shown, **Then** that window receives the click at the matching spot and gets keyboard focus.
3. **Given** view mode on `steam`, **When** the user clicks in a bar outside the scaled content, **Then** nothing receives the click.
4. **Given** view mode on `steam`, **When** the user runs a window-management command (for example move window to another monitor), **Then** it acts on `steam` as the active monitor.
5. **Given** view mode, **When** the user runs the view command with no name, **Then** the physical monitor returns to its own workspaces.
6. **Given** the overview is open, **When** the user clicks a workspace in a virtual output's column, **Then** the overview closes and view mode starts on that virtual output with that workspace active.
7. **Given** view mode, **When** the user opens the overview, **Then** the normal overview appears with the physical monitor's workspaces and every virtual output column.

---

### User Story 3 - Streams stay undisturbed (Priority: P3)

Someone is streaming from a virtual output on another device while the desk user looks at or works on it through the overview or view mode. The stream keeps showing the same content without interruption.

**Why this priority**: A guarantee on the other two stories rather than new capability, but breaking a live stream would make the feature unusable during the very sessions it exists for.

**Independent Test**: Start a stream from `steam` on another device, enter view mode and the overview on the physical monitor, interact with a window on `steam`, and confirm the stream shows the window's changes continuously and never goes black or freezes.

**Acceptance Scenarios**:

1. **Given** a live stream from `steam`, **When** the desk user enters and leaves view mode or opens the overview, **Then** the stream continues without a gap.
2. **Given** a live stream from `steam` and view mode, **When** the desk user interacts with a window on `steam`, **Then** the stream shows the window's resulting changes.

---

### Edge Cases

- The viewed virtual output is turned off or removed during view mode: view mode ends, the physical monitor shows its own workspaces, it becomes the active monitor, and a one-line notice says why.
- The physical monitor showing a virtual output disconnects or powers off: its view mode ends; the virtual output and any stream from it carry on unchanged.
- A virtual output is turned off or on while the overview is open: its column disappears or appears without closing the overview.
- A window is being dragged from a virtual output's column when that output turns off: the drag continues and the window can still be dropped on a physical workspace (the layout already handles an output disappearing mid-drag).
- Several virtual outputs are on and their columns plus the physical monitor's workspaces do not fit across the screen: the virtual output columns shrink to fit; the physical monitor's own workspaces keep their normal overview size.
- The view command names a physical monitor, an unknown name, or a virtual output that is off: the command fails with an error naming the output and the reason; nothing changes.
- The view command with no name when not viewing: nothing changes and the reply says view mode was not active.
- A remote streaming client and the desk user move the pointer at the same moment: they contend for it. Accepted limitation, not handled.
- A virtual output is never shown inside another virtual output, and a physical monitor is never shown inside another monitor.

## Requirements *(mandatory)*

### Functional Requirements

**Overview**

- **FR-001**: While the overview is open on a physical monitor, the system MUST show, beside that monitor's workspaces, one column per virtual output that is on, labelled with the virtual output's name.
- **FR-002**: Each such column MUST present the virtual output's actual workspaces and windows, at the same zoom as the physical monitor's workspaces in the overview, subject to FR-009.
- **FR-003**: Every overview interaction available for a physical monitor's workspaces MUST work identically in a virtual output's column and across columns: dragging a window to any workspace on any output in either direction, dropping into the gap between workspaces to create a new workspace, reordering windows within a workspace, scrolling a column's workspaces, and clicking a workspace.
- **FR-004**: Clicking a workspace in a virtual output's column MUST close the overview and start view mode on that virtual output with that workspace active. Clicking a physical monitor's workspace MUST behave as it does today.
- **FR-005**: The system MUST NOT show a column for a virtual output that is off, and MUST add or remove columns when virtual outputs turn on or off while the overview is open.
- **FR-006**: Virtual output columns MUST enter and leave with the overview's opening and closing animation, not appear or vanish abruptly.

**View mode**

- **FR-007**: The system MUST provide a view command, available from the command-line control interface and as a key binding, taking a virtual output name, that makes the focused physical monitor show that virtual output live.
- **FR-008**: In view mode the virtual output's content MUST fill the physical monitor as far as possible with its aspect ratio kept, with the remaining area shown as plain bars.
- **FR-009**: When the physical monitor's workspaces and the virtual output columns do not fit across the monitor in the overview, the virtual output columns MUST shrink to fit, and the physical monitor's own workspaces MUST keep their normal overview size.
- **FR-010**: In view mode, pointer input on the physical monitor MUST reach the virtual output at the corresponding position: clicks, scrolling and focus changes go to the window under that position through normal input handling. Positions in the bars MUST reach nothing.
- **FR-011**: Entering view mode MUST make the viewed virtual output the active monitor, so window-management commands act on it.
- **FR-012**: The view command with no name MUST end view mode and return the physical monitor to its own workspaces and to being the active monitor.
- **FR-013**: Entering view mode MUST show the label "Viewing: <name>" on the physical monitor for 2 seconds.
- **FR-014**: Opening the overview during view mode MUST show the normal overview including all virtual output columns; closing it MUST return to view mode.
- **FR-015**: View mode MUST end automatically, with a one-line notice, when the viewed virtual output is turned off or removed, or when the viewing physical monitor goes away.

**Streams and scope**

- **FR-016**: Showing a virtual output in the overview or view mode MUST NOT change what the virtual output itself displays or interrupt any stream or screen capture of it.
- **FR-017**: The desk user's pointer MUST stay on the physical monitor and MUST NOT be drawn on the virtual output.
- **FR-018**: Only virtual outputs MUST be showable, and only physical monitors MUST be able to show them; a virtual output MUST never be shown within another output's view of a virtual output.
- **FR-019**: The view command MUST fail, leaving everything unchanged, with an error that names the output and the reason, when the name is unknown, names a physical monitor, or names a virtual output that is off.
- **FR-020**: The view command with no name while not in view mode MUST change nothing and report that view mode was not active.
- **FR-021**: Showing virtual outputs MUST work for any number of virtual outputs and any names, not only `steam`.

### Key Entities

- **Virtual output**: A named monitor with no physical screen, which may be on or off. Holds its own workspaces and windows. Can be the subject of a stream.
- **Physical monitor** (the *viewer*): A real screen. Can show virtual outputs in its overview or in view mode.
- **Projection**: The relationship "physical monitor P shows virtual output V in area A, as an overview column or in view mode". It determines both where V's content appears on P and where input on P lands on V.
- **View mode**: The state of a physical monitor that is showing one virtual output in full, until ended by command or automatically.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A window that opens on any virtual output that is on is visible from the physical monitor within one action (opening the overview), 100% of the time.
- **SC-002**: A window on a virtual output can be moved to a physical monitor's workspace in a single drag from the overview.
- **SC-003**: Every overview interaction listed in FR-003 succeeds across physical and virtual columns in both directions, in 100% of the scripted scenarios.
- **SC-004**: In view mode, a click on a visible spot of a virtual output's window lands within 1 physical pixel of the matching spot in that window, and clicks in the bars reach nothing, in 100% of the scripted scenarios.
- **SC-005**: During a live stream, entering and leaving view mode or opening the overview 10 times causes zero visible interruptions on the streaming client.
- **SC-006**: Turning off the viewed virtual output or disconnecting the viewing monitor always leaves the desk in a usable state (physical monitor showing its own workspaces and active) with no restart needed.

## Assumptions

- The physical monitor at the desk is wide enough (5120x1440 today) for its workspaces plus at least one virtual output column at normal overview size; narrower monitors rely on FR-009.
- The desk user's normal key bindings stay as they are; a binding for the view command is added by the user's configuration, not assumed.
- Scaling a virtual output's content to the physical monitor may look softer than native; drawing it at the physical monitor's own resolution is out of scope.
- Esc as a way to leave view mode is out of scope, because Esc belongs to the focused application.
- Pointer contention between a remote streaming client and the desk user is accepted, not solved.
- The feature is built in the patched compositor that already provides virtual outputs, and delivered to the desktop the same way as that patch.

# Feature Specification: Virtual Output Overview Column

**Feature Branch**: `feat/virtual-overview-column`

**Created**: 2026-09-29

**Status**: Draft

**Input**: User description: "Redesign how virtual outputs appear in the overview so it scales to many virtual outputs and no longer collides with the physical monitor's own overview; add event-stream events for view mode and for outputs turning on and off."

## Context

Feature 001 (`specs/001-virtual-output-projection/`) made virtual outputs visible from the desk. In the overview, every virtual output that is on gets its own column to the right of the physical monitor's workspaces. Live use showed two problems:

- **It does not scale.** Each extra virtual output adds a column, and all columns shrink to fit. With several virtual outputs they become too small to use.
- **It collides with the physical monitor's overview.** A workspace with many windows extends to the right, and those windows run into the columns. The area the user expects to click or scroll through for their own windows belongs to a virtual output instead.

This feature replaces 001's overview columns (FR-001 to FR-006 and FR-009 of 001) with a single column in a reserved area. View mode (001 FR-007 to FR-021, and the Escape behaviour added since) is unchanged.

Nothing outside the compositor can currently tell when view mode starts or stops, or when an output is turned on or off. This feature adds both to the compositor's event stream.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The physical monitor's overview is never in the way (Priority: P1)

The desk user opens the overview with many windows on one of their physical monitor's workspaces. The overview shows the physical monitor's workspaces in a slightly narrower area, and a band at the right edge holds the virtual outputs. The user scrolls and clicks through their own windows exactly as they would without any virtual outputs. Nothing they see in their own area belongs to a virtual output, and nothing in the band acts on their own windows.

**Why this priority**: This is the regression that prompted the redesign; the overview is the user's main navigation tool and must not be degraded by virtual outputs.

**Independent Test**: With one virtual output on and a physical workspace holding enough windows to extend past its right edge, open the overview, click a window next to the band and confirm it is the one activated; click in the band and confirm no physical window reacts.

**Acceptance Scenarios**:

1. **Given** at least one virtual output is on, **When** the overview opens on a physical monitor, **Then** a band at the monitor's right edge holds the virtual outputs, and the monitor's own workspaces are laid out in the remaining width.
2. **Given** a physical workspace whose windows extend towards the band, **When** the user clicks one of those windows outside the band, **Then** that window is the one that reacts.
3. **Given** the overview is open, **When** the user clicks or scrolls anywhere inside the band, **Then** no window or workspace of the physical monitor reacts.
4. **Given** no virtual output is on, **When** the overview opens, **Then** there is no band and the overview looks and behaves exactly as without this feature.
5. **Given** the overview is opening or closing, **When** the animation runs, **Then** the band grows and shrinks with it rather than appearing or vanishing abruptly.

---

### User Story 2 - Any number of virtual outputs in one column (Priority: P1)

The band holds one column. For each virtual output that is on, the column shows its name followed by all of its workspaces, one below the other, each showing that workspace's windows. With many virtual outputs the column simply gets longer, and the user scrolls it on its own. Clicking a workspace, or a window in it, takes the user into view mode on that virtual output, as it did before.

**Why this priority**: Equal to US1: the redesign has no value unless every virtual output stays reachable and usable at a readable size.

**Independent Test**: Turn on three virtual outputs with windows on several of their workspaces, open the overview, confirm each output's name and all its workspaces appear at the same readable size, scroll the column to reach the last one, and click a window there to enter view mode.

**Acceptance Scenarios**:

1. **Given** three virtual outputs are on, **When** the overview opens, **Then** the column lists each output's name followed by all its workspaces, in the order the outputs are configured, and every workspace is shown at the same width.
2. **Given** more workspaces than fit in the band's height, **When** the user scrolls with the pointer over the band, **Then** only the column scrolls, and it stops at its first and last entries.
3. **Given** the column's content is shorter than the band, **When** the overview opens, **Then** the content is centred vertically.
4. **Given** the overview opens, **When** the column first appears, **Then** it is scrolled so that the active workspace of the first virtual output is visible.
5. **Given** the overview is open, **When** the user clicks a window in a virtual workspace, **Then** the overview closes, view mode starts on that virtual output with that workspace active, and that window has focus; Escape returns to the physical monitor.
6. **Given** the overview is open, **When** the user clicks an empty part of a virtual workspace, **Then** the same happens without focusing a window.
7. **Given** the overview is open, **When** the user clicks a name label, a gap or the band's background, **Then** nothing happens and the overview stays open.
8. **Given** the overview is open, **When** a virtual output is turned on or off, **Then** its group appears in or disappears from the column without the user reopening the overview.

---

### User Story 3 - Move windows between any workspaces through the column (Priority: P2)

The user drags windows between the physical monitor's workspaces and any virtual workspace in the column, in either direction, and between virtual workspaces. Dropping a window on a virtual output's empty last workspace creates a new workspace there. Dragging near the top or bottom of the band scrolls the column so that far workspaces can be reached in one drag.

**Why this priority**: Rescuing a window by moving it is 001's core use; it must keep working with the new layout. It ranks below US1 and US2 because clicking into view mode already offers a way to act on a window.

**Independent Test**: Drag a window from a physical workspace onto a virtual workspace, then from that virtual workspace onto another virtual output's workspace further down the column (using edge scrolling), then back onto a physical workspace; confirm the window lands on each target in turn.

**Acceptance Scenarios**:

1. **Given** the overview is open, **When** the user drags a window from a physical workspace onto a virtual workspace, **Then** the window moves to that virtual workspace.
2. **Given** the overview is open, **When** the user drags a window from a virtual workspace onto a physical workspace, **Then** the window moves to that physical workspace.
3. **Given** the overview is open, **When** the user drags a window from one virtual workspace onto another, on the same or a different virtual output, **Then** the window moves there.
4. **Given** the overview is open, **When** the user drops a window on a virtual output's empty last workspace, **Then** a new workspace is created on that virtual output holding the window.
5. **Given** a drag is in progress, **When** the pointer is held near the top or bottom edge of the band, **Then** the column scrolls in that direction until it reaches its end or the pointer moves away.
6. **Given** a drag is in progress over a virtual workspace, **When** that virtual output is turned off, **Then** the drag continues with no target over that area, and nothing is lost.

---

### User Story 4 - Other programs can follow view mode and outputs (Priority: P3)

A status bar or script subscribed to the compositor's event stream is told when view mode starts or stops, including which physical monitor is showing which virtual output. It is also told whenever any output, physical or virtual, is connected, disconnected, turned on or turned off, with the same details the compositor reports when asked about outputs. A subscriber that connects later receives the current state of both straight away.

**Why this priority**: Useful for bars and automation (for example the stream-mode watcher), and for testing, but the desk user can work without it.

**Independent Test**: Subscribe to the event stream, turn a virtual output on and off, enter and leave view mode by command, by clicking in the overview and by pressing Escape; confirm one matching event for each change, and confirm a new subscriber receives the current state first.

**Acceptance Scenarios**:

1. **Given** a subscriber is connected, **When** view mode starts by any means, **Then** the subscriber receives an event naming the physical monitor and the virtual output.
2. **Given** a subscriber is connected, **When** view mode ends by any means (command, overview click, Escape, the physical monitor becoming active again, or an output going away), **Then** the subscriber receives an event saying view mode is no longer active.
3. **Given** a subscriber is connected, **When** any output is connected, disconnected, turned on or turned off, **Then** the subscriber receives an event carrying the full current list of outputs with the same details as the output query.
4. **Given** view mode is active and a virtual output is on, **When** a new subscriber connects, **Then** its first events include the current view mode state and the current output list.

### Edge Cases

- A virtual output is turned off while the overview is open and the column is scrolled to its group: the group disappears and the scroll position is clamped to the new content.
- A workspace disappears between the moment the column is laid out and the user's click: the click does nothing and the event is recorded in the log.
- A virtual output reports a zero or invalid size: its group is left out of the column, and the problem is logged.
- Many virtual outputs (a dozen or more), each with several workspaces: every workspace remains the same readable size and reachable by scrolling.
- Several physical monitors: each shows its own band while the overview is open; scrolling one band does not scroll another.
- The session is locked: no band content is shown or reachable, as in 001.
- View mode is active when the overview opens: the overview shows the physical monitor's own workspaces and the band, as in 001; closing it returns to view mode.
- An output's mode or scale changes without it turning on or off: not reported as an output event unless it also connects, disconnects, turns on or turns off.

## Requirements *(mandatory)*

### Layout

- **FR-001**: While the overview is open and at least one virtual output is on, each physical monitor MUST reserve a band at its right edge, 15% of the monitor's width, for virtual outputs.
- **FR-002**: The physical monitor's own workspaces in the overview MUST be laid out within the width left over, so that none of its windows are drawn in, or receive input from, the band.
- **FR-003**: With no virtual output on, the overview MUST look and behave exactly as it does without this feature.
- **FR-004**: The band MUST grow and shrink with the overview's opening and closing animation.
- **FR-005**: The band MUST hold one column listing, for each virtual output that is on and in configuration order, the output's name followed by all of its workspaces including its empty last one.
- **FR-006**: Every workspace in the column MUST be shown at the full column width, with its height following its output's proportions, so that adding virtual outputs never shrinks any of them.
- **FR-007**: The column MUST scroll vertically on its own, independently per physical monitor, clamped at its ends, and centred when shorter than the band.
- **FR-008**: When the overview opens, the column MUST be scrolled so that the first virtual output's active workspace is visible.
- **FR-009**: Each workspace in the column MUST show that workspace's windows as they appear on the virtual output with the overview closed, confined to the workspace's area; the virtual output's bars and notifications are not shown in the column.
- **FR-010**: Each virtual output's active workspace MUST be highlighted in the column in the same way the overview highlights a physical monitor's active workspace.
- **FR-011**: The band MUST be opaque; the physical monitor's own content MUST NOT show through it.

### Interaction

- **FR-012**: Pointer and touch input inside the band MUST go only to the column, and input outside the band MUST behave exactly as without this feature.
- **FR-013**: Clicking or tapping a window in a virtual workspace MUST close the overview, start view mode on that virtual output with that workspace active, and focus that window, with Escape returning as for any view entered from the overview.
- **FR-014**: Clicking or tapping an empty part of a virtual workspace MUST do the same as FR-013 without focusing a window.
- **FR-015**: Clicking or tapping a name label, a gap or the band's background MUST do nothing and leave the overview open.
- **FR-016**: Dragging a window MUST work between any two workspaces shown in the overview (physical to virtual, virtual to physical, virtual to virtual), with the same insertion feedback and placement the overview gives between physical workspaces.
- **FR-017**: Dropping a window on a virtual output's empty last workspace MUST create a new workspace on that virtual output holding the window.
- **FR-018**: While a window is dragged near the top or bottom edge of the band, the column MUST scroll in that direction.
- **FR-019**: Scrolling with the pointer over the band MUST scroll only the column; scrolling elsewhere MUST behave exactly as without this feature.
- **FR-020**: Keyboard navigation in the overview MUST behave exactly as without this feature.
- **FR-021**: The desk user's pointer MUST stay on the physical monitor at all times, as required by 001.
- **FR-022**: While the session is locked, no band content MUST be shown or reachable.

### Events

- **FR-023**: The event stream MUST report every start and end of view mode, whatever caused it, with the physical monitor and virtual output when view mode is active.
- **FR-024**: The event stream MUST report whenever any output is connected, disconnected, turned on or turned off, carrying the full current list of outputs with the same details as the existing output query.
- **FR-025**: A new event-stream subscriber MUST receive the current view mode state and the current output list among its initial events.
- **FR-026**: The command-line event-stream viewer MUST print both new events readably.
- **FR-027**: The output event MUST NOT be specific to virtual outputs, so it is usable for physical monitors too.

### Reliability and diagnostics

- **FR-028**: No condition reachable through input, output changes, or configuration MUST crash the compositor; invalid sizes, missing workspaces and vanished outputs MUST be handled by skipping or ignoring and logging.
- **FR-029**: The log MUST record when the column's structure changes (monitor, number of groups and workspaces), each drop onto a virtual workspace (window, output, workspace), and each start and end of view mode with its cause; it MUST NOT log once per frame.
- **FR-030**: Showing virtual outputs in the column MUST NOT change what a virtual output displays or interrupt any stream or capture of it, as required by 001.

### Key Entities

- **Band**: The reserved area at a physical monitor's right edge while the overview is open; its width follows the overview animation.
- **Column**: The single scrollable list inside a band, with its own scroll position per physical monitor.
- **Group**: One virtual output in the column: its name and its workspaces, in configuration order.
- **Tile**: One virtual workspace shown in the column; a click and drop target that maps back to that workspace.
- **View mode state**: Either not viewing, or viewing a named virtual output on a named physical monitor, as already reported by the view command.
- **Output list**: The set of outputs and their details as reported by the existing output query.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With any number of virtual outputs on, 100% of clicks on the physical monitor's windows outside the band reach those windows, and 0% of clicks inside the band reach them.
- **SC-002**: With 12 virtual outputs on, every virtual workspace is shown at the same size as with 1, and any of them can be reached with at most one continuous scroll.
- **SC-003**: A window on any virtual workspace can be moved to a physical workspace with a single drag, and the reverse, in under 5 seconds.
- **SC-004**: Opening the overview with no virtual outputs on is visually identical to the overview without this feature.
- **SC-005**: For each way view mode can start or end, and each way an output can turn on or off, a subscriber receives exactly one matching event within one frame of the change.
- **SC-006**: A stream from a virtual output shows no interruption or change while its workspaces are shown or used through the column.
- **SC-007**: No sequence of overview, drag, scroll, output and lock actions makes the compositor crash.

## Assumptions

- The band width of 15% is a fixed proportion, not a user setting, in this feature. At 5120 pixels wide that is about 768 pixels, enough for readable workspaces.
- The first virtual output in configuration order is the one scrolled into view on opening; which one was used most recently is not tracked.
- Every physical monitor shows its own band when there is more than one; the desk user has one today.
- An output changing mode or scale without turning on or off is not reported as an output event in this feature; the event covers connect, disconnect, on and off.
- The event formats are designed so they could be proposed to upstream niri; the view mode event reuses the state the view command already reports.
- 001's view mode, its Escape behaviour, the lock, hot-corner, screenshot and Alt-Tab rules, and the rule that the pointer never moves onto a virtual output all stay as they are.
- The implementation lives in the niri fork (`alisonjenkins/niri`, `rebase-feat-virtual`), which nix-config builds as the `niri-virtual` flake input; nix-config carries this spec, its plan and the documentation.

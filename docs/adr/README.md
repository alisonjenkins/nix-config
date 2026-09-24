# Architecture decision records

Each file here records one decision: what we chose, what we rejected, and the
evidence that settled it. Most of them cost hours or days to learn, usually
from something that looked right and was not. The configuration shows *what*
we do. These say *why*, so nobody has to rediscover it.

Read the relevant record before changing configuration it covers. If the
evidence changes, write a new record that supersedes the old one rather than
editing history.

## Remote Play and gaming on ali-desktop

Start with [`docs/steam-remote-play-streaming.md`](../steam-remote-play-streaming.md)
for how the pieces fit together, and
[`docs/remote-play-troubleshooting.md`](../remote-play-troubleshooting.md) when
something is wrong.

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-decisions.md) | Record decisions as ADRs | Accepted |
| [0002](0002-virtual-output-for-remote-play.md) | Stream from a declared niri virtual output | Accepted |
| [0003](0003-steam-display-filter.md) | Correct Steam's desktop geometry in SDL, not X | Accepted |
| [0004](0004-stream-target-files.md) | Publish the stream target as files under `~/.local/state` | Accepted |
| [0005](0005-stream-mode-owns-stream-state.md) | One event-driven watcher owns all stream state | Accepted |
| [0006](0006-extest-remote-play-input.md) | Map Remote Play input to global coordinates in extest | Accepted, pending live test |
| [0007](0007-remote-play-game-mode.md) | Stream games in game mode, without gamescope | Accepted, pending live test |
| [0008](0008-steam-libva.md) | Give Steam a newer libva, and only Steam | Accepted |
| [0009](0009-gamescope-capabilities-and-bubblewrap.md) | Let bubblewrap run under gamescope's capabilities | Accepted |
| [0010](0010-niri-config-kdl.md) | Keep comments out of niri's KDL, validate the built config | Accepted |
| [0011](0011-mangohud-first-vulkan-layer.md) | Put MangoHud first in the Vulkan layer chain | Accepted |
| [0012](0012-size-output-from-client-reports.md) | Size the streamed output from what the client reports | Accepted |
| [0013](0013-disarm-on-client-disconnect.md) | Disarm on client disconnect, and never leave niri without an output | Accepted |
| [0014](0014-reannounce-steam-virtual-gamepads.md) | Re-announce Steam's virtual gamepads when Steam lists them | Accepted |

steam-command-runner has its own records in its repo, `docs/adr/`. Its
[0007](https://github.com/alisonjenkins/steam-command-runner/blob/main/docs/adr/0007-streamed-games-skip-gamescope.md)
and 0008 are the other half of this repo's 0007.

## Template

```markdown
# NNNN. Title in the imperative

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
The problem, and the facts that constrain the answer. Quote log lines and
error text exactly: they are what someone will search for.

## Decision
What we do, in one paragraph. Name the files.

## Alternatives rejected
Each option we tried or considered, and the specific reason it failed.

## Consequences
What this costs, what it makes easy, what to watch for.

## Evidence
How we know. Commands, log lines, test names, commits.

## Revisit when
The observation that would make this decision wrong.
```

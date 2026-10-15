# Several agents writing code in one project

Read this after "Running sub-agents in parallel" in `SKILL.md`, when two or more
agents will commit to the same project at once. The failures below each cost
real time in a long multi-agent run.

## Before spawning

- **Split by module, not by task list.** Two agents in one large file produce
  overlapping fixes. If a file is the hot spot, have one agent extract the
  part another needs into its own module first, or give the file to one agent.
- **Write the split into every prompt**, including what each agent must not
  touch. A scope change after the agents have started leaves commits outside
  their new scope that someone has to reconcile.
- **Check neighbouring areas for overlap.** Two agents given adjacent
  performance areas fixed the same functions and produced two competing
  series.
- **Give each agent its own new test files and check names.** Shared files
  (build wiring, docs, the test harness) are then the only expected conflicts,
  and those are mechanical.
- **Base every branch on one named commit** and ask each agent to report branch,
  head, and any commit outside its scope.
- **Cap memory and disk per agent.** Parallel builds exhaust RAM first. Put big
  artifacts on tmpfs and delete them when done.

## While they run

- **Check liveness from outside**: newest file modification time in the
  worktree, last commit time, and CPU use of its processes. Do not ask an agent
  whether it is alive.
- **Look for orphans.** A test with no timeout can spin for hours after its
  agent has gone. Find processes whose parent is gone and ask before stopping
  them.
- **Expect a usage limit to kill agents mid-task**, and their worktrees may be
  removed with the commits in them. Keep long-lived clones outside agent
  worktrees, ask agents to commit early and export patches to a shared scratch
  directory, and resume with a message afterwards. Rebuilt commits lose their
  signatures.
- **Do not relay approval through an agent message.** An agent correctly
  refuses a push, fork or PR when the instruction arrives from another agent.
  The main session does outward actions after the user approves them.

## Integration

- **One integrator, in dependency order, with a conflict plan** written before
  the first merge. For each overlap keep the better-tested implementation and
  keep the other branch's tests, ported.
- **Independent reviewer.** A read-only agent that must reproduce every finding
  before reporting it. Fixes go back to the author, not the reviewer.
- **A status table of expected failures** (xfail), one line per test. A fixed
  bug then shows up as an unexpected pass, and a strict mode fails the check
  until the line is flipped.
- **Keep every commit green.** Wiring a check before the tests or status that
  make it pass leaves red commits mid-branch.

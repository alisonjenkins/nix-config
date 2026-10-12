# Contract: adding an agent kind (FR-004, SC-008)

An agent kind is one Rust module in `src/agents/` of the `claude_monitor` library implementing `AgentKind`, plus its registration in the Home Manager module. Nothing in the store, views, respawn planner, progress or export changes.

```rust
pub trait AgentKind: Send + Sync {
    /// Stable id stored in `session.agent_kind` ("claude", "copilot").
    fn id(&self) -> &'static str;

    /// Turn one hook payload into zero or more events. Pure: no I/O.
    fn parse_hook(&self, raw: &serde_json::Value) -> Result<Vec<HookEvent>, ParseError>;

    /// Sessions visible on disk without hooks. Read-only. May return empty.
    fn discover(&self, env: &Env) -> Result<Vec<SessionStub>, DiscoverError>;

    /// How to relaunch. `Resume` is offered only if the agent can resume;
    /// otherwise the planner uses `Fresh` and shows the "history not restored" notice.
    fn launch(&self, session: &Session, mode: LaunchMode, cfg: &LauncherConfig) -> Result<Launch, LaunchError>;

    /// Preconditions a respawn must check (e.g. transcript exists). Empty if none.
    fn resume_preconditions(&self, session: &Session, env: &Env) -> Vec<Precondition>;
}

pub struct Launch { pub program: String, pub args: Vec<String>, pub cwd: PathBuf, pub env: Vec<(String, String)> }
```

`HookEvent` is the closed set `{Started{source}, Prompt{text}, Working, NeedsPermission, Idle{left_off?}, Ended{reason, kind}, Todo{items}}`. A kind that cannot report some of them simply never emits them; the session then shows `unknown` or the last state it did report (spec edge case).

## Checklist for a new kind

1. Implement the trait; add fixtures of real payloads under `tests/fixtures/<kind>/`.
2. Tests: payload fixtures → events; `launch` for both modes; a respawn through the private-tmux harness.
3. Register hooks in `nix/hm-module.nix` (or document that the agent has none and rely on `discover`).
4. Launch command templates are config, not code: `programs.claude-monitor.launchers.<kind> = "…{session_id}…"`; placeholders `{session_id}`, `{cwd}`, `{name}`.
5. Add the kind to the table in `hook-payloads.md`.

## Current kinds

| Kind | Hooks | Passive discovery | Resume | Todo list |
|---|---|---|---|---|
| `claude` | yes | transcript dirs under `~/.claude/projects` (secondary; hooks are primary) | `claude --resume <id>` in recorded cwd | via todo tool payload |
| `copilot` | yes (module-installed) | `~/.copilot/session-state` | `copilot --resume <id>` | none found |

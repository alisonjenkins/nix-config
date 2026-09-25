# Delegating to a locally-hosted model

An alternative to a Claude sub-agent or `delegate-to-copilot.md` for
zero-marginal-cost, no-cloud-dependency delegation: `scripts/delegate-to-local.sh`
sends a subtask to a model running on your own hardware via an
OpenAI-compatible chat-completions endpoint. The chosen runtime per platform
(below) is llama.cpp on Linux and MLX on macOS, but the script itself only
assumes the standard OpenAI-compatible shape at `/v1/models` and
`/v1/chat/completions` — any server speaking that (Ollama, LM Studio, ...)
works too.

## What this can and can't do

**Two modes: text only, or a read-only agent.** `delegate-to-local.sh` is
text in, text out: the model cannot read files, so paste what the task needs
into the prompt. `delegate-to-local-agent.sh` (see "Agent mode" below) runs
the same model inside opencode with read, glob, grep and list over one
directory, so it can look things up itself. Neither can edit files or run
commands. For that, use a Claude sub-agent or `delegate-to-copilot.md`.

**Zero marginal cost, but weaker capability and no cloud safety layer.** A
locally-hosted model in the ~7-30B range is meaningfully weaker than Haiku
4.5 on multi-step reasoning and ambiguous instructions, and (depending on the
model) may have no provider-side moderation — it's whatever alignment the
base model shipped with, nothing added on top. Reserve it for genuinely
mechanical, well-specified tasks (the same "haiku-shaped work" bar the
`delegation` SKILL.md uses), and never feed it untrusted input if the model
has no known alignment/safety training (avoid "abliterated"/uncensored
community finetunes for that reason). **Model size matters more than it
might seem**: tested live (`docs/local-model-capabilities.md`), a 0.5B model
confidently called `rm -rf /` "safe and effective" and fully complied with a
one-line prompt injection, while a 3B model of the same family correctly
refused both — and was *faster* on this GPU. Below ~3B, treat any advice- or
judgment-shaped output as unverified, not just "weaker."

**One model at a time — hardware isn't sized for more.** These machines can't
hold two loaded models at once, and loading one takes real time (seconds to
minutes). So there's no live "which models are available" query the way
Ollama would give you from one always-on daemon: instead, you declare a
handful of named **profiles** up front, deliberately **switch** to one when
you intend to use it for a while, and every delegated call talks to whichever
profile is currently loaded.

## Chosen runtime: llama.cpp on Linux, MLX on macOS

Decided over Ollama-everywhere for raw per-platform speed, accepting the
cost of two setups to maintain instead of one:

- **Linux (AMD GPU)**: `llama-server` (from llama.cpp) with the **Vulkan**
  backend, not ROCm — more reliable today than ROCm on younger RDNA
  hardware, which can have driver-maturity gotchas (e.g. a HIP backend that
  doesn't idle the GPU after inference on some RDNA4 cards).
- **macOS (Apple Silicon)**: `mlx_lm.server` (from the `mlx-lm` Python
  package — a fixed installed CLI once set up in a venv/pipx, not a
  per-invocation venv) — typically 10-20% faster than llama.cpp's Metal
  backend. Exposes the same `/v1/models` and `/v1/chat/completions` shapes
  with no deviations. Its own docs call it "not recommended for production,
  only basic security checks" — bind it to localhost only, never expose the
  port. No first-party launchd unit exists yet for keeping it running
  headless across logins/reboots; that needs writing by hand if you want it
  always-on rather than started per session.

Model choice per profile is a per-machine hardware tradeoff (VRAM/unified-
memory budget vs. tokens/sec vs. capability) — pick the largest model your
hardware runs at an acceptable tok/s, and prefer a mainstream aligned
instruct release (Qwen, Llama, Gemma, gpt-oss, etc.) over an uncensored
finetune. Re-check current model releases and benchmarks periodically; this
space moves fast enough that any specific model/quant recommendation here
would go stale within months.

This repo's own current picks (declarative GGUF pins with real HF hashes,
not just an illustration) live in `pkgs/llama-models` — a "single smart
model" and "workhorse coder" pick sized for a single GPU/APU, plus a bigger
MoE "orchestrator" and a "fast agent" MoE for hardware with more headroom.
Last refreshed 2026-09-22; check its per-entry comments (and re-run
`docs/local-model-capabilities.md`'s safety/injection probes on any new
candidate) before trusting a pin as still current.

## Profiles

In this repo, declare them per host with the home-manager option
`modules.delegateToLocal.profiles` (`home/modules/delegate-to-local`), which
writes the file below; ali-desktop's are in `home/machines/ali-desktop`. A
host with none declared keeps a hand-written file, or none.

A profile names a runtime + model + launch settings. Declared in a TOML file
at `$LOCAL_LLM_PROFILES_FILE`, else `$XDG_CONFIG_HOME/delegate-to-local/profiles.toml`,
else `$HOME/.config/delegate-to-local/profiles.toml` — one `[name]` table per
profile:

```toml
[fast]
runtime = "llama-server"
model = "/home/you/models/qwen3.5-9b-instruct-q4_k_m.gguf"
port = 8080
launch_args = ["--ctx-size", "8192"]
description = "quick mechanical edits"

[quality]
runtime = "llama-server"
model = "/home/you/models/gpt-oss-20b-q4.gguf"
launch_args = ["--ctx-size", "16384"]
description = "harder reasoning, slower to load and run"
```

The scripts parse it via `yq` (mikefarah/yq — `yq -p toml -o json`), so `yq`
is a dependency alongside `curl`/`jq` for `switch-local-profile.sh` and
`list-local-profiles.sh`. `delegate-to-local.sh` and `stop-local-profile.sh`
never touch profiles.toml directly — they only read the active-profile state
file (still plain JSON, since nothing hand-edits it).

- `runtime` (required) — `llama-server`, `mlx-lm`, or `mock` (see below).
- `model` (required) — a path (llama-server) or path/repo id (`mlx_lm.server`);
  any string for `mock`, echoed back in the response.
- `port` (optional, default `8080`) — only matters if you want to run a
  quick manual comparison; normally leave it at the default, since exactly
  one profile runs at a time.
- `launch_args` (optional) — extra CLI args appended verbatim (e.g.
  context-size, quantization flags).
- `description` (optional) — shown by `list-local-profiles.sh`.
- `vram_mib` (optional) — the VRAM the loaded profile actually uses, in
  MiB. The fit check uses it instead of its estimate (model size × 1.2 +
  512MiB), which can refuse a profile that fits: it put a 13.5GB model with
  a q8_0 KV cache at 16.7GiB, where it measured 14.6GiB. Measure it as the
  card's used VRAM (`mem_info_vram_used` in sysfs) with the profile loaded
  and one request served, less the same reading with nothing loaded.

## Testing the pipeline without a real model

`scripts/mock-llm-server.py` is a tiny stdlib-only Python `http.server`
speaking the same `/v1/models`/`/v1/chat/completions` shape, for exercising
the real switch/queue/worker/delegate pipeline (real processes, real HTTP,
real concurrency) with no GPU and no model weights involved:

```toml
[test]
runtime = "mock"
model = "mock-model"
port = 8199
```

`scripts/switch-local-profile.sh test` then `scripts/delegate-to-local.sh
"..."` exercises everything except actual inference — useful for verifying
a change to the queue/worker machinery itself without risking a real load.
It's exempt from the fit check (see below) since it never touches the
GPU.

## One worker, one queue

`delegate-to-local.sh`, `switch-local-profile.sh`, and `stop-local-profile.sh`
don't touch the model or `active-profile.json` themselves — they submit a job
(`chat`/`switch`/`stop`) to `queue-worker.sh` and block until it answers.
The worker processes jobs **strictly one at a time, in submission order**,
so however many of these run concurrently (multiple Claude Code sessions,
several parallel sub-agents, a switch racing a delegate call), none of them
ever race the model or each other:

- A `switch` while chat jobs are already queued runs *after* them, not
  instead of them — nothing gets the model pulled out from under it mid-call.
- Two `delegate-to-local.sh` calls that land at the same instant get served
  in order, not garbled together against a runtime that may not handle
  concurrent requests well.
- Two Claude sessions starting cold at the same moment can't end up with two
  worker processes — an `mkdir`-based lock (portable, no `flock` dependency)
  ensures exactly one wins the race to start it.

The worker is **never started by hand**: each of the three client scripts
lazily starts one if the pidfile shows none alive, then submits its job.
It exits itself after `LOCAL_LLM_QUEUE_IDLE_TIMEOUT` idle seconds (default
600) rather than running forever unattended — the next call respawns it.
`list-local-profiles.sh` is the one script that stays direct/read-only; it
never mutates state, so it doesn't need to queue.

- **`switch-local-profile.sh <name>`** — submits a `switch` job: stop
  whatever's running, launch the named profile, wait
  (`LOCAL_LLM_READY_TIMEOUT`, default 120s) until it's actually ready to
  serve a request — checked against `/health` (`{"status": "ok"}`) when the
  runtime has one, not just whether the port accepts connections: confirmed
  live against a real llama-server that `/v1/models` answers 200 while the
  model is still loading in the background, so a bare reachability check
  reports ready before a chat call would actually succeed. Runtimes with no
  `/health` route (the mock server, `mlx_lm.server`) fall back to the
  `/v1/models` check as before. Loading a model is the one place allowed to
  be slow — run it deliberately before a stretch of work, not per delegated
  task. Records the active profile (name, url, model, pid) to
  `$LOCAL_LLM_STATE_DIR/active-profile.json`.
  **Checks the requested profile actually fits alongside whatever else is
  using the GPU** (a game) instead of refusing outright just because the GPU
  is busy: it reads free VRAM (total minus used, on the DRM device with the
  largest VRAM pool — picks the real dGPU over a tiny iGPU/display-only one
  if the machine has both) and the profile's own model size (the `.gguf`
  file, or the total of a directory for `mlx_lm.server`), and only refuses
  if that model plus a safety margin (`LOCAL_LLM_VRAM_OVERHEAD_FRACTION`,
  default `0.2` — extra headroom for KV cache/activations, scaled with model
  size — plus `LOCAL_LLM_VRAM_BUFFER_MB`, default `512`, a flat buffer)
  wouldn't fit in what's free. A small profile can still load next to a game
  using the rest of the card; a big one gets refused only when it genuinely
  wouldn't fit. On refusal, it scans every *other* declared, non-`mock`
  profile and names whichever ones *would* fit right now, so switching to a
  smaller profile instead is a real, offered option, not just "no."
  `LOCAL_LLM_FORCE_SWITCH=1` skips the check entirely for when you're sure
  it's fine. The `mock` runtime (below) is always exempt — it never touches
  the GPU. If VRAM usage or the model's size can't be determined at all (no
  AMD sysfs — e.g. Nvidia, or macOS unified memory isn't covered yet; or the
  model is a bare HF repo id not downloaded locally), it fails **open** and
  proceeds, rather than blocking on data the check can't see.
- **`list-local-profiles.sh`** — prints every declared profile, marks which
  one the state file says is active, and live-checks whether that active one
  is actually still responding. Read-only; never loads, unloads, or queues.
- **`stop-local-profile.sh`** — submits a `stop` job: stops the active
  profile and clears the state file, to free VRAM/unified memory when
  you're done. No-op, safe to run any time.
- **`delegate-to-local.sh "<task>"`** — submits a `chat` job for whichever
  profile is currently active. Never loads or switches a profile itself.

`LOCAL_LLM_STATE_DIR` (all four scripts, plus the worker) overrides the
state/queue location, falling back to `$XDG_CACHE_HOME/delegate-to-local/`
then `$HOME/.cache/delegate-to-local/`. `LOCAL_LLM_QUEUE_TIMEOUT` on each
client caps how long it waits in the queue (60s for delegate/stop,
`LOCAL_LLM_READY_TIMEOUT + 60s` for switch, since that wait has to cover the
model's own load time too).

## Coordinating across sessions: reservations

The queue prevents *corruption* (racing operations), but two Claude sessions
can still have conflicting *intent* — one wants `fast` loaded, another wants
`quality`. Without anything more, they'd just keep switching each other's
profile out from under one another. A **reservation** lets a session that's
about to make many calls protect the active profile for a while, so the
other session sees that and can choose to wait, fall back to
`delegate-to-copilot.md` or a Claude sub-agent, or force it if it really
needs to.

Reservations are **opt-in and self-renewing** — there's no separate
reserve/release step:

- A single `delegate-to-local.sh` call with no `LOCAL_LLM_RESERVE_SECONDS`
  set never reserves anything. It's always fine for another session to
  switch away immediately after — that's the default, matching "just one
  call is fine to preempt."
- Set `LOCAL_LLM_RESERVE_SECONDS=N` (and optionally `LOCAL_LLM_RESERVE_REASON`)
  when you intend a batch, not a single call. Each successful call renews
  the reservation for another `N` seconds. As long as calls keep coming
  within that window, the profile stays protected; once they stop, it
  **lapses on its own** shortly after the batch actually finishes — nothing
  has to explicitly release it.
- While a reservation is active, `switch-local-profile.sh` and
  `stop-local-profile.sh` both refuse (exit 1) rather than preempt it,
  naming the reason and how long it has left, and suggesting the fallback:
  "Consider delegate-to-copilot.md or a Claude sub-agent meanwhile, wait it
  out, or set `LOCAL_LLM_FORCE_SWITCH=1` to preempt it anyway."
  `LOCAL_LLM_FORCE_SWITCH=1` always overrides, same as the fit check above.
- `list-local-profiles.sh` shows an active reservation (reason + time
  remaining) next to the active profile, so checking before you switch is
  a normal read, not a guess.
- A successful switch or stop clears any reservation — it was for the
  profile that's now gone, so there's nothing left to protect.

## Usage

```
scripts/switch-local-profile.sh fast   # once, deliberately, before a stretch of work
scripts/delegate-to-local.sh "<task>"  # as many times as needed while it's loaded
scripts/stop-local-profile.sh          # when done, to free the hardware
```

`delegate-to-local.sh` env vars:

- `LOCAL_LLM_URL` — bypass profiles entirely, talk to this endpoint directly
  (for ad hoc use against something not managed via a profile).
- `LOCAL_LLM_MODEL` — override the model name sent in the request.
- `LOCAL_LLM_EXPECT_PROFILE` — fail loudly (exit 4) if this isn't the
  profile actually active, instead of silently running against whatever is
  loaded. Use this when a task assumed a specific profile ("run this against
  `quality`") so a stale `fast` load doesn't silently answer instead.
- `LOCAL_LLM_RESERVE_SECONDS` / `LOCAL_LLM_RESERVE_REASON` — protect the
  active profile from being switched away for this long after each call
  (see "Coordinating across sessions" above). Set it when you intend many
  calls, not for a single one — unset/`0` (the default) reserves nothing.

## Exit codes: this is the graceful-degradation contract

- **1** — usage or config error (bad args, `curl`/`jq` missing, unresolvable
  state dir). A bug, not a reason to fall back to another delegate.
- **2** — no profile is active, or the recorded one isn't actually
  responding (crashed). Expected whenever nothing is loaded right now.
  **Treat this as "fall back to `delegate-to-copilot.md` or a Claude
  sub-agent"**, not a hard failure — don't retry in a loop hoping a profile
  loads itself; nothing loads a profile except `switch-local-profile.sh`.
- **3** — the active endpoint answered but the chat-completion call itself
  failed or returned something unparseable. A real failure worth surfacing.
- **4** — `LOCAL_LLM_EXPECT_PROFILE` was given and doesn't match what's
  actually loaded.

The script prints the model's reply to stdout on success.

## Agent mode: `delegate-to-local-agent.sh`

```
scripts/switch-local-profile.sh fast
scripts/delegate-to-local-agent.sh /abs/path/to/dir "<task>"
```

Runs the task in `opencode run` against the active profile, with read,
glob, grep and list allowed inside `<dir>` and everything else denied:
edit, bash, web, sub-agents, skills, and reads outside `<dir>`. Prints the
model's final reply on stdout and one line per tool call on stderr, and
keeps the full event log under `$state_dir/agent-runs/`. Read the tool
lines: they show whether the answer came from the file or from the model.

Why it builds its own opencode setup (`$state_dir/agent-home`) instead of
using yours:

- **Size.** The global opencode config (skills, MCP servers, instructions)
  made the first request 17,249 tokens, more than `fast`'s 16k context
  before the model did anything. The isolated setup starts at 3,105.
- **Permissions.** The global config allows every tool.
- **Context size.** opencode must be told the profile's real `--ctx-size`
  (read from `profiles.toml`): told more, it overflows the server.
- **Compaction is off.** On overflow opencode compacts the conversation
  and carries on, and the summary lost the task: Qwen3.6-27B then replied
  "I don't have access to prior conversation history", exit 0. The script
  exits 5 on an overflow instead.

It reserves the profile for the run (it talks to the server directly, not
through the queue) and releases it on exit. Needs opencode 1.18.31 or later:
1.18.30 crashes on every prompt (anomalyco/opencode#48965). Exit codes are
the table above plus **5**: the task outgrew the context; split it. In edit
mode, **6**: the run changed a file that runs code later (see below).

**Exit 0 means the run finished, not that the task was done.** A model that
could not do something says so in prose and exits 0.

## Edit mode: the model edits, the caller reviews

```
LOCAL_LLM_AGENT_EDIT=1 scripts/delegate-to-local-agent.sh /abs/path/to/dir "<task>"
```

Adds opencode's edit and write tools inside `<dir>`. Shell, web and
anything outside `<dir>` stay denied. Before the run the script copies
`<dir>` to `<log>.before`; after it, even a failed one, it writes
`<log>.diff`, lists the changed files, and prints the command that restores
the snapshot.

**Review the diff, never the model's summary.** In the permission test the
model reported a refused write as "created successfully" and a completed
write as "denied". The diff and the tool lines were right both times.

- Point it at a copy or a scratch checkout, not a tree with work in
  progress: the snapshot covers the whole directory, and a large one is
  slow to copy.
- Denying the shell does not stop it reaching the same result another way:
  asked to `touch` a file, it created the file with the write tool.
- Nothing it writes is kept by the script. Keep, commit or restore after
  review.
- **Exit 6: it changed a file that runs code later**, anything under `.git/`
  (a hook runs on your next commit) or an `.envrc` (direnv runs it). The
  script lists the paths after the diff. Read those first; "no shell" does
  not hold past them. It wins over 3 and 5: a failed run can leave one too.
- A run that changed nothing deletes its snapshot; other snapshots are
  deleted after a week.

## What the local models are good and bad at

Measured 2026-09-25 on ali-desktop (RX 9070 XT) with agent mode, on real
tasks with answers checked against the source. Add to this table when a
new model or task shape is tried; it is the evidence for the rules below it.

| Model (profile) | Task | Result |
|---|---|---|
| Qwen3-8B (`fast`) | Read one file, return line 3 | ✓ 23 s, used `read` with offset 3, limit 1 |
| Qwen3-8B | Asked to write a file and run a command | ✓ Both denied, said it could not; exit 0 |
| Qwen3-8B | Asked to read `/etc/hostname` (outside the dir) | ✓ Denied |
| Qwen3-8B | List the calls in one function of a 1,400-line patch, with line numbers | Calls and order ✓, 2 of 4 line numbers wrong by 2 to 4; re-read from line 1 after grep gave the line; 61 s |
| Qwen3-8B | Which Wayland events does smithay's `change_current_state` send? | ✗ Read the lines that send `xdg_output.logical_size`, answered that it sends none; quoted a real but irrelevant comment; 40 s |
| Qwen3.6-27B (`quality`, 8k context) | Same smithay question | Navigation ✓ (found both functions I did, in the same order), ran out of context at 8,554 tokens before answering; 264 s |
| Qwen3.6-27B (`quality`, 16k, q8_0 KV cache) | Same smithay question | ✓ Every field right, including the event order, how the size is computed, and the line of `done()`; 79 s |
| Qwen3.6-27B (16k) | Open-ended: trace what xwayland-satellite does with the size at `wl_output.done` | Read the right lines on its 5th call, then chased a macro and RandR through 25 calls and overflowed at 17,882 tokens; 119 s. The answer was in the lines it had read |
| Qwen3-8B (32k, edit mode) | Change one line of a file | ✓ One `edit` call, exactly that line; 29 s |
| Qwen3-8B (32k, edit mode) | Write outside the dir, and run a shell command | ✓ Outside write refused; no shell, so it created the file with `write` instead. ✗ Its summary had both outcomes backwards |
| Qwen3.6-27B (16k, edit mode) | Fix xwayland-satellite's `Mode` handler, given the file, line range and behaviour but not the code | ✓ Same change a reviewer would write; builds; all 80 existing tests pass; 51 s |
| Qwen3.6-27B (16k, edit mode) | Add a regression test and a test-compositor helper, from a written spec | Helper ✓. Test ✗: spec said the *last* event, it used `find_map` (the first), so the test failed with and without the fix; 78 s |
| Qwen3.6-27B (16k, edit mode) | Apply one review comment ("pick the last event, not the first") | ✓ One-line `.rev()` fix; the test then failed without the fix and passed with it; 23 s |
| Qwen3.6-27B (16k, edit mode) | Two small bash edits to this skill's own script, given the exact lines to add | ✓ Both exactly as specified; 56 s. (Its run exited 5, a false alarm from the script's own compaction check, since fixed) |
| Qwen3.6-27B (16k, edit mode) | Move an early `exit 6` to after the reply is printed, given the lines | ✓ Exactly as specified, line numbers right; 32 s |
| Qwen3-8B (32k, edit mode) | Replace one doc line with two given lines | Words ✓, shape ✗: joined them into one 150-character line despite being told two; 40 s |
| Qwen3-8B (32k, edit mode) | Write a new 6-part module from a numbered spec, "first read heldkeys.py" for the ioctl | The sysfs scan ✓. Never read the reference: left one function with no body, invented the ioctl number, skipped "sorted"; 27 s |
| Qwen3-8B (32k, edit mode) | Apply three review comments, each with the exact new lines | ✓ All three; dropped the blank lines between functions; 93 s |
| Qwen3-8B (32k, edit mode) | Write a unittest file from an exact spec | 3 of 4 tests right. The fixture wrote the name to `device`, not `device/name`, so its own test failed; skipped one case; ignored the blank-line rule; 18 s |
| Qwen3-8B (32k, edit mode) | Fix that fixture from one review comment | ✗ 34 `edit` calls, all "Could not find oldString". It never re-read the file (a line had trailing spaces), and ended with no reply; 398 s |

What that means for writing a task:

- **Extraction yes, comprehension no (8B).** It finds and lists things
  reliably. Asked what code *does*, it can read the right lines and state
  the opposite. Ask the 8B for the text; decide what it means yourself.
- **The 8B follows what, not always how.** Asked for two wrapped lines, it
  wrote the right words as one long line. Check the shape of its edits too.
- **The 8B skips "read X first".** Told to copy a function from a file, it
  never opened the file and made the code up. Paste what it needs into the
  task instead of pointing at it.
- **The 8B cannot recover from a failed edit.** When its `oldString` did
  not match, it retried the same guess 34 times without re-reading the
  file. For the 8B, ask for a new file or a whole-function rewrite, not an
  edit of existing lines. Run it on the 27B when an edit is unavoidable.
- **The 8B writes new code fast and about half right.** 18 to 27 s per
  file, the easy parts right, one real bug per file. Worth it only with the
  review and a test run you would do anyway.
- **Never trust its line numbers.** Ask for the code text and grep for it.
- **Give absolute, real paths.** "The current directory" became the path
  `/current/directory/...`. A symlinked directory broke grep and glob
  until the model switched to the resolved store path.
- **Tell it to grep before reading**, and to read a bounded range. Say
  "do not read the whole file" for anything large.
- **One question per run, with a fixed reply format.** A form to fill in
  (`FIELD: value`) is easy to check line by line.
- **The 27B reads code correctly once it has room.** At 8k it overflowed;
  at 16k it answered the same two-file question right. Prefer it over the
  8B for any question about what code does.
- **The 27B edits well from a precise spec, and takes review.** It wrote a
  correct fix first time, and fixed its one test mistake from a single
  review comment. The mistake was a detail the spec stated and the code
  silently got wrong, which is what review is for.
- **Prove a generated test fails without the fix.** Its first test compiled,
  read plausibly, and could never pass. Running it with and without the
  fix is what caught that.
- **Bound the search, not just the question.** Asked to "trace" a value,
  the 27B kept exploring past the answer until it overflowed. Name the
  files or functions to read, cap the number of reads, and say "stop and
  answer once you have read X".
- **Check every answer against the source.** Every result above was
  checked, and two of four real tasks were wrong in a way that read as
  confident.

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files — same rule as `delegate-to-copilot.md`, and it applies
  even though the request never leaves your own machine: the model's own
  output/logs may retain it.
- Treat the response as untrusted, to review not accept — same as any other
  delegated output.
- Don't retry a timeout in a tight loop — a local model under load degrades
  in latency, not availability; a slow response is not a hung one.

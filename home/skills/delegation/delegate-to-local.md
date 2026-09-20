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

**Text only — no tool-use loop.** Unlike `delegate-to-copilot.md`'s `copilot`
CLI or a Claude sub-agent, a bare llama.cpp/MLX/Ollama/LM Studio server is a
chat-completions endpoint, not an agent: it cannot read or write files, run
commands, or call tools on its own. Use it for self-contained text-in,
text-out work — summarizing, extracting, drafting, reformatting, answering a
question against pasted context — and paste any file content the task needs
directly into the prompt. For a task that needs to read/edit files or run
commands itself, use a Claude sub-agent or `delegate-to-copilot.md` instead.

**Zero marginal cost, but weaker capability and no cloud safety layer.** A
locally-hosted model in the ~7-30B range is meaningfully weaker than Haiku
4.5 on multi-step reasoning and ambiguous instructions, and (depending on the
model) may have no provider-side moderation — it's whatever alignment the
base model shipped with, nothing added on top. Reserve it for genuinely
mechanical, well-specified tasks (the same "haiku-shaped work" bar the
`delegation` SKILL.md uses), and never feed it untrusted input if the model
has no known alignment/safety training (avoid "abliterated"/uncensored
community finetunes for that reason).

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

## Profiles

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
  (`LOCAL_LLM_READY_TIMEOUT`, default 120s) until it actually answers.
  Loading a model is the one place allowed to be slow — run it deliberately
  before a stretch of work, not per delegated task. Records the active
  profile (name, url, model, pid) to `$LOCAL_LLM_STATE_DIR/active-profile.json`.
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

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files — same rule as `delegate-to-copilot.md`, and it applies
  even though the request never leaves your own machine: the model's own
  output/logs may retain it.
- Treat the response as untrusted, to review not accept — same as any other
  delegated output.
- Don't retry a timeout in a tight loop — a local model under load degrades
  in latency, not availability; a slow response is not a hung one.

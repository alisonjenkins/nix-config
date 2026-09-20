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

- `runtime` (required) — `llama-server` or `mlx-lm`.
- `model` (required) — a path (llama-server) or path/repo id (`mlx_lm.server`).
- `port` (optional, default `8080`) — only matters if you want to run a
  quick manual comparison; normally leave it at the default, since exactly
  one profile runs at a time.
- `launch_args` (optional) — extra CLI args appended verbatim (e.g.
  context-size, quantization flags).
- `description` (optional) — shown by `list-local-profiles.sh`.

## Scripts

- **`switch-local-profile.sh <name>`** — stops whatever profile is currently
  running, launches the named one, and waits (`LOCAL_LLM_READY_TIMEOUT`,
  default 120s) until it actually answers before returning. This is the one
  place that's allowed to be slow — run it deliberately when you're about to
  do a stretch of work with a specific profile, not per delegated task.
  Records the active profile (name, url, model, pid) to
  `$LOCAL_LLM_STATE_DIR/active-profile.json`.
- **`list-local-profiles.sh`** — prints every declared profile, marks which
  one the state file says is active, and live-checks whether that active one
  is actually still responding. Read-only; never loads or unloads anything.
- **`stop-local-profile.sh`** — stops the active profile and clears the
  state file, to free VRAM/unified memory when you're done. No-op, safe to
  run any time.
- **`delegate-to-local.sh "<task>"`** — sends the task to whichever profile
  is currently active. Never loads or switches a profile itself (too slow
  for a per-call operation) — it only reads the state file, does one
  liveness check, and posts the request.

`LOCAL_LLM_STATE_DIR` (all four scripts) overrides the state location,
falling back to `$XDG_CACHE_HOME/delegate-to-local/` then
`$HOME/.cache/delegate-to-local/`.

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

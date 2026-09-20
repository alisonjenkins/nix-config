# Delegating to a locally-hosted model

An alternative to a Claude sub-agent or `delegate-to-copilot.md` for
zero-marginal-cost, no-cloud-dependency delegation: `scripts/delegate-to-local.sh`
sends a subtask to a model running on your own hardware via an
OpenAI-compatible chat-completions endpoint (`llama-server`, Ollama, LM
Studio, and similar all expose this same shape at `/v1/chat/completions`).
Works from any machine that has a local endpoint reachable — it doesn't
assume any particular host or GPU.

## What this can and can't do

**Text only — no tool-use loop.** Unlike `delegate-to-copilot.md`'s `copilot`
CLI or a Claude sub-agent, a bare llama.cpp/Ollama/LM Studio server is a
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

## Setup: one endpoint per machine

Any OpenAI-compatible local server works. `llama-server` (from llama.cpp)
with the Vulkan backend is a reasonable default on Linux with an AMD GPU —
more reliable today than ROCm on younger RDNA hardware, which can have
driver-maturity gotchas (e.g. a HIP backend that doesn't idle the GPU after
inference on some RDNA4 cards). On Apple Silicon, MLX (via `mlx-lm` or LM
Studio's MLX engine) is typically faster than llama.cpp's Metal backend.

Model choice is a per-machine hardware tradeoff (VRAM/unified-memory budget
vs. tokens/sec vs. capability), not something this doc hardcodes — pick the
largest model your hardware runs at an acceptable tok/s, and prefer a
mainstream aligned instruct release (Qwen, Llama, Gemma, gpt-oss, etc.) over
an uncensored finetune. Re-check current model releases and benchmarks
periodically; this space moves fast enough that any specific model/quant
recommendation here would go stale within months.

## It never assumes which machine it's on

`delegate-to-local.sh` doesn't hardcode a host's endpoint or model. With
`LOCAL_LLM_URL` unset, it probes a short list of well-known default ports —
`localhost:8080` (llama-server), `:11434` (Ollama), `:1234` (LM Studio) — one
fast request per candidate (`LOCAL_LLM_PROBE_TIMEOUT`, default 0.5s), and
uses the first one that answers. The same probe request also discovers a
model name from the endpoint's `/v1/models` list, so a bare invocation with
no env vars set works unmodified on any of your three machines as long as
one of those default servers is running. Set `LOCAL_LLM_URL`/`LOCAL_LLM_MODEL`
explicitly only to skip auto-detection (e.g. a non-default port, or a server
that needs a specific model name).

## Usage

```
scripts/delegate-to-local.sh "<task>"
```

- `LOCAL_LLM_URL` — skip auto-detection, use only this endpoint.
- `LOCAL_LLM_MODEL` — skip model auto-discovery, request this model name.
- `LOCAL_LLM_PROBE_TIMEOUT` — seconds allotted per candidate during
  auto-detection (default `0.5`).

## Exit codes: this is the graceful-degradation contract

- **1** — usage or dependency error (bad args, `curl`/`jq` missing). A bug,
  not a reason to fall back to another delegate.
- **2** — no local endpoint is reachable. Expected whenever nothing is
  running locally on that machine. **Treat this as "fall back to
  `delegate-to-copilot.md` or a Claude sub-agent"**, not a hard failure —
  don't retry in a loop hoping a server appears.
- **3** — an endpoint answered but the actual chat-completion call failed or
  returned something unparseable. A real failure worth surfacing, since the
  endpoint is there but something is actually wrong with it.

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

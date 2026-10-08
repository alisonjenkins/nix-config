# Model configuration

llama-server runs on its own defaults unless told otherwise: temperature 0.8,
top-k 40, top-p 0.95, min-p 0.05, no presence penalty. No profile in this repo
sets sampling, so every model so far ran off its vendor's recommendation.

## Where to look, in order

1. The model card on Hugging Face: a "best practices" or "quickstart" section
   with sampling, a thinking switch and a serving command.
2. `chat_template.jinja` in the model repo, and any note about a changed
   template. Ornith, for one, says it adjusted the Qwen template.
3. The quantiser's page (unsloth, bartowski). Unsloth sometimes ships fixed
   templates and flags per model.
4. llama.cpp issues for the architecture name (`qwen35`, `qwen35moe`, `gemma4`).

Record each value with its source, and mark it vendor-reported.

## Vendor settings seen so far (2026-10-08)

Order: temp / top_p / top_k / min_p / presence / repeat. "Coding" is the card's
precise-coding or agentic profile.

| Model | Coding / agentic | Thinking switch | Tool format |
|---|---|---|---|
| Qwen3-8B | 0.6 / 0.95 / 20 / 0, presence 0 to 2 optional; no greedy | `enable_thinking`; `/think`, `/no_think` only while it is true | Hermes JSON (not on the card) |
| Qwen3.5-9B | 0.6 / 0.95 / 20 / 0 / 0 / 1.0 | `chat_template_kwargs {"enable_thinking": false}` | Qwen3-Coder XML |
| Qwen3.6-27B | 0.6 / 0.95 / 20 / 0 / 0 / 1.0 | as above; `preserve_thinking` | Qwen3-Coder XML |
| Qwen3.6-35B-A3B | 0.6 / 0.95 / 20 / 0 / 0 / 1.0 | as above | Qwen3-Coder XML |
| Qwen3.8-27B | 1.0 / 0.95 / 20 / 0 / 0 / 1.0 | `enable_thinking`; `reasoning_effort` xhigh, medium or low | not stated |
| Gemma 4 12B | 1.0 / 0.95 / top-k 64; others unset | the think token at the start of the system prompt turns it on (Unsloth's Gemma 4 page gives the exact token); `enable_thinking: false` turns it off | not stated |
| Ornith-1.5-9B | 0.6 / 0.95 / 20 / 0 / 0 / 1.0 | thinks by default, no documented off switch | Qwen3-Coder XML (`<tool_call><function=...>`) |
| Ornith-1.5-35B-A3B | 0.6 / 0.95 / 20; nothing else given | as the 9B | as the 9B |

Generic (non-coding) profiles on the Qwen3.5/3.6 and Ornith cards use temp 1.0
and presence 1.5. Do not use those for an editing agent.

Not documented by any card: whether a q8_0 KV cache or flash attention hurts
that architecture. Treat the production flags (`--cache-type-k q8_0
--cache-type-v q8_0 --flash-attn on`) as a variable if a model misbehaves, and
test with the cache at f16.

## Flags

| Setting | llama-server |
|---|---|
| temperature, top-p, top-k, min-p | `--temp`, `--top-p`, `--top-k`, `--min-p` |
| presence, repeat penalty | `--presence-penalty`, `--repeat-penalty` |
| vendor chat template | `--chat-template-file <path>` (with `--jinja`) |
| thinking off, per call (no reload) | `chat_template_kwargs: {"enable_thinking": false}` in the request body; the delegation scripts set it from `LOCAL_LLM_THINKING=off` |
| thinking off, fixed for a profile | `--reasoning off` at launch; changing it restarts the server and reloads the weights |
| thinking budget | `--reasoning-budget N` (0 ends thinking at once) |

Sampling a client puts in the request overrides the server flags. This has not
been checked for opencode here, so when a profile's sampling seems to have no
effect, look at the request the client actually sends (the agent runner keeps
an event log under `~/.cache/delegate-to-local/agent-runs/`).

## Does the embedded template match the vendor's?

```
curl -s http://127.0.0.1:8080/props | python3 -c 'import json,sys; print(json.load(sys.stdin)["chat_template"])' > embedded.jinja
diff embedded.jinja vendor-chat_template.jinja
```

If they differ in the tool-call or thinking sections, test the profile with
`--chat-template-file`. Say in the write-up which one was used.

## Ornith specifics

Ornith 1.5 was post-trained on Qwen3.5 and Gemma 4 checkpoints, emits
Qwen3-Coder XML tool calls, thinks by default, and ships an adjusted chat
template. Its card's own serving command is `llama-server -hf
ornith-ai/Ornith-1.5-9B-GGUF -c 262144`. The vendor's own parser names are
vLLM `qwen3_xml` and SGLang `qwen3_coder`. The first comparison of it against
Qwen3.5-9B ran on the buggy engine; see [engine-preflight.md](engine-preflight.md).

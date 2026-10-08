---
name: local-llm-setup
description: >-
  Use when adding, configuring or benchmarking a locally hosted LLM (llama.cpp llama-server, mlx_lm) for the delegation skill's local rung or for opencode: choosing a model and quant, writing a profile (launch_args, sampling, chat template, thinking mode), checking the llama.cpp build, a model whose tool calls fail or loop (edit loops, "oldString and newString are identical", indentation one space short, five failed tool calls in a row), comparing a candidate against the incumbent, measuring vram_mib, or deciding whether a model is an upgrade or should be dropped. Not for using an already loaded model (see delegation).
---

# Local LLM setup and benchmarking

A model that loops or fails tool calls has not been shown to be a bad model.
Engine, chat template, sampling and thinking mode each cause the same
symptoms. Rule out all four before you write a model off, and before you
believe a comparison that did not hold them equal.

## What went wrong once (2026-10-08)

Ornith-1.5 looped on `edit` calls and was eliminated. Looking at the raw
traffic showed the model writing `<parameter=oldString>` with 8 leading
spaces and llama-server returning 7. The production build (b9190) trimmed one
leading space from every tool-call parameter; the fix is llama.cpp PR #24624,
in b9644. The incumbent had the same defect and coped; the candidate did not.
Every earlier tool-calling elimination on that engine is suspect, and none of
the models had been given the sampling their own cards recommend.

## The order to work in

1. **Engine.** `llama-server --version`. Anything older than b9644 corrupts
   leading whitespace in tool arguments. Run the probe in
   [engine-preflight.md](engine-preflight.md) before trusting any tool-calling
   result.
2. **Model card config.** Read the card for sampling, thinking switch, tool
   format and chat template. Our profiles set none of the sampling, so every
   model has run on llama-server's defaults (temp 0.8, top-k 40, min-p 0.05).
   See [model-config.md](model-config.md).
3. **Template.** Compare the GGUF's embedded template (`GET /props`) with the
   vendor's `chat_template.jinja`. If they differ, test `--chat-template-file`.
4. **Thinking.** Know whether it is on, and try it off before blaming the
   model (`--reasoning off` or `chat_template_kwargs`).
5. **Fit.** Measure `vram_mib` loaded minus idle with one request served.
6. **Benchmark both sides the same way.** Same engine, same flags class,
   incumbent also on its card config. See [benchmarking.md](benchmarking.md).
7. **Only then** decide upgrade, keep or drop, and say which of the four
   confounds above you ruled out.

## Rules

- Never delete a candidate's files before you know why it failed. Re-downloading
  a 13 GB GGUF costs more than a diagnosis.
- Compare on the same llama.cpp build. If the candidate needs a newer build,
  run the incumbent on it too.
- Report abnormal exits and failed tool calls next to pass counts. A model that
  passes 10 of 12 while looping in 6 of 14 runs is not equal to one that passes
  10 of 12 cleanly.
- A grader that fails every model, including the strongest, is a grader bug.
  Read the replies.
- Label vendor benchmark numbers as vendor-reported.

## Routing

| Doing | Read |
|---|---|
| Checking the llama.cpp build, tool-call parsing, Vulkan builds | [engine-preflight.md](engine-preflight.md) |
| Choosing sampling, template and thinking settings for a model | [model-config.md](model-config.md) |
| Running the suite, reading results, ruling out confounds | [benchmarking.md](benchmarking.md) |
| Pinning a model and profile in this repo | [adopting-a-model.md](adopting-a-model.md) |

The scripts under `scripts/` need the `delegation` skill's
`switch-local-profile.sh` and friends. They find it under `~/.claude/skills`,
`~/.agents/skills` or the repo; set `DELEGATION_SCRIPTS` to override.

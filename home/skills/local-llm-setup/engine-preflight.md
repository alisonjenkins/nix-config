# Engine pre-flight

Do this before any tool-calling result is believed.

## 1. Build number

```
llama-server --version      # version: 9190 (b64739e)  /  0.6.0 (build 11429, ...)
llama-server --list-devices # the GPU must appear, not only BLAS/CPU
```

| Build | Meaning |
|---|---|
| below b9644 | Tool-call parameters lose one leading space. Do not trust edit-tool results. |
| b9644 and later | Fixed by llama.cpp PR #24624, "chat: fix whitespace problems once and for all", merged 2026-06-15. b9644 is the first release whose notes name it; commit ancestry was not checked. Measured here: b9190 drops the space, b11429 does not. |
| b10687 and later | Reported floor for Qwen3.8 (its Gated-DeltaNet layers gave garbage on older CUDA builds, discussion 27164). Secondhand and not confirmed here: Qwen3.8-27B UD-Q3_K_XL loaded on b9190 with Vulkan and answered a simple prompt correctly on 2026-10-08, though it was only benchmarked on b11429. Check any new architecture by loading it and asking something with a known answer. |

As of 2026-10-08 nixpkgs master had b11429 and nixos-unstable b11146. A host
still reporting b9190 has a stale nixpkgs input; updating it is the fix. Both
numbers come from the research notes for this skill; re-check the package
version before relying on them.

Two neighbouring parser bugs exist and are not the same defect: #26763
(a Qwen3.6 parameter swallowing later tool calls when the model omits a
newline before the value) and #28327 (array-of-object arguments).

## 2. Prove it with the raw-versus-parsed probe

```
scripts/probe-tool-whitespace.sh <profile> [old|new]
```

It loads the profile and asks the model to call an `edit` tool with two
strings that each start with exactly eight spaces. It prints two views:

- **parsed**: what `/v1/chat/completions` returns in `tool_calls`, with the
  leading-space count of `oldString` and `newString`;
- **raw**: the model's own text from `/apply-template` plus `/completion`,
  where you can read the `<parameter=oldString>` block and count the spaces
  the model really wrote.

Reading it:

| parsed | raw | Meaning |
|---|---|---|
| 8 and 8 | 8 | Healthy. |
| 7 and 7 | 8 | Server parser bug. Update the engine; do not blame the model. |
| 7 and 7 | 7 | The model miscounted. A model problem, or a thinking or sampling problem. |

Run it for the incumbent as a control. On 2026-10-08, b9190 gave 7 for both
Qwen3.5-9B and Ornith-1.5-9B, and b11429 gave 8 for both.

`PROBE_SCENARIO=newlines` runs a second check: a `write` call with four
consecutive lines. Parsed `blank_lines_in_content` should be 0 and the raw
text should show single newlines. On 2026-10-08 both Ornith-1.5-9B and
Qwen3.5-9B passed it at temperature 0.6, so doubled blank lines in real runs
did not come from newline handling. `PROBE_TEMPERATURE` sets the sampling
temperature for the probe.

Symptoms it explains: `edit` failing with "oldString not found", then
"No changes to apply: oldString and newString are identical", and the agent
script stopping after five failed tool calls in a row.

## 3. A second llama.cpp side by side

To test a newer build without touching the system one, build it and put it
first on `PATH` for that run:

```
LLAMA_BIN_DIR=/path/to/newer/bin scripts/bench-matrix.sh myprofile:new
```

In this repo `pkgs/llama-cpp-upstream` is a pinned upstream commit layered on
`pkgs.master.llama-cpp`. It is CPU/BLAS only unless the layer underneath has
Vulkan on:

```nix
pkgs.callPackage ./pkgs/llama-cpp-upstream {
  llama-cpp = pkgs.llama-cpp.override { vulkanSupport = true; };
}
```

Overriding the outer expression instead fails with "called with unexpected
argument 'vulkanSupport'", because the outer function takes `llama-cpp`.
Check `--list-devices` shows the Vulkan device before benchmarking.

## 4. The queue worker keeps its PATH

`switch-local-profile.sh` starts a background queue worker that inherits the
PATH of whichever client started it. A worker left over from an earlier run
keeps launching the earlier `llama-server`. The scripts here stop the worker
between profiles; if you load by hand after switching engines, stop it first
(`stop-local-profile.sh`, then end the process named in
`~/.cache/delegate-to-local/queue-worker.pid`).

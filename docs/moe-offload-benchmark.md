# Running large models on limited VRAM: what's credible, what works here

Researched "run huge models fast on low-VRAM hardware by not loading the
full model at once" for `home/skills/delegation`'s local-LLM path on
ali-desktop (RX 9070 XT, 16GB, Vulkan/RADV via
`pkgs.llama-cpp.override { vulkanSupport = true; }` — **not** CUDA, **not**
ROCm, which was already rejected for this GPU; see
`home/skills/delegation/delegate-to-local.md`).

## The projects, and why most don't apply here

| Project | Credible? | Works on this hardware? |
|---|---|---|
| **AirLLM** (layer-by-layer disk streaming) | Real, actively maintained (v3.0, June 2026) | **No** — CUDA/Apple-MLX/CPU only, no AMD/Vulkan support anywhere. Also genuinely slow regardless: well under 1 tok/s on a 70B model even where it does run, disk-bandwidth-bound. |
| **PowerInfer** (SJTU — hot/cold neuron GPU/CPU split) | Real, actively maintained | **Reopened and tested** (`docs/powerinfer-rocm-benchmark.md`) — the ROCm idle-bug blocker has a confirmed fix (`-DGGML_HIP_GRAPHS=OFF`). Built and ran for real: correct output, no idle-bug regression, but ~9x slower than plain Vulkan full-GPU offload on a model that already fits. Same verdict as `--cpu-moe` below, now via a second, independent technique. |
| **ktransformers** (Tsinghua — MoE expert offload for DeepSeek-scale models) | Real, very actively maintained (DeepSeek-V4-Flash support added May 2026) | **No — not a ROCm blocker this time, a scale mismatch.** Its whole value proposition is running 400GB+ MoE models (DeepSeek-V3/R1 class) via CPU expert-offload; there's no small-model path to meaningfully test, unlike PowerInfer's 7B. Also pins PyTorch-ROCm 6.2.4 against our ROCm 7.2.3, recommends conda over nix, and its ROCm docs only mention RDNA3 (7900 XTX) — RDNA4 is untested territory on top of the scale problem. Not pursued: even if it built, there is nothing to run it against here. |
| **llama.cpp's own `--cpu-moe`/`--n-cpu-moe`/`--override-tensor`** | Ships in the exact llama-server already built and tested this session | **Yes — no new tooling needed.** Backend-agnostic tensor placement, not CUDA-specific code. |
| mmap-based lazy loading | Real | Already the default in llama.cpp, already in use — not a distinct technique to adopt. |

**Verdict: skip AirLLM/PowerInfer/ktransformers for this machine.** AirLLM has
no AMD path at all. PowerInfer's ROCm blocker was later resolved and it was
actually benchmarked (see above) — still not worth adopting, on throughput
grounds rather than compatibility ones. ktransformers targets a scale
(400GB+ MoE models) with nothing feasible to test it against here. For
day-to-day use, `llama.cpp`'s native MoE-offload flags, already present on
the build wired into `flake-modules/hosts/ali-desktop/default.nix`, are the
actual answer — confirmed by direct benchmark, not just by reading the docs
(which skew CUDA-heavy and don't call out Vulkan explicitly either way).

## Live benchmark: does `--cpu-moe` actually work on Vulkan, and is it worth it?

Model: `allenai/OLMoE-1B-7B-0924-Instruct-GGUF` (Q4_K_M) — a real MoE model,
official AllenAI quantization, 7B total parameters but only ~1B active per
token, small enough to test the mechanism without a multi-hour download.
Same prompt, `temperature 0`, `--ctx-size 2048`, three configurations:

| Configuration | VRAM used | Generation speed | Prompt processing |
|---|---|---|---|
| `--n-gpu-layers 99` (full GPU) | 4368 MiB | **382.9 tok/s** | 1176.3 tok/s |
| `--n-gpu-layers 99 --cpu-moe` (experts on CPU, attention/shared on GPU) | 687 MiB | 43.5 tok/s | 104.8 tok/s |
| `--n-gpu-layers 0` (CPU only, baseline) | ~0 MiB | 37.7 tok/s | 72.7 tok/s |

**The mechanism works** — `--cpu-moe` runs correctly on this Vulkan build,
cuts VRAM use by ~6.4x (4368 MiB → 687 MiB), and confirms the flag is
genuinely backend-agnostic as the docs implied but never stated for Vulkan
specifically.

**For a model this size, it's a net loss.** `--cpu-moe` gets you back to
roughly CPU-only speed (43.5 tok/s vs 37.7 tok/s baseline — the
GPU-resident attention/shared layers barely help once the CPU-resident
experts dominate the compute) while giving up **8.8x throughput** versus
just fitting the whole 4.3GB model on the GPU, which this card has more
than enough VRAM for anyway.

**When it would actually be worth it**: a MoE model that genuinely can't
fit in 16GB VRAM at all otherwise — e.g. a 30B+-total-parameter MoE
(Qwen3-30B-A3B class) or larger. There, the choice isn't "8.8x slower vs.
full speed," it's "8.8x slower vs. doesn't run at all." Worth a follow-up
benchmark against a model in that size class if a genuine need for one
comes up; not worth adopting pre-emptively for models that already fit.

## Practical takeaway for `home/skills/delegation` profiles

- Don't reach for `--cpu-moe`/`--n-cpu-moe` on a model that already fits in
  VRAM at full offload — it's strictly worse there.
- If a future profile needs a MoE model too large to fit fully (unlikely at
  16GB unless deliberately choosing a much bigger model), `--n-cpu-moe N`
  (offload only the first N layers' experts to CPU, keep the rest on GPU) is
  the tunable middle ground between the two extremes benchmarked above —
  not tested here since nothing in the current profile set needs it, but
  confirmed available on the build in use.

## Reproducing this

```bash
# Full GPU
llama-server -m olmoe-1b-7b-0924-instruct-q4_k_m.gguf --port 8099 --n-gpu-layers 99

# All experts on CPU
llama-server -m olmoe-1b-7b-0924-instruct-q4_k_m.gguf --port 8099 --n-gpu-layers 99 --cpu-moe

# CPU only (baseline)
llama-server -m olmoe-1b-7b-0924-instruct-q4_k_m.gguf --port 8099 --n-gpu-layers 0
```

Then POST the same prompt at `temperature: 0` to each and compare
`.timings.predicted_per_second` in the response, and
`/sys/class/drm/card*/device/mem_info_vram_used` before/after for the VRAM
delta.

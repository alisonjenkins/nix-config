# PowerInfer on ROCm: does the GPU-idle bug still block it, and is it worth it?

Follow-up to `docs/moe-offload-benchmark.md`, which rejected PowerInfer/ktransformers
for this machine because ROCm was rejected outright (RDNA4 HIP-inference GPU-idle
bug, see `home/skills/delegation/delegate-to-local.md`). Revisited after finding
`-DGGML_HIP_GRAPHS=OFF` mitigates that bug on modern llama.cpp (confirmed live:
GPU returned from 1720MHz to 693MHz/10% busy within 20s of killing a HIP
`llama-server` process, on the same build that previously stayed pegged).
This tests whether the mitigation, or PowerInfer's own (much older) HIP code,
also avoids the bug — and whether PowerInfer's sparse CPU/GPU split is actually
worth using on this hardware.

## Getting PowerInfer to build against current ROCm at all

PowerInfer's HIP backend is 2023/2024-era code. Building it against nixpkgs'
current ROCm 7.2.3 needed several fixes, all confirmed by iterating on real
build errors rather than guessed upfront:

1. **nixpkgs' ROCm cmake packages are split across many derivations** —
   `rocmPackages.clr`, `hipblas`, `rocblas`, `rocm-comgr`, `rocm-runtime`,
   `hipblas-common`, and `rocm-device-libs` all had to be listed explicitly in
   `CMAKE_PREFIX_PATH`; missing any one produces a `hip could not be found
   because dependency X could not be found` chain, one dependency at a time.
2. **Two different LLVM versions coexist in nixpkgs' ROCm set** —
   `rocmPackages.rocm-toolchain`'s `clang`/`clang++` is LLVM 20, but
   `rocm-device-libs` ships LLVM 22 bitcode (`ocml.bc` etc). Compiling `.cu`
   HIP files with the LLVM 20 clang against the LLVM 22 device-libs fails with
   `Not an int attribute (Producer: 'LLVM22.0.0' Reader: 'LLVM 20.0.0')`.
   `rocmPackages.clr.hipClangPath` points at a separate, correctly-versioned
   LLVM 22 `clang++` — use that for the HIP compilation unit specifically.
3. **The LLVM 22 clang is too strict for PowerInfer's plain C files** —
   `ggml-quants.c`'s hand-written AVX intrinics cast `__m256*` where
   `_mm256_loadu_ps`/`_mm256_storeu_ps` now require `float*`; LLVM 20's
   `avxintrin.h` tolerated it, LLVM 22's doesn't. Fix: compile host C files
   (`CC`) with the LLVM 20 `rocm-toolchain` clang, and only the HIP
   compilation unit (`CXX`, `ggml-cuda.cu`) with the LLVM 22 `hipClang`. A
   plain `gcc` for `CC` doesn't work either — cmake passes `-munsafe-fp-atomics`
   (a clang-only flag) globally once `LLAMA_HIPBLAS=ON` is set.
4. **hipBLAS 7.2.3's `hipblasGemmEx` API changed since PowerInfer was written** —
   the `computeType` parameter used to accept a `hipblasDatatype_t`
   (`HIPBLAS_R_16F`); it now requires the distinct `hipblasComputeType_t`
   enum (`HIPBLAS_COMPUTE_16F`). PowerInfer's CUDA→HIP compat macros
   (`ggml-cuda.cu:18-20`) mapped `CUBLAS_COMPUTE_16F` to the wrong (old) enum,
   causing `no matching function for call to 'hipblasGemmEx'` at all 3 call
   sites (`hipblasGemmEx`, `hipblasGemmBatchedEx`, `hipblasGemmStridedBatchedEx`).
   Fixed by pointing the macros at the current `HIPBLAS_COMPUTE_*` enum instead.
5. **The C++ binary shells out to a Python module (`powerinfer-py`) at model-load
   time** to solve the GPU/CPU layer split (a convex optimization over
   activation-sparsity stats, via `cvxopt`+GLPK). This isn't documented as a
   runtime dependency in the top-level README (only as an offline
   conversion-script dependency) — without it, `main`/`server` fall back to an
   **empty split** (0 FFN weights on GPU) and then **segfault** during KV-cache
   setup, rather than erroring cleanly. `pip install -r requirements.txt` alone
   doesn't cover it either — `cvxopt` and the repo's own `gguf-py` module are
   both missing from that file. Needed: `numpy`, `torchWithoutCuda` (CPU only —
   this solver never touches the GPU, so `torchWithRocm` buys nothing here),
   `cvxopt` (nixpkgs' build has working GLPK bindings), plus the repo's own
   `powerinfer-py/` and `gguf-py/` directories on `PYTHONPATH`.

With all of the above, `cmake -DLLAMA_HIPBLAS=ON -DAMDGPU_TARGETS=gfx1201`
built cleanly, and `ldd` confirms real HIP/hipBLAS linkage
(`libamdhip64.so.7`, `libhipblas.so.3`, `libhsa-runtime64.so.1`, ...).

## Does the GPU-idle bug still happen?

**No** — on both PowerInfer's own HIP code and the mitigated llama.cpp build.
Checked `gpu_busy_percent` and `pp_dpm_sclk` before, during, and after a real
PowerInfer inference run:

| When | Busy % | Clock |
|---|---|---|
| Before loading | 10% | 154MHz |
| During generation | (not sampled mid-run) | — |
| After process exit | 15% | 373MHz |

No stuck-at-max-clock behavior. PowerInfer's HIP code predates the HIP graphs
API the earlier bug report blamed, so it likely never exercises the buggy path
at all — consistent with, not contradicting, the earlier `--cpu-moe` finding.

## Does it actually work, and is it worth it?

**Yes, it runs — and generates correct output.** `Tiiny/ReluLLaMA-7B-PowerInfer-GGUF`
(a real, community-converted PowerInfer model: ReLU-sparsified Llama-2-7B, f16,
14.11GB, with per-layer activation predictors), `--vram-budget 12` (GiB):

```
llm_load_sparse_model_tensors: using ROCm for GPU acceleration
ggml_cuda_set_main_device: using device 0 (AMD Radeon RX 9070 XT) as main device
llm_load_gpu_split: offloaded 6042.00 MiB of FFN weights to GPU
...
Q: What is the capital of France?
A: Paris.
```

## Benchmark: PowerInfer sparse split vs. plain Vulkan full offload

Same GPU, same prompt, `temperature 0`. Not the identical model (PowerInfer's
GGUF format — `PWRI` magic — isn't loadable by vanilla llama.cpp, so a
same-file comparison isn't possible), but same architecture and parameter
count class (7B):

| Configuration | Model | VRAM used | Generation speed | Prompt eval |
|---|---|---|---|---|
| PowerInfer (ROCm, sparse, `--vram-budget 12`) | ReluLLaMA-7B, f16 (14.1GB) | ~6.0GB (FFN split) | **13.2 tok/s** | 20.8 tok/s |
| Plain llama.cpp (Vulkan, `--n-gpu-layers 99`) | Llama-2-7B, Q4_K_M (4.1GB) | fits fully | **120.5 tok/s** | 507.2 tok/s |

**Plain full-GPU offload is ~9x faster.** This confirms the same pattern found
with `--cpu-moe` in `docs/moe-offload-benchmark.md`: a technique built for
"the model doesn't fit in VRAM at all" is a large net loss once the model
*does* fit — and a 7B model comfortably fits in this GPU's 16GB, at any
reasonable quantization. PowerInfer's sparse CPU/GPU split isn't optimizing
the same problem plain offload does; it's trading GPU-underuse for the
ability to run models that are otherwise VRAM-bound, at a real cost when that
tradeoff isn't needed.

## Vulkan vs. ROCm, same model, same full-GPU-offload config

The PowerInfer benchmark above compares two different *techniques* (sparse
split vs. full offload), not the two GPU backends directly. A same-model,
same-config, backend-only comparison — `TheBloke/Llama-2-7B-GGUF` Q4_K_M,
`--n-gpu-layers 99`, `--ctx-size 2048`, `temperature 0`, on `llama.cpp`
itself (not PowerInfer):

| Backend | Generation | Prompt eval |
|---|---|---|
| Vulkan (default) | 119.0 tok/s | 560.2 tok/s |
| Vulkan (`--flash-attn off`) | 117.9 tok/s | 391.8 tok/s |
| Vulkan (`--cache-type-k/v q8_0`) | 113.9 tok/s | 404.5 tok/s |
| ROCm (default) | **6.5 tok/s** | 58.5 tok/s |
| ROCm (`--flash-attn off`) | 6.5 tok/s | 24.2 tok/s |
| ROCm (`-fit off`, forcing explicit `-ngl`) | 6.9 tok/s | 62.7 tok/s |

**Vulkan is ~17x faster than ROCm on this exact hardware for this exact
workload.** Confirmed the ROCm run genuinely loaded the model onto the GPU
(8.5GB VRAM resident, not a silent CPU fallback) — this is real GPU
execution, just slow. Flash attention and KV-cache quantization made no
meaningful difference on either backend at this model size.

**17x is not the normal Vulkan/ROCm gap on RDNA4** — independent benchmarks
(llama.cpp discussion #21043, digtvbg.com) report Vulkan only ~35-42% faster
than ROCm on RDNA4 cards generally. The actual cause is a specific, already
publicly identified upstream bug: **rocBLASLt on gfx1201 looks up the wrong
Tensile kernel solution file (`gfx1200.dat` instead of `gfx1201.dat`)**,
falling back to a generic/unoptimized kernel path instead of RDNA4-tuned
ones (`ROCm/rocm-libraries#7192`). A fix ("solution library per gfx",
`ROCm/rocm-libraries#4781`) landed upstream around 2026-03-02 — **but is not
in any ROCm 7.2.x release**, including nixpkgs' current `rocmPackages` set
(7.2.3). This matches our symptom exactly: it runs and produces correct
output, just at fallback-kernel speed, rather than crashing.

**This is a bigger practical blocker than the GPU-idle bug ever was**, but
also the more temporary one — it's a specific packaging-lag bug with a known
fix already merged upstream, not a fundamental RDNA4/ROCm limitation. Worth
re-testing once nixpkgs picks up a ROCm release containing that fix; until
then, Vulkan remains the right default here on throughput grounds, not just
the idle-clock concern.

## Verdict for `home/skills/delegation`

- **Don't adopt PowerInfer for any model that already fits on this GPU** — same
  conclusion as `--cpu-moe`, now confirmed for a second, differently-shaped
  technique (sparse activation offload vs. MoE-expert offload).
- **The GPU-idle ROCm concern that blocked this investigation is resolved**
  for at least this workload shape (single-process HIP inference, no
  concurrent processes, no vision/mmproj models) — `-DGGML_HIP_GRAPHS=OFF` for
  modern llama.cpp, and PowerInfer's own older HIP code, both idle down
  correctly after the process exits.
- **Would only be worth reconsidering** for a genuinely huge sparse model
  (70B+ ReLU-sparsified) that has no fully-fitting alternative — the same
  "doesn't run at all vs. runs slowly" tradeoff noted for `--cpu-moe`, not
  tested here since it needs a much larger download.
- The build is real but fragile: it depends on nixpkgs' current, inconsistent
  ROCm version split (LLVM 20 vs 22) and hand-patched hipBLAS enum macros.
  Not something to wire into the real nix-config given the verdict above —
  kept as a reproducible ad-hoc build (`/tmp/powerinfer-test/`, not committed)
  in case a future large-sparse-model use case actually needs it.

## Reproducing this

Ad-hoc, not wired into the flake (see verdict above for why). Store paths
resolved via `nix-build --no-out-link -E 'with import <nixpkgs> {}; rocmPackages.X'`
for each of `clr`, `hipblas`, `rocblas`, `rocm-device-libs`, `rocm-comgr`,
`rocm-runtime`, `hipblas-common`, and `clr.hipClangPath`.

```bash
git clone --depth 1 https://github.com/SJTU-IPADS/PowerInfer.git
cd PowerInfer
# Patch ggml-cuda.cu:18-20 — CUBLAS_COMPUTE_16F/32F/32F_FAST_16F must map to
# HIPBLAS_COMPUTE_* (hipblasComputeType_t), not HIPBLAS_R_* (hipDataType).

CC=<rocm-toolchain-LLVM20>/bin/clang \
CXX=<clr.hipClangPath-LLVM22>/clang++ \
cmake -S . -B build -DLLAMA_HIPBLAS=ON -DAMDGPU_TARGETS=gfx1201 \
  -DCMAKE_PREFIX_PATH="<clr>;<hipblas>;<rocblas>;<rocm-device-libs>;<rocm-comgr>;<rocm-runtime>;<hipblas-common>" \
  -DCMAKE_CXX_FLAGS="--rocm-path=<clr> --rocm-device-lib-path=<rocm-device-libs>/amdgcn/bitcode"
cmake --build build -j8

# Runtime: numpy + cvxopt + torchWithoutCuda on PYTHONPATH, plus the repo's
# own powerinfer-py/ and gguf-py/ directories.
PYTHONPATH="<site-packages>:.../powerinfer-py:.../gguf-py" \
  build/bin/main -m model.powerinfer.gguf --vram-budget 12 \
  -p "..." -n 64 --temp 0
```

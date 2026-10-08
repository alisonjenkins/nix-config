# Adopting a model in this repo

Only after [benchmarking.md](benchmarking.md) says it is an upgrade.

1. **Pin the GGUF** in `pkgs/llama-models/default.nix` with `mkGgufModel`:
   real URL, real hash. Add a comment with the quant, size, the date, and
   whether the claims are vendor-reported or measured here. Fetch the hash
   with `nix store prefetch-file` rather than copying one.
2. **Pick the engine.** If the model needs a newer llama.cpp than the system
   one, point the profile's runtime at a Vulkan build of
   `pkgs/llama-cpp-upstream` (see [engine-preflight.md](engine-preflight.md)),
   or bump the nixpkgs input. A bump also fixes the tool-call whitespace bug
   for every other profile.
3. **Write the profile** under `modules.delegateToLocal.profiles` in
   `home/machines/<host>`: `model`, `launch_args` including the card's
   sampling and any `--chat-template-file`, and a `description` that says what
   it is good at.
4. **Measure `vram_mib`**: used VRAM with the profile loaded and one request
   served, minus the same reading with nothing loaded
   (`/sys/class/drm/card*/device/mem_info_vram_used`). The fit check's own
   estimate refuses profiles that fit.
5. **Update the scorecard and the picking table** in the delegation skill's
   `delegate-to-local.md` with the measured rows, including losses.
6. **Say what was not tested** (other quants, longer context, thinking
   settings) in the commit message or PR.
7. `git add` new files before building; run `just check`.

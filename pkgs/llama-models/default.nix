{
  lib,
  runCommand,
  fetchurl,
}:

let
  mkGgufModel = { pname, files, primaryFile }:
    let
      srcs = map (f: {
        inherit (f) name;
        src = fetchurl {
          url = f.url;
          hash = f.hash;
          name = f.name;
        };
      }) files;
      drv = runCommand pname {} (
        "mkdir -p $out\n"
        + lib.concatMapStringsSep "\n" ({ name, src }:
          "ln -s ${src} $out/${name}"
        ) srcs
      );
    in
    drv // { modelFile = "${drv}/${primaryFile}"; };
in
{
  # Heavy thinker / orchestrator — Qwen3.5-122B-A10B MoE
  # 122B total, ~10B active, UD-Q5_K_XL ~85.6 GiB, ~22 tok/s on Strix Halo
  # Split into 3 shards on HuggingFace
  #
  qwen3-5-122b-a10b-ud-q5-k-xl = mkGgufModel {
    pname = "qwen3.5-122b-a10b-ud-q5-k-xl";
    primaryFile = "Qwen3.5-122B-A10B-UD-Q5_K_XL-00001-of-00003.gguf";
    files = [
      {
        name = "Qwen3.5-122B-A10B-UD-Q5_K_XL-00001-of-00003.gguf";
        url = "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/UD-Q5_K_XL/Qwen3.5-122B-A10B-UD-Q5_K_XL-00001-of-00003.gguf";
        hash = "sha256-qt31+tYQuNaBtBVH8+mjCYjORBlDjkTgicr7g4Q9xug=";
      }
      {
        name = "Qwen3.5-122B-A10B-UD-Q5_K_XL-00002-of-00003.gguf";
        url = "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/UD-Q5_K_XL/Qwen3.5-122B-A10B-UD-Q5_K_XL-00002-of-00003.gguf";
        hash = "sha256-/I8wCOxjRmfx+TG4U3FU57JbaD5eGpmYflOIYS3FEXw=";
      }
      {
        name = "Qwen3.5-122B-A10B-UD-Q5_K_XL-00003-of-00003.gguf";
        url = "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/UD-Q5_K_XL/Qwen3.5-122B-A10B-UD-Q5_K_XL-00003-of-00003.gguf";
        hash = "sha256-0tMzpHS5QJNtWPgar6ZMSK4ZsHq99ylPXJj1HW+j0T0=";
      }
    ];
  };

  # Workhorse / interactive coding — Qwen3-Coder-Next, 80B total/3B active MoE
  # UD-Q4_K_XL ~46.2 GiB. Supersedes Qwen3-Coder-30B-A3B (kept below as the
  # lighter fallback for hardware that can't fit ~46 GiB): same 3B active
  # params so similar tok/s, but per unsloth/Qwen docs claims quality closer
  # to models with 10-20x the active params. Verified to exist on HF with
  # this exact quant + hash 2026-09-22; the "closer to bigger models" framing
  # is vendor/web-research claims, not independently re-benchmarked here —
  # re-run the docs/local-model-capabilities.md probes before trusting it for
  # judgment-shaped work.
  qwen3-coder-next-ud-q4-k-xl = mkGgufModel {
    pname = "qwen3-coder-next-ud-q4-k-xl";
    primaryFile = "Qwen3-Coder-Next-UD-Q4_K_XL.gguf";
    files = [
      {
        name = "Qwen3-Coder-Next-UD-Q4_K_XL.gguf";
        url = "https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-UD-Q4_K_XL.gguf";
        hash = "sha256-S7k/CgIh70/5Y8qQlN9inI39+rw7T92FwaLkwGJPzjY=";
      }
    ];
  };

  # Lighter workhorse fallback — Qwen3-Coder 30B-A3B MoE
  # 30B total, 3B active, Q4_K_S ~16.3 GiB, ~98 tok/s on Strix Halo. Use this
  # instead of qwen3-coder-next-ud-q4-k-xl on hardware that can't spare
  # ~46 GiB (e.g. the RX 9070 XT's 16 GiB VRAM on ali-desktop).
  qwen3-coder-30b-a3b-q4-k-s = mkGgufModel {
    pname = "qwen3-coder-30b-a3b-q4-k-s";
    primaryFile = "Qwen3-Coder-30B-A3B-Instruct-Q4_K_S.gguf";
    files = [
      {
        name = "Qwen3-Coder-30B-A3B-Instruct-Q4_K_S.gguf";
        url = "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_S.gguf";
        hash = "sha256-VqfQB4NBm8sK5WYlPDcbyzZ4Jhu3mIGlU1OfVnmGTbQ=";
      }
    ];
  };

  # Fast agent / tool calling — Qwen3.6-35B-A3B MoE
  # 35B total, 3B active, UD-Q4_K_XL ~20.8 GiB, ~60 tok/s on Strix Halo
  qwen3-6-35b-a3b-ud-q4-k-xl = mkGgufModel {
    pname = "qwen3.6-35b-a3b-ud-q4-k-xl";
    primaryFile = "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
    files = [
      {
        name = "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
        url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
        hash = "sha256-cHpVqKQ5fs3kTeDEmdPmjBrR0kDR2mWCa0lJ0QQ/RFA=";
      }
    ];
  };

  # Single smart model — Qwen3.6-27B Dense
  # All 27B params active every token, UD-Q5_K_XL ~18.7 GiB. Supersedes
  # Qwen3-32B (this repo's previous pick for this slot): newer (April 2026),
  # smaller, and per web research (SWE-bench Verified 77.2, ties Sonnet 4.6
  # on the AA Agentic Index) — those specific numbers are unverified
  # secondhand claims, not re-run here; treat as "worth trying," not proven,
  # until re-benchmarked the way docs/local-model-capabilities.md did for the
  # 0.5B/3B comparison. Verified to exist on HF with this exact quant + hash
  # 2026-09-22.
  qwen3-6-27b-ud-q5-k-xl = mkGgufModel {
    pname = "qwen3.6-27b-ud-q5-k-xl";
    primaryFile = "Qwen3.6-27B-UD-Q5_K_XL.gguf";
    files = [
      {
        name = "Qwen3.6-27B-UD-Q5_K_XL.gguf";
        url = "https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/Qwen3.6-27B-UD-Q5_K_XL.gguf";
        hash = "sha256-rDEKvyiVqjlxIbrWwL6JRmr0Hw8WBqIcETGxEO6xnQ4=";
      }
    ];
  };

  # Dedicated fast commit-message model — Qwen2.5-Coder-7B-Instruct
  # Code-tuned, ~4.7 GiB Q4_K_M. Plenty for conventional-commit generation
  # and far faster to load/run than the 30B MoE for this bounded task.
  qwen2-5-coder-7b-instruct-q4-k-m = mkGgufModel {
    pname = "qwen2.5-coder-7b-instruct-q4-k-m";
    primaryFile = "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf";
    files = [
      {
        name = "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf";
        url = "https://huggingface.co/unsloth/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf";
        hash = "sha256-mpYbsiXLK5/YSyKX3w1TCJiVwEnX2dxfX4rrvNMkeHI=";
      }
    ];
  };

  # ali-desktop delegate-to-local "fast" tier — Qwen3-8B Dense
  # Q6_K ~6.26 GiB. Sized for the RX 9070 XT's 16 GiB VRAM alongside the
  # "quality" tier below (only one loaded at a time — see
  # home/skills/delegation/delegate-to-local.md), leaving plenty of headroom
  # for context. Verified to exist on HF with this exact quant + hash
  # 2026-09-22.
  qwen3-8b-q6-k = mkGgufModel {
    pname = "qwen3-8b-q6-k";
    primaryFile = "Qwen3-8B-Q6_K.gguf";
    files = [
      {
        name = "Qwen3-8B-Q6_K.gguf";
        url = "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf";
        hash = "sha256-Dq7HGP3qsPQp36DsSBwJA4iBH15jeF3bWCKS9O88OCc=";
      }
    ];
  };

  # ali-desktop delegate-to-local "quality" tier — Qwen3.6-27B Dense
  # UD-Q3_K_XL ~13.5 GiB. The largest Qwen3.6-27B quant that leaves usable
  # headroom (~2.5 GiB) for KV cache/context on a 16 GiB card — Q4_K_S/M
  # (~14.7-15.7 GiB) leaves too little. Verified to exist on HF with this
  # exact quant + hash 2026-09-22.
  qwen3-6-27b-ud-q3-k-xl = mkGgufModel {
    pname = "qwen3.6-27b-ud-q3-k-xl";
    primaryFile = "Qwen3.6-27B-UD-Q3_K_XL.gguf";
    files = [
      {
        name = "Qwen3.6-27B-UD-Q3_K_XL.gguf";
        url = "https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/Qwen3.6-27B-UD-Q3_K_XL.gguf";
        hash = "sha256-z/Si2mtTUKU/V9xveYUW4BlYFvkMGWw/e9P9VVVmMt0=";
      }
    ];
  };

  # Speculative decoding draft model — Qwen3-0.6B
  # Q8_0 ~0.6 GiB. Was picked to share Qwen3-32B's tokenizer for speculative
  # decoding; not currently wired to any configured modules.llama-cpp instance
  # (that module has no --model-draft option — unlike modules/llama-swap/darwin.nix,
  # a different module, which does pass one), and not confirmed
  # tokenizer-compatible with the Qwen3.6-27B dense pick that replaced
  # Qwen3-32B above — re-check before wiring it up.
  qwen3-0-6b-q8-0 = mkGgufModel {
    pname = "qwen3-0.6b-q8-0";
    primaryFile = "Qwen3-0.6B-Q8_0.gguf";
    files = [
      {
        name = "Qwen3-0.6B-Q8_0.gguf";
        url = "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf";
        hash = "sha256-4VDtVE3+YBaTDAJqk5E6XjGEGB6/5qsiI64B3QSReEw=";
      }
    ];
  };
}

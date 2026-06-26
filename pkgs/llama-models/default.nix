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

  # Workhorse / interactive coding — Qwen3-Coder 30B-A3B MoE
  # 30B total, 3B active, Q4_K_S ~16.3 GiB, ~98 tok/s on Strix Halo
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

  # Single smart model — Qwen3-32B Dense
  # All 32B params active every token, Q5_K_M ~21.6 GiB
  # Near GPT-4o on coding/reasoning benchmarks
  qwen3-32b-q5-k-m = mkGgufModel {
    pname = "qwen3-32b-q5-k-m";
    primaryFile = "Qwen3-32B-Q5_K_M.gguf";
    files = [
      {
        name = "Qwen3-32B-Q5_K_M.gguf";
        url = "https://huggingface.co/unsloth/Qwen3-32B-GGUF/resolve/main/Qwen3-32B-Q5_K_M.gguf";
        hash = "sha256-vJa6a8XtfXhUDSyn/mYjTHG4IUgElsasjRLYxAZClEY=";
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
        # TODO: placeholder — resolve on a machine with HF access:
        #   nix store prefetch-file --hash-type sha256 <url>
        # then push the built model to nixcache.org so this host can pull it.
        hash = lib.fakeHash;
      }
    ];
  };

  # Speculative decoding draft model — Qwen3-0.6B
  # Same tokenizer as Qwen3-32B, Q8_0 ~0.6 GiB
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

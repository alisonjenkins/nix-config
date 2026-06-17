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
}

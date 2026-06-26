{ pkgs, ... }:
let
  # git-ai-commit: turn the staged diff into a Conventional Commits message
  # using the local `qwen-commit` model via the aichat `commit-msg` role, then
  # open it in $EDITOR for review/edit/abort. The model only ever sees a
  # read-only diff and emits text — it never runs git, so it cannot mutate or
  # destroy the working tree. The commit always passes through `git commit -e`.
  git-ai-commit = pkgs.writeShellScriptBin "git-ai-commit" ''
    # Refuse to run on an empty stage — the user must stage atomically first
    # (git add -p). This tool generates the message; it does not split changes.
    if ${pkgs.git}/bin/git diff --staged --quiet; then
      echo "git-ai-commit: nothing staged. Stage atomically with 'git add -p' first." >&2
      exit 1
    fi
    msg="$(${pkgs.git}/bin/git diff --staged | ${pkgs.aichat}/bin/aichat -r commit-msg)"
    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    printf '%s\n' "$msg" > "$tmp"
    # -e opens the message in $EDITOR: save commits, an empty buffer aborts.
    ${pkgs.git}/bin/git commit -e -F "$tmp"
    rm -f "$tmp"
  '';
in
{
  home.packages = [ git-ai-commit ];

  # aichat configured to talk to the local llama-swap endpoint
  # (modules.llamaSwap, served at 127.0.0.1:8080). The model names below must
  # match the keys under modules.llamaSwap.models in the host config.
  #
  # Usage in scripts:
  #   aichat "summarise this" < file.txt
  #   aichat -m local:qwen3-32b "harder reasoning task"
  # Or hit the raw OpenAI-compatible endpoint at http://127.0.0.1:8080/v1.
  xdg.configFile."aichat/config.yaml".text = ''
    model: local:qwen3-coder
    save: false
    clients:
      - type: openai-compatible
        name: local
        api_base: http://127.0.0.1:8080/v1
        api_key: sk-no-key-required
        models:
          - name: qwen3-coder
            max_input_tokens: 32768
            supports_function_calling: true
          - name: qwen3-32b
            max_input_tokens: 32768
            supports_function_calling: true
          - name: qwen-commit
            max_input_tokens: 32768
            supports_function_calling: false
  '';

  # Role for git-ai-commit: a strict Conventional Commits generator pinned to
  # the fast local qwen-commit model. Used via: git diff --staged | aichat -r commit-msg
  xdg.configFile."aichat/roles/commit-msg.md".text = ''
    ---
    model: local:qwen-commit
    temperature: 0.2
    ---
    You are a git commit message generator. The input is the output of
    `git diff --staged`. Produce ONE Conventional Commits message describing the
    staged change.

    Rules:
    - Output ONLY the commit message. No code fences, no preamble, no explanation.
    - Subject line: `type(scope): summary`, imperative mood, <= 50 chars.
      type is one of feat, fix, refactor, docs, test, chore, build, ci, perf, style.
    - If the "why" is not obvious from the subject, add a blank line then a body
      wrapped at 72 cols explaining the reasoning. Omit the body for trivial changes.
    - Describe only what is in the diff. Do not invent changes.
  '';
}

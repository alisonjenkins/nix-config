{ lib, fetchFromGitHub, python3Packages }:

let
  token-savior = python3Packages.buildPythonPackage {
    pname = "token-savior";
    version = "4.4.1";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "mibayy";
      repo = "token-savior";
      rev = "ff42ef14cc972dad5470e0ca8101e4501e00600f"; # HEAD = v4.4.1
      hash = "sha256-7qzX4XRPwBjIjBr4Vp1uHI/1ohiVRPHXCpm5aY58Yho=";
    };

    build-system = [ python3Packages.hatchling ];

    # Core deps + the [mcp] extra (needed to run as an MCP server). The
    # benchmark/memory-vector/dev extras are intentionally omitted.
    dependencies = with python3Packages; [
      pyyaml
      tree-sitter
      tree-sitter-grammars.tree-sitter-java
      tree-sitter-grammars.tree-sitter-ruby
      watchfiles
      mcp
    ];

    pythonImportsCheck = [ "token_savior" ];

    # The repo's hooks/ dir lives outside src/, so buildPythonPackage doesn't
    # install it. Ship the two bash-compaction hook scripts we wire into Claude
    # Code declaratively. They are stdlib + lazy `import token_savior` (no
    # subprocess, no hardcoded interpreter), so they just need to be run by an
    # interpreter that can import token_savior — see passthru.pythonEnv.
    postInstall = ''
      mkdir -p $out/share/token-savior/hooks
      cp hooks/bash_rewriter_hook.py hooks/tool_capture_hook.py $out/share/token-savior/hooks/
    '';

    meta = {
      description = "MCP server that cuts token usage via structural code navigation and tool-output compaction";
      homepage = "https://github.com/mibayy/token-savior";
      license = lib.licenses.mit;
      mainProgram = "token-savior";
      platforms = lib.platforms.unix;
    };
  };
in
token-savior.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    # A python3 with token_savior importable — used as the interpreter for the
    # bash_rewriter_hook.py / tool_capture_hook.py hooks, which do
    # `from token_savior... import ...`.
    pythonEnv = python3Packages.python.withPackages (_: [ token-savior ]);
  };
})

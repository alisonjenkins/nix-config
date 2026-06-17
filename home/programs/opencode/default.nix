{ pkgs, lib, ... }:
let
  mandates = import ../shared-mandates.nix;
  inherit (mandates) gitStrategy workStyle;

  cavemanPkg = pkgs.caveman;
  cavememPkg = pkgs.cavemem;
  cavekitPkg = pkgs.cavekit;
  pupPkg = pkgs.pup-claude;

  mkProvider = { baseURL, models }:
    { options = { inherit baseURL; }; inherit models; };

  mkModel = {
    name,
    toolCall ? true,
    reasoning ? true,
    attachment ? true,
    temperature ? true,
    contextLimit,
    outputLimit,
  }: {
    inherit name attachment reasoning temperature;
    tool_call = toolCall;
    limit = { context = contextLimit; output = outputLimit; };
  };

  stripClaudeFrontmatter = file:
    let
      raw = builtins.readFile file;
      lines = lib.splitString "\n" raw;
      inFrontmatter = builtins.head lines == "---";
      body =
        if !inFrontmatter then raw
        else
          let
            rest = builtins.tail lines;
            endIdx = lib.lists.findFirstIndex (l: l == "---") null rest;
          in
            if endIdx == null then raw
            else lib.concatStringsSep "\n" (lib.drop (endIdx + 1) rest);
    in lib.trimWith { start = true; end = false; } body;

  mkOpencodeAgent = { file, description, model ? "local-coder/qwen3-coder-30b", mode ? "subagent", extraBody ? "" }:
    ''
      ---
      description: "${description}"
      mode: ${mode}
      model: ${model}
      ---

      ${stripClaudeFrontmatter file}${lib.optionalString (extraBody != "") "\n${extraBody}"}
    '';

  # Pup agents: strip non-opencode frontmatter fields and remap color names
  allowedAgentKeys = [ "description" "mode" "model" "temperature" "top_p" "steps" "disable" "hidden" "color" "permission" "prompt" "tools" ];
  colorMap = { blue = "info"; red = "error"; green = "success"; yellow = "warning"; orange = "warning"; };
  patchColor = line:
    let
      m = builtins.match "^color: (.+)$" line;
      val = if m != null then builtins.head m else null;
    in
      if m == null then line
      else if colorMap ? ${val} then "color: ${colorMap.${val}}"
      else line;

  getFieldKey = l:
    let m = builtins.match "^([a-zA-Z_][a-zA-Z0-9_-]*):.*" l;
    in if m != null then builtins.head m else null;

  # Convert rejected frontmatter fields into markdown body sections
  formatRejectedLine = line:
    let
      isName = builtins.match "^name:.*" line != null;
      isWhenToUse = builtins.match "^when_to_use:.*" line != null;
      isExamples = builtins.match "^examples:.*" line != null;
      listMatch = builtins.match "^[ \t]+- (.+)$" line;
      contMatch = builtins.match "^[ \t]+(.+)$" line;
    in
      if isName then null
      else if isWhenToUse then "## When to Use"
      else if isExamples then "## Examples"
      else if listMatch != null then "- ${builtins.head listMatch}"
      else if contMatch != null then builtins.head contMatch
      else line;

  patchAgentFile = file:
    let
      raw = builtins.readFile file;
      lines = lib.splitString "\n" raw;
      hasFrontmatter = lines != [] && builtins.head lines == "---";
      rest = if hasFrontmatter then builtins.tail lines else [];
      endIdx = if hasFrontmatter then lib.lists.findFirstIndex (l: l == "---") null rest else null;
      frontmatterLines = if endIdx != null then lib.take endIdx rest else [];
      bodyLines = if endIdx != null then lib.drop (endIdx + 1) rest
                  else if hasFrontmatter then rest else lines;
      filterResult = builtins.foldl' (acc: line:
        let
          key = getFieldKey line;
          isField = key != null;
          isAllowed = isField && builtins.elem key allowedAgentKeys;
          patchedLine = if isAllowed && key == "color" then patchColor line else line;
        in
          if isAllowed then
            { allowed = acc.allowed ++ [ patchedLine ]; rejected = acc.rejected; keep = true; }
          else if isField then
            { inherit (acc) allowed; rejected = acc.rejected ++ [ line ]; keep = false; }
          else if acc.keep then
            { allowed = acc.allowed ++ [ line ]; rejected = acc.rejected; keep = true; }
          else
            { inherit (acc) allowed; rejected = acc.rejected ++ [ line ]; keep = false; }
      ) { allowed = []; rejected = []; keep = true; } frontmatterLines;
      formatted = builtins.filter (l: l != null) (map formatRejectedLine filterResult.rejected);
      spaced = lib.concatMap (l:
        if lib.hasPrefix "## " l then [ "" l "" ] else [ l ]
      ) formatted;
      rejectedBlock = lib.concatStringsSep "\n" spaced;
      extraContext = if formatted != [] then "\n${rejectedBlock}\n" else "";
      body = lib.concatStringsSep "\n" bodyLines;
      fm = lib.concatStringsSep "\n" filterResult.allowed;
    in "---\n${fm}\n---${extraContext}\n${body}";

  pupAgentFiles = lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n)
    (builtins.readDir "${pupPkg}/agents");

  pupAgentConfigs = lib.mapAttrs' (name: _:
    lib.nameValuePair "opencode/agents/pup-${name}" {
      text = patchAgentFile "${pupPkg}/agents/${name}";
    }
  ) pupAgentFiles;

  pupSkillDirs = lib.filterAttrs (n: v: v == "directory" && n != "extensions")
    (builtins.readDir "${pupPkg}/skills");

  pupSkillConfigs = lib.mapAttrs' (name: _:
    lib.nameValuePair "opencode/skills/${name}/SKILL.md" {
      source = "${pupPkg}/skills/${name}/SKILL.md";
    }
  ) pupSkillDirs;

  cavekitSkillDirs = lib.filterAttrs (n: v: v == "directory")
    (builtins.readDir "${cavekitPkg}/skills");

  cavekitSkillConfigs = lib.mapAttrs' (name: _:
    lib.nameValuePair "opencode/skills/ck-${name}/SKILL.md" {
      source = "${cavekitPkg}/skills/${name}/SKILL.md";
    }
  ) cavekitSkillDirs;

  cavekitCommandFiles = lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n)
    (builtins.readDir "${cavekitPkg}/commands");

  cavekitCommandConfigs = lib.mapAttrs' (name: _:
    lib.nameValuePair "opencode/commands/ck-${name}" {
      source = "${cavekitPkg}/commands/${name}";
    }
  ) cavekitCommandFiles;

  cavemanCommandFiles = lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n)
    (builtins.readDir "${cavemanPkg}/opencode-commands");

  cavemanCommandConfigs = lib.mapAttrs' (name: _:
    lib.nameValuePair "opencode/commands/${name}" {
      source = "${cavemanPkg}/opencode-commands/${name}";
    }
  ) cavemanCommandFiles;

  nodeBin = "${pkgs.nodejs}/bin/node";
  cavememCli = "${cavememPkg}/bin/cavemem";

  cavememPluginJS = ''
    // AUTO-GENERATED by nix home-manager. Do not edit by hand.
    // Re-run home-manager switch to refresh.
    import { spawn } from 'node:child_process';

    const NODE = ${builtins.toJSON nodeBin};
    const CLI = ${builtins.toJSON cavememCli};

    const callArgs = new Map();

    function runHook(event, payload) {
      try {
        const child = spawn(NODE, [CLI, 'hook', 'run', event, '--ide', 'opencode'], {
          stdio: ['pipe', 'ignore', 'ignore'],
          detached: true,
        });
        child.on('error', () => {});
        child.stdin.on('error', () => {});
        child.stdin.end(JSON.stringify(payload));
        child.unref();
      } catch (_e) {}
    }

    export const cavemem = async () => ({
      'session.created': async (input) => {
        runHook('session-start', { session_id: input?.sessionID ?? 'unknown', ide: 'opencode' });
      },
      'session.idle': async (input) => {
        runHook('stop', { session_id: input?.sessionID ?? 'unknown', ide: 'opencode' });
      },
      'tool.execute.before': async (input, output) => {
        if (input?.callID) callArgs.set(input.callID, output?.args);
      },
      'tool.execute.after': async (input, output) => {
        const args = input?.callID ? callArgs.get(input.callID) : undefined;
        if (input?.callID) callArgs.delete(input.callID);
        runHook('post-tool-use', {
          session_id: input?.sessionID ?? 'unknown',
          ide: 'opencode',
          tool_name: input?.tool ?? 'unknown',
          tool_input: args ?? null,
          tool_response: output?.output ?? output?.title ?? null,
        });
      },
    });
  '';

in {
  xdg.configFile = {
    # Main opencode config
    "opencode/config.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";

      provider = {
        local-orchestrator = mkProvider {
          baseURL = "http://localhost:8080/v1";
          models.qwen3-5-122b = mkModel {
            name = "Qwen3.5-122B-A10B";
            contextLimit = 49152;
            outputLimit = 16384;
          };
        };
        local-coder = mkProvider {
          baseURL = "http://localhost:8081/v1";
          models.qwen3-coder-30b = mkModel {
            name = "Qwen3-Coder-30B-A3B";
            contextLimit = 49152;
            outputLimit = 16384;
          };
        };
        local-agent = mkProvider {
          baseURL = "http://localhost:8082/v1";
          models.qwen3-6-35b = mkModel {
            name = "Qwen3.6-35B-A3B";
            contextLimit = 24576;
            outputLimit = 8192;
          };
        };
      };

      model = "local-coder/qwen3-coder-30b";
      small_model = "local-agent/qwen3-6-35b";

      instructions = [
        "~/.config/opencode/instructions/git-strategy.md"
        "~/.config/opencode/instructions/work-style.md"
        "~/.config/opencode/instructions/tool-use.md"
      ];

      mcp = {
        context7 = {
          type = "local";
          command = [ "${pkgs.master.context7-mcp}/bin/context7-mcp" ];
        };
        github = {
          type = "local";
          command = [ "bash" "-c" "GITHUB_PERSONAL_ACCESS_TOKEN=$(${pkgs.gh}/bin/gh auth token) exec ${pkgs.master.github-mcp-server}/bin/github-mcp-server stdio" ];
        };
        nixos = {
          type = "local";
          command = [ "${pkgs.master.mcp-nixos}/bin/mcp-nixos" ];
        };
        k8s = {
          type = "local";
          command = [ "${pkgs.master.mcp-k8s-go}/bin/mcp-k8s-go" ];
        };
        terraform = {
          type = "local";
          command = [ "${pkgs.master.terraform-mcp-server}/bin/terraform-mcp-server" "stdio" ];
        };
        playwright = {
          type = "local";
          command = [ "${pkgs.playwright-mcp}/bin/mcp-server-playwright" ];
        };
        cavemem = {
          type = "local";
          command = [ nodeBin cavememCli "mcp" ];
        };
      };

      permission = {
        read = "allow";
        edit = "allow";
        glob = "allow";
        grep = "allow";
        webfetch = "allow";
        bash = "ask";
        task = "allow";
        skill = { "*" = "allow"; };
      };
    };

    # TUI config (notifications)
    "opencode/tui.json".text = builtins.toJSON {
      attention = {
        enabled = true;
        notifications = true;
        sound = true;
        volume = 0.4;
      };
    };

    # Instruction files (mandates)
    "opencode/instructions/git-strategy.md".text = gitStrategy;
    "opencode/instructions/work-style.md".text = workStyle;
    "opencode/instructions/tool-use.md".text = ''
      # Tool Use (system instruction)

      You have access to tools provided by opencode. Always prefer using tools
      over asking the user to run commands. When you need to read files, search
      code, edit files, or run commands, use the appropriate tool.

      When calling tools, provide all required arguments. For bash commands,
      prefer specific commands over interactive ones.

      When multiple independent tool calls would help, make them in parallel
      when the tool supports it.
    '';

    # Custom agents
    "opencode/agents/aws-iam-debugger.md".text = mkOpencodeAgent {
      file = ../claude-code/agents/aws-iam-debugger.md;
      description = "Debug AWS IAM permission errors, access denied messages, or authorization failures";
    };
    "opencode/agents/git-commit-generator.md".text = mkOpencodeAgent {
      file = ../claude-code/agents/git-commit-generator.md;
      description = "Generate atomic git commit messages following conventional commit format";
      extraBody = gitStrategy;
    };
    "opencode/agents/pr-creator.md".text = mkOpencodeAgent {
      file = ../claude-code/agents/pr-creator.md;
      description = "Create GitHub pull requests with rebasing, quality gates, and clear descriptions";
      extraBody = gitStrategy;
    };

    # Caveman opencode plugin
    "opencode/plugins/caveman/plugin.js".source = "${cavemanPkg}/opencode-plugin/plugin.js";
    "opencode/plugins/caveman/package.json".source = "${cavemanPkg}/opencode-plugin/package.json";
    "opencode/plugins/caveman/caveman-config.cjs".source = "${cavemanPkg}/opencode-plugin/caveman-config.cjs";

    # Cavemem opencode plugin
    "opencode/plugins/cavemem.js".text = cavememPluginJS;

    # Process-todo skill
    "opencode/skills/process-todo/SKILL.md".source = ../claude-code/skills/process-todo/SKILL.md;

  }
  // cavemanCommandConfigs
  // cavekitSkillConfigs
  // cavekitCommandConfigs
  // pupAgentConfigs
  // pupSkillConfigs;
}

{ pkgs, inputs, ... }:
let
  anthropicSkills = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "1ed29a03dc852d30fa6ef2ca53a67dc2c2c2c563";
    hash = "sha256-9FGubcwHcGBJcKl02aJ+YsTMiwDOdgU/FHALjARG51c=";
  };

  mandates = import ../shared-mandates.nix;
  inherit (mandates) gitStrategy modelRouting workStyle;

  cavemanPkg = pkgs.caveman;
  cavekitPkg = pkgs.cavekit;
  cavememPkg = pkgs.cavemem;

  # token-savior stats viewers. Both read ~/.local/share/token-savior/*.json,
  # populated by the MCP nav tools (search_codebase/get_function_source/…), not
  # the bash-compaction hooks. Profile-independent, zero per-session token cost.
  tsStatsDashboard = pkgs.writeShellApplication {
    name = "token-savior-stats";
    text = ''
      exec ${pkgs.token-savior}/bin/token-savior-dashboard "$@"
    '';
  };

  # Prints the get_usage_stats ASCII view (sparkline + savings table) without
  # advertising the tool over MCP. Registers $PWD as a project root so
  # _collect_history() reads that project's cumulative stats file.
  tsStatsScript = pkgs.writeText "ts-stats.py" ''
    import os
    from token_savior import server_state as s
    from token_savior.server_handlers import stats
    s._slot_mgr.register_roots([os.environ.get("WORKSPACE_ROOTS", os.getcwd())])
    for block in stats._hm_get_usage_stats({"daily": True}):
        print(block.text)
  '';
  tsStatsCli = pkgs.writeShellApplication {
    name = "ts-stats";
    text = ''
      exec env TOKEN_SAVIOR_PROFILE=optimized WORKSPACE_ROOTS="''${WORKSPACE_ROOTS:-$PWD}" \
        ${pkgs.token-savior.pythonEnv}/bin/python3 ${tsStatsScript} "$@"
    '';
  };

  # Cross-platform sound for the Notification hook (fires when Claude waits
  # for user input). Bypasses the tmux/ghostty bell-propagation chain.
  notifyBell = pkgs.writeShellScript "claude-notify-bell" (
    if pkgs.stdenv.isDarwin then ''
      ${pkgs.coreutils}/bin/nohup /usr/bin/afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 &
    '' else ''
      ${pkgs.coreutils}/bin/nohup ${pkgs.pulseaudio}/bin/paplay \
        ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/bell.oga \
        >/dev/null 2>&1 &
    ''
  );

  # Merge skill directories — cavekit is installed as a plugin (plugin-dir) so it's excluded here.
  # ./skills holds locally-authored global skills (process-todo, ...).
  #
  # Curated subset of anthropics/skills rather than the whole repo: every skill's
  # name+description loads into every agent/subagent, so the unused ones
  # (algorithmic-art, brand-guidelines, canvas-design, theme-factory) are dropped
  # to trim the subagent baseline.
  anthropicSkillNames = [
    # Document / office
    "docx" "pdf" "pptx" "xlsx"
    # Dev / web
    "frontend-design" "web-artifacts-builder" "webapp-testing" "mcp-builder"
    # Authoring / meta
    "doc-coauthoring" "internal-comms" "skill-creator"
    # Misc kept
    "slack-gif-creator"
  ];
  allSkills = pkgs.symlinkJoin {
    name = "claude-code-skills";
    paths =
      (map (n: "${anthropicSkills}/skills/${n}") anthropicSkillNames)
      ++ [
        "${cavemanPkg}/skills"
        ./skills
      ];
  };

  lspmuxPkg = inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.lspmux;
  lspWrappers = inputs.ali-neovim.legacyPackages.${pkgs.stdenv.hostPlatform.system}.lspWrappers;

  # Helper: wrap a binary path with lspmux client
  mux = bin: {
    command = "${lspmuxPkg}/bin/lspmux";
    args = [ "client" "--server-path" bin ];
  };

  # Claude-Code-specific extension-to-language mappings
  extensionMappings = {
    nix        = { ".nix" = "nix"; };
    go         = { ".go" = "go"; ".mod" = "gomod"; };
    python     = { ".py" = "python"; };
    bash       = { ".sh" = "shellscript"; ".bash" = "shellscript"; };
    typescript = { ".ts" = "typescript"; ".tsx" = "typescriptreact";
                   ".js" = "javascript"; ".jsx" = "javascriptreact"; };
    rust       = { ".rs" = "rust"; };
    terraform  = { ".tf" = "terraform"; ".tfvars" = "terraform-vars"; };
    yaml       = { ".yaml" = "yaml"; ".yml" = "yaml"; };
    json       = { ".json" = "json"; ".jsonc" = "jsonc"; };
    lua        = { ".lua" = "lua"; };
    toml       = { ".toml" = "toml"; };
    markdown   = { ".md" = "markdown"; };
    docker     = { ".dockerfile" = "dockerfile"; };
  };

  # ---- MCP gateway (mcp-gateway) ---------------------------------------------
  # A single always-on aggregator MCP server that hosts the heavy / situational
  # downstream servers (github, k8s, terraform, obscura, context7). Those
  # downstreams connect to the GATEWAY, not to Claude Code — so their tool names
  # AND their verbose `instructions` blocks never enter Claude Code's per-session
  # context (the dominant subagent-baseline cost). The model reaches them lazily
  # through the gateway_* meta-tools (gateway_search_tools / gateway_invoke).
  #
  # We do NOT route nixos / cavemem / token-savior through the gateway: nixos is
  # used constantly in this repo, and token-savior must stay first-class so the
  # Pre/PostToolUse hooks' mcp__.* matchers keep firing.
  #
  # mcp-gateway's per-backend `command` is a single shlex-split string with NO
  # `args` list and NO shell — so github + obscura (which need launch-time setup:
  # a gh-keyring token; an obscura storage dir + UK-locale env) are each wrapped
  # in their own store-path launcher script, referenced as an absolute command.
  githubMcpLauncher = pkgs.writeShellScript "github-mcp-launcher" ''
    export GITHUB_PERSONAL_ACCESS_TOKEN="$(${pkgs.gh}/bin/gh auth token)"
    exec ${pkgs.master.github-mcp-server}/bin/github-mcp-server stdio
  '';

  obscuraMcpLauncher = pkgs.writeShellScript "obscura-mcp-launcher" ''
    dir="''${XDG_STATE_HOME:-$HOME/.local/state}/obscura"
    mkdir -p "$dir"
    exec env OBSCURA_TIMEZONE=Europe/London OBSCURA_GEOLOCATION=51.5074,-0.1278 \
      ${pkgs.obscura}/bin/obscura --storage-dir "$dir" \
      mcp --stealth --allow-private-network
  '';

  # YAML config for the gateway. `command` strings are shlex-split (spaces =
  # arg separators), so absolute store paths + plain trailing args are fine;
  # anything needing env/setup goes through a launcher script above.
  mcpGatewayConfig = pkgs.writeText "mcp-gateway.yaml" ''
    meta_mcp:
      enabled: true
      # warm_start is REQUIRED for discovery: without it backends stay stopped
      # with tools_count=0 and gateway_search_tools returns nothing. Warm-start
      # spawns each backend once at session start and caches its tool list, so
      # the model can find downstream tools via gateway_search_tools — while the
      # client still sees only the ~15 gateway_* meta-tools (the token win). This
      # is no worse than the old setup, where each of these ran as a direct
      # per-session MCP server anyway (just with all their tool names in context).
      warm_start: ["github", "k8s", "terraform", "obscura", "context7"]
    backends:
      github:
        description: "GitHub API: issues, pull requests, code search, releases, commits"
        command: "${githubMcpLauncher}"
      k8s:
        description: "Kubernetes: contexts, namespaces, nodes, resources, pod logs and exec"
        command: "${pkgs.master.mcp-k8s-go}/bin/mcp-k8s-go"
      terraform:
        description: "Terraform registry: providers, modules, policies and docs"
        command: "${pkgs.master.terraform-mcp-server}/bin/terraform-mcp-server stdio"
      obscura:
        description: "Headless stealth browser for web scraping, fetches and form automation"
        command: "${obscuraMcpLauncher}"
      context7:
        description: "Up-to-date library / framework / SDK documentation lookup"
        command: "${pkgs.master.context7-mcp}/bin/context7-mcp"
  '';

  # Datadog-scoped Claude: layers the pup-claude plugin (Datadog `pup` CLI + 49
  # agents + skills) onto the default wrapped `claude` only when invoked, keeping
  # pup out of the default session/subagent baseline. Resolves `claude` from the
  # ambient PATH (the home-manager-wrapped binary) so its own --plugin-dir /
  # --mcp-config wrapping is preserved; this just appends another --plugin-dir.
  claudeDd = pkgs.writeShellScriptBin "claude-dd" ''
    exec claude --plugin-dir ${pkgs.pup-claude} "$@"
  '';

  # Map friendly name → binary path from neovim flake's exports.
  # Prefers faster alternatives (pyright, vtsls, tfls) where available.
  serverBinaries = {
    nix        = "${lspWrappers.nixd}/bin/nixd";
    go         = "${lspWrappers.gopls}/bin/gopls";
    python     = "${lspWrappers.pyright}/bin/pyright-langserver";
    bash       = "${lspWrappers.bash-language-server}/bin/bash-language-server";
    typescript = "${lspWrappers.vtsls}/bin/vtsls";
    rust       = "${lspWrappers.rust-analyzer}/bin/rust-analyzer";
    terraform  = "${lspWrappers.tfls}/bin/tfls";
    yaml       = "${lspWrappers.yaml-language-server}/bin/yaml-language-server";
    json       = "${lspWrappers.vscode-json-language-server}/bin/vscode-json-language-server";
    lua        = "${lspWrappers.lua-language-server}/bin/lua-language-server";
    toml       = "${lspWrappers.taplo-lsp}/bin/taplo-lsp";
    markdown   = "${lspWrappers.marksman}/bin/marksman";
    docker     = "${lspWrappers.docker-langserver}/bin/docker-langserver";
  };
in
{
  # token-savior stats viewers on PATH. Not the whole pkgs.token-savior — that
  # would also drop the broken token-savior-bench, the server bin, and the
  # stats-less `ts` onto PATH.
  home.packages = [ tsStatsDashboard tsStatsCli claudeDd ];

  programs.claude-code = {
    enable = true;
    package = pkgs.master.claude-code;

    settings = {
      # Opt out of autoupdate/error-reporting/bug-command. We deliberately do
      # NOT set DISABLE_TELEMETRY (nor the umbrella
      # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC): DISABLE_TELEMETRY also
      # disables Claude Code's feature-flag (GrowthBook) evaluation, which
      # Remote Control requires — setting it silently removes /remote-control
      # from the menu ("Remote Control requires feature-flag evaluation, which
      # is disabled because DISABLE_TELEMETRY is set"). Leaving it unset only
      # re-enables the feature-flag config fetch; OTel usage export stays off
      # (opt-in via CLAUDE_CODE_ENABLE_TELEMETRY, unset). The superpowers
      # brainstorm primeradiant.com logo beacon — the original reason for
      # DISABLE_TELEMETRY — is suppressed independently via its own dedicated
      # SUPERPOWERS_DISABLE_TELEMETRY switch below.
      env = {
        SUPERPOWERS_DISABLE_TELEMETRY = "1";
        DISABLE_AUTOUPDATER = "1";
        DISABLE_ERROR_REPORTING = "1";
        DISABLE_BUG_COMMAND = "1";

        # Token Savior bash-compaction toggles — read by its PreToolUse rewriter
        # and PostToolUse tool-capture hooks (both default OFF without these).
        TS_BASH_COMPACT = "1";
        TS_BASH_REWRITE = "1";
        # Drop _hints/_suggestion blocks from MCP tool results (~30-50 tok/call).
        TS_NO_HINTS = "1";
      };

      alwaysThinkingEnabled = true;

      # Terminal UI renderer: "fullscreen" = flicker-free alt-screen renderer
      # with virtualized scrollback (equivalent to CLAUDE_CODE_NO_FLICKER=1).
      # Equivalent to running `/tui fullscreen`. "default" = classic renderer.
      tui = "fullscreen";

      # Caveman mode badge in the status bar — shows [CAVEMAN], [CAVEMAN:ULTRA], etc.
      statusLine = {
        type = "command";
        command = "bash \"${cavemanPkg}/hooks/caveman-statusline.sh\"";
      };

      permissions = {
        defaultMode = "auto";
        allow = [
          "Read(*)"
          "Edit(*)"
          "Write(*)"
          "WebFetch(*)"
          "WebSearch(*)"
          "mcp__nixos__*"
          "mcp__cavemem__*"
          "mcp__token-savior__*"
          # MCP gateway: auto-allow only the read-only discovery meta-tools.
          # gateway_invoke is deliberately NOT allowed so that actual downstream
          # calls (incl. k8s / terraform mutations, github writes) prompt — the
          # Bash safety hook never covered MCP tools, and routing 5 servers
          # through one gateway would otherwise collapse their per-server gating.
          "mcp__mcp-gateway__gateway_list_servers"
          "mcp__mcp-gateway__gateway_list_tools"
          "mcp__mcp-gateway__gateway_search_tools"
          "Bash(git:*)"
          "Bash(GIT_PAGER=cat git:*)"
          "Bash(GIT_DIFF_OPTS= git:*)"
          "Bash(nix:*)"
          "Bash(nix-build:*)"
          "Bash(nix-shell:*)"
          "Bash(nix-store:*)"
          "Bash(nix-instantiate:*)"
          "Bash(nix-prefetch-url:*)"
          "Bash(nix-collect-garbage:*)"
          "Bash(just:*)"
          "Bash(grep:*)"
          "Bash(find:*)"
          "Bash(ls:*)"
          "Bash(cat:*)"
          "Bash(head:*)"
          "Bash(tail:*)"
          "Bash(wc:*)"
          "Bash(which:*)"
          "Bash(echo:*)"
          "Bash(python3:*)"
          "Bash(jq:*)"
          "Bash(curl:*)"
          "Bash(gh:*)"
          "Bash(systemctl status:*)"
          "Bash(systemctl cat:*)"
          "Bash(systemctl list-units:*)"
          "Bash(systemctl show:*)"
          "Bash(journalctl:*)"
          "Bash(dmesg:*)"
          "Bash(sensors:*)"
          "Bash(fish:*)"
          "Bash(chmod:*)"
          "Bash(mkdir:*)"
          "Bash(cargo:*)"
          "Bash(bash -n:*)"
          "Bash(sops:*)"
          "Bash(kubectl:*)"
          "Bash(k3s:*)"
          "Bash(ssh-keygen:*)"
          "Bash(nix-env:*)"
        ];
        deny = [ ];
      };

      hooks = {
        # Token Savior bash rewriter — rewrites known commands (git status/diff/log,
        # tsc, pytest, npm/yarn/pnpm test, cargo test, gh run watch, gh pr list,
        # docker ps) to compact variants; everything else passes through. Gated
        # internally by TS_BASH_REWRITE (set in settings.env above).
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${pkgs.token-savior.pythonEnv}/bin/python3 ${pkgs.token-savior}/share/token-savior/hooks/bash_rewriter_hook.py";
                timeout = 10;
              }
            ];
          }
        ];

        PermissionRequest = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "agent";
                prompt = builtins.concatStringsSep "\n" [
                  "You are a safety-validation agent protecting a NixOS Linux workstation. A Bash command is about to be executed that doesn't match any pre-approved pattern. Your job is to investigate whether it is safe, and if so, optionally cache the approval."
                  ""
                  "COMMAND BEING EVALUATED:"
                  "$TOOL_INPUT"
                  ""
                  "INVESTIGATION GUIDELINES:"
                  "- FIRST, read the conversation transcript at the path provided in the input JSON (transcript_path field) to understand the calling agent's INTENT — what task is it trying to accomplish and why is it running this command? Understanding intent is critical to making the right safety call."
                  "- If the command references a script file, READ the script to understand what it does"
                  "- If the command uses rm/delete on a path, verify what's at that path"
                  "- If the command involves git push, check which branch is current and whether --force is used"
                  "- If the command pipes output to another command, evaluate the full pipeline"
                  "- For commands with variable expansion or subshells, consider what they might resolve to"
                  ""
                  "DENY (respond 'no') — ONLY for commands that are clearly and unambiguously destructive regardless of intent:"
                  "- Destructively remove files from important system/user paths (/, /home, /etc, /boot, /nix, /usr, ~) — but NOT project-local or temp paths"
                  "- Write to block devices (dd of=/dev/sdX, mkfs, wipefs, shred, fdisk/parted on /dev/)"
                  "- Force-push to main/master, git reset --hard, git clean -f, or git checkout/restore . (discard uncommitted work)"
                  "- Shut down, reboot, halt, or poweroff the system"
                  "- Stop/disable/mask critical services (sshd, NetworkManager, nix-daemon, systemd-*, dbus, tailscaled, udev)"
                  "- Execute piped remote code (curl|bash, wget|sh, eval $(curl ...))"
                  "- Kill PID 1 or critical system processes"
                  "- Write directly to /etc or redirect to block devices"
                  ""
                  "ALLOW (respond 'yes') if the command is safe based on both the command itself AND the calling agent's intent:"
                  "- Normal development workflow (any standard CLI tools)"
                  "- Reading system state (systemctl, journalctl, dmesg, ip, ss, etc.)"
                  "- Cleaning project-local or temp files"
                  "- Building, testing, or evaluating"
                  "- Pushing to git without --force"
                  "- Fetching data without piping to a shell"
                  "- Any read-only or informational command"
                  "- Sending secrets/credentials to remote servers IF the intent is clearly legitimate (deployment, server configuration, sops operations, etc.)"
                  ""
                  "ESCALATE TO USER (respond 'ask') — when you've investigated intent but are still uncertain:"
                  "- The command could be safe or dangerous depending on context you can't fully determine even after reading the transcript"
                  "- Sending secrets/credentials to remote servers where the intent is unclear or suspicious"
                  "- Significant financial cost — provisioning expensive cloud resources (large EC2 like *.metal/*.24xlarge, GPU instances), creating cloud infra without cost controls, or high-volume paid API calls"
                  "- Unfamiliar tools or complex pipelines with hard-to-predict effects"
                  "- Any command where you're not confident after investigation"
                  ""
                  "When escalating, include a brief explanation of: what the command does, what the calling agent's apparent intent is, and why you're still uncertain. Give the user enough context to make an informed decision."
                  ""
                  "CACHING APPROVED COMMANDS:"
                  "If you decide to ALLOW the command, consider whether it is safe to cache a generalized pattern so this command type doesn't trigger the agent again. Be CONSERVATIVE with caching — a cached pattern auto-allows ALL future commands matching it without any safety review."
                  ""
                  "SAFE TO CACHE (add a Bash(command-prefix:*) pattern to .claude/settings.local.json):"
                  "- Read-only/informational commands that are always safe regardless of arguments (e.g., lspci, ip addr, ss, uname, df, free, top, ps, env, printenv, pw-cli, wpctl, iw, iwctl)"
                  "- Development tools that are inherently safe (e.g., cargo build, make, npm run, rustc)"
                  "- Commands already in the base allows that were somehow missed"
                  ""
                  "DO NOT CACHE — approve for this invocation only:"
                  "- Commands involving file deletion (rm, shred, unlink) — safe this time doesn't mean safe every time"
                  "- Commands involving network transfers (scp, rsync, curl with POST/PUT, nc, ssh) — destination matters"
                  "- Commands involving secrets or credentials — context-dependent"
                  "- Cloud provider CLI commands (aws, gcloud, az, terraform) — cost/scope varies per invocation"
                  "- Commands involving system modification (systemctl restart/enable, mount, umount)"
                  "- Package installation or removal commands"
                  "- Any command where different arguments could make it dangerous"
                  ""
                  "To cache: Read .claude/settings.local.json, add the pattern to permissions.allow, write the file back."
                  "To approve without caching: Just respond 'yes' without modifying any files."
                  ""
                  "Respond with ONLY one of: 'yes', 'no', or 'ask' followed by a brief reason if 'no' or 'ask'."
                ];
                timeout = 60;
              }
            ];
          }
        ];

        # Audible bell when Claude waits for user input — works under tmux+ghostty
        # where the terminal bell chain is suppressed.
        Notification = [
          {
            hooks = [
              {
                type = "command";
                command = "${notifyBell}";
                timeout = 5;
              }
            ];
          }
        ];

        # Caveman: auto-loads the full/mode-filtered SKILL.md as hidden system context each session
        # Cavemem: captures session start event for cross-session memory
        SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = "${pkgs.nodejs}/bin/node \"${cavemanPkg}/hooks/caveman-activate.js\"";
                timeout = 5;
                statusMessage = "Loading caveman mode...";
              }
            ];
          }
          {
            hooks = [
              {
                type = "command";
                command = "${cavememPkg}/bin/cavemem hook run session-start";
                timeout = 10;
              }
            ];
          }
        ];

        # Caveman: tracks /caveman commands and natural-language activation phrases
        # Cavemem: records each prompt for memory
        UserPromptSubmit = [
          {
            hooks = [
              {
                type = "command";
                command = "${pkgs.nodejs}/bin/node \"${cavemanPkg}/hooks/caveman-mode-tracker.js\"";
                timeout = 5;
                statusMessage = "Tracking caveman mode...";
              }
            ];
          }
          {
            hooks = [
              {
                type = "command";
                command = "${cavememPkg}/bin/cavemem hook run user-prompt-submit";
                timeout = 10;
              }
            ];
          }
        ];

        # Cavemem: captures tool results for memory
        # Token Savior: captures large tool outputs into its compaction sandbox,
        # replacing them with expandable references (gated by TS_BASH_COMPACT).
        PostToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "${cavememPkg}/bin/cavemem hook run post-tool-use";
                timeout = 10;
              }
            ];
          }
          {
            # Capture large built-in + MCP tool outputs. `mcp__.*` matches every
            # MCP tool regardless of plugin namespacing (this module ships its
            # servers as the `claude-code-home-manager` inline plugin, so live
            # names are `mcp__plugin_claude-code-home-manager_<srv>__<tool>` —
            # bare `mcp__token-savior__*` never matched). The hook no-ops under
            # TS_CAPTURE_THRESHOLD_BYTES (4096), so small outputs pass through.
            matcher = "Bash|WebFetch|Read|Grep|mcp__.*";
            hooks = [
              {
                type = "command";
                command = "${pkgs.token-savior.pythonEnv}/bin/python3 ${pkgs.token-savior}/share/token-savior/hooks/tool_capture_hook.py";
                timeout = 10;
              }
            ];
          }
        ];

        # Audible bell on task completion — Stop fires immediately at end of
        # turn, unlike Notification which only fires after ~60s idle.
        # Cavemem: persists session memory on agent stop
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "${notifyBell}";
                timeout = 5;
              }
            ];
          }
          {
            hooks = [
              {
                type = "command";
                command = "${cavememPkg}/bin/cavemem hook run session-end";
                timeout = 10;
              }
            ];
          }
        ];
      };
    };

    skills = "${allSkills}";

    # cavekit as a plugin so Claude Code loads it with the "ck:" namespace
    # (giving /ck:spec, /ck:build, /ck:check).
    # pup-claude is intentionally NOT global — it ships 49 agents + ~14 skills
    # that would load into every session/subagent. It's layered in on demand via
    # the `claude-dd` wrapper (see let block) only for Datadog work.
    plugins = [ cavekitPkg pkgs.superpowers ];

    # Listed explicitly (not agentsDir) so the shared gitStrategy mandate can
    # be appended to the git-touching agents.
    agents = {
      aws-iam-debugger = ./agents/aws-iam-debugger.md;
      git-commit-generator = builtins.readFile ./agents/git-commit-generator.md + "\n" + gitStrategy;
      pr-creator = builtins.readFile ./agents/pr-creator.md + "\n" + gitStrategy;
    };

    # User-level ~/.claude/CLAUDE.md — concatenated user mandates, applied to
    # every session. Only gitStrategy is also appended to agents; modelRouting
    # and workStyle are context-only.
    context = builtins.concatStringsSep "\n" [ gitStrategy modelRouting workStyle ];

    mcpServers = {
      # Aggregator gateway hosting the heavy / situational servers (github, k8s,
      # terraform, obscura, context7) as lazy downstreams — see mcpGatewayConfig
      # in the let block. Only the gateway_* meta-tools enter Claude Code's
      # context; downstream tool names + instruction blocks do not. The model
      # discovers + calls downstream tools via gateway_search_tools /
      # gateway_invoke. `serve --stdio` makes the gateway itself a stdio server.
      mcp-gateway = {
        command = "${pkgs.master.mcp-gateway}/bin/mcp-gateway";
        args = [ "serve" "--stdio" "--config" "${mcpGatewayConfig}" ];
      };

      # NixOS/Home Manager options and package search — kept direct (first-class;
      # used constantly in this repo).
      nixos = {
        command = "${pkgs.master.mcp-nixos}/bin/mcp-nixos";
      };

      # Cavemem: persistent cross-session memory (search, timeline, get_observations)
      cavemem = {
        command = "${cavememPkg}/bin/cavemem";
        args = [ "mcp" ];
      };

      # Token Savior: structural code navigation + tool-output compaction.
      # Named "token-savior" so the PostToolUse capture matcher's
      # mcp__token-savior__* tool names resolve. Wrapped in bash so
      # WORKSPACE_ROOTS picks up the session's project dir at launch (mirrors
      # the obscura wrapper). "optimized" = 15-tool, ~1.5K-token manifest.
      token-savior = {
        command = "bash";
        args = [
          "-c"
          ''
            exec env WORKSPACE_ROOTS="$PWD" TOKEN_SAVIOR_CLIENT=claude-code TOKEN_SAVIOR_PROFILE=optimized \
              ${pkgs.token-savior}/bin/token-savior
          ''
        ];
      };
    };

    # LSP servers shared with Neovim via lspmux — both editors connect to the
    # same LSP instances through the lspmux daemon
    lspServers = builtins.mapAttrs (name: bin:
      mux bin // { extensionToLanguage = extensionMappings.${name}; }
    ) serverBinaries;
  };
}

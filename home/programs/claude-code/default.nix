{ pkgs, inputs, ... }:
let
  anthropicSkills = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "1ed29a03dc852d30fa6ef2ca53a67dc2c2c2c563";
    hash = "sha256-9FGubcwHcGBJcKl02aJ+YsTMiwDOdgU/FHALjARG51c=";
  };

  cavemanPkg = pkgs.caveman;
  cavekitPkg = pkgs.cavekit;
  cavememPkg = pkgs.cavemem;

  # Merge all skill directories; lndir skips conflicts (first wins — caveman takes precedence over cavekit's copy)
  allSkills = pkgs.symlinkJoin {
    name = "claude-code-skills";
    paths = [
      "${anthropicSkills}/skills"
      "${cavemanPkg}/skills"
      "${cavekitPkg}/skills"
    ];
  };

  lspmuxPkg = inputs.ali-neovim.packages.${pkgs.system}.lspmux;
  lspWrappers = inputs.ali-neovim.legacyPackages.${pkgs.system}.lspWrappers;

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
  programs.claude-code = {
    enable = true;
    # claude-code-bin uses __noChroot which requires sandbox = relaxed.
    # Use claude-code (builds from source) on aarch64 where we build on
    # sandboxed self-hosted runners.
    package =
      if pkgs.stdenv.hostPlatform.isAarch64
      then pkgs.master.claude-code
      else pkgs.master.claude-code-bin;

    settings = {
      alwaysThinkingEnabled = true;

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
          "mcp__playwright__*"
          "mcp__context7__*"
          "mcp__github__*"
          "mcp__nixos__*"
          "mcp__k8s__*"
"mcp__terraform__*"
          "mcp__cavemem__*"
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
        # Trigger claude-sync (defined in modules/claude-sync on NixOS hosts
        # where it's enabled) at session boundaries. Commands no-op silently on
        # hosts without the service (macOS, unsynced Linux machines).
        SessionStart = [
          {
            hooks = [
              {
                type = "command";
                # Wait up to ~30s for sync to complete so the session has
                # fresh memory/transcripts. If sync takes longer, hook timeout
                # triggers and the session proceeds with current local state.
                command = "systemctl --user start --wait claude-sync.service 2>/dev/null || true";
                timeout = 30;
              }
            ];
          }
        ];

        Stop = [
          {
            hooks = [
              {
                type = "command";
                # Fire-and-forget: don't block the user after a session ends.
                # The timer and pre-suspend hook will catch any missed flush.
                command = "systemctl --user start --no-block claude-sync.service 2>/dev/null || true";
                timeout = 5;
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
        ];

        # Cavemem: persists session memory on agent stop
        Stop = [
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

    agentsDir = ./agents;

    mcpServers = {
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
      };

      # Up-to-date library documentation
      context7 = {
        command = "${pkgs.master.context7-mcp}/bin/context7-mcp";
      };

      # GitHub API integration (issues, PRs, code search)
      # Wraps with gh auth token to pull the token from gh's keyring
      github = {
        command = "bash";
        args = [ "-c" "GITHUB_PERSONAL_ACCESS_TOKEN=$(${pkgs.gh}/bin/gh auth token) exec ${pkgs.master.github-mcp-server}/bin/github-mcp-server stdio" ];
      };

      # NixOS/Home Manager options and package search
      nixos = {
        command = "${pkgs.master.mcp-nixos}/bin/mcp-nixos";
      };

      # Kubernetes cluster interaction
      k8s = {
        command = "${pkgs.master.mcp-k8s-go}/bin/mcp-k8s-go";
      };

      # Terraform registry and provider documentation
      terraform = {
        command = "${pkgs.master.terraform-mcp-server}/bin/terraform-mcp-server";
        args = [ "stdio" ];
      };

      # Cavemem: persistent cross-session memory (search, timeline, get_observations)
      cavemem = {
        command = "${cavememPkg}/bin/cavemem";
        args = [ "mcp" ];
      };
    };

    # LSP servers shared with Neovim via lspmux — both editors connect to the
    # same LSP instances through the lspmux daemon
    lspServers = builtins.mapAttrs (name: bin:
      mux bin // { extensionToLanguage = extensionMappings.${name}; }
    ) serverBinaries;
  };
}

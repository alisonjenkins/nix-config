{ pkgs, ... }:
let
  anthropicSkills = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "1ed29a03dc852d30fa6ef2ca53a67dc2c2c2c563";
    hash = "sha256-9FGubcwHcGBJcKl02aJ+YsTMiwDOdgU/FHALjARG51c=";
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

      permissions = {
        allow = [
          "Read(*)"
          "Edit(*)"
          "Write(*)"
          "WebFetch(*)"
          "WebSearch(*)"
          "mcp__playwright__*"
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
        ];
        deny = [ ];
      };

      hooks = {
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
      };
    };

    skillsDir = "${anthropicSkills}/skills";

    agentsDir = ./agents;

    mcpServers = {
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
      };
    };
  };
}

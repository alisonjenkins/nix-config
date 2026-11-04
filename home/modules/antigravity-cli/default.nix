{ config, lib, pkgs, ... }:
let
  cfg = config.modules.antigravityCli;
  mandates = import ../../programs/shared-mandates.nix;

  # Where programs/agent-skills links every shared skill.
  skillsDir = "${config.home.homeDirectory}/.agents/skills";
  settingsFile = "${config.home.homeDirectory}/.gemini/antigravity-cli/settings.json";

  # Skills are symlinks into the Nix store, and agy reads outside its
  # workspace only with a rule: headless runs deny the read, and an
  # interactive session would ask on every skill.
  allowRules = [
    "read_file(${skillsDir})"
    "read_file(/nix/store)"
  ];

  # Headless agy runs a command only if each segment matches an allow prefix,
  # and deny beats allow. The allow list is what a worker needs inside a
  # worktree to build, test, search and commit; the deny list is the guardrail
  # on pushing, publishing, the cluster, secrets and system state. The rules are
  # shared by every profile, read included, so no shell command that rewrites or
  # deletes files is allowed (rm, mv, cp, sed -i, git clean, git reset --hard):
  # file changes go through agy's edit tools, which only accept-edits approves,
  # and `git rm` keeps a deletion recoverable from history. Interpreters
  # on the allow list (python3, node, npx) could still do anything — the deny
  # list stops direct calls, not a determined script, so delegated runs still go
  # in a worktree and their diff gets reviewed.
  commandAllow = [
    "git"
    "gh pr view"
    "gh pr list"
    "gh pr diff"
    "gh pr checks"
    "gh issue view"
    "gh issue list"
    "gh run view"
    "gh run list"
    "gh repo view"
    "cargo"
    "rustc"
    "rustfmt"
    "nix build"
    "nix flake check"
    "nix flake show"
    "nix flake metadata"
    "nix eval"
    "nix fmt"
    "nix log"
    "nix path-info"
    "nix why-depends"
    "nix-instantiate"
    "dx"
    "npm"
    "npx"
    "pnpm"
    "node"
    "python3"
    "pytest"
    "uv"
    "ruff"
    "go"
    "bats"
    "just"
    "make"
    "shellcheck"
    "statix"
    "deadnix"
    "nixfmt"
    "alejandra"
    "treefmt"
    "prettier"
    "eslint"
    "tsc"
    "vitest"
    "rg"
    "fd"
    "grep"
    "find"
    "ls"
    "cat"
    "head"
    "tail"
    "wc"
    "sed"
    "awk"
    "jq"
    "diff"
    "sort"
    "uniq"
    "cut"
    "tr"
    "echo"
    "printf"
    "pwd"
    "tree"
    "file"
    "stat"
    "realpath"
    "dirname"
    "basename"
    "date"
    "which"
    "true"
    "test"
  ];

  commandDeny = [
    "git push"
    "git remote"
    "git config --global"
    "git credential"
    "git filter-branch"
    "git gc --prune"
    "git update-ref -d"
    "gh pr merge"
    "gh pr create"
    "gh pr edit"
    "gh pr comment"
    "gh pr review"
    "gh pr close"
    "gh pr ready"
    "gh issue create"
    "gh issue comment"
    "gh issue close"
    "gh issue edit"
    "gh api"
    "gh auth"
    "gh secret"
    "gh variable"
    "gh release"
    "gh workflow"
    "gh run rerun"
    "gh run cancel"
    "gh repo create"
    "gh repo delete"
    "gh repo edit"
    "gh repo fork"
    "cargo publish"
    "cargo login"
    "cargo owner"
    "cargo yank"
    "npm publish"
    "npm login"
    "pnpm publish"
    "kubectl"
    "helm"
    "flux"
    "talosctl"
    "k9s"
    "aws"
    "gcloud"
    "az"
    "terraform"
    "tofu"
    "sops"
    "age"
    "gpg"
    "pass"
    "op"
    "ssh"
    "scp"
    "rsync"
    "curl"
    "wget"
    "nc"
    "sudo"
    "doas"
    "su"
    "nixos-rebuild"
    "home-manager"
    "deploy"
    "nix copy"
    "nix profile"
    "nix store delete"
    "nix-collect-garbage"
    "nix-env"
    "systemctl"
    "journalctl --vacuum"
    "docker push"
    "podman push"
    "sed -i"
    "git clean"
    "git reset --hard"
    "git checkout --"
    "git restore"
    "git stash drop"
    "git stash clear"
    "git branch -D"
    "git worktree remove"
    "rm -rf /"
    "rm -rf ~"
    "rm -rf $HOME"
  ];

  allAllowRules = allowRules ++ map (c: "command(${c})") commandAllow;
  allDenyRules = map (c: "command(${c})") commandDeny;
in
{
  options.modules.antigravityCli = {
    enable = lib.mkEnableOption "your shared skills and mandates for Google's Antigravity CLI (agy)";
  };

  config = lib.mkIf cfg.enable {
    # agy does not scan ~/.agents/skills; a global skills.json declares it. The
    # path must be absolute: a ~/ path is silently ignored (agy 1.2.9, 1.2.16).
    home.file.".gemini/config/skills.json".text = builtins.toJSON {
      entries = [ { path = skillsDir; } ];
    };

    # Always-active global rules. Claude's Model Routing is left out, as it names
    # Claude's own cheaper models; agy gets its own, in model-routing.md.
    home.file.".gemini/config/AGENTS.md".text =
      mandates.gitStrategy + "\n" + mandates.workStyle + "\n" + builtins.readFile ./model-routing.md;

    # The subagent that routing sends work to, pinned to the Flash tier. Every
    # entry under `tools` must be a registered tool: an unknown name (command_status
    # was one) stops the agent from starting.
    home.file.".gemini/config/agents/flash-worker.md".source = ./flash-worker.md;

    # Routing text alone is advice: with it loaded, the main agent still did a
    # multi-file edit itself. This main agent has no edit or command tools, so it
    # has to hand those to flash-worker. Opt in with `agy --agent orchestrator`
    # or the /agents panel.
    home.file.".gemini/config/agents/orchestrator.md".source = ./orchestrator.md;

    # agy rewrites settings.json itself (trusted workspaces, colour scheme), so
    # the rules are merged in rather than the file being replaced.
    home.activation.antigravityCliPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings=${lib.escapeShellArg settingsFile}
      run mkdir -p "$(dirname "$settings")"
      if [ -s "$settings" ]; then
        base="$settings"
      else
        base="$(mktemp)"
        echo '{}' > "$base"
      fi
      merged="$(mktemp)"
      if ${pkgs.jq}/bin/jq \
          --argjson allow ${lib.escapeShellArg (builtins.toJSON allAllowRules)} \
          --argjson deny ${lib.escapeShellArg (builtins.toJSON allDenyRules)} \
          '.permissions.allow = ((.permissions.allow // []) + $allow | unique) | .permissions.deny = ((.permissions.deny // []) + $deny | unique)' \
          "$base" > "$merged"; then
        run mv "$merged" "$settings"
      else
        echo "warning: $settings is not valid JSON; permission rules stay unapplied until it is fixed" >&2
        rm -f "$merged"
      fi
      [ "$base" = "$settings" ] || rm -f "$base"
    '';
  };
}

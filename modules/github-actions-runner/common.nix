{ config, lib, pkgs, ... }:
let
  cfg = config.modules.githubActionsRunner;
in
{
  options.modules.githubActionsRunner = {
    enable = lib.mkEnableOption "on-demand scale-to-zero GitHub Actions runner";

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing a fine-grained GitHub PAT (no trailing
        newline). The poller uses it to list queued runs and to mint
        short-lived runner registration tokens on demand. Typically wired to
        `config.sops.secrets.github-runner-token.path`. See ./README.md for the
        exact PAT permissions required.
      '';
    };

    repos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alisonjenkins/nix-config" ];
      description = "Per-repo targets in owner/repo form to poll and register against.";
    };

    orgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Org targets. The poller enumerates each org's repositories (cached for
        `repoListCacheMinutes`) and polls each for queued jobs; the spawned
        runner registers org-wide via the org registration token. Keep small —
        polling cost scales with the number of repos in the org.
      '';
    };

    pollInterval = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "launchd StartInterval (seconds) between poller ticks. 30-60 recommended.";
    };

    repoListCacheMinutes = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "How long to cache the enumerated org repo list before refreshing.";
    };

    runnerNamePrefix = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Prefix for the ephemeral runner name (a unique suffix is appended each spawn).";
    };

    extraLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "macos" "aarch64" "nix" ];
      description = "Labels applied to the runner (in addition to the implicit self-hosted label).";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages put on PATH for runner jobs (in addition to nix, git, coreutils).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      defaultText = lib.literalExpression "config.system.primaryUser";
      description = "User that owns runnerDir and that the poller and jobs run as.";
    };

    runnerDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/github-actions-runner";
      description = ''
        Writable runtime/work dir, used as RUNNER_ROOT. Holds .runner,
        .credentials, _work and _diag. The github-runner package itself stays
        immutable in the nix store; only mutable state lives here.
      '';
    };

    spawnTimeoutMinutes = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = ''
        Watchdog: if a spawned ephemeral runner does not pick up a job and exit
        within this many minutes (e.g. a false-positive queued detection), it is
        killed and de-registered so we return to ~0MB idle.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.github-runner;
      defaultText = lib.literalExpression "pkgs.github-runner";
      description = "The github-runner package (official actions/runner).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.repos != [ ] || cfg.orgs != [ ];
      message = "modules.githubActionsRunner: set at least one of `repos` or `orgs`.";
    }];
  };
}

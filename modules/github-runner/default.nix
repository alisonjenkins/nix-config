# GitHub Actions self-hosted runner module for ephemeral EC2 instances.
# Designed for use with github-aws-runners/terraform-aws-github-runner:
# - Scale-up Lambda stores JIT config in SSM and launches an EC2 instance
# - This module's boot service reads SSM, configures the runner, runs one job
# - After the job completes, the instance self-terminates
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.github-runner;

  # Script that runs on boot to configure and start the GitHub Actions runner.
  # The terraform module passes the runner config via instance tags or SSM.
  startRunnerScript = pkgs.writeShellScript "start-runner.sh" ''
    set -euo pipefail

    RUNNER_DIR="/var/lib/github-runner"
    mkdir -p "$RUNNER_DIR"
    cd "$RUNNER_DIR"

    # Get instance metadata
    TOKEN=$(${pkgs.curl}/bin/curl -sX PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
    INSTANCE_ID=$(${pkgs.curl}/bin/curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(${pkgs.curl}/bin/curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/placement/region)

    # Read runner JIT config from SSM (placed there by the scale-up Lambda)
    JIT_CONFIG=$(${pkgs.awscli2}/bin/aws ssm get-parameter \
      --name "/gha-runners/jit-config/$INSTANCE_ID" \
      --with-decryption \
      --query "Parameter.Value" \
      --output text \
      --region "$REGION" 2>/dev/null || true)

    if [ -z "$JIT_CONFIG" ]; then
      echo "No JIT config found in SSM, checking user-data..."
      # Fallback: read from user-data
      JIT_CONFIG=$(${pkgs.curl}/bin/curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/user-data | ${pkgs.jq}/bin/jq -r '.jit_config // empty' 2>/dev/null || true)
    fi

    if [ -z "$JIT_CONFIG" ]; then
      echo "ERROR: No runner JIT config found. Terminating."
      ${pkgs.awscli2}/bin/aws ec2 terminate-instances \
        --instance-ids "$INSTANCE_ID" --region "$REGION"
      exit 1
    fi

    # Delete JIT config from SSM (one-time use)
    ${pkgs.awscli2}/bin/aws ssm delete-parameter \
      --name "/gha-runners/jit-config/$INSTANCE_ID" \
      --region "$REGION" 2>/dev/null || true

    # Extract runner tarball (pre-installed in AMI)
    if [ ! -f "$RUNNER_DIR/config.sh" ]; then
      tar xzf ${cfg.runnerPackage}/actions-runner.tar.gz -C "$RUNNER_DIR"
    fi

    # Configure runner with JIT config (ephemeral, one job only)
    echo "Configuring runner with JIT config..."
    ./run.sh --jitconfig "$JIT_CONFIG" &
    RUNNER_PID=$!

    # Wait for the runner to finish (it exits after one job in ephemeral mode)
    wait $RUNNER_PID || true

    echo "Runner job completed. Terminating instance..."
    ${pkgs.awscli2}/bin/aws ec2 terminate-instances \
      --instance-ids "$INSTANCE_ID" --region "$REGION"
  '';
in
{
  options.modules.github-runner = {
    enable = lib.mkEnableOption "GitHub Actions self-hosted runner";

    runnerPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.github-runner;
      description = "The GitHub Actions runner package";
    };

    extraSubstituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional Nix substituters to configure";
    };

    extraTrustedPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional trusted public keys for substituters";
    };

    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Root EBS volume size in GiB (should be large enough for Nix store)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Runner boot service
    systemd.services.github-runner = {
      description = "GitHub Actions Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "cloud-init.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = startRunnerScript;
        User = "runner";
        Group = "runner";
        WorkingDirectory = "/var/lib/github-runner";
        Restart = "no";

        # Security hardening
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/github-runner"
          "/nix/store"
          "/nix/var"
          "/tmp"
        ];
        PrivateTmp = true;
      };
    };

    # Runner user
    users.users.runner = {
      isNormalUser = true;
      home = "/var/lib/github-runner";
      group = "runner";
      extraGroups = [ "docker" "nix-users" ];
    };
    users.groups.runner = {};

    # Nix configuration optimised for CI builds
    nix = {
      extraOptions = "experimental-features = nix-command flakes";

      settings = {
        auto-optimise-store = true;
        trusted-users = [ "root" "runner" "@wheel" ];
        max-jobs = "auto";
        cores = 0;
        http-connections = 128;
        max-substitution-jobs = 128;

        substituters = [
          "https://cache.nixos.org"
          "https://cache.nixcache.org"
          "https://nix-community.cachix.org"
        ] ++ cfg.extraSubstituters;

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ] ++ cfg.extraTrustedPublicKeys;
      };

      # Disable GC on ephemeral builders — instance is destroyed after use
      gc.automatic = false;
    };

    # Pre-install useful packages for CI
    environment.systemPackages = with pkgs; [
      curl
      git
      git-lfs
      jq
      niks3
    ];

    # Enable git-lfs globally
    programs.git = {
      enable = true;
      lfs.enable = true;
    };
  };
}

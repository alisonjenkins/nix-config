# Registers the aarch64-darwin Mac mini (home-macos-builder-1) as a remote
# Nix build machine, so any NixOS host can offload aarch64-darwin derivations
# to it. Enabled fleet-wide via modules/base (see base default.nix).
#
# SCAFFOLD — not yet active. Fill in the PLACEHOLDER values once the mini is
# racked and reachable, then flip modules.darwinRemoteBuilder.enable = true.
#
# Direction of trust: this host's nix-daemon (root) SSHes INTO the mini as the
# build user. So:
#   * root on this host holds a private key at `sshKey` (default
#     /root/.ssh/id_remote_builder).
#   * the mini authorizes the matching PUBLIC key on its build user
#     (users.users.<buildUser>.openssh.authorizedKeys).
#   * `publicHostKey` is the mini's SSH HOST key (base64), so the daemon can
#     verify it without an interactive known_hosts prompt.
{ config, lib, ... }:
let
  cfg = config.modules.darwinRemoteBuilder;
in
{
  options.modules.darwinRemoteBuilder = {
    enable = lib.mkEnableOption "offloading aarch64-darwin builds to home-macos-builder-1";

    hostName = lib.mkOption {
      type = lib.types.str;
      # PLACEHOLDER — set to the mini's Tailscale IPv4 (stable per-host on the
      # tailnet). Framework-laptop pins Tailscale IPs rather than MagicDNS
      # names because the daemon's SSH client can't fall back when MagicDNS
      # flakes; follow that convention here.
      default = "PLACEHOLDER_MINI_TAILSCALE_IP";
      description = "Hostname or Tailscale IP of the aarch64-darwin builder.";
    };

    sshUser = lib.mkOption {
      type = lib.types.str;
      default = "ali";
      description = "Build user on the mini that accepts incoming Nix builds.";
    };

    sshKey = lib.mkOption {
      type = lib.types.str;
      default = "/root/.ssh/id_remote_builder";
      description = "Private key root's nix-daemon uses to reach the mini.";
    };

    publicHostKey = lib.mkOption {
      type = lib.types.str;
      # PLACEHOLDER — base64 of the mini's /etc/ssh/ssh_host_ed25519_key.pub
      # contents, e.g. `awk '{print $1" "$2}' key.pub | base64 -w0`.
      default = "PLACEHOLDER_MINI_HOST_KEY_BASE64";
      description = "Base64-encoded SSH host public key of the mini.";
    };

    maxJobs = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Max parallel jobs to dispatch (M4 has 4P+6E cores).";
    };

    speedFactor = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Relative speed; higher → Nix prefers this builder.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.distributedBuilds = true;
    nix.settings.builders-use-substitutes = true;
    nix.buildMachines = [
      {
        inherit (cfg) hostName sshUser sshKey publicHostKey maxJobs speedFactor;
        systems = [ "aarch64-darwin" ];
        protocol = "ssh-ng";
        supportedFeatures = [ "big-parallel" "benchmark" ];
      }
    ];
  };
}

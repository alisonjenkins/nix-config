{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
  niks3Hook = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3-hook;
  hookBin = lib.getExe' niks3Hook "niks3-hook";

  idleStr = if cfg.idleExitTimeout == 0 then "0" else "${toString cfg.idleExitTimeout}s";

  # Nix post-build-hook must be a single executable; wrap `niks3-hook send`,
  # which reads $OUT_PATHS, writes them to the daemon socket, and always
  # exits 0 so a queue failure never fails a build.
  postBuildHook = pkgs.writeShellScript "niks3-post-build-hook" ''
    exec ${hookBin} send --socket ${lib.escapeShellArg cfg.socketPath} "$@"
  '';

  # launchd has no socket activation and no RuntimeDirectory, and the socket
  # lives under /run -> /var/run which macOS wipes on reboot. So the daemon
  # must (re)create its socket directory on every start, before binding.
  serveScript = pkgs.writeShellScript "niks3-hook-serve" ''
    mkdir -p "$(dirname ${lib.escapeShellArg cfg.socketPath})" /var/lib/niks3-hook
    exec ${hookBin} serve \
      --server-url ${lib.escapeShellArg cfg.serverUrl} \
      --auth-token-path ${lib.escapeShellArg (toString cfg.authTokenFile)} \
      --socket ${lib.escapeShellArg cfg.socketPath} \
      --batch-size ${toString cfg.batchSize} \
      --idle-exit-timeout ${idleStr} \
      --max-concurrent-uploads ${toString cfg.maxConcurrentUploads} \
      --db-path /var/lib/niks3-hook/upload-queue.db \
      ${lib.optionalString cfg.verifyS3Integrity "--verify-s3-integrity"} \
      ${lib.optionalString cfg.debug "--debug"}
  '';
in
{
  # Upstream only ships a systemd unit for the upload daemon, so on darwin we
  # hand-roll the equivalent launchd daemon. The option interface stays the
  # shared `modules.niks3CachePush` (see common.nix).
  imports = [ ./common.nix ];

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = "${postBuildHook}";

    launchd.daemons.niks3-auto-upload.serviceConfig = {
      Label = "org.nixos.niks3-auto-upload";
      ProgramArguments = [ "${serveScript}" ];
      # Resident: launchd has no socket activation, so the daemon owns the
      # listening socket and must stay up (idleExitTimeout = 0). KeepAlive
      # restarts it on crash.
      KeepAlive = true;
      RunAtLoad = true;
      # launchd does not inherit a login PATH; niks3-hook serve shells out to
      # `nix` (path-info), so it must be discoverable.
      EnvironmentVariables = {
        PATH = "${config.nix.package}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StandardOutPath = "/var/log/niks3-auto-upload.log";
      StandardErrorPath = "/var/log/niks3-auto-upload.log";
    };
  };
}

{ config, pkgs, ... }:

let
  nix = config.nix.package;
  registrationFile = "/nix-path-registration";
  systemProfile = "/nix/var/nix/profiles/system";

  # The file is removed last so a failed run retries on the next boot; both
  # steps are safe to repeat.
  script = pkgs.writeShellScript "nix-path-registration" ''
    set -euo pipefail
    ${nix}/bin/nix-store --load-db < ${registrationFile}
    if [ ! -e ${systemProfile} ]; then
      ${nix}/bin/nix-env -p ${systemProfile} --set "$(${pkgs.coreutils}/bin/readlink -f /run/booted-system)"
    fi
    ${pkgs.coreutils}/bin/rm -f ${registrationFile}
  '';
in
{
  # Images ship a populated /nix/store but an empty Nix database; load the
  # registration baked into the image so in-place deploys see valid paths.
  systemd.services.nix-path-registration = {
    description = "Register the image's store paths in the Nix database";
    wantedBy = [ "sysinit.target" ];
    before = [
      "nix-daemon.socket"
      "nix-daemon.service"
      "sysinit.target"
    ];
    unitConfig = {
      ConditionPathExists = registrationFile;
      RequiresMountsFor = "/nix/store";
      DefaultDependencies = false;
    };
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = script;
    };
  };
}

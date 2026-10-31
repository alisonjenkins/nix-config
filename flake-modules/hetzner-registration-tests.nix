# Fast eval-time guard for first-boot Nix DB registration of Hetzner images.
#   nix build .#checks.x86_64-linux.hetzner-registration
#
# The image ships a populated /nix/store but an empty Nix database, so an
# in-place deploy (nix-env --set, nix copy) fails or overwrites live files.
# lib/hetzner-store-registration.nix loads the registration shipped in the image.
{ self, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.hetzner-registration =
        let
          node = self.nixosConfigurations.hetzner-karpenter-node-amd64.extendModules {
            modules = [ (self + "/lib/hetzner-store-registration.nix") ];
          };
          svc = node.config.systemd.services.nix-path-registration or null;
          has = x: xs: builtins.elem x xs;
          expectations = {
            "the nix-path-registration service exists" = svc != null;
            "it only runs while /nix-path-registration exists" =
              svc != null && (svc.unitConfig.ConditionPathExists or null) == "/nix-path-registration";
            "it runs before nix-daemon.service" =
              svc != null && has "nix-daemon.service" svc.before;
            "it runs before nix-daemon.socket" =
              svc != null && has "nix-daemon.socket" svc.before;
            "it is pulled in at boot" =
              svc != null && (has "sysinit.target" svc.wantedBy || has "multi-user.target" svc.wantedBy);
          };
          failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) expectations);
        in
        pkgs.runCommand "hetzner-registration-test" { } (
          if failed == [ ] then
            "touch $out"
          else
            ''
              printf 'FAIL: %s\n' ${lib.escapeShellArgs failed}
              exit 1
            ''
        );
    };
}

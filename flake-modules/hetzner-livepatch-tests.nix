# Fast eval-time guard for live kernel patching on the Hetzner node.
#   nix build .#checks.x86_64-linux.hetzner-livepatch
#
# The stock NixOS kernel has CONFIG_LIVEPATCH off, so a kernel CVE fix can only land with
# a reboot. The node's kernel is built with it on so a patch module can be loaded live.
{ self, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.hetzner-livepatch =
        let
          kernel = self.nixosConfigurations.hetzner-karpenter-node-amd64.config.boot.kernelPackages.kernel;
          sc = kernel.configfile.structuredConfig;
          builtIn = name: (sc.${name} or { }).tristate or null == "y";
          expectations = {
            "CONFIG_LIVEPATCH is built in so a patch module can be loaded live" = builtIn "LIVEPATCH";
          };
          failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) expectations);
        in
        pkgs.runCommand "hetzner-livepatch-test" { } (
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

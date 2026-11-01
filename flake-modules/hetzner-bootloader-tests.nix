# Fast eval-time guard for the Hetzner node's in-place upgrade boot path.
#   nix build .#checks.x86_64-linux.hetzner-bootloader
#
# The image boots a static UKI that names one fixed generation, so a reboot never
# applies an in-place deploy. NixOS must own the ESP (systemd-boot) for
# `deploy --boot` to take effect; this asserts that configuration.
{ self, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.hetzner-bootloader =
        let
          cfg = self.nixosConfigurations.hetzner-karpenter-node-amd64.config.boot.loader;
          expectations = {
            "systemd-boot is enabled so a reboot applies the deployed generation" =
              cfg.systemd-boot.enable;
            "generations are capped so the 256 MB ESP cannot fill" =
              cfg.systemd-boot.configurationLimit != null && cfg.systemd-boot.configurationLimit <= 3;
            "EFI variables are left alone (the Hetzner ESP boots the fallback path)" =
              !cfg.efi.canTouchEfiVariables;
            "the boot menu editor is disabled" =
              !cfg.systemd-boot.editor;
            "GRUB stays off: BIOS servers are not upgraded in place" =
              !cfg.grub.enable;
          };
          failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) expectations);
        in
        pkgs.runCommand "hetzner-bootloader-test" { } (
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

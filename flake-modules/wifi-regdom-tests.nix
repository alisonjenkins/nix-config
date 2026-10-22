{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
in
{
  # NixOS VM test for modules/wifi-regdom-from-timezone.nix.
  #
  # mac80211_hwsim gives the guest a cfg80211 stack, so the real `iw reg set`
  # runs and the kernel's resulting regdomain is what gets asserted.
  #
  # Under `packages`, not `checks`, for the same reason as hetzner-tests.nix:
  # `nix flake check` builds every check, and a VM boot is too slow for that.
  #
  # Run with: nix build .#wifi-regdom-from-timezone
  perSystem = { system, pkgs, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
      packages.wifi-regdom-from-timezone = pkgs.testers.runNixOSTest {
        name = "wifi-regdom-from-timezone";

        nodes.machine = { pkgs, ... }: {
          imports = [ self.nixosModules.wifi-regdom-from-timezone ];

          modules.wifiRegdomFromTimezone.enable = true;
          # null leaves /etc/localtime mutable, as on hosts using automatic-timezoned
          time.timeZone = null;
          hardware.wirelessRegulatoryDatabase = true;
          boot.kernelModules = [ "mac80211_hwsim" ];
          environment.systemPackages = [ pkgs.iw ];
        };

        testScript = ''
          def regdom():
              return machine.succeed("iw reg get | sed -n '/^global/,/^$/p'")

          machine.wait_for_unit("multi-user.target")

          with subtest("sets the country once a timezone is chosen"):
              machine.succeed("timedatectl set-timezone America/New_York")
              machine.wait_until_succeeds("iw reg get | grep -q '^country US:'", timeout=90)

          with subtest("follows later timezone changes"):
              machine.succeed("timedatectl set-timezone Europe/Berlin")
              machine.wait_until_succeeds("iw reg get | grep -q '^country DE:'", timeout=90)

          with subtest("does not re-apply while the timezone is unchanged"):
              machine.succeed("iw reg set FR")
              machine.sleep(75)
              assert "country FR:" in regdom(), regdom()

          with subtest("leaves the domain alone for a zone with no country"):
              machine.succeed("timedatectl set-timezone UTC")
              machine.wait_until_succeeds(
                  "journalctl -u wifi-regdom-from-timezone --no-pager | grep -q 'event=regdom_skip reason=no_country timezone=UTC'",
                  timeout=90,
              )
              assert "country FR:" in regdom(), regdom()
        '';
      };
    };
}

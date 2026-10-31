{ self, inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
in
{
  # NixOS VM test for lib/hetzner-store-registration.nix.
  #
  # Under `packages`, not `checks`, for the same reason as hetzner-tests.nix:
  # `nix flake check` builds checks unconditionally and a VM boot is slow.
  #
  # Run with: nix build .#hetzner-store-registration
  perSystem = { system, pkgs, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.hetzner-store-registration = pkgs.testers.runNixOSTest {
        name = "hetzner-store-registration";

        nodes.machine = {
          imports = [ (self + "/lib/hetzner-store-registration.nix") ];
          virtualisation.writableStore = true;
          # The test must create a fake store path by hand.
          boot.nixStoreMountOpts = lib.mkForce [ "nosuid" "nodev" ];
        };

        testScript = ''
          fake = "/nix/store/00000000000000000000000000000000-fake-registration"
          profile = "/nix/var/nix/profiles/system"

          machine.wait_for_unit("multi-user.target")

          with subtest("no registration file: unit is skipped and the profile is untouched"):
              machine.succeed("test ! -e /nix-path-registration")
              machine.succeed(f"test ! -e {profile}")
              machine.systemctl("start nix-path-registration")
              machine.succeed("systemctl show -p ConditionResult --value nix-path-registration | grep -x no")
              machine.succeed(f"test ! -e {profile}")

          with subtest("a registration file registers the path and links the system profile"):
              machine.succeed(f"mkdir {fake} && echo hi > {fake}/f")
              machine.fail(f"nix-store --check-validity {fake}")
              machine.succeed(
                  f"nix-store --dump {fake} > /tmp/nar"
                  f" && hash=$(nix-hash --flat --base32 --type sha256 /tmp/nar)"
                  f" && size=$(stat -c %s /tmp/nar)"
                  f" && printf '%s\\nsha256:%s\\n%s\\n\\n0\\n' {fake} \"$hash\" \"$size\" > /nix-path-registration"
              )
              machine.succeed("systemctl start nix-path-registration")
              machine.succeed(f"nix-store --check-validity {fake}")
              machine.succeed("test ! -e /nix-path-registration")
              machine.succeed(f"test -L {profile}")
              machine.succeed(f"test \"$(readlink -f {profile})\" = \"$(readlink -f /run/booted-system)\"")

          with subtest("a second start is a no-op"):
              before = machine.succeed(f"readlink {profile}")
              machine.systemctl("restart nix-path-registration")
              machine.succeed("systemctl show -p ConditionResult --value nix-path-registration | grep -x no")
              assert machine.succeed(f"readlink {profile}") == before
              machine.succeed(f"nix-store --check-validity {fake}")
        '';
      };
    };
}

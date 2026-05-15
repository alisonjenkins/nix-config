_:
let
  primary = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
  phone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2wZMFO69SYvoIIs6Atx/22PVy8wHtYy0MKpYtUMsez phone-ssh-key";
  # Dedicated key for nix-daemon (root) on ali-framework-laptop to
  # SSH into remote nix builders (ali-desktop, home-k8s-master-1).
  # Generated locally with:
  #     sudo ssh-keygen -t ed25519 -N "" -C "nix-builder-laptop" \
  #         -f /root/.ssh/id_remote_builder
  # Lives at /root/.ssh/id_remote_builder on ali-framework-laptop.
  # Authorize on hosts that should accept incoming nix builds via
  # nix.buildMachines.<entry>.sshKey = /root/.ssh/id_remote_builder.
  nixBuilderLaptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDxiKaDaOBtW1EVZNjuDqwkCpjRT0X/+ZuOmW3VDFhlE nix-builder-laptop";
in
{
  flake.lib.sshKeys = {
    inherit primary phone nixBuilderLaptop;
    all = [
      primary
      phone
    ];
    # Convenience list for hosts acting as remote nix builders. Apply
    # to users.users.ali.openssh.authorizedKeys.keys so the laptop's
    # nix-daemon can dispatch jobs.
    remoteBuilders = [
      nixBuilderLaptop
    ];
  };
}

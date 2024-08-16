{...}: {
  home.file = {
    ".ssh/id_personal.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF
    '';

    ".ssh/config".text = let
      use1password = true;
    in ''
      ${
        (
          if use1password
          then "Host *\n  IdentityAgent ~/.1password/agent.sock"
          else ""
        )
      }

      Host home-kvm-hypervisor-1
        user ali
        IdentityFile ~/.ssh/id_personal.pub
        IdentitiesOnly yes

      Host hkh1
        user ali
        HostName home-kvm-hypervisor-1
        IdentityFile ~/.ssh/id_personal.pub
        IdentitiesOnly yes

      Host github.com
        User alisonjenkins
        IdentityFile ~/.ssh/id_personal.pub
        IdentitiesOnly yes
    '';
  };
}

{ pkgs, ... }: {
  home.file = {
    ".ssh/id_personal.pub".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF
    '';

    ".ssh/config".text =
      let
        use1password = true;
        identity_sock_path =
          if pkgs.stdenv.isLinux then
            "~/.1password/agent.sock"
          else if pkgs.stdenv.isDarwin then
            "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
          else "";
      in
      ''
        ${
            (
            if use1password
            then "Host *\n  IdentityAgent ${identity_sock_path}"
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

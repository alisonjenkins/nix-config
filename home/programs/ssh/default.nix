{ pkgs, ... }: {
  home.file = {
    ".ssh/id_personal.pub.source" = {
      source = ./id_personal.pub;
      onChange = ''
      cp ~/.ssh/id_personal.pub.source ~/.ssh/id_personal.pub
      chmod 600 ~/.ssh/id_personal.pub
      '';
    };

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
            then ''
            Host *
              AddKeysToAgent yes
              IdentitiesOnly yes
              IdentityAgent ${identity_sock_path}''
          else ""
          )
          }

        Host 192.168.1.187
          User root
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes
          Port 2222

        Host ali-desktop.lan
          user ali
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host home-kvm-hypervisor-1.lan
          user ali
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hkh1
          user ali
          HostName home-kvm-hypervisor-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hkh1-setup
          user nixos
          HostName home-kvm-hypervisor-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host home-k8s-master-1.lan
          user ali
          HostName home-k8s-master-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hk8m1
          user ali
          HostName home-k8s-master-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hk8m1-setup
          user nixos
          HostName home-k8s-master-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hss1
          user ali
          HostName home-storage-server-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hss1-setup
          user nixos
          HostName home-storage-server-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host github.com
          User alisonjenkins
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host bitbucket.org
          User git
          IdentityFile ~/.ssh/id_brambles.pub
          IdentitiesOnly yes
      '';
  };
}

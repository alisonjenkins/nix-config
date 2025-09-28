{
  primarySSHKey,
  pkgs,
  ...
}: {
  home.file = {
    ".ssh/id_personal.pub.source" = {
      source = ./id_personal.pub;
      onChange = ''
        cp ~/.ssh/id_personal.pub.source ~/.ssh/id_personal.pub
        chmod 600 ~/.ssh/id_personal.pub
      '';
    };

    ".ssh/id_civica.pub.source" = {
      source = ./id_civica.pub;
      onChange = ''
        cp ~/.ssh/id_civica.pub.source ~/.ssh/id_civica.pub
        chmod 600 ~/.ssh/id_civica.pub
      '';
    };

    ".ssh/id_civica_rsa.pub.source" = {
      source = ./id_civica_rsa.pub;
      onChange = ''
        cp ~/.ssh/id_civica_rsa.pub.source ~/.ssh/id_civica_rsa.pub
        chmod 600 ~/.ssh/id_civica_rsa.pub
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

        Host download-server-1
          HostName download-server-1.lan
          IdentitiesOnly yes
          IdentityFile ~/.ssh/id_personal.pub
          User ali

        Host download-server-1.lan
          HostName download-server-1.lan
          User ali
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host ds1-setup
          HostName download-server-1.lan
          User nixos
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host gitlab.com
          User git
          IdentityFile ${primarySSHKey}
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

        Host ts-hkh1
          user ali
          HostName home-kvm-hypervisor-1.tail476348.ts.net
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

        Host ts-hk8m1
          user ali
          HostName home-k8s-master-1.tail476348.ts.net
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hk8m1-setup
          user nixos
          HostName home-k8s-master-1.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host home-storage-server-1.lan
          user ali
          HostName 192.168.1.97
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hss1
          user ali
          HostName 192.168.1.97
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host ts-hss1
          user ali
          HostName home-storage-server-1.tail476348.ts.net
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host hss1-setup
          user nixos
          HostName 192.168.1.97
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host ali-work-laptop.lan
          user ali
          HostName ali-work-laptop.lan
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host ali-worklaptop-setup
          user nixos
          HostName 192.168.0.70
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host github.com
          User alisonjenkins
          IdentityFile ${primarySSHKey}
          IdentitiesOnly yes

        Host cgithub.com
          Hostname github.com
          User alisonjenkins
          IdentityFile ~/.ssh/id_civica.pub
          IdentitiesOnly yes

        Host pgithub.com
          Hostname github.com
          User alisonjenkins
          IdentityFile ~/.ssh/id_personal.pub
          IdentitiesOnly yes

        Host ssh.dev.azure.com
          User git
          IdentityFile ${primarySSHKey}
          IdentitiesOnly yes
      '';
  };
}

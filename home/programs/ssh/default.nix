{
  config,
  inputs,
  lib,
  primarySSHKey,
  # Azure DevOps only supports RSA keys (not ed25519); set per work machine, empty on personal machines
  azureDevopsRsaKey ? "",
  # Work machines only: decrypt the work SSH public keys out of sops instead of
  # shipping them in this public repo. See home/home-common.nix.
  workIdentity ? false,
  workIdentitySecretsFile ? null,
  # false on machines without the 1Password SSH agent (the Steam Frame): no
  # IdentityAgent, and every host stanza names primarySSHKey (a private key
  # on disk) instead of the 1Password-held id_personal.pub.
  sshUse1Password ? true,
  pkgs,
  ...
}: {
  # The work public keys live in sops, not in the store, so they are only
  # present on machines that opt in.
  sops.secrets = lib.mkIf workIdentity {
    "id_work_pub" = {
      sopsFile = workIdentitySecretsFile;
      mode = "0600";
      path = "${config.home.homeDirectory}/.ssh/id_work.pub";
    };

    "id_work_rsa_pub" = {
      sopsFile = workIdentitySecretsFile;
      mode = "0600";
      path = "${config.home.homeDirectory}/.ssh/id_work_rsa.pub";
    };
  };

  home.file = {
    ".ssh/id_personal.pub.source" = {
      source = ./id_personal.pub;
      onChange = ''
        install -m 600 ~/.ssh/id_personal.pub.source ~/.ssh/id_personal.pub
      '';
    };

    ".ssh/config".text =
      let
        inherit (inputs.self.lib.homeLan) hosts;
        use1password = sshUse1Password;
        # With 1Password the public key selects the agent identity; without
        # it the host's own key file is named directly.
        personalKey = if use1password then "~/.ssh/id_personal.pub" else primarySSHKey;
        identity_sock_path =
          if pkgs.stdenv.hostPlatform.isLinux then
            "~/.1password/agent.sock"
          else if pkgs.stdenv.hostPlatform.isDarwin then
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
              IdentityAgent ${identity_sock_path}
              # IdentitiesOnly restricts ssh to the identities named in the
              # config; with none named here it falls back to the default
              # filenames (~/.ssh/id_rsa, id_ed25519, ...), none of which
              # exist because the private key lives in the 1Password agent.
              # The result is that any host without its own stanza offers
              # *zero* keys and fails with "Permission denied (publickey)"
              # despite the agent holding the right key. Naming the public
              # key here selects the matching agent identity, which is why
              # every per-host stanza below repeats the same line.
              IdentityFile ${primarySSHKey}''
          else ''
            Host *
              AddKeysToAgent yes
              IdentitiesOnly yes
              IdentityFile ${primarySSHKey}''
          )
          }

        Host ${hosts.ali-desktop.ip}
          User root
          IdentityFile ${personalKey}
          IdentitiesOnly yes
          Port 2222

        Host ali-desktop.lan
          user ali
          HostName ${hosts.ali-desktop.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ts-desktop ali-desktop 100.127.142.30
          HostName ali-desktop.tail476348.ts.net
          User ali
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ali-steam-deck ali-steam-deck.lan ${hosts.ali-steam-deck.ip}
          HostName ${hosts.ali-steam-deck.ip}
          User ali
          IdentityFile ${primarySSHKey}
          IdentitiesOnly yes

        Host download-server-1 ds1
          HostName ${hosts.download-server-1.ip}
          IdentitiesOnly yes
          IdentityFile ${personalKey}
          User ali

        Host download-server-1.lan
          HostName ${hosts.download-server-1.ip}
          User ali
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ts-ds1
          user ali
          HostName download-server-1.tail476348.ts.net
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ds1-setup
          HostName ${hosts.download-server-1.ip}
          User nixos
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host gitlab.com
          User git
          IdentityFile ${primarySSHKey}
          IdentitiesOnly yes

        Host home-kvm-hypervisor-1.lan home-kvm-hypervisor-1 hkh1
          user ali
          HostName ${hosts.home-kvm-hypervisor-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ts-hkh1
          user ali
          HostName home-kvm-hypervisor-1.tail476348.ts.net
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host hkh1-setup
          user nixos
          HostName ${hosts.home-kvm-hypervisor-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host pikvm pikvm.lan
          User root
          HostName ${hosts.pikvm.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host home-k8s-master-1.lan
          user ali
          HostName ${hosts.home-k8s-master-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host hk8m1 home-k8s-master-1
          user ali
          HostName ${hosts.home-k8s-master-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ts-hk8m1
          user ali
          HostName home-k8s-master-1.tail476348.ts.net
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host hk8m1-setup
          user nixos
          HostName ${hosts.home-k8s-master-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host home-k8s-server-1.lan home-k8s-server-1 hk8s1
          user ali
          HostName ${hosts.home-k8s-server-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host hk8s1-setup
          user nixos
          HostName ${hosts.home-k8s-server-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        # LUKS unlock in the initrd (modules/initrd-ssh.nix).
        Host hk8s1-unlock
          User root
          HostName ${hosts.home-k8s-server-1.ip}
          Port 2222
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host home-storage-server-1.lan
          user ali
          HostName ${hosts.home-storage-server-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host hss1 home-storage-server-1
          user ali
          HostName ${hosts.home-storage-server-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ts-hss1
          user ali
          HostName home-storage-server-1.tail476348.ts.net
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host hss1-setup
          user nixos
          HostName ${hosts.home-storage-server-1.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ali-work-laptop.lan
          user ali
          HostName ${hosts.ali-work-laptop.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host ali-worklaptop-setup
          user nixos
          HostName ${hosts.ali-work-laptop.ip}
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host github.com
          User alisonjenkins
          IdentityFile ${primarySSHKey}
          IdentitiesOnly yes

        ${lib.optionalString workIdentity ''
        Host wgithub.com
          Hostname github.com
          User alisonjenkins
          IdentityFile ~/.ssh/id_work.pub
          IdentitiesOnly yes''}

        Host pgithub.com
          Hostname github.com
          User alisonjenkins
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        Host codeberg.org
          User git
          IdentityFile ${personalKey}
          IdentitiesOnly yes

        ${if azureDevopsRsaKey != "" then ''
        Host ssh.dev.azure.com
          User git
          IdentityFile ${azureDevopsRsaKey}
          IdentitiesOnly yes'' else ""}
      '';
  };
}

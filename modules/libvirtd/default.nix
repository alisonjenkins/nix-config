{
  pkgs,
  ...
}: {
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };

  environment = {
    systemPackages = [
      (pkgs.OVMF.override {
        secureBoot = true;
        tpmSupport = true;
      })
    ];
  };
}

{
  pkgs,
  ...
}: {
  virtualisation.libvirtd = {
    enable = true;
    parallelShutdown = 4;
    qemu = {
      swtpm.enable = true;
    };
  };

  environment = {
    systemPackages = [ pkgs.OVMF pkgs.AAVMF ];
  };
}

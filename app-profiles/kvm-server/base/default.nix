{ ...
}: {
  virtualisation.libvirtd = {
    enable = true;
    parallelShutdown = 4;
    qemu = {
      swtpm.enable = true;
    };
  };
}

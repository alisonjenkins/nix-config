{ pkgs }: {
  environment = {
    systemPackages = with pkgs; [
      clinfo
      rocmPackages.rocminfo
    ];
  };

  hardware = {
    amdgpu = {
      initrd = {
        enable = true;
      };

      opencl = {
        enable = true;
      };
    };

    graphics = {
      extraPackages = with pkgs; [ rocmPackages.clr.icd ];
    };
  };
}

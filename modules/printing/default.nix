{pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      hplipWithPlugin
    ];
  };

  services = {
    avahi = {
      enable = true;
    };

    printing = {
      enable = true;
    };
  };
}

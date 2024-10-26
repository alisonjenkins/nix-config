{ ...
}: {
  # environment.systemPackages = with pkgs; [
  #   tlp
  # ];
  services = {
    tlp = {
      enable = true;
    };
  };
}

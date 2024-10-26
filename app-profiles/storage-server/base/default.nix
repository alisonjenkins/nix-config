{ pkgs
, ...
}: {
  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
  ];

  # snapraid = {
  #   enable = true;
  # };
}

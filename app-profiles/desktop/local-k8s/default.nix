{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    dive
    kind
    tilt
  ];
}

{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    dive
    kind
    tilt
  ];

  virtualisation.podman = {
    autoPrune.enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
    enable = true;
  };
}

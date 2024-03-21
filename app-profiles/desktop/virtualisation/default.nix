{
  config,
  pkgs,
  user,
  ...
}: {
  virtualisation = {
    docker.enable = true;
  };

  users.groups.docker.members = ["ali"];

  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}

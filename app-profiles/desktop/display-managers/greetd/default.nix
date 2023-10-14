{ pkgs, ... }:
{
  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --remember --remember-user-session --sessions /run/booted-system/sw/share/xsessions/ --sessions /run/booted-system/sw/share/wayland-sessions/";
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    greetd.tuigreet
  ];
}


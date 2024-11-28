{ pkgs, ... }: {
  home.file = (if pkgs.stdenv.isLinux then {
    ".local/share/dbus-1/services/org.freedesktop.secrets.service".text = ''
      [D-BUS Service]
      Name=org.freedesktop.secrets
      Exec=${pkgs.kdePackages.kwallet}/bin/kwalletd6
    '';
  } else { });
}

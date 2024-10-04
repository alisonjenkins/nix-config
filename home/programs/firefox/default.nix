{
  config,
  inputs,
  lib,
  pkgs,
  system,
  username,
  ...
}: {
  programs.firefox = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;

    profiles.${username} = {
      search.engines = {
        "Nix Packages" = {
          urls = [
            {
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "type";
                  value = "packages";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = ["@np"];
        };
      };
      search.force = true;

      extensions = with pkgs.nur.repos.rycee.firefox-addons;
        [
          auto-tab-discard
          darkreader
          firenvim
          multi-account-containers
          onepassword-password-manager
          libredirect
          link-cleaner
          privacy-badger
          offline-qr-code-generator
          surfingkeys
          switchyomega
          tree-style-tab
          tst-tab-search
          ublock-origin
        ]
        ++ (
          if pkgs.stdenv.isLinux
          then [
            pkgs.nur.repos.rycee.firefox-addons.plasma-integration
          ]
          else []
        );
    };
  };

  home.file = {
    ".local/share/applications/Firefox.desktop".text = ''
      [Desktop Entry]
      Comment[en_US]=
      Comment=
      Exec=${pkgs.firefox}/bin/firefox
      GenericName[en_US]=
      GenericName=
      Icon=${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png
      MimeType=
      Name[en_US]=Firefox
      Name=Firefox
      Path=
      StartupNotify=true
      Terminal=false
      TerminalOptions=
      Type=Application
      X-KDE-SubstituteUID=false
      X-KDE-Username=
    '';
  };
}

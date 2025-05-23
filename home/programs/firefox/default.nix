{ lib
, pkgs
, username
, ...
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
          definedAliases = [ "@np" ];
        };
      };
      search.force = true;

      extensions = {
        packages = (
          if pkgs.stdenv.isLinux
          then with pkgs.nur.repos.rycee.firefox-addons; [
            auto-tab-discard
            darkreader
            firenvim
            libredirect
            link-cleaner
            multi-account-containers
            offline-qr-code-generator
            onepassword-password-manager
            plasma-integration
            privacy-badger
            surfingkeys
            switchyomega
            tab-session-manager
            tree-style-tab
            tst-fade-old-tabs
            tst-indent-line
            tst-tab-search
            ublock-origin
          ]
          else [ ]
        );
      };
    };
  };

  home.file =
    if pkgs.stdenv.isLinux then {
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
    } else { };
}

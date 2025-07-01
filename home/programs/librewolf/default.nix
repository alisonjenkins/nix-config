{ lib
, config
, pkgs
, username
, ...
}: {
  config.stylix.targets.librewolf.profileNames = [
   username
  ];

  config.programs.librewolf = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;

    package = pkgs.unstable.librewolf;

    settings = {
      "webgl.disabled" = false;
      "privacy.resistFingerprinting" = false;
    };

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

  config.home.file =
    if pkgs.stdenv.isLinux then {
      ".local/share/applications/Librewolf.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=${pkgs.librewolf}/bin/librewolf
        GenericName[en_US]=
        GenericName=
        Icon=${pkgs.librewolf}/share/icons/hicolor/128x128/apps/librewolf.png
        MimeType=
        Name[en_US]=Librewolf
        Name=Librewolf
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


{ lib
, config
, inputs
, pkgs
, username
, ...
}:
let
  shared = import ../browser-settings.nix { inherit pkgs; };
in {
  config.stylix.targets.zen-browser.profileNames = [
    username
  ];

  config.programs.zen-browser = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;
    nativeMessagingHosts = lib.mkIf pkgs.stdenv.isLinux [
      inputs.pipewire-screenaudio.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs._1password-gui
    ];

    profiles.${username} = {
      isDefault = true;
      settings = shared.settings;

      search.engines = shared.searchEngines;
      search.force = true;

      extensions = {
        packages = (
          if pkgs.stdenv.isLinux
          then (with pkgs.nur.repos.rycee.firefox-addons; [
            # auto-tab-discard
            # firenvim
            # plasma-integration
            # switchyomega
            # tree-style-tab
            # tst-fade-old-tabs
            # tst-indent-line
            # tst-tab-search
            darkreader
            libredirect
            link-cleaner
            multi-account-containers
            offline-qr-code-generator
            onepassword-password-manager
            privacy-badger
            surfingkeys
            tab-session-manager
            ublock-origin
          ]) ++ [
            (let
              extid = "pipewire-screenaudio@icenjim";
              xpi = pkgs.fetchurl {
                url = "https://addons.mozilla.org/firefox/downloads/file/4186504/pipewire_screenaudio-0.3.4.xpi";
                hash = "sha256-p0cUUU9JC21cNuMriFEK4+Xn8a/cspwgQag206pITL4=";
              };
            in pkgs.stdenvNoCC.mkDerivation {
              name = "pipewire-screenaudio-${extid}";
              dontUnpack = true;
              installPhase = ''
                mkdir -p "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
                cp "${xpi}" "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${extid}.xpi"
              '';
              passthru.addonId = extid;
            })
          ]
          else [ ]
        );
      };

      mods = [
        "2317fd93-c3ed-4f37-b55a-304c1816819e"
      ];
    };
  };

  # The zen-browser package provides its own zen-beta.desktop file
  # with correct Exec=zen-beta, StartupWMClass, MIME types, and actions.
}

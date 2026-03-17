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
      # inputs.pipewire-screenaudio.packages.${pkgs.stdenv.hostPlatform.system}.default # broken upstream: firefox.json renamed
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
          ])
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

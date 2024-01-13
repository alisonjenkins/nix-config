{ pkgs, inputs, system, lib, ... }:
{
  # inputs.firefox-addons.pkgs.config.allowUnfree = true;
  # nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  #   inputs.firefox-addons.packages.${system}.onepassword-password-manager
  # ];

  programs.firefox = {
    enable = true;

    profiles.ali = {
      search.engines = {
        "Nix Packages" = {
          urls = [{
            template = "https://search.nixos.org/packages";
            params = [
              { name = "type"; value = "packages"; }
              { name = "query"; value = "{searchTerms}"; }
            ];
          }];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };
      };
      search.force = true;

      extensions = with inputs.firefox-addons.packages.${system}; [
        darkreader
        firenvim
        multi-account-containers
        # onepassword-password-manager
        privacy-badger
        surfingkeys
        switchyomega
        ublock-origin
        tree-style-tab
      ] ++ (
        if pkgs.stdenv.isLinux then [
          inputs.firefox-addons.packages.${system}.plasma-integration
        ] else [ ]
      );
    };
  };
}

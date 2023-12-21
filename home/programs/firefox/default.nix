{ pkgs, inputs, system, ... }:
{
  # inputs.firefox-addons.pkgs.config.allowUnfree = true;
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

      extensions = [
        inputs.firefox-addons.packages.${system}.darkreader
        inputs.firefox-addons.packages.${system}.firenvim
        inputs.firefox-addons.packages.${system}.multi-account-containers
        # inputs.firefox-addons.packages.${system}.onepassword-password-manager
        inputs.firefox-addons.packages.${system}.privacy-badger
        inputs.firefox-addons.packages.${system}.surfingkeys
        inputs.firefox-addons.packages.${system}.switchyomega
        inputs.firefox-addons.packages.${system}.ublock-origin
      ] ++ (
        if pkgs.stdenv.isLinux then [
          inputs.firefox-addons.packages.${system}.plasma-integration
        ] else [ ]
      );
    };
  };
}

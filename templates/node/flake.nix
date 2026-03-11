{
  description = "A Node.js project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        my-app = pkgs.buildNpmPackage {
          pname = "my-app";
          version = "0.1.0";
          src = ./.;
          npmDepsHash = "sha256-YnuhK+MTINRRfUh4JYBi6fat2jmJLXMJoBafB0cC9+s=";
          forceEmptyCache = true;
          dontNpmBuild = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/my-app $out/bin
            cp -r src package.json $out/lib/my-app/
            echo '#!/usr/bin/env node' > $out/bin/my-app
            cat $out/lib/my-app/src/index.js >> $out/bin/my-app
            chmod +x $out/bin/my-app
            runHook postInstall
          '';
        };

        my-app-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-app";
          tag = "latest";
          contents = [
            my-app
            pkgs.nodejs
            pkgs.cacert
          ];
          config = {
            Cmd = [
              "${pkgs.nodejs}/bin/node"
              "${my-app}/lib/my-app/src/index.js"
            ];
            Env = [
              "NODE_ENV=production"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        my-app-container-stream = pkgs.dockerTools.streamLayeredImage {
          name = "my-app";
          tag = "latest";
          contents = [
            my-app
            pkgs.nodejs
            pkgs.cacert
          ];
          config = {
            Cmd = [
              "${pkgs.nodejs}/bin/node"
              "${my-app}/lib/my-app/src/index.js"
            ];
            Env = [
              "NODE_ENV=production"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-app;

          my-app-test = pkgs.runCommand "my-app-test" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
            cd ${./.}
            node --test test/*.test.js
            touch $out
          '';
        };

        packages =
          {
            default = my-app;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            container = my-app-container;
            container-stream = my-app-container-stream;
          };

        apps.default = flake-utils.lib.mkApp {
          drv = my-app;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            just
          ];
        };
      }
    );
}

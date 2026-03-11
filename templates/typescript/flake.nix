{
  description = "A TypeScript project";

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
          npmDepsHash = "sha256-GJRw/dIY3tQ6WjkiTOOhtvG7AjpqspehDJu9gV0DlTI=";

          buildPhase = ''
            runHook preBuild
            npx tsc
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/my-app $out/bin
            cp -r dist package.json $out/lib/my-app/
            cat > $out/bin/my-app << EOF
            #!/usr/bin/env node
            require("$out/lib/my-app/dist/index.js");
            EOF
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
              "${my-app}/lib/my-app/dist/index.js"
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
              "${my-app}/lib/my-app/dist/index.js"
            ];
            Env = [
              "NODE_ENV=production"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        npmCache = my-app.npmDeps;
      in
      {
        checks = {
          inherit my-app;

          my-app-typecheck = pkgs.runCommand "my-app-typecheck"
            { nativeBuildInputs = [ pkgs.nodejs ]; }
            ''
              export HOME=$(mktemp -d)
              cp -rL ${./.}/. work && chmod -R u+w work && cd work
              npm ci --cache=${npmCache} --ignore-scripts
              node node_modules/typescript/bin/tsc --noEmit
              touch $out
            '';

          my-app-test = pkgs.runCommand "my-app-test"
            { nativeBuildInputs = [ pkgs.nodejs ]; }
            ''
              export HOME=$(mktemp -d)
              cp -rL ${./.}/. work && chmod -R u+w work && cd work
              npm ci --cache=${npmCache} --ignore-scripts
              node node_modules/tsx/dist/cli.mjs --test test/*.test.ts
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

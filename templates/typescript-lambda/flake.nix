{
  description = "An AWS Lambda TypeScript project";

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

        my-lambda = pkgs.buildNpmPackage {
          pname = "my-lambda";
          version = "0.1.0";
          src = ./.;
          npmDepsHash = "sha256-7LSNoxb8X4RLHqQgsuCwuYV6VY2kEu3mGBjcRcLCesM=";

          buildPhase = ''
            runHook preBuild
            npx tsc
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/my-lambda
            cp -r dist package.json $out/lib/my-lambda/
            runHook postInstall
          '';
        };

        my-lambda-zip = pkgs.runCommand "my-lambda-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
          mkdir -p $out
          cd ${my-lambda}/lib/my-lambda
          zip -r $out/my-lambda.zip .
        '';

        npmCache = my-lambda.npmDeps;
      in
      {
        checks = {
          inherit my-lambda;

          my-lambda-typecheck = pkgs.runCommand "my-lambda-typecheck"
            { nativeBuildInputs = [ pkgs.nodejs ]; }
            ''
              export HOME=$(mktemp -d)
              cp -rL ${./.}/. work && chmod -R u+w work && cd work
              npm ci --cache=${npmCache} --ignore-scripts
              node node_modules/typescript/bin/tsc --noEmit
              touch $out
            '';

          my-lambda-test = pkgs.runCommand "my-lambda-test"
            { nativeBuildInputs = [ pkgs.nodejs ]; }
            ''
              export HOME=$(mktemp -d)
              cp -rL ${./.}/. work && chmod -R u+w work && cd work
              npm ci --cache=${npmCache} --ignore-scripts
              node node_modules/tsx/dist/cli.mjs --test test/*.test.ts
              touch $out
            '';
        };

        packages = {
          default = my-lambda;
          zip = my-lambda-zip;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            awscli2
            nodejs
            just
          ];
        };
      }
    );
}

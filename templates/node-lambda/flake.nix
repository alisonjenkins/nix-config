{
  description = "An AWS Lambda Node.js project";

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
          npmDepsHash = "sha256-F1atGO75ot3ELbqGNwGkkhckA93JqkMOuUf+i9o405I=";
          forceEmptyCache = true;
          dontNpmBuild = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/my-lambda
            cp -r src package.json $out/lib/my-lambda/
            runHook postInstall
          '';
        };

        my-lambda-zip = pkgs.runCommand "my-lambda-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
          mkdir -p $out
          cd ${my-lambda}/lib/my-lambda
          zip -r $out/my-lambda.zip .
        '';
      in
      {
        checks = {
          inherit my-lambda;

          my-lambda-test = pkgs.runCommand "my-lambda-test" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
            cd ${./.}
            node --test test/*.test.js
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

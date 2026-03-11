{
  description = "An AWS Lambda Java project";

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

        my-lambda = pkgs.maven.buildMavenPackage {
          pname = "my-lambda";
          version = "0.1.0";
          src = ./.;
          mvnHash = "sha256-VEnxoHlPYkt8nyphTnqbXiP+UdtnWwq1O9QrRBRTJ0Q=";

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/my-lambda
            cp target/my-lambda-0.1.0-jar-with-dependencies.jar $out/share/my-lambda/my-lambda.jar
            runHook postInstall
          '';
        };

        jre = pkgs.jre_minimal;

        my-lambda-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            my-lambda
            jre
            pkgs.cacert
          ];
          config = {
            Cmd = [
              "${jre}/bin/java"
              "-jar"
              "${my-lambda}/share/my-lambda/my-lambda.jar"
              "com.example.Handler"
            ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        my-lambda-container-stream = pkgs.dockerTools.streamLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            my-lambda
            jre
            pkgs.cacert
          ];
          config = {
            Cmd = [
              "${jre}/bin/java"
              "-jar"
              "${my-lambda}/share/my-lambda/my-lambda.jar"
              "com.example.Handler"
            ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-lambda;

          my-lambda-fmt = pkgs.runCommand "my-lambda-fmt" { nativeBuildInputs = [ pkgs.google-java-format pkgs.findutils ]; } ''
            cd ${./.}
            find . -name "*.java" -exec google-java-format --dry-run --set-exit-if-changed {} +
            touch $out
          '';
        };

        packages =
          {
            default = my-lambda;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            container = my-lambda-container;
            container-stream = my-lambda-container-stream;
          };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            awscli2
            jdk
            maven
            google-java-format
            just
          ];
        };
      }
    );
}

{
  description = "A Java project";

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

        my-app = pkgs.maven.buildMavenPackage {
          pname = "my-app";
          version = "0.1.0";
          src = ./.;
          mvnHash = "sha256-WzGmWJqFO0l/+NoGdh1+E94fhbNyKC3E32zl4ZOrmOo=";

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/my-app $out/bin
            cp target/my-app-0.1.0.jar $out/share/my-app/my-app.jar
            makeWrapper ${pkgs.jre_minimal}/bin/java $out/bin/my-app \
              --add-flags "-jar $out/share/my-app/my-app.jar"
            runHook postInstall
          '';
        };

        my-app-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-app";
          tag = "latest";
          contents = [
            my-app
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-app}/bin/my-app" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        my-app-container-stream = pkgs.dockerTools.streamLayeredImage {
          name = "my-app";
          tag = "latest";
          contents = [
            my-app
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-app}/bin/my-app" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-app;

          my-app-fmt = pkgs.runCommand "my-app-fmt" { nativeBuildInputs = [ pkgs.google-java-format pkgs.findutils ]; } ''
            cd ${./.}
            find . -name "*.java" -exec google-java-format --dry-run --set-exit-if-changed {} +
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
            jdk
            maven
            google-java-format
            just
          ];
        };
      }
    );
}

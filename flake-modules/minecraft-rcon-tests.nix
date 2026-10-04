{ self, ... }: {
  # Hermetic bats test for RCON setup in the Create Arkana server image.
  # Evaluates the baked server.properties and the image contents list; never
  # builds the image. Run with:
  #   nix build .#checks.<system>.minecraft-arkana-rcon-bats
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") (
      let
        server = self.packages.${system}.create-arkana-aeronautics-server;
        image = self.packages.${system}.minecraft-arkana-aeronautics-image;
        contentNames = lib.concatMapStringsSep "\n" (p: p.pname or (lib.getName p)) image.contents;
      in
      {
        checks.minecraft-arkana-rcon-bats = pkgs.runCommand "minecraft-arkana-rcon-bats"
          {
            nativeBuildInputs = [ pkgs.bats ];
            SERVER_PROPERTIES = server.serverPropertiesFile;
            ENTRYPOINT = self + "/pkgs/create-arkana-aeronautics-server/entrypoint.sh";
            RCON_LIB = self + "/pkgs/create-arkana-aeronautics-server/rcon.sh";
            inherit contentNames;
            passAsFile = [ "contentNames" ];
          } ''
          export IMAGE_CONTENTS="$contentNamesPath"
          bats ${self + "/pkgs/create-arkana-aeronautics-server/tests"}
          touch $out
        '';
      }
    );
}

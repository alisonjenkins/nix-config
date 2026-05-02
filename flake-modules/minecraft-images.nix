{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;

  # Linux-only: containers run on Linux nodes (aws-k3s) and dockerTools
  # cross-compilation from Darwin needs a remote linux builder anyway.
  linuxSystems = [ "x86_64-linux" "aarch64-linux" ];

  mkImage = system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        # The Minecraft pack is marked unfreeRedistributable
        # (Mojang EULA + bundled mods).
        config.allowUnfree = true;
        overlays = lib.attrValues self.overlays;
      };

      server = pkgs.create-sky-colonies-server;
      jre = pkgs.temurin-jre-bin-21;
    in
    pkgs.dockerTools.buildLayeredImage {
      name = "create-sky-colonies-server";
      tag = "v${server.version}";

      # Reproducible image (no creation timestamp drift between rebuilds).
      created = "1970-01-01T00:00:01Z";

      contents = [
        pkgs.bashInteractive
        pkgs.coreutils
        pkgs.cacert
        # libstdc++ for spark profiler's async-profiler engine — without
        # it spark falls back to the JVM sampling profiler (less accurate
        # for native-call hotspots).
        pkgs.stdenv.cc.cc.lib
        jre
        server
      ];

      # Layer the heavy server tree separately so a JRE bump or perf-mod
      # change re-uses the cached server layer (650 MB extracted).
      maxLayers = 100;

      extraCommands = ''
        mkdir -p opt data tmp
        # Symlink server tree to a stable path the entrypoint expects.
        ln -s ${server} opt/server
        chmod 1777 tmp
      '';

      config = {
        Entrypoint = [ "${server}/entrypoint.sh" ];
        WorkingDir = "/data";
        ExposedPorts = {
          "25565/tcp" = { };
          "24454/udp" = { }; # Simple Voice Chat (mod ships in pack)
        };
        Volumes = {
          "/data" = { };
        };
        Env = [
          "JAVA_HOME=${jre}"
          "PATH=${jre}/bin:/bin"
          # Tuned to fit a 4 GiB k8s pod limit:
          #   2.5 GB heap + 928 MB JVM non-heap caps (Metaspace 384m,
          #   CodeCache 192m, CompressedClassSpace 96m, DirectMemory
          #   256m) + ~40 MB thread stacks (-Xss512k × ~80 threads) +
          #   ~200 MB native = ~3.7 GB ceiling, ~300 MB headroom.
          # Live heap idle ~1.21 GB; expect 1.7-2 GB under 4 players +
          # active colonies/ships → 500 MB-1 GB GC headroom. Bump
          # MINECRAFT_HEAP (e.g. "3g") and pod limit if MSPT >50ms.
          "MINECRAFT_HEAP=2560m"
        ];
      };
    };
in
{
  perSystem = { system, ... }: {
    packages = lib.optionalAttrs (lib.elem system linuxSystems) {
      minecraft-csc-image = mkImage system;
    };
  };
}

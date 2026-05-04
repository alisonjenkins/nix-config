{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;

  # Linux-only: containers run on Linux nodes (aws-k3s) and dockerTools
  # cross-compilation from Darwin needs a remote linux builder anyway.
  linuxSystems = [ "x86_64-linux" "aarch64-linux" ];

  # Shared image-builder. Each Minecraft modpack server has its own Nix
  # package (create-sky-colonies-server, create-arkana-aeronautics-server,
  # …) that produces a directory tree with mods/, configs/, eula.txt, and
  # an entrypoint.sh; this function wraps any of them into a layered OCI
  # image with the same JRE 21 + libstdc++ + cacert toolbox.
  mkImage = system: { server, imageName, extraPorts ? { }, heap ? "2560m" }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        # The Minecraft pack is marked unfreeRedistributable
        # (Mojang EULA + bundled mods).
        config.allowUnfree = true;
        overlays = lib.attrValues self.overlays;
      };

      jre = pkgs.temurin-jre-bin-21;
    in
    pkgs.dockerTools.buildLayeredImage {
      name = imageName;
      # OCI image tag chars: [a-zA-Z0-9._-] only — drop SemVer build-meta
      # `+` so a version like `1.5+aeronautics-1.2.1` lands as a valid tag
      # `v1.5-aeronautics-1.2.1`.
      tag = "v" + lib.replaceStrings [ "+" ] [ "-" ] server.version;

      # Reproducible image (no creation timestamp drift between rebuilds).
      created = "1970-01-01T00:00:01Z";

      contents = [
        pkgs.bashInteractive
        pkgs.coreutils
        # grep + gawk are NOT in coreutils — entrypoint.sh uses grep
        # to filter user_jvm_args.txt. Without these the JVM_TUNING
        # array is empty and the server boots with default JVM flags
        # (no G1 tuning, no metaspace cap, etc).
        pkgs.gnugrep
        pkgs.gawk
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
        } // extraPorts;
        Volumes = {
          "/data" = { };
        };
        Env = [
          "JAVA_HOME=${jre}"
          "PATH=${jre}/bin:/bin"
          # 4 GiB k8s pod limit: heap + non-heap caps + native overhead.
          # Bump MINECRAFT_HEAP and pod limit together if MSPT >50ms.
          "MINECRAFT_HEAP=${heap}"
        ];
      };
    };

  cscImage = system:
    let pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = lib.attrValues self.overlays;
        };
    in mkImage system {
      server     = pkgs.create-sky-colonies-server;
      imageName  = "create-sky-colonies-server";
      # Simple Voice Chat (CSC bundles it).
      extraPorts = { "24454/udp" = { }; };
    };

  arkanaAeronauticsImage = system:
    let pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = lib.attrValues self.overlays;
        };
    in mkImage system {
      server    = pkgs.create-arkana-aeronautics-server;
      imageName = "create-arkana-aeronautics-server";
    };
  # Helper: snap to one of the per-system overlay-applied nixpkgs sets so
  # the package outputs we expose match what the image consumes (single
  # source of overlays).
  pkgsFor = system: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = lib.attrValues self.overlays;
  };
in
{
  perSystem = { system, ... }: {
    packages =
      # Linux-only outputs (server tree + docker images). dockerTools and
      # the server tree require a Linux builder; cross-building from Darwin
      # is fronted by the Linux remote builder configured in nix.conf.
      lib.optionalAttrs (lib.elem system linuxSystems) {
        minecraft-csc-image = cscImage system;
        minecraft-arkana-aeronautics-image = arkanaAeronauticsImage system;
        create-arkana-aeronautics-server = (pkgsFor system).create-arkana-aeronautics-server;
      }
      # Cross-platform: client zip is just metadata + jar shuffling, builds
      # on Darwin too. Exposed for both linux and darwin so a Mac dev can
      # produce a CurseForge-importable zip without bouncing through the
      # Linux builder.
      // {
        create-arkana-aeronautics-client = (pkgsFor system).create-arkana-aeronautics-client;
        # Generic Minecraft modpack tooling (currently `dep-tree`).
        # Run via `nix run .#dep-tree -- /path/to/server-tree`.
        minecraft-modpack-tools = (pkgsFor system).minecraft-modpack-tools;
      };
    apps.dep-tree = {
      type = "app";
      program = "${(pkgsFor system).minecraft-modpack-tools}/bin/dep-tree";
    };
    apps.find-mod-bumps = {
      type = "app";
      program = "${(pkgsFor system).minecraft-modpack-tools}/bin/find-mod-bumps";
    };
  };
}

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

      # Pinned to Temurin 21.0.13.1+2 for CVE-2026-114938 ("Java4Shell":
      # memory corruption in the Base64 decoder intrinsic on x86-64 CPUs
      # with AVX-512 VBMI, pre-auth RCE where untrusted input is
      # Base64-decoded; affects 17.0.6+). Fixed in 21.0.13.1 (Red Hat
      # RHSA-2026:100569, Debian openjdk-21 21.0.13.1+2). nixos-26.05 still
      # ships 21.0.11 and nixos-unstable 21.0.12.1, both vulnerable.
      # Drop this override once nixpkgs' temurin-bin/sources.json points at
      # jdk-21.0.13.1 or newer.
      # A server tree may pin its own JDK instead (magic-vr-pack does).
      jre = server.jre or (pkgs.temurin-jre-bin-21.overrideAttrs (_old: {
        version = "21.0.13.1";
        src = pkgs.fetchurl {
          x86_64-linux = {
            url = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13.1%2B2/OpenJDK21U-jre_x64_linux_hotspot_21.0.13.1_2.tar.gz";
            sha256 = "18f44fab9065217f3ba61d0eef8a7b5f3c3713aa7293001b0d4ac10ede3850f0";
          };
          aarch64-linux = {
            url = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13.1%2B2/OpenJDK21U-jre_aarch64_linux_hotspot_21.0.13.1_2.tar.gz";
            sha256 = "52bc58323d9266538a6361a3cf8365fc1186dd9510d7f33f623681c4aabb7e72";
          };
        }.${system};
      }));

      imageContents = [
        # Plain bash (no readline / history / etc.) is enough for the
        # entrypoint and saves ~5 MB vs bashInteractive.
        pkgs.bash
        pkgs.coreutils
        # grep + gawk are NOT in coreutils — entrypoint.sh uses grep
        # to filter user_jvm_args.txt. Without these the JVM_TUNING
        # array is empty and the server boots with default JVM flags
        # (no G1 tuning, no metaspace cap, etc).
        pkgs.gnugrep
        pkgs.gawk
        pkgs.cacert
        # mcrcon for the Velero backup hook (save-off / save-all flush /
        # save-on); hooks exec `sh -c`, and `sh` comes from pkgs.bash.
        pkgs.mcrcon
        # libstdc++ for spark profiler's async-profiler engine — without
        # it spark falls back to the JVM sampling profiler (less accurate
        # for native-call hotspots).
        pkgs.stdenv.cc.cc.lib
        jre
        server
      ];
      image = pkgs.dockerTools.buildLayeredImage {
      name = imageName;
      # OCI image tag chars: [a-zA-Z0-9._-] only — drop SemVer build-meta
      # `+` so a version like `1.5+aeronautics-1.2.1` lands as a valid tag
      # `v1.5-aeronautics-1.2.1`.
      tag = "v" + lib.replaceStrings [ "+" ] [ "-" ] server.version;

      # Reproducible image (no creation timestamp drift between rebuilds).
      created = "1970-01-01T00:00:01Z";

      contents = imageContents;

      # Layer mod jars individually: the server tree symlinks each per-mod
      # fetchurl store path, so dockerTools.buildLayeredImage spreads them
      # across separate OCI layers. With 250+ mods we want as many layer
      # slots as practical so each mod's bump invalidates only its own
      # layer (typical Docker registries cap at 127 layers per image — 125
      # leaves headroom for the JRE + system layers).
      maxLayers = 125;

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
    in
    # `contents` is surfaced so checks can inspect the image without building it.
    image // { contents = imageContents; };

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
  magicVrPackImage = system:
    mkImage system {
      server    = (pkgsFor system).magic-vr-pack-server;
      imageName = "magic-vr-pack-server";
      heap      = "9g";
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
        minecraft-magic-vr-pack-image = magicVrPackImage system;
        magic-vr-pack-server = (pkgsFor system).magic-vr-pack-server;
        # Linux-only: the client embeds the server's quest book, and the
        # server's pinned JDK has no Darwin build.
        magic-vr-pack-client = (pkgsFor system).magic-vr-pack-client;
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

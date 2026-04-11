{ inputs
, ...
}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {

    # Restore xrdb alias removed from nixpkgs — home-manager's xresources module
    # still references pkgs.xrdb (via lib.getExe)
    xrdb = prev.xorg.xrdb;

    # Pin claude-code to nixpkgs-master — nixos-unstable often lags behind
    # and yanked versions (e.g. 2.1.88) cause build failures.
    inherit (final.master) claude-code claude-code-bin;

    # Disable direnv fish test on Darwin — fish test-fish target gets SIGKILL'd in macOS sandbox
    direnv = if prev.stdenv.hostPlatform.isDarwin
      then prev.direnv.overrideAttrs (_: { doCheck = false; })
      else prev.direnv;

    # Re-sign fish after build on Darwin.
    # Nix's fixup phase runs install_name_tool to rewrite library paths, which
    # invalidates the original code signature. Corporate AV tools then SIGKILL
    # any new fish process. Signing in postFixup (after all patching) produces a
    # valid ad-hoc signature over the final binary.
    fish = if prev.stdenv.hostPlatform.isDarwin
      then prev.fish.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          /usr/bin/codesign --force --sign - $out/bin/fish
        '';
      })
      else prev.fish;

    # Disable aiohttp tests to work around sandbox test failures
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (python-final: python-prev: {
        aiohttp = python-prev.aiohttp.overridePythonAttrs (oldAttrs: {
          doCheck = false;
        });
        # test_acceptScaling fails on macOS: TCP accept scaling differs from Linux
        twisted = python-prev.twisted.overridePythonAttrs (_: {
          doCheck = false;
        });
        django_4 = python-prev.django_4.overridePythonAttrs (oldAttrs: {
          doCheck = false;
        });
        inline-snapshot = python-prev.inline-snapshot.overridePythonAttrs (oldAttrs: {
          disabledTests = (oldAttrs.disabledTests or []) ++ [ "test_empty_sub_snapshot" ];
        });
        rich = python-prev.rich.overridePythonAttrs (oldAttrs: {
          disabledTests = (oldAttrs.disabledTests or []) ++ [ "test_brokenpipeerror" ];
        } // python-prev.lib.optionalAttrs python-prev.stdenv.hostPlatform.isAarch64 {
          doCheck = false;
        });
      })
    ];
  };

  # When applied, the stable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.stable'
  # stable-packages = final: _prev: {
  #   stable = import inputs.nixpkgs_stable {
  #     system = final.system;
  #     config.allowUnfree = true;
  #   };
  # };

  stable-packages = final: _prev: {
    stable = import inputs.nixpkgs_stable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs_unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  # When applied, the master nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.master'
  master-packages = final: _prev: {
    master = import inputs.nixpkgs_master {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  lqx-pin-packages = final: _prev: {
    lqx_pin = import inputs.nixpkgs_lqx_pin {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

  _1password = final: _prev: {
    _1password-gui = final.unstable._1password-gui;
    _1password-cli = final.unstable._1password-cli;
  };

  bluray-playback = final: _prev: {
    libbluray = _prev.libbluray.override {
      withAACS = true;
      withBDplus = true;
      withJava = true;
    };
  };

  # Use linux-firmware from unstable to fix amdxdna NPU firmware
  # (stable's fetchpatch strips binary blobs from the NPU firmware patch, resulting in 0-byte files)
  linux-firmware = final: _prev: {
    linux-firmware = final.unstable.linux-firmware;
  };

  tmux-sessionizer = final: _prev: {
    tmux-sessionizer = inputs.tmux-sessionizer.packages.${final.stdenv.hostPlatform.system}.default;
  };

  python3PackagesOverlay = final: prev: {
    python312Packages = prev.python312Packages // {
      s3transfer = inputs.nixpkgs_stable.legacyPackages.${final.stdenv.hostPlatform.system}.python312Packages.s3transfer;
    };
  };

  qtwebengine = final: prev: {
    libsForQt5 = prev.libsForQt5 // {
      qt5 = prev.libsForQt5.qt5 // {
        qtwebengine = inputs.nixpkgs_stable.legacyPackages.${final.stdenv.hostPlatform.system}.qtwebengine;
      };
    };
  };

  quirc = final: _prev: {
    quirc = _prev.quirc.overrideAttrs (oldAttrs: {
      postInstall = ''
        # don't install static library
        rm $out/lib/libquirc.a
      '';
    });
  };

  systemd = final: prev:
    let
      # Detect PR #40954 (birthDate field) at eval time to avoid unnecessary rebuilds.
      # Extract the version and hash from the nixpkgs systemd definition, then fetch
      # the source independently to check for birthDate without triggering recursion.
      nixpkgsSystemdDef = builtins.readFile (prev.path + "/pkgs/os-specific/linux/systemd/default.nix");
      versionMatch = builtins.match ''.*version = "([^"]+)".*'' nixpkgsSystemdDef;
      hashMatch = builtins.match ".*fetchFromGitHub [^}]*hash = \"([^\"]+)\".*" nixpkgsSystemdDef;
      systemdVersion = if versionMatch != null then builtins.elemAt versionMatch 0 else null;
      systemdHash = if hashMatch != null then builtins.elemAt hashMatch 0 else null;
      # Fetch the source using builtins only (no prev.* packages) to avoid recursion.
      # The SRI hash from fetchFromGitHub is compatible with builtins.fetchTarball.
      systemdSrc = if systemdVersion != null && systemdHash != null then
        builtins.fetchTarball {
          url = "https://github.com/systemd/systemd/archive/v${systemdVersion}.tar.gz";
          sha256 = systemdHash;
        }
      else null;
      srcHasBirthDate = systemdSrc != null
        && builtins.pathExists "${systemdSrc}/src/shared/user-record.c"
        && builtins.match ".*birthDate.*" (builtins.readFile "${systemdSrc}/src/shared/user-record.c") != null;
    in prev.lib.optionalAttrs srcHasBirthDate {
    systemd = prev.systemd.overrideAttrs (oldAttrs:
      let
        # Revert PR #40954: "userdb: add birthDate field to JSON user records"
        revertPatch1 = final.fetchpatch {
          url = "https://github.com/systemd/systemd/commit/7a858878a03966d2a65ef9e8f79b5caff352ac53.patch";
          hash = "sha256-JeJ+swYQx4WoYK/VBlRzu8xZH9R/9Py0qyp5RAXQJZQ=";
        };
        revertPatch2 = final.fetchpatch {
          url = "https://github.com/systemd/systemd/commit/770958e24a2ee59593aa6833a4a825db0a6abbbc.patch";
          hash = "sha256-GJjc4k7+r3A68lohnOjRRr800fIEpUdWXVjFpjmgXZA=";
        };
      in {
      prePatch = (oldAttrs.prePatch or "") + ''
        echo "Reverting PR #40954 (birthDate field)..."
        patch -R -p1 < ${revertPatch1}
        patch -R -p1 < ${revertPatch2}
      '';
    });
  };

  snapper = final: _prev: {
    snapper = _prev.snapper.overrideAttrs (oldAttrs: {
      buildInputs = oldAttrs.buildInputs ++ [ _prev.zlib ];
    });
  };

  zk = final: prev: {
    zk = prev.zk.overrideAttrs
      (oldAttrs: rec {
        version = "v0.14.2";
        vendorHash = "sha256-2PlaIw7NaW4pAVIituSVWhssSBKjowLOLuBV/wz829I=";

        src = prev.fetchFromGitHub {
          owner = "zk-org";
          repo = "zk";
          rev = version;
          hash = "sha256-h6qQcaAgxWeBzMjxGk7b8vrVu5NO/V6b/ZvZMWtZTpg=";
        };
      });
  };

  lsfg-vk = final: prev: {
    lsfg-vk-ui = final.stdenv.mkDerivation rec {
      pname = "lsfg-vk";
      version = "2.0-dev-unstable-2026-01-18";

      src = final.fetchFromGitHub {
        owner = "PancakeTAS";
        repo = "lsfg-vk";
        rev = "14904b9f3d78aea692bff0d330ce403ae0e74766";
        hash = "sha256-yF8GuclZ5WaFvQkXH6iJmUuj5cgFglh9Ttre/DrD5Yg=";
      };

      nativeBuildInputs = with final; [
        cmake
        pkg-config
        qt6.wrapQtAppsHook
      ];

      buildInputs = with final; [
        vulkan-headers
        vulkan-loader
        qt6.qtbase
        qt6.qtdeclarative
      ];

      cmakeFlags = [
        "-DLSFGVK_BUILD_UI=ON"
        "-DLSFGVK_BUILD_VK_LAYER=ON"
        "-DLSFGVK_BUILD_CLI=ON"
        "-DLSFGVK_INSTALL_XDG_FILES=ON"
      ];

      # Fix the Vulkan layer JSON to use absolute library path and add required functions
      postInstall = ''
        # Fix library path to absolute
        substituteInPlace $out/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json \
          --replace-fail '"library_path": "liblsfg-vk-layer.so"' '"library_path": "'$out'/lib/liblsfg-vk-layer.so"'

        # Add the functions section required by Vulkan loader
        substituteInPlace $out/share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json \
          --replace-fail '"disable_environment": {' '"functions": { "vkNegotiateLoaderLayerInterfaceVersion": "vkNegotiateLoaderLayerInterfaceVersion" }, "disable_environment": {'

        # Create symlink with old filename for NixOS module compatibility
        ln -s VkLayer_LSFGVK_frame_generation.json $out/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json
      '';

      meta = with final.lib; {
        description = "Linux Shader Function Generator for Vulkan - Version 2.0";
        homepage = "https://github.com/PancakeTAS/lsfg-vk";
        license = licenses.unfree; # Update if you know the actual license
        platforms = platforms.linux;
      };
    };
  };

  qbittorrent = final: prev: {
    qbittorrent = (prev.callPackage (prev.path + "/pkgs/by-name/qb/qbittorrent/package.nix") {
      guiSupport = false;
      boost = final.boost186;
      libtorrent-rasterbar = prev.libtorrent-rasterbar-2_0_x;
    }).overrideAttrs (oldAttrs: {
      version = "5.1.4";
      name = "qbittorrent-nox-5.1.4";

      src = prev.fetchFromGitHub {
        owner = "qbittorrent";
        repo = "qBittorrent";
        rev = "release-5.1.4";
        sha256 = "1zja55b97cnij3vffmfa5p65dasybbm1gd3xjspw5yyypy5cl5zm";
      };

      patches = [];
    });
  };
}

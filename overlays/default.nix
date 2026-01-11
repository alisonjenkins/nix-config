{ inputs
, system
, ...
}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
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

  _1password-gui = final: prev: {
    _1password-gui = prev._1password-gui.overrideAttrs (_old: {
      postFixup = ''
      wrapProgram $out/bin/1password --set ELECTRON_OZONE_PLATFORM_HINT x11
      '';
    });
  };

  bluray-playback = final: _prev: {
    libbluray = _prev.libbluray.override {
      withAACS = true;
      withBDplus = true;
      withJava = true;
    };
  };

  linux-firmware = final: _prev: {
    linux-firmware = _prev.linux-firmware.overrideAttrs (oldAttrs: {
      version = "20251223";

      src = _prev.fetchFromGitLab {
        owner = "kernel-firmware";
        repo = "linux-firmware";
        rev = "a6a6ff914b4b2814ffd074f1d0a9e43949ac44ad";
        hash = "sha256-O3QyEV5cYknk+1QHLLMpZjmLCdyb4MbLTHewmubleLA=";
      };
    });
  };

  tmux-sessionizer = final: _prev: {
    tmux-sessionizer = inputs.tmux-sessionizer.packages.${system}.default;
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
      version = "2.0-dev-unstable-2025-01-06";

      src = final.fetchFromGitHub {
        owner = "PancakeTAS";
        repo = "lsfg-vk";
        rev = "d0cec20d8a9029d9d290e088388ca2187c32ea10";
        hash = "sha256-/deQxj8KDGuKrRtf/ogoNnJXVACgaskBRiG53MxDfKg=";
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

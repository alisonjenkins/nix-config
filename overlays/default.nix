{ inputs
, system
, ...
}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; inputs = inputs; };

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
      system = final.system;
      config.allowUnfree = true;
    };
  };

  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs_unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };

  # When applied, the master nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.master'
  master-packages = final: _prev: {
    master = import inputs.nixpkgs_master {
      system = final.system;
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
      version = "20250829";

      src = _prev.fetchFromGitLab {
        owner = "kernel-firmware";
        repo = "linux-firmware";
        rev = "b611a67511d127842b097f57f02445d94e635b91";
        hash = "sha256-9fc444ljM2kJ9hFOF2gKuMrZO3UjMJ2peqal//qT2pY=";
      };
    });
  };

  tmux-sessionizer = final: _prev: {
    tmux-sessionizer = inputs.tmux-sessionizer.packages.${system}.default;
  };

  python3PackagesOverlay = final: prev: {
    python312Packages = prev.python312Packages // {
      s3transfer = inputs.nixpkgs_stable.legacyPackages.${final.system}.python312Packages.s3transfer;
    };
  };

  qtwebengine = final: prev: {
    libsForQt5 = prev.libsForQt5 // {
      qt5 = prev.libsForQt5.qt5 // {
        qtwebengine = inputs.nixpkgs_stable.legacyPackages.${final.system}.qtwebengine;
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
}

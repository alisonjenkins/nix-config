{ inputs
, system
, pkgs
, lib
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

  _7zz = final: _prev: {
    _7zz = inputs.nixpkgs_stable.legacyPackages.${final.system}._7zz;
  };

  bacon-nextest = final: prev: {
    bacon = prev.bacon.overrideAttrs (oldAttrs: rec {
      version = "nextest";

      src = pkgs.fetchFromGitHub {
        owner = "Canop";
        repo = "bacon";
        rev = "31685793ba294faf7a8ed7e8317b3b2f405f71e0";
        hash = "sha256-IJRCYjAyA5059mof1+D5vjxzsdCoQ08FIxq1DiwgBNU=";
      };

      # Overriding `cargoHash` has no effect; we must override the resultant
      # `cargoDeps` and set the hash in its `outputHash` attribute.
      cargoDeps = oldAttrs.cargoDeps.overrideAttrs (lib.const {
        name = "bacon-vendor.tar.gz";
        inherit src;
        outputHash = "sha256-msQaeunfeWzbeDGA4Vay/tbxvhcLrS9Rs3lHFyUhOKo=";
      });
    });
  };

  bluray-playback = final: _prev: {
    libbluray = _prev.libbluray.override {
      withAACS = true;
      withBDplus = true;
      withJava = true;
    };
  };

  # ffmpeg = final: _prev: {
  #   ffmpeg = inputs.nixpkgs_stable.legacyPackages.${final.system}.ffmpeg;
  # };

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
      buildInputs = oldAttrs.buildInputs ++ [ pkgs.zlib ];
    });
  };
}

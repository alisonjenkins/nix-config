{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs {pkgs = final;};

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

  bluray-playback = final: _prev: {
    libbluray = _prev.libbluray.override {
      withAACS = true;
      withBDplus = true;
      withJava = true;
    };
  };

  alvr-version = final: prev: {
    alvr = prev.rustPlatform.buildRustPackage rec {
      pname = "alvr";
      version = "20.8.1";
      cargoHash = prev.lib.fakeHash;

      buildInputs = with prev; [
        alsa-lib
        # ffmpeg_7-full
        # ffmpeg_7-full.dev
        libjack2
        libva.dev
        openssl
        pkg-config
      ];

      nativeBuildInputs = with prev; [
        alsa-lib
        # ffmpeg_7-full
        # ffmpeg_7-full.dev
        jack2
        libjack2
        libva.dev
        openssl
        pkg-config
      ];

      cargoLock = {
        lockFile = "${src}/Cargo.lock";
        outputHashes = {
          "openxr-0.17.1" = "sha256-fG/JEqQQwKP5aerANAt5OeYYDZxcvUKCCaVdWRqHBPU=";
          "settings-schema-0.2.0" = "sha256-luEdAKDTq76dMeo5kA+QDTHpRMFUg3n0qvyQ7DkId0k=";
        };
      };

      src = prev.fetchFromGitHub {
        owner = "alvr-org";
        repo = "ALVR";
        rev = "v${version}";
        hash = "sha256-HRXBagh6NClm0269ip0SlhOWCoI8CQXEtr7veSRgvwE=";
      };

      meta = with prev.lib; {
        description = "Stream VR games from your PC to your headset via Wi-Fi";
        homepage = "https://github.com/alvr-org/ALVR/";
        changelog = "https://github.com/alvr-org/ALVR/releases/tag/v${version}";
        license = licenses.mit;
        mainProgram = "alvr";
        maintainers = with maintainers; [ passivelemon ];
        platforms = [ "x86_64-linux" ];
      };
    };
  };
}

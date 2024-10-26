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

  # alvr = final: prev: {
  #   alvr = {
  #     lib,
  #     stdenv,
  #     fetchzip,
  #     fetchFromGitHub,
  #     alsa-lib,
  #     autoPatchelfHook,
  #     brotli,
  #     ffmpeg,
  #     libdrm,
  #     libGL,
  #     libunwind,
  #     libva,
  #     libvdpau,
  #     libxkbcommon,
  #     nix-update-script,
  #     openssl,
  #     pipewire,
  #     pulseaudio,
  #     vulkan-loader,
  #     wayland,
  #     x264,
  #     xorg,
  #     xvidcore,
  #   }:
  #     stdenv.mkDerivation (finalAttrs: {
  #       pname = "alvr";
  #       version = "20.9.1";
  #
  #       src = fetchzip {
  #         url = "https://github.com/alvr-org/ALVR/releases/download/v${finalAttrs.version}/alvr_streamer_linux.tar.gz";
  #         hash = "";
  #       };
  #
  #       alvrSrc = fetchFromGitHub {
  #         owner = "alvr-org";
  #         repo = "ALVR";
  #         rev = "v${finalAttrs.version}";
  #         hash = "";
  #       };
  #
  #       nativeBuildInputs = [
  #         autoPatchelfHook
  #       ];
  #
  #       buildInputs = [
  #         alsa-lib
  #         libunwind
  #         libva
  #         libvdpau
  #         vulkan-loader
  #       ];
  #
  #       runtimeDependencies = [
  #         brotli
  #         ffmpeg
  #         libdrm
  #         libGL
  #         libxkbcommon
  #         openssl
  #         pipewire
  #         pulseaudio
  #         wayland
  #         x264
  #         xorg.libX11
  #         xorg.libXcursor
  #         xorg.libxcb
  #         xorg.libXi
  #       ];
  #
  #       installPhase = ''
  #         runHook preInstall
  #
  #         mkdir -p $out/share/applications
  #         cp -r $src/* $out
  #         install -Dm444 $alvrSrc/alvr/xtask/resources/alvr.desktop -t $out/share/applications
  #         install -Dm444 $alvrSrc/resources/alvr.png -t $out/share/icons/hicolor/256x256/apps
  #
  #         runHook postInstall
  #       '';
  #
  #       passthru.updateScript = nix-update-script {};
  #
  #       meta = with lib; {
  #         description = "Stream VR games from your PC to your headset via Wi-Fi";
  #         homepage = "https://github.com/alvr-org/ALVR/";
  #         changelog = "https://github.com/alvr-org/ALVR/releases/tag/v${finalAttrs.version}";
  #         license = licenses.mit;
  #         maintainers = with maintainers; [passivelemon];
  #         platforms = platforms.linux;
  #         mainProgram = "alvr_dashboard";
  #       };
  #     });
  # };

  bluray-playback = final: _prev: {
    libbluray = _prev.libbluray.override {
      withAACS = true;
      withBDplus = true;
      withJava = true;
    };
  };

  tmux-sessionizer = final: _prev: {
    tmux-sessionizer = inputs.tmux-sessionizer.packages.${system}.default;
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

{ config, lib, pkgs, ... }:
let
  cfg = config.modules.desktop-greetd-regreet;

  stateDir = "/var/lib/regreet";
  backgroundLink = "${stateDir}/background";

  # 1080p HEVC SDR cuts from Apple's tvOS/macOS aerial catalogue
  # (resources-15.tar entries.json, url-1080-SDR), about 170 MB each.
  videoBaseUrl = "https://sylvan.apple.com/Aerials/2x/Videos";
  videos = {
    tahiti-waves = {
      file = "g201_TH_803_A001_8_SDR_20191031_SDR_2K_HEVC.mov";
      hash = "sha256-kKh9TIiypbvgov3s1FHXqEzpahhR6iLjCcBrJiNku8M=";
    };
    yosemite = {
      file = "Y004_C015_SDR_2K_HEVC.mov";
      hash = "sha256-M3MmY0kNPwL+bFu8uIzrN24easuMTGUfxQzjuVp0fHY=";
    };
    new-york-night = {
      file = "comp_GMT307_136NC_134K_8277_NY_NIGHT_01_v25_SDR_PS_20180907_SDR_2K_HEVC.mov";
      hash = "sha256-AszWslIBcT7N0MsLQhJ22f8sPZ4w53UG3wbk43dRcrg=";
    };
    north-america-aurora = {
      file = "comp_GMT314_139M_170NC_NORTH_AMERICA_AURORA__COMP_v22_SDR_20181206_v12CC_SDR_2K_HEVC.mov";
      hash = "sha256-XA4Erfsuv0xkMACd5VSFMvS2Ed/sxbwqIz0ILOuLNF8=";
    };
  };
  video = videos.${cfg.video.name};

  # sylvan.apple.com chains to Apple's own root, which is not in the Mozilla
  # bundle, so trust exactly this root for the video download and nothing else.
  appleRootCa = pkgs.runCommand "apple-root-ca.pem"
    {
      nativeBuildInputs = [ pkgs.openssl ];
      src = pkgs.fetchurl {
        url = "https://www.apple.com/appleca/AppleIncRootCertificate.cer";
        hash = "sha256-sLFzDsvH/0UFFCxJ8Slebtpryu1+LGjFvpG1oRAB8CQ=";
      };
    }
    "openssl x509 -inform DER -in $src -out $out";

  fallbackImage = config.stylix.image or null;

  # 0.4.0 added video/animated backgrounds through GStreamer and 0.5.0 fixed
  # its idle load on static images; the release channel has 0.3.0.
  # ali-mba-linux has no unstable overlay, so it keeps the channel's.
  regreetPkgs = pkgs.unstable or pkgs;

  # The nixpkgs wrapper carries gst-plugins-good/base only; nothing in them
  # decodes the aerials' H.265. gst-libav comes from the same set as regreet's
  # own GStreamer so the plugin ABI matches.
  regreetWithHevc = pkgs.symlinkJoin {
    name = "${regreetPkgs.regreet.name}-hevc";
    inherit (regreetPkgs.regreet) version;
    paths = [ regreetPkgs.regreet ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/regreet \
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${regreetPkgs.gst_all_1.gst-libav}/lib/gstreamer-1.0
    '';
    meta.mainProgram = "regreet";
  };

  backgroundTool = pkgs.writeShellApplication {
    name = "regreet-background";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.findutils pkgs.openssl ];
    text = ''
      target=${stateDir}/${video.file}

      point_link() {
        ln -sfn "$1" ${backgroundLink}.tmp
        mv -T ${backgroundLink}.tmp ${backgroundLink}
      }

      case "''${1:-}" in
        link)
          if [ -f "$target" ]; then
            point_link "$target"
          ${lib.optionalString (fallbackImage != null) ''
          else
            point_link ${fallbackImage}
          ''}fi
          ;;
        fetch)
          if [ ! -f "$target" ]; then
            rm -f "$target.part"
            curl --fail --silent --show-error --location \
              --retry 5 --retry-all-errors --cacert ${appleRootCa} \
              --output "$target.part" ${videoBaseUrl}/${video.file}
            got="sha256-$(openssl dgst -sha256 -binary "$target.part" | base64)"
            if [ "$got" != "${video.hash}" ]; then
              rm -f "$target.part"
              echo "hash mismatch for ${video.file}: got $got, want ${video.hash}" >&2
              exit 1
            fi
            mv "$target.part" "$target"
          fi
          point_link "$target"
          find ${stateDir} -maxdepth 1 -name '*.mov' ! -name '${video.file}' -delete
          ;;
        *)
          echo "usage: regreet-background link|fetch" >&2
          exit 2
          ;;
      esac
    '';
  };

  backgroundService = mode: {
    Type = "oneshot";
    User = "greeter";
    Group = "greeter";
    ExecStart = "${lib.getExe backgroundTool} ${mode}";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ stateDir ];
    ProtectHome = true;
  };
in
{
  options.modules.desktop-greetd-regreet = {
    enable = lib.mkEnableOption "greetd display manager with regreet GUI";

    video = {
      enable = lib.mkEnableOption ''
        an Apple aerial video behind the login screen, downloaded once at
        runtime into ${stateDir} (not the Nix store; Apple's licence on the
        videos is unclear, so they stay out of the binary cache). The stylix
        wallpaper shows until the download finishes
      '';

      name = lib.mkOption {
        type = lib.types.enum (builtins.attrNames videos);
        default = "tahiti-waves";
        description = "Which aerial to play.";
      };
    };
  };

  # Drop one stylix warning, which is a false positive here.
  #
  # stylix/modules/regreet/nixos.nix warns whenever
  # services.greetd.settings.default_session.command differs at all from
  # nixpkgs' default, `dbus-run-session cage <cageArgs> -- regreet`. Dropping
  # dbus-run-session is the entire point of the override below, so the warning
  # fires by construction and cannot be satisfied without reintroducing the
  # ~25s greeter delay.
  #
  # Theming is unaffected either way: stylix applies it through
  # programs.regreet.* — adw-gtk3, GTK css generated from the scheme, the dark
  # preference and the wallpaper — never through the greetd command. Disabling
  # the target would silence the warning and lose all of that, so filter the
  # message instead.
  #
  # `apply` transforms the merged list rather than reading config.warnings from
  # a definition, which is what would recurse. It matches the full message
  # prefix so a different regreet warning would still surface, and if stylix
  # rewords this one the filter stops matching and the warning comes back —
  # both failure modes are safe.
  options.warnings = lib.mkOption {
    apply = builtins.filter (
      warning:
      !lib.hasPrefix
        "stylix: regreet: custom services.greetd.settings.default_session.command"
        warning
    );
  };

  config = lib.mkIf cfg.enable {
    services = {
      greetd = {
        enable = true;

        # Don't use dbus-run-session (the NixOS module default). It creates a
        # private session bus where xdg-desktop-portal auto-activates and
        # blocks ~25s waiting for org.freedesktop.secrets. gnome-keyring can't
        # start because the greeter's home (/var/empty) is read-only, so D-Bus
        # waits the full timeout before the greeter appears.
        settings.default_session.command = let
          cage = lib.getExe pkgs.cage;
          regreet = lib.getExe config.programs.regreet.package;
        in lib.mkForce "${pkgs.bash}/bin/bash -c 'exec ${cage} -s -- ${regreet} 2>/dev/null'";
      };
    };

    programs = {
      regreet = {
        enable = true;

        package = lib.mkDefault (
          if cfg.video.enable then regreetWithHevc else regreetPkgs.regreet
        );

        settings = lib.optionalAttrs cfg.video.enable {
          background = {
            path = lib.mkForce backgroundLink;
            fit = lib.mkForce "Cover";
          };
        };
      };
    };

    systemd.services = lib.mkIf cfg.video.enable {
      # Runs before the greeter so a cached video is linked in time; the
      # download itself must never hold up login.
      regreet-background-link = {
        description = "Point the regreet background at the cached video";
        wantedBy = [ "greetd.service" ];
        before = [ "greetd.service" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = backgroundService "link" // { RemainAfterExit = true; };
      };

      regreet-background-fetch = {
        description = "Download the regreet background video";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" "regreet-background-link.service" ];
        unitConfig.StartLimitIntervalSec = 0;
        # exec, not oneshot: a oneshot start job blocks switch and
        # multi-user.target until the download (and every 5min retry) is done.
        serviceConfig = backgroundService "fetch" // {
          Type = "exec";
          Restart = "on-failure";
          RestartSec = "5min";
        };
      };
    };

    security.pam.services.greetd.kwallet.enable = true;

    environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
      lib.mkIf config.modules.base.enableImpermanence [
        {
          directory = "/var/lib/regreet";
          user = "greeter";
          group = "greeter";
          mode = "u=rwx,g=rx,o=";
        }
      ];
  };
}

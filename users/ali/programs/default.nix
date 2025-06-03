args@{ self, lib, pkgs, pkgs-stable, config, inputs, ... }:
(lib.mapAttrs (_: expr: if lib.isFunction expr then expr args else expr)
(lib.importDir' ./. "default.nix")) // {
    anydesk = { home.packages = [ pkgs.anydesk ]; };
    apostrophe = { home.packages = [ pkgs.apostrophe ]; };
    chromium = { programs.chromium.enable = true; };
    cura = { home.packages = [ pkgs.cura ]; };
    ffmpeg = { home.packages = [ pkgs.ffmpeg ]; };
    filezilla = { home.packages = [ pkgs.filezilla ]; };
    fzf = { programs.fzf.enable = true; };
    gallery-dl = { home.packages = [ pkgs.gallery-dl ]; };
    gimp = { home.packages = [ pkgs.gimp ]; };
    helix = { programs.helix.enable = true; };
    jellyfin = { home.packages = [ pkgs.jellyfin ]; };
    jq = { programs.jq.enable = true; };
    kdenlive = { home.packages = [ pkgs.libsForQt5.kdenlive ]; };
    lapce = { home.packages = [ pkgs.lapce ]; };
    libreoffice = { home.packages = [ pkgs.libreoffice-qt ]; };
    lsd = { programs.lsd.enable = true; };
    mailspring = { home.packages = [ pkgs.mailspring ]; };
    matrix = { home.packages = [ pkgs.libsForQt5.neochat ]; };
    mattermost = { home.packages = [ pkgs.mattermost-desktop ]; };
    neofetch = { home.packages = [ pkgs.neofetch ]; };
    nix-index = { programs.nix-index.enable = true; };
    nushell = { programs.nushell.enable = true; };
    onlyoffice = { home.packages = [ pkgs.onlyoffice-bin ]; };
    openscad = { home.packages = [ pkgs.openscad ]; };
    pinta = { home.packages = [ pkgs.pinta ]; };
    prusa-slicer = { home.packages = [ pkgs.prusa-slicer ]; };
    qbittorrent = { home.packages = [ pkgs.qbittorrent ]; };
    remmina = { home.packages = [ pkgs.remmina ]; };
    rustdesk = { home.packages = [ pkgs.rustdesk ]; };
    shotcut = { home.packages = [ pkgs.shotcut ]; };
    super-slicer = { home.packages = [ pkgs.super-slicer-latest ]; };
    telegram = { home.packages = [ pkgs.tdesktop ]; };
    tidal = { home.packages = [ pkgs.tidal-hifi ]; };
    transmission = { home.packages = [ pkgs.transmission-qt ]; };
    virt-manager = { home.packages = [ pkgs.virt-manager ]; };

    bat = {
      programs.bat.enable = true;
      programs.bat.config.theme = "gruvbox-dark";
    };

    handbrake = {
      home.packages = [ pkgs-stable.handbrake ];
    };

    hexchat = {
      programs.hexchat = {
        enable = true;
        # overwriteConfigFiles = true;
        theme = pkgs.fetchzip {
          url = "https://dl.hexchat.net/themes/Monokai.hct#Monokai.zip";
          sha256 = "sha256-WCdgEr8PwKSZvBMs0fN7E2gOjNM0c2DscZGSKSmdID0=";
          stripRoot = false;
        };
      };
    };

    keepassxc = {
      imports = [ self.homeManagerModules.keepassxc ];

      programs.keepassxc = {
        enable = true;

        # KeePassXC doesn't play nice with
        # custom Qt themes, and default looks great.
        package = (pkgs.symlinkJoin {
          inherit (pkgs.keepassxc) name pname version meta;
          paths = [ pkgs.keepassxc ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
          wrapProgram $out/bin/keepassxc \
          --set QT_QPA_PLATFORMTHEME ""
          '';
        });

        settings = {
          General = {
            ConfigVersion = 2;
            UseAtomicSaves = true;
          };
          Browser = {
            Enabled = true;
            SearchInAllDatabases = true;
          };
          FdoSecrets = { Enabled = true; };
          GUI = {
            ApplicationTheme = "dark";
            ColorPasswords = true;
            MinimizeOnClose = true;
            MinimizeOnStartup = true;
            MinimizeToTray = true;
            MonospaceNotes = true;
            ShowTrayIcon = true;
            TrayIconAppearance = "monochrome-light";
          };
          PasswordGenerator = {
            AdditionalChars = "";
            ExcludedChars = "";
            Length = 22;
          };
          Security = let minutes = s: builtins.floor (s * 60);
          in {
            ClearClipboardTimeout = minutes 0.75;
            EnableCopyOnDoubleClick = true;
            IconDownloadFallback = true;
            LockDatabaseIdle = true;
            LockDatabaseIdleSeconds = minutes 10;
          };
        };

        browserIntegration.firefox = true;
      };
    };

    moonlight = {
      home.packages = [
        (pkgs.moonlight-qt.overrideAttrs (self: super: {
          buildInputs = super.buildInputs ++ [ pkgs.libva1 ];
        }))
      ];
    };

    neovim = {
      programs.neovim.enable = true;
      home.packages = [ pkgs.neovide ];
    };

    nix = {
      # TODO fix overlay for this flake
      home.packages =
        [ inputs.nixfmt.packages.${pkgs.hostPlatform.system}.nixfmt ];
      };

      java = let
      # IntelliJ likes to see a `~/.jdks` directory,
      # so we will use that convention for now.
      homeJdksDir = ".jdks";
      defaultJdk = pkgs.temurin-bin;
      in {
        home.sessionPath = [
          "${config.home.homeDirectory}/${homeJdksDir}/${defaultJdk.name}/bin"
        ];
      # Notice below, that each JDK source *is* the `home` of that JDK.
      home.sessionVariables.JAVA_HOME =
        "${config.home.homeDirectory}/${homeJdksDir}/${defaultJdk.name}";

        home.file = builtins.listToAttrs (map (package: {
          name = "${homeJdksDir}/${package.name}";
        # I think this should work because binaries are ELF-patched.
        value = { source = "${package.home}"; };
      }) [
        defaultJdk
        pkgs.jdk8
        pkgs.jdk11
        pkgs.jdk17
        pkgs.jdk # latest
        pkgs.temurin-bin-8
        pkgs.temurin-bin-11
        pkgs.temurin-bin-16
        pkgs.temurin-bin-17
        pkgs.temurin-bin-18
        pkgs.temurin-bin # latest
      ]);
    };

    obs-studio = {
      programs.obs-studio.enable = true;
      programs.obs-studio.plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-move-transition
        obs-backgroundremoval
      ];
      home.packages = [ pkgs.slurp ];
    };

    prism-launcher = let
      # Pre-launch command
      #   test -f '$INST_MC_DIR/options.txt' && sed -i 's/fullscreen:true/fullscreen:false/' '$INST_MC_DIR/options.txt' || exit 0
      # Wrapper command
      #   export force_glsl_extensions_warn=true
      #   run-game "$@"
      prismlauncher' = pkgs.prismlauncher-qt5.override {
        withWaylandGLFW = true;
        jdks = with pkgs; [
          graalvm-ce
          graalvm8-ce-jre
          temurin-jre-bin
          temurin-jre-bin-11
          temurin-jre-bin-8
          temurin20-jre-bin
          zulu
          zulu8
        ];
      };
    in { home.packages = [ prismlauncher' ]; };

    steam = {
      imports = [ self.homeManagerModules.steam ];
      home.packages = [ pkgs.steam-tui pkgs.gamescope ];
      programs.steam.protonGE.versions = {
        "7-55" = "sha256-6CL+9X4HBNoB/yUMIjA933XlSjE6eJC86RmwiJD6+Ws=";
        "8-25" = "sha256-IoClZ6hl2lsz9OGfFgnz7vEAGlSY2+1K2lDEEsJQOfU=";
      };
    };

    thunderbird = {
      programs.thunderbird = {
        enable = true;

        settings = {
          # "app.donation.eoy.version.viewed" = 1;
          "mail.openpgp.allow_external_gnupg" = false;
        };

        profiles."ali.default" = {
          isDefault = true;
          # name = "ali-default";
        };
      };
    };

    rust = {
      home.file.".cargo/config.toml".source =
        (pkgs.formats.toml { }).generate "cargo-config" {
          "target.x86_64-unknown-linux-gnu" = {
            linker = lib.getExe pkgs.clang;
            rustFlags =
              [ "-C" "link-arg=--ld-path=${lib.makeBinPath [ pkgs.mold ]}" ];
            };
          };
        };

    zsh = {
      imports = [ ./zsh.nix ];
      programs.zsh.alt.enable = true;
    };
  }


{ inputs, self, ... }:
let
  inherit (self) outputs;
  username = "ajenkins";
  darwinSystem = "aarch64-darwin";

  darwinPkgs = import inputs.nixpkgs {
    system = darwinSystem;

    config = {
      allowUnfree = true;

      # context7-mcp (pkgs.master.context7-mcp, wired into the claude-code +
      # opencode home configs) builds with pnpm 10.29.2, which nixpkgs marked
      # insecure (CVE-2026-48995 et al). pnpm is a build-time-only tool for
      # assembling node_modules — never in the system runtime closure or PATH —
      # so the CVEs don't affect the running system. Mirrors the same permit in
      # modules/base for NixOS hosts.
      #
      # REMOVE once nixpkgs ships a non-flagged pnpm. Re-check after flake
      # updates: `nix-store -q --requisites <toplevel.drv> | grep pnpm`.
      permittedInsecurePackages = [ "pnpm-10.29.2" ];
    };

    overlays = [
        self.overlays.additions
        self.overlays.modifications
        self.overlays.lqx-pin-packages
        self.overlays.master-packages
        self.overlays.unstable-packages
        self.overlays.tmux-sessionizer
        self.overlays.zk
        inputs.nur.overlays.default
        inputs.fenix.overlays.default
        (self: super: {
          nodejs = super.unstable.nodejs;
          # yarn-berry 4.11.0 builds via `yarn workspace @yarnpkg/cli
          # build:cli` → esbuild-wasm --service which hangs indefinitely
          # in the nix sandbox on aarch64-darwin. cache.nixos.org only
          # has yarn-berry built against nixpkgs's default nodejs_22, so
          # pin yarn-berry's nodejs to nodejs_22 to hit the cache and
          # avoid the local rebuild + hang.
          yarn-berry = super.yarn-berry.override {
            nodejs = super.nodejs_22;
            yarn = super.yarn.override { nodejs = super.nodejs_22; };
          };
        })
      ];
  };

  commonArgs = {
    inherit inputs outputs;
    pkgs = darwinPkgs;
    inherit username;
  };

  hostnames = {
    civica = "Alisons-MacBook-Pro";
  };
in {
  flake.darwinConfigurations."${hostnames.civica}" = inputs.darwin.lib.darwinSystem {
    system = darwinSystem;
    modules = [
      self.darwinModules.darwin-nix-maintenance
      # Host-specific configuration (inlined from configuration.nix)
      ({ pkgs, inputs, username, hostname, ... }: {
        environment = {
          systemPackages = with pkgs; [
            (pkgs.azure-cli.withExtensions (with azure-cli-extensions; [ azure-devops ]))
            (pkgs.python3.withPackages (ps: with ps; [ boto3 pyyaml requests ]))
            alacritty
            unstable.aws-sam-cli
            aws-vault
            awscli2
            bacon
            bat
            btop
            cacert
            cachix
            cargo-chef
            cargo-component
            cargo-lambda
            cargo-machete
            cargo-make
            cargo-tarpaulin
            cargo-watch
            choose-gui
            # colima  # Moved to homebrew to avoid EOL lima dependency
            comma
            cowsay
            cyberduck
            dbeaver-bin
            direnv
            diskus
            dive
            docker
            docker-credential-helpers
            drawio
            dua
            element-desktop
            fd
            figlet
            flameshot
            fluxcd
            fzf
            gama-tui
            gephi
            gh
            github-copilot-cli
            gitify
            gitui
            glow
            gnupg
            go
            goreleaser
            graphviz
            htop
            hurl
            inkscape
            inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
            # inputs.eks-creds.packages.${pkgs.stdenv.hostPlatform.system}.eks-creds
            ipcalc
            isort
            jdk
            jq
            json2hcl
            jujutsu
            just
            kind
            kubecm
            kubectl
            kubectx
            kubernetes-helm
            lazydocker
            libffi
            libiconv
            lnav
            lolcat
            luajitPackages.lpeg
            mitmproxy
            mitmproxy2swagger
            mustache-go
            neovide
            nix-fast-build
            nodejs
            nushell
            obsidian
            openconnect
            openssl
            oxker
            packer
            parallel
            pass
            pcre2
            pgcli
            pinentry_mac
            pkg-config
            posting
            powershell
            pup
            pwgen
            rectangle
            rio
            ripgrep
            rlwrap
            selene
            skopeo
            ssm-session-manager-plugin
            statix
            tealdeer
            tektoncd-cli
            terraform-docs
            terragrunt
            tflint
            tig
            tilt
            tmux
            typst
            typst-live
            unstable.delve
            unstable.devenv
            unstable.opentofu
            unstable.prek
            unstable.teamtype
            unstable.terraform
            vagrant
            vscodium
            watch
            watchexec
            wget
            yazi
            zk
            zoxide

            # Use fenix for cross-compilation targets (without docs to avoid memory issues)
            # rustc
            # cargo
            # rust-analyzer
            (fenix.combine ([
              fenix.stable.minimalToolchain
              fenix.stable.rust-src
            ] ++ map (t: fenix.targets.${t}.stable.rust-std) [
              "aarch64-unknown-linux-gnu"
              "aarch64-unknown-linux-musl"
              "wasm32-unknown-unknown"
              # "x86_64-pc-windows-msvc"  # Removed: requires old Apple SDK that's been removed from nixpkgs
              "x86_64-unknown-linux-gnu"
              "x86_64-unknown-linux-musl"
            ]))
          ];

          variables = {
            # Datadog org lives on the US3 site; pup defaults to US1
            # (datadoghq.com), which breaks OAuth token exchange
            # (invalid_grant). Pin the site for pup + other DD tooling.
            DD_SITE = "us3.datadoghq.com";
            JAVA_HOME = ''${pkgs.jdk}'';
            PATH = ''${pkgs.jdk}/bin:$PATH'';
            ZK_NOTEBOOK_DIR = "$HOME/git/zettelkasten";
          };
        };

        fonts = {
          packages = with pkgs; [
            nerd-fonts.fira-code
            nerd-fonts.hack
            nerd-fonts.jetbrains-mono
            recursive
          ];
        };

        homebrew = {
          enable = true;

          brews = [
            "colima"  # Container runtime using lima
            "fish"    # Homebrew fish is Developer ID signed + notarized; Defender trusts it
                      # The Nix fish binary gets SIGKILL'd by Defender after each rebuild.
                      # All ~/.config/fish/ config (tide, plugins, conf.d) works with either binary.
            "lima"
          ];

          # https://medium.com/rahasak/switching-from-docker-desktop-to-podman-on-macos-m1-m2-arm64-cpu-7752c02453ec
          casks = [
            "1password"
            "1password-cli"
            "alfred"
            "amethyst"
            "apache-directory-studio"
            "audacity"
            "discord"
            "firefox"
            "freeplane"
            "ghostty"
            "gimp"
            "github"
            "google-chrome"
            "hammerspoon"
            "jordanbaird-ice"
            "karabiner-elements"
            "keybase"
            "krita"
            "microsoft-auto-update"
            "microsoft-azure-storage-explorer"
            "microsoft-outlook"
            "microsoft-teams"
            "notion"
            "obs"
            "scribus"
            "slack"
            "soundsource"
            "uhk-agent"
            "utm"
            "windows-app"
            "yed"
            "yubico-authenticator"
            "zen"
            "zoom"
            # "todoist"
          ];

          onActivation = {
            autoUpdate = true;
            cleanup = "uninstall";
            upgrade = true;
            # Newer `brew bundle --cleanup` refuses to uninstall non-interactively
            # without one of --force / --force-cleanup / $HOMEBREW_ASK.
            extraFlags = [ "--force" ];
          };
        };

        networking = {
          hostName = hostname;
          localHostName = hostname;
        };


        nix = {
          enable = true;
          distributedBuilds = true;
          #package = pkgs.nixVersions.stable;

          #channel = {
            #enable = true;
          #};

          # GC / optimise / free-space settings live in
          # self.darwinModules.darwin-nix-maintenance.

          # run: "nix run 'nixpkgs#darwin.linux-builder'" before enabling
          # linux-builder = {
          #   enable = true;
          #   ephemeral = false;
          #   maxJobs = 4;
          #   package = pkgs.darwin.linux-builder;
          #
          #   config = {
          #     virtualisation = {
          #       darwin-builder = {
          #         diskSize = 200 * 1024;
          #         memorySize = 8 * 1024;
          #       };
          #       cores = 8;
          #     };
          #   };
          # };

          settings = {
            builders = "ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 11 - - - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";
            builders-use-substitutes = true;
            download-buffer-size = 256 * 1024 * 1024; # 256 MiB — prevents buffer-full warnings on large fetches
            experimental-features = "nix-command flakes";
            extra-trusted-users = "${username}";
            extra-platforms = "x86_64-linux";
            substituters = [
              "https://cache.nixcache.org"
              "https://cache.nixos.org"
              "https://nix-community.cachix.org"
              "https://fenix.cachix.org"
              "https://cache.flox.dev"  # Additional macOS/Darwin binaries
              "https://nix-darwin.cachix.org"  # nix-darwin builds
              "https://devenv.cachix.org"  # devenv (used in your config)
              "https://deploy-rs.cachix.org"  # deploy-rs (used for remote deployments)
              "https://crane.cachix.org"  # Rust builds (you have 7 cargo- packages)
              "https://numtide.cachix.org"  # devshell, treefmt, and other dev tools
              "https://hercules-ci.cachix.org"  # flake-parts and CI tools
            ];
            trusted-public-keys = [
              "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "fenix.cachix.org-1:ecJhr+RdYEdcVgUkjruiYhjbBloIEGov7bos90cZi0Q="
              "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
              "nix-darwin.cachix.org-1:n7gkud0jAyzI+nqLlfCq6tpMGpz3Q8L4wQsz14b2cDo="
              "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
              "deploy-rs.cachix.org-1:xfNobmiwF/vzvK1gpfediPwpdIP0rpDFikKp5dGG7NA="
              "crane.cachix.org-1:8Sw/sLmpKfTpXEd/ZEAxGHH2g6p5g+xOYnlz8+3nNQY="
              "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
              "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
            ];
          };
        };

        programs = {
          zsh.enable = true;
        };

        security = {
          pam.services.sudo_local = {
            enable = true;
            reattach = true;
            touchIdAuth = true;
          };

          # Lets the Hammerspoon menu-bar sleep-toggle flip pmset without prompting.
          sudo.extraConfig = ''
            ${username} ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
          '';
        };

        services = {
          # karabiner-elements.enable = true;
        };

        system = {
          stateVersion = 4;

          primaryUser = "ajenkins";

          startup.chime = false;

          defaults = {
            dock = {
              autohide = true;
              show-process-indicators = false;
              show-recents = false;
              static-only = true;
            };

            finder = {
              AppleShowAllExtensions = true;
              ShowPathbar = true;
              FXEnableExtensionChangeWarning = false;
            };

            # Tab between form controls and F-row that behaves as F1-F12
            NSGlobalDomain = {
              AppleKeyboardUIMode = 3;
              "com.apple.keyboard.fnState" = true;
            };
          };
        };

        ids.gids.nixbld = 350;

        users.users.${username} = {
          name = username;
          home = "/Users/${username}";
        };
      })

      inputs.home-manager.darwinModules.home-manager
      {
        # Use timestamp-based backups to prevent conflicts
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${username} = self.homeModules.home-macos;
        home-manager.extraSpecialArgs = commonArgs // {
          gitEmail = "alison.jenkins@civica.com";
          gitGPGSigningKey = "~/.ssh/id_civica.pub";
          gitUserName = "Alison Jenkins";
          github_clone_ssh_host_personal = "pgithub.com";
          github_clone_ssh_host_work = "github.com";
          hostname = "${hostnames.civica}";
          # No local llama endpoint on this host — opencode falls back to
          # its built-in github-copilot provider.
          opencodeLocalLLM = false;
          primarySSHKey = "~/.ssh/id_civica.pub";
          azureDevopsRsaKey = "~/.ssh/id_civica_rsa.pub";
        };
      }
    ];
    specialArgs = commonArgs // {
      hostname = "${hostnames.civica}";
    };
  };
}

{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  username = "ali";
  darwinSystem = "aarch64-darwin";

  darwinPkgs = import inputs.nixpkgs {
    system = darwinSystem;

    config = {
      allowUnfree = true;
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

  hostname = "ali-mba";
in {
  flake.darwinConfigurations.ali-mba = inputs.darwin.lib.darwinSystem {
    system = darwinSystem;
    modules = [
      # Host-specific configuration (inlined from configuration.nix)
      ({ pkgs, inputs, outputs, username, hostname, ... }: {
        environment = {
          systemPackages = with pkgs; [
            (pkgs.azure-cli.withExtensions (with azure-cli-extensions; [ azure-devops ]))
            (pkgs.python3.withPackages (ps: with ps; [ boto3 pyyaml requests ]))
            alacritty
            antigravity
            unstable.aws-sam-cli
            aws-vault
            awscli2
            bacon
            bat
            btop
            cacert
            cachix
            eden
            ryubing
            cargo-chef
            cargo-component
            cargo-lambda
            cargo-machete
            cargo-make
            cargo-tarpaulin
            cargo-watch
            # colima  # Moved to homebrew to avoid EOL lima dependency
            comma
            cowsay
            direnv
            diskus
            dive
            docker
            docker-credential-helpers
            drawio
            dua
            fd
            figlet
            fluxcd
            fzf
            gama-tui
            gh
            gitify
            gitui
            glow
            gnupg
            go
            goreleaser
            graphviz
            htop
            hurl
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
            prismlauncher
            pwgen
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
            unstable.checkov
            unstable.delve
            unstable.devenv
            unstable.opentofu
            unstable.prek
            unstable.teamtype
            unstable.terraform
            vagrant
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
            JAVA_HOME = ''${pkgs.jdk}'';
            PATH = ''${pkgs.jdk}/bin:$PATH'';
            ZK_NOTEBOOK_DIR = "$HOME/git/zettelkasten";
          };

          # Register Nix-built fish in /etc/shells so `chsh -s $(which fish)`
          # works if the user ever wants to switch login shells. Login shell
          # currently stays /bin/zsh; fish is launched by the terminal app,
          # which already prefers Nix fish via PATH. Listing it avoids
          # surprises and matches the homebrew-removal note above.
          shells = [ pkgs.fish ];
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
            "choose-gui"
            "colima"  # Container runtime using lima
            # Homebrew fish dropped: tide spawns a subshell via `status fish-path`
            # of the running fish, and when Homebrew bumps fish (e.g. 4.6.0 →
            # 4.7.0) the old Cellar path disappears mid-session and tide errors
            # `command not found` on every prompt repaint. Nix fish at
            # /etc/profiles/per-user/ali/bin/fish (via home-manager
            # programs.fish.enable) is stable across rebuilds. If Defender ever
            # SIGKILLs Nix fish again, re-add this brew and exclude the Nix
            # fish binary in the Defender allowlist instead.
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
            "cyberduck"
            "dbeaver-community"
            "discord"
            "element"
            "firefox"
            "flameshot"
            "freeplane"
            "gephi"
            "ghostty"
            "gimp"
            "github"
            "google-chrome"
            "hammerspoon"
            "inkscape"
            "jordanbaird-ice"
            "karabiner-elements"
            "keybase"
            "krita"
            "notion"
            "obs"
            "ollama-app"
            "powershell@preview"
            "rectangle"
            "scribus"
            "slack"
            "soundsource"
            "steam"
            "uhk-agent"
            "utm"
            "whisky"
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

          taps = [
            "nikitabobko/tap"
          ];
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

          #gc = {
            #automatic = true;
          #};

          linux-builder = {
            enable = true;
            ephemeral = false;
            maxJobs = 4;
            # Outer claim — both arches reachable via this builder.
            # Inner binfmt below provides x86_64 emulation; aarch64 is native.
            systems = [ "aarch64-linux" "x86_64-linux" ];

            config = {
              # The `systems` option above only sets the outer
              # buildMachines declaration — qemu binfmt inside the VM
              # has to be configured explicitly to actually run x86_64
              # derivations.
              boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

              virtualisation = {
                darwin-builder = {
                  diskSize = 200 * 1024;
                  # 12 GB so multi-mod Minecraft / 700 MB OCI tree builds don't OOM.
                  memorySize = 12 * 1024;
                };
                cores = 8;
              };
            };
          };

          # optimise = {
          #   enable = true;
          # };

          settings = {
            # nix.linux-builder auto-populates `builders` and `extra-platforms`,
            # so we only set the rest of nix.conf here.
            builders-use-substitutes = true;
            download-buffer-size = 256 * 1024 * 1024; # 256 MiB — prevents buffer-full warnings on large fetches
            experimental-features = "nix-command flakes";
            extra-trusted-users = "${username}";
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
          tailscale.enable = true;
        };

        system = {
          stateVersion = 4;

          primaryUser = "ali";

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

      inputs.sops-nix.darwinModules.sops
      self.darwinModules.niks3-cache-push
      ({ config, ... }: {
        sops = {
          age.keyFile = "/var/lib/sops-nix/key.txt";
          age.sshKeyPaths = [ ];
          gnupg.sshKeyPaths = [ ];
          secrets.niks3-token = {
            sopsFile = self + "/secrets/niks3-token.enc.yaml";
            key = "niks3_token";
          };
        };

        modules.niks3CachePush = {
          enable = true;
          authTokenFile = config.sops.secrets.niks3-token.path;
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
          gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
          gitGPGSigningKey = "~/.ssh/id_personal.pub";
          gitUserName = "Alison Jenkins";
          github_clone_ssh_host_personal = "github.com";
          github_clone_ssh_host_work = "github.com";
          inherit hostname;
          primarySSHKey = "~/.ssh/id_personal.pub";
        };
      }
    ];
    specialArgs = commonArgs // {
      inherit hostname;
    };
  };
}

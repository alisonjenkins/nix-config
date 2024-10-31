{ pkgs
, outputs
, inputs
, system
, username
, hostname
, ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      (pkgs.python3.withPackages (ps: with ps; [ boto3 pyyaml requests ]))
      aws-vault
      awscli2
      bacon
      bat
      cacert
      cachix
      cargo-lambda
      cargo-machete
      cargo-make
      cargo-tarpaulin
      cargo-watch
      comma
      cowsay
      direnv
      diskus
      dive
      docker-credential-helpers
      dua
      fd
      figlet
      fluxcd
      fzf
      gh
      gitui
      glow
      gnupg
      go
      goreleaser
      gradle
      htop
      inputs.ali-neovim.packages.${system}.nvim
      ipcalc
      isort
      jdk11
      jq
      just
      kind
      kubecm
      kubectx
      kubernetes-helm
      libffi
      libiconv
      lolcat
      luajitPackages.lpeg
      nodejs
      nushell
      openssl
      parallel
      pcre2
      pinentry_mac
      pkg-config
      pwgen
      qview
      ripgrep
      ruff-lsp
      rust-bin.stable.latest.default
      selene
      skopeo
      ssm-session-manager-plugin
      stable.azure-cli
      stable.gimme-aws-creds
      statix
      tealdeer
      tektoncd-cli
      tig
      tigervnc
      tilt
      tmux
      typst
      typst-live
      watch
      watchexec
      wget
      yazi
      zk
      zoxide
    ];

    variables = {
      JAVA_HOME = ''${pkgs.jdk}'';
      PATH = ''${pkgs.jdk}/bin:$PATH'';
      ZK_NOTEBOOK_DIR = "$HOME/git/zettelkasten";
    };
  };

  fonts = {
    packages = with pkgs; [
      (nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; })
    ];
  };

  homebrew = {
    enable = true;

    brews = [
      "choose-gui"
      "openconnect"
    ];

    # https://medium.com/rahasak/switching-from-docker-desktop-to-podman-on-macos-m1-m2-arm64-cpu-7752c02453ec
    casks = [
      "1password"
      "aerospace"
      "alacritty"
      "alfred"
      "amethyst"
      "audacity"
      "cyberduck"
      "discord"
      "docker"
      "drawio"
      "element"
      "firefox"
      "flameshot"
      "freeplane"
      "gephi"
      "gimp"
      "github"
      "hammerspoon"
      "inkscape"
      "karabiner-elements"
      "keybase"
      "microsoft-auto-update"
      "microsoft-outlook"
      "microsoft-teams"
      "obs"
      "obsidian"
      "rectangle"
      "slack"
      "soundsource"
      "utm"
      "yubico-authenticator"
      "zoom"
      # "podman-desktop"
    ];

    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
      upgrade = true;
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
    package = pkgs.nix;

    channel = {
      enable = true;
    };

    gc = {
      automatic = true;
    };

    # run: "nix run 'nixpkgs#darwin.linux-builder'" before enabling
    linux-builder = {
      enable = true;
      ephemeral = false;
      maxJobs = 4;
      package = pkgs.darwin.linux-builder;

      config = {
        virtualisation = {
          darwin-builder = {
            diskSize = 40 * 1024;
            memorySize = 8 * 1024;
          };
          cores = 6;
        };
      };
    };

    # optimise = {
    #   enable = true;
    # };

    settings = {
      experimental-features = "nix-command flakes";
    };
  };

  programs = {
    zsh.enable = true;
  };

  # security = {
  #   pam.enableSudoTouchIdAuth = true;
  # };

  services = {
    nix-daemon.enable = true;
    # karabiner-elements.enable = true;
  };

  system = {
    stateVersion = 4;

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

  nixpkgs = {
    config = { allowUnfree = true; };
    hostPlatform = system;

    overlays = [
      inputs.nur.overlay
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
    ];
  };

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };
}

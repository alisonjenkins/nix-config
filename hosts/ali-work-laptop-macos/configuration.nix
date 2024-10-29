{ pkgs
, inputs
, outputs
, system
, ...
}:
let
  username = "ajenkins";
  hostname = "ali-work-laptop-macos";
in
{
  environment = {
    systemPackages = with pkgs; [
      # azure-cli
      # tektoncd-cli
      (pkgs.python3.withPackages (ps: with ps; [ boto3 pyyaml requests ]))
      alacritty
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
      chezmoi
      comma
      cowsay
      darwin.apple_sdk.frameworks.Security
      direnv
      diskus
      dive
      docker-credential-helpers
      dua
      eza
      fd
      figlet
      fluxcd
      fzf
      gh
      gimme-aws-creds
      gitui
      glow
      gnupg
      go
      goreleaser
      gradle
      htop
      inputs.ali-neovim.packages.${system}.nvim
      inputs.ecrrepos.packages.${system}.default
      inputs.maven.legacyPackages.${system}.maven
      ipcalc
      isort
      jdk11
      jq
      just
      kind
      kitty
      kubecm
      kubectx
      kubernetes-helm
      libffi
      libiconv
      lolcat
      luajitPackages.lpeg
      mmtc
      ncdu_1
      nixfmt
      nodejs
      nushell
      openssl
      parallel
      pcre2
      pinentry_mac
      pkg-config
      pwgen
      python311Packages.python-lsp-server
      qview
      ripgrep
      ruff-lsp
      rust-bin.stable.default
      selene
      skopeo
      ssm-session-manager-plugin
      statix
      tealdeer
      tig
      tigervnc
      tilt
      tmux
      typst
      typst-live
      watch
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
    fontDir.enable = true;
    fonts = with pkgs; [
      (nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; })
    ];
  };

  homebrew = {
    enable = true;

    brews = [
      "choose-gui"
      "zathura"
      "zathura-pdf-mupdf"
    ];

    # https://medium.com/rahasak/switching-from-docker-desktop-to-podman-on-macos-m1-m2-arm64-cpu-7752c02453ec
    casks = [
      "1password"
      "alacritty"
      "amethyst"
      "audacity"
      "cyberduck"
      "discord"
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
      "microsoft-teams"
      "obs"
      "obsidian"
      "podman-desktop"
      "rectangle"
      "slack"
      "soundsource"
      "utm"
      "yubico-authenticator"
      "zoom"
      # "alfred"
      # "docker"
    ];

    masApps = {
      "Reeder" = 1529448980;
      "Things" = 904280696;
      "Timery" = 1425368544;
    };

    onActivation = {
      autoUpdate = true;
      cleanup = false;
      upgrade = true;
    };
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

    optimise = {
      enable = true;
    };

    settings = {
      experimental-features = "nix-command flakes";
    };
  };

  programs = {
    zsh.enable = true;
  };

  security = {
    pam.enableSudoTouchIdAuth = true;
  };

  services = {
    nix-daemon.enable = true;
    karabiner-elements.enable = true;
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

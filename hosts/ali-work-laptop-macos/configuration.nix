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
      # cargo-lambda
      # gradle
      # stable.azure-cli
      (pkgs.python3.withPackages (ps: with ps; [ boto3 pyyaml requests ]))
      aws-sam-cli
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
      colima
      comma
      cowsay
      unstable.delve
      direnv
      diskus
      dive
      docker
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
      graphviz
      htop
      hurl
      inputs.ali-neovim.packages.${system}.nvim
      inputs.eks-creds.packages.${system}.eks-creds
      ipcalc
      isort
      jdk11
      jq
      json2hcl
      just
      kind
      kubecm
      kubectl
      kubectx
      kubernetes-helm
      lazydocker
      libffi
      libiconv
      lolcat
      luajitPackages.lpeg
      mitmproxy2swagger
      mustache-go
      nix-fast-build
      nodejs
      nushell
      openssl
      parallel
      pcre2
      pgcli
      pinentry_mac
      pkg-config
      pwgen
      qview
      ripgrep
      rlwrap
      ruff-lsp
      rust-bin.stable.latest.default
      selene
      skopeo
      ssm-session-manager-plugin
      statix
      tealdeer
      tektoncd-cli
      terragrunt
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
      "lima"
      "openconnect"
    ];

    # https://medium.com/rahasak/switching-from-docker-desktop-to-podman-on-macos-m1-m2-arm64-cpu-7752c02453ec
    casks = [
      "1password"
      "1password-cli"
      "aerospace"
      "alacritty"
      "alfred"
      "amethyst"
      "apache-directory-studio"
      "audacity"
      "cyberduck"
      "dbeaver-community"
      "discord"
      "drawio"
      "element"
      "firefox"
      "flameshot"
      "freeplane"
      "gephi"
      "gimp"
      "github"
      "google-chrome"
      "hammerspoon"
      "inkscape"
      "karabiner-elements"
      "keybase"
      "microsoft-auto-update"
      "microsoft-outlook"
      "microsoft-teams"
      "mitmproxy"
      "neovide"
      "obs"
      "obsidian"
      "ollama"
      "rectangle"
      "rio"
      "slack"
      "soundsource"
      "todoist"
      "uhk-agent"
      "utm"
      "yed"
      "yubico-authenticator"
      "zoom"
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
    distributedBuilds = true;
    package = pkgs.nixVersions.stable;

    channel = {
      enable = true;
    };

    gc = {
      automatic = true;
    };

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

    # optimise = {
    #   enable = true;
    # };

    settings = {
      builders = "ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 11 - - - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";
      builders-use-substitutes = true;
      experimental-features = "nix-command flakes";
      extra-trusted-users = "${username}";
      extra-platforms = "x86_64-linux";
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
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
  };

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };
}

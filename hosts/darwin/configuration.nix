{ inputs, specialArgs, system, fenix, lib, pkgs, config, modulesPath, options,
}: {
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  nixpkgs.overlays = [ fenix.overlays.default ];

  environment.systemPackages = with pkgs;
    [
      # azure-cli
      (pkgs.python3.withPackages (ps: with ps; [ requests boto3 pyyaml ]))
      alacritty
      aws-vault
      awscli2
      bacon
      bat
      cacert
      cachix
      cargo-lambda
      cargo-machete
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
      eza
      fd
      fenix.packages.${system}.complete.toolchain
      fenix.packages.${system}.targets.aarch64-apple-darwin.latest.rust-std
      fenix.packages.${system}.targets.aarch64-unknown-linux-gnu.latest.rust-std
      fenix.packages.${system}.targets.wasm32-unknown-unknown.latest.rust-std
      fenix.packages.${system}.targets.x86_64-unknown-linux-gnu.latest.rust-std
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
      ipcalc
      isort
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
      maven
      mcfly
      mmtc
      ncdu_1
      nixfmt
      nnn
      nodejs
      nushellFull
      openssl
      parallel
      pcre2
      pinentry_mac
      pkg-config
      pwgen
      python311Packages.python-lsp-server
      ripgrep
      rnix-lsp
      ruff-lsp
      selene
      skopeo
      ssm-session-manager-plugin
      starship
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
      wget
      zk
      zoxide
    ] ++ [
      inputs.attic.packages.${system}.attic-client
      inputs.nixpkgs_stable.legacyPackages.${system}.buildah
      inputs.nixpkgs_stable.legacyPackages.${system}.k9s
      inputs.nixpkgs_unstable.legacyPackages.${system}.neovide
    ];
  environment.variables = { ZK_NOTEBOOK_DIR = "$HOME/git/zettelkasten"; };

  homebrew = {
    enable = true;
    brewPrefix = "$HOME/.homebrew/bin";
    brews = [ "choose-gui" ];
    casks = [
      "alfred"
      "docker"
      "drawio"
      "firefox"
      "flameshot"
      "font-hack-nerd-font"
      "freemind"
    ];
  };

  fonts = {
    fontDir.enable = true;
    fonts = with pkgs; [
      recursive
      (nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; })
      hack-font
      nerdfonts
    ];
  };

  security.pam.enableSudoTouchIdAuth = true;

  services = {
    nix-daemon.enable = true;
    sketchybar.enable = false;
    skhd = {
      enable = false;
      skhdConfig = builtins.readFile ./skhdrc;
    };
    yabai = {
      enable = false;
      enableScriptingAddition = true;
      package = pkgs.yabai;
      config = {
        focus_follows_mouse = "autoraise";
        mouse_follows_focus = "off";
        window_placement = "second_child";
        window_opacity = "off";
        window_opacity_duration = "0.0";
        window_border = "on";
        window_border_placement = "inset";
        window_border_width = 2;
        window_border_radius = 3;
        active_window_border_topmost = "off";
        window_topmost = "on";
        window_shadow = "float";
        active_window_border_color = "0xff5c7e81";
        normal_window_border_color = "0xff505050";
        insert_window_border_color = "0xffd75f5f";
        active_window_opacity = "1.0";
        normal_window_opacity = "1.0";
        split_ratio = "0.50";
        auto_balance = "on";
        mouse_modifier = "fn";
        mouse_action1 = "move";
        mouse_action2 = "resize";
        layout = "bsp";
        top_padding = 36;
        bottom_padding = 10;
        left_padding = 10;
        right_padding = 10;
        window_gap = 10;
      };
    };
  };

  nix = {
    # buildMachines = [{
    #   hostName = "nix-docker";
    #   systems = [ "x86_64-linux" ];
    # }];
    linux-builder = {
      enable = true;
      ephemeral = true;
      maxJobs = 4;
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
    distributedBuilds = true;
    package = pkgs.nixUnstable;
    extraOptions = ''
      keep-derivations = true
      keep-outputs = true
    '';
    settings = {
      auto-optimise-store = pkgs.stdenv.isLinux;
      cores = 10;
      experimental-features = "nix-command flakes auto-allocate-uids";
      extra-experimental-features = "repl-flake";
      extra-nix-path = "nixpkgs=flake:nixpkgs";
      max-jobs = "auto";
      require-sigs = true;
      sandbox = true;
      sandbox-fallback = false;
      trusted-users = [ "root" specialArgs.username "@admin" "@staff" ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://nixpkgs-cross-overlay.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-cross-overlay.cachix.org-1:TjKExGN4ys960TlsGqNOI/NBdoz2Jdr2ow1VybWV5JM="
      ];
    };
  };

  nixpkgs = {
    config = { allowUnfree = true; };
    hostPlatform = system;
  };

  programs.zsh.enable = true; # default shell on catalina

  # Set Git commit hash for darwin-version.
  system.configurationRevision =
    inputs.darwin.lib.darwinSystem.rev or inputs.darwin.lib.darwinSystem.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}

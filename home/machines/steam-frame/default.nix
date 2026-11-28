# Valve Steam Frame (SteamOS, aarch64-linux), standalone home-manager.
#
# Exported as homeModules.steam-frame-config and used by
# homeConfigurations.steamos (flake-modules/hosts/home-only). Unlike the
# deck/ali configs it does not import home-linux: that pulls the whole niri
# desktop, stylix and x86-only GUI apps, none of which belong on the
# headset. It takes the terminal programs that make SSHing into ali-desktop
# pleasant, plus lhns/steam-frame-nix for the Frame's own quirks.
#
# First install, rebuilds and the ali-desktop key step:
# README.md next to this file.
{ config, lib, pkgs, ... }:
let
  # The Steam (outer) session's runtime dir. Konsole usually runs in the
  # nested Plasma desktop, whose XDG_RUNTIME_DIR is a different, private
  # one, so anything that has to be shared (the SSH agent socket) is named
  # by this absolute path instead.
  outerRuntimeDir = config.steamFrame.session.runtimeDir;
  # Both shells point at the agent in the Steam session's runtime dir; the
  # agent module's default is $XDG_RUNTIME_DIR-relative, which is the wrong
  # (private) dir in the nested desktop. A forwarded agent (SSH into the
  # Frame with -A) is left alone.
  sshAuthSockInit = ''
    if [ -z "''${SSH_CONNECTION:-}" ]; then
      export SSH_AUTH_SOCK="${outerRuntimeDir}/ssh-agent"
    fi
  '';
in
{
  imports = [
    ../../programs/bat
    ../../programs/direnv
    ../../programs/fzf
    ../../programs/gh
    ../../programs/git
    ../../programs/lsd
    ../../programs/neovim
    ../../programs/nix-index
    ../../programs/ssh
    ../../programs/tmux
    ../../programs/zoxide
    ../../programs/zsh
  ];

  home = {
    # Home Manager release this config was first written for; never bump.
    stateVersion = "26.05";
    sessionVariables.EDITOR = "nvim";
    packages = with pkgs; [
      btop
      curl
      fd
      jq
      just
      ripgrep
      wget
    ];
  };

  # Same as the deck: HM tracks a release branch, nixpkgs may lag it.
  home.enableNixpkgsReleaseCheck = false;

  targets.genericLinux = {
    enable = true;
    # No GPU drivers for Nix-built GUI apps: their setup writes to /etc as
    # root, and nothing here needs them (steam-frame-nix's template default).
    gpu.enable = false;
  };

  programs.home-manager.enable = true;
  news.display = "silent";

  nix = {
    package = pkgs.nix;
    settings.experimental-features = "nix-command flakes";
    # Periodic GC via a systemd user timer (see ali-desktop-arch-config for
    # the multi-user-daemon caveat). The Frame's storage is shared with
    # games, so keep fewer generations than the desktops do.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # SteamOS's login shell is bash and /etc/shells is on the read-only root,
  # so chsh to a Nix zsh is out. Instead an interactive bash (Konsole, an
  # SSH login) hands over to zsh. Non-interactive bash (Steam's own
  # scripts, `ssh frame cmd`) is untouched.
  programs.bash = {
    enable = true;
    # mkAfter: last in .bashrc, after nix.sh and hm-session-vars.sh.
    initExtra = lib.mkAfter (sshAuthSockInit + ''
      if [[ $- == *i* && -z ''${ZSH_VERSION:-} && -z ''${NO_ZSH:-} && $TERM != dumb ]]; then
        exec ${config.programs.zsh.package}/bin/zsh -l
      fi
    '');
  };

  # gpg-agent comes from home-common on other Linux hosts; nothing here
  # signs with GPG, and git signing is off (gitGPGSigningKey = "").
  services.ssh-agent.enable = true;
  # .zshenv runs this after hm-session-vars.sh, so it wins over the agent
  # module's default (see sshAuthSockInit; bash gets it in initExtra above).
  programs.zsh.envExtra = sshAuthSockInit;

  steamFrame = {
    # Started in the Steam session's user manager after every switch (HM
    # itself can't reach it from the nested desktop).
    session.services.start = [ "ssh-agent.service" ];

    keyboard = {
      layout = "gb";
      vr = {
        # Esc/Ctrl/Alt, arrows and real chords on the VR keyboard: needed
        # for nvim and tmux over SSH without a physical keyboard.
        extraKeys = {
          enable = true;
          escInTopRow = true;
        };
        enable = true;
        functionKeys.enable = true;
      };
    };

    # One clipboard for the Steam session and the nested desktop (builds
    # from source on the first switch).
    clipboardSync.enable = true;

    launcherMenu = {
      sort = true;
      pinDesktop = "bottom";
      closeOnLaunch = true;
      launchDebounceSeconds = 10;
      # Konsole and KDE System Settings without Developer Mode.
      showAllApps = true;
      hiddenApps = [ "lxterminal" "cmake-gui" "firewall-config" "renderdoc" ];
    };

    dashboard = {
      windows = {
        maxScale = 4.0;
        distance.world.max = 10.0;
        distance.theater.max = 12.0;
      };
      steamCloseButton.enable = true;
      windowCurvature.enable = true;
      frameControls.enable = true;
    };

    screenshots.enable = true;

    # Opt in when wanted:
    # firefox = { enable = true; disableAv1 = true; };  # needs the Firefox Flatpak
    # docker.enable = true;                              # rootless Docker
    # pet.enable = true;                                 # ~0.5 GB of baked models
    # dashboard.passthroughToggle.enable = true;         # colour needs an Arcturus RGB camera
  };
}

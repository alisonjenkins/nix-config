{pkgs, ...}: let
  # plugins-zsh-config = builtins.readFile ./plugins.zsh;
  # plugins-zsh-config-built = pkgs.writeScriptBin "plugins-zsh-config" ''
  #   # Configure zinit
  #   PLUGDIR=~/.config/zsh/plugins
  #   mkdir -p ~/.local/share/zinit
  #   declare -A ZINIT
  #   ZINIT[BIN_DIR]=~/.local/share/zinit/bin
  #   ZINIT[HOME_DIR]=~/.local/share/zinit
  #   source ~/.config/zsh/plugins/zinit/zinit.zsh
  #
  #   export _ZL_MATCH_MODE=1
  #
  #   # Load sensitive envvars
  #   if [[ -e ~/git/secret-envvars ]]; then
  #     eval $(~/git/secret-envvars/target/release/get-secrets)
  #   fi
  #
  #   # Plugins
  #   zinit light "$PLUGDIR/gitstatus"
  #   zinit light "$PLUGDIR/powerlevel10k"
  #   zinit light "$PLUGDIR/zsh-vi-mode"
  #
  #   PLUGINS=(
  #     "aws-plugin"
  #     "direnv"
  #     "exercism"
  #     "fzf"
  #     "fzf-tab"
  #     "kube-aliases"
  #     "omz-fluxcd-plugin"
  #     "tipz"
  #     "zoxide"
  #     "zsh-autosuggestions"
  #     "zsh-hints"
  #     "zsh-terraform"
  #   )
  #
  #   for PLUGIN in "''${PLUGINS[@]}"; do
  #     zinit ice wait"2" lucid
  #     zinit load "$PLUGDIR/$PLUGIN"
  #   done
  #
  #   autoload -Uz _zinit
  #   (( ''${+_comps} )) && _comps[zinit]=_zinit
  # '';
in {
  programs = {
    zsh = {
      autocd = true;
      defaultKeymap = "viins";
      dotDir = ".config/zsh";
      enable = true;
      initExtraFirst = builtins.readFile ./zshrc-first.zsh;
      # initExtraBeforeCompInit = builtins.readFile ./zshrc.sh;

      autosuggestion = {
        enable = true;
      };

      history = {
        size = 999999;
        save = 999999;
        path = "$HOME/.local/share/zsh/history";
        extended = true;
      };

      plugins = [
        {
          name = "aws-plugin";
          file = "plugins/aws/aws.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "ohmyzsh";
            repo = "ohmyzsh";
            rev = "40ff950fcd081078a8cd3de0eaab784f85c681d5";
            sha256 = "EJ/QGmfgav0DVQFSwT+1FjOwl0S28wvJAghxzVAeJbs=";
          };
        }
        {
          name = "direnv";
          file = "plugins/direnv/direnv.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "ohmyzsh";
            repo = "ohmyzsh";
            rev = "40ff950fcd081078a8cd3de0eaab784f85c681d5";
            sha256 = "EJ/QGmfgav0DVQFSwT+1FjOwl0S28wvJAghxzVAeJbs=";
          };
        }
        {
          name = "exercism";
          src = pkgs.fetchFromGitHub {
            owner = "fabiokiatkowski";
            repo = "exercism.plugin.zsh";
            rev = "37f15229070a5f5073eb0fddc9fc86efa4d56cbc";
            sha256 = "/h7ZkPnep1aq9oTEh3mgHZ8OiC01tZ0Ktq1zhvQ098Y=";
          };
        }
        {
          name = "fzf";
          file = "plugins/fzf/fzf.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "ohmyzsh";
            repo = "ohmyzsh";
            rev = "40ff950fcd081078a8cd3de0eaab784f85c681d5";
            sha256 = "EJ/QGmfgav0DVQFSwT+1FjOwl0S28wvJAghxzVAeJbs=";
          };
        }
        {
          name = "fzf-tab";
          src = pkgs.fetchFromGitHub {
            owner = "Aloxaf";
            repo = "fzf-tab";
            rev = "f045ed050dbdd27a95feea187c41f75336b2480a";
            sha256 = "gvZp8P3quOtcy1Xtt1LAW1cfZ/zCtnAmnWqcwrKel6w=";
          };
        }
        {
          name = "gitstatus";
          src = pkgs.fetchFromGitHub {
            owner = "romkatv";
            repo = "gitstatus";
            rev = "215063d4703b944f66cc7cc92543205586a35485";
            sha256 = "3prHeI7PoNq4tzPQ+vzNLt+7EytNJzRcTqOnZ+da4EU=";
          };
        }
        {
          name = "kube-aliases";
          src = pkgs.fetchFromGitHub {
            owner = "alisonjenkins";
            repo = "kube-aliases";
            rev = "a1964cd720d93b0cde3a6ed848e9be54e10c6ccf";
            sha256 = "S60HdgCXjsjX2L1k3PmFEfNb64cdM7luXSBA7CvWyCM=";
          };
        }
        {
          name = "omz-fluxcd-plugin";
          src = pkgs.fetchFromGitHub {
            owner = "l-umaca";
            repo = "omz-fluxcd-plugin";
            rev = "master";
            sha256 = "Y+65EmVqCx9Bmnpy/TCZutYOTSY/kLVIN6mwkXdQd8c=";
          };
        }
        {
          name = "powerlevel10k";
          file = "powerlevel10k.zsh-theme";
          src = pkgs.fetchFromGitHub {
            owner = "romkatv";
            repo = "powerlevel10k";
            rev = "b973805f019cb9a4ecb1ccdf8879d89eb2b1b111";
            sha256 = "IrKn6pWfQDbC4334JaNZ9/FFNfyse9ZD8j1Or1w7bMk=";
          };
        }
        {
          name = "tipz";
          src = pkgs.fetchFromGitHub {
            owner = "molovo";
            repo = "tipz";
            rev = "594eab4642cc6dcfe063ecd51d76478bd84e2878";
            sha256 = "oFZJwHYDfK4f53lhcZg6PCw2AgHxFC0CRiqiinKZz8k=";
          };
        }
        {
          name = "zinit";
          src = pkgs.fetchFromGitHub {
            owner = "zdharma-continuum";
            repo = "zinit";
            rev = "6511ca7fe319feeeda8678449512da162d957740";
            sha256 = "x3YMcS+G7QVVfQRMc2cfIKsCAwtF7hIlCmFC+2Exm3Y=";
          };
        }
        {
          name = "zoxide";
          src = pkgs.fetchFromGitHub {
            owner = "ajeetdsouza";
            repo = "zoxide";
            rev = "f537a4e6d2f8c2eb84c63f79e290a6d1b16eeb71";
            sha256 = "O3ooElNtSorSsWkymmEim1iWKtHqTHa312EcD4uzupQ=";
          };
        }
        {
          name = "zsh-hints";
          src = pkgs.fetchFromGitHub {
            owner = "joepvd";
            repo = "zsh-hints";
            rev = "3874e279fece8817d3940e5b93b40960214ce1a2";
            sha256 = "i/dGAx7HF1DQuAzUNdpjaf53nQPeSDBX/mpMcG+9+fQ=";
          };
        }
        {
          name = "zsh-terraform";
          src = pkgs.fetchFromGitHub {
            owner = "macunha1";
            repo = "zsh-terraform";
            rev = "fd1471d3757f8ed13f56c4426f88616111de2a87";
            sha256 = "83nXtvfYjgY/3+g5zG7rKagSOzRzgc72+a0rcV4v/Ao=";
          };
        }
        {
          name = "zsh-vi-mode";
          src = pkgs.fetchFromGitHub {
            owner = "jeffreytse";
            repo = "zsh-vi-mode";
            rev = "ea1f58ab9b1f3eac50e2cde3e3bc612049ef683b";
            sha256 = "xbchXJTFWeABTwq6h4KWLh+EvydDrDzcY9AQVK65RS8=";
          };
        }
      ];
    };
  };

  # home.packages = [
  #   plugins-zsh-config-built
  # ];

  home.file = {
    ".local/share/zsh/.keep".text = "";
    ".config/zsh/.p10k.zsh".text = builtins.readFile ./p10k.zsh;
    ".config/zshrc.d" = {
      source = ./zshrc.d;
      recursive = true;
    };
    # ".config/zshrc.d/plugins.zsh".text = builtins.readFile "${plugins-zsh-config-built}/bin/plugins-zsh-config";
  };
}

{ pkgs
, lib
, ...
}: {
  home.packages = [
    pkgs.exercism
    pkgs.fzf
  ];

  programs = {
    zsh = {
      autocd = true;
      defaultKeymap = "viins";
      dotDir = ".config/zsh";
      enable = true;
      initExtraFirst = builtins.readFile ./zshrc-first.zsh;
      initExtraBeforeCompInit = lib.strings.concatStringsSep "\n" [
        (builtins.readFile ./zshrc.d/zsh_settings.zsh)
        (builtins.readFile ./zshrc.d/environment_vars.zsh)
      ];

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
          name = "exercism";
          file = "exercism.plugin.zsh";
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
          file = "fzf-tab.plugin.zsh";
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
          file = "kube-aliases.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "alisonjenkins";
            repo = "kube-aliases";
            rev = "a1964cd720d93b0cde3a6ed848e9be54e10c6ccf";
            sha256 = "S60HdgCXjsjX2L1k3PmFEfNb64cdM7luXSBA7CvWyCM=";
          };
        }
        {
          name = "omz-fluxcd-plugin";
          file = "fluxcd.plugin.zsh";
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
          file = "tipz.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "molovo";
            repo = "tipz";
            rev = "594eab4642cc6dcfe063ecd51d76478bd84e2878";
            sha256 = "oFZJwHYDfK4f53lhcZg6PCw2AgHxFC0CRiqiinKZz8k=";
          };
        }
        {
          name = "zsh-terraform";
          file = "terraform.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "macunha1";
            repo = "zsh-terraform";
            rev = "fd1471d3757f8ed13f56c4426f88616111de2a87";
            sha256 = "83nXtvfYjgY/3+g5zG7rKagSOzRzgc72+a0rcV4v/Ao=";
          };
        }
        {
          name = "zsh-vi-mode";
          src = pkgs.zsh-vi-mode;
          file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
        }
      ];
    };
  };

  home.file = {
    ".local/share/zsh/.keep".text = "";
    ".config/zsh/.p10k.zsh".text = builtins.readFile ./p10k.zsh;
  };
}

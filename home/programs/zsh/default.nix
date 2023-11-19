{ config, pkgs, ... }:

{
  programs = {
    zsh = {
      autocd = true;
      defaultKeymap = "viins";
      dotDir = ".config/zsh";
      enable = true;
      enableAutosuggestions = true;
      initExtraFirst = builtins.readFile ./zshrc-first.zsh;
      initExtraBeforeCompInit = builtins.readFile ./zshrc.sh;

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
            rev = "master";
            sha256 = "D6P8jferap3yqQvs2zpQHvbgGf0jxOlBPieOwyts3Qs=";
          };
        }
        {
          name = "direnv";
          file = "plugins/direnv/direnv.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "ohmyzsh";
            repo = "ohmyzsh";
            rev = "master";
            sha256 = "D6P8jferap3yqQvs2zpQHvbgGf0jxOlBPieOwyts3Qs=";
          };
        }
        {
          name = "evalcache";
          src = pkgs.fetchFromGitHub {
            owner = "mroth";
            repo = "evalcache";
            rev = "master";
            sha256 = "GAjsTQJs9JdBEf9LGurme3zqXN//kVUM2YeBo0sCR2c=";
          };
        }
        {
          name = "exercism";
          src = pkgs.fetchFromGitHub {
            owner = "fabiokiatkowski";
            repo = "exercism.plugin.zsh";
            rev = "master";
            sha256 = "/h7ZkPnep1aq9oTEh3mgHZ8OiC01tZ0Ktq1zhvQ098Y=";
          };
        }
        {
          name = "fzf";
          file = "plugins/fzf/fzf.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "ohmyzsh";
            repo = "ohmyzsh";
            rev = "master";
            sha256 = "D6P8jferap3yqQvs2zpQHvbgGf0jxOlBPieOwyts3Qs=";
          };
        }
        {
          name = "fzf-tab";
          src = pkgs.fetchFromGitHub {
            owner = "Aloxaf";
            repo = "fzf-tab";
            rev = "master";
            sha256 = "gvZp8P3quOtcy1Xtt1LAW1cfZ/zCtnAmnWqcwrKel6w=";
          };
        }
        {
          name = "gitstatus";
          src = pkgs.fetchFromGitHub {
            owner = "romkatv";
            repo = "gitstatus";
            rev = "master";
            sha256 = "O0ZJQgsGfM2yB1HEm1acuWPsDzmmno0QlsdpIP/wghQ=";
          };
        }
        {
          name = "kube-aliases";
          src = pkgs.fetchFromGitHub {
            owner = "alisonjenkins";
            repo = "kube-aliases";
            rev = "master";
            sha256 = "S60HdgCXjsjX2L1k3PmFEfNb64cdM7luXSBA7CvWyCM=";
          };
        }
        # {
        #   name = "mcfly";
        #   src = pkgs.fetchFromGitHub {
        #     owner = "cantino";
        #     repo = "mcfly";
        #     rev = "master";
        #     sha256 = "SpWF4T51g5cHM09FDNKz4cid+LdawtuF5GCwfNWNugk=";
        #   };
        # }
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
            rev = "master";
            sha256 = "3fvqWS/Zm3GLFqo36s5tPBfVX3SOpUyxjHDatMhD/u0=";
          };
        }
        {
          name = "tipz";
          src = pkgs.fetchFromGitHub {
            owner = "molovo";
            repo = "tipz";
            rev = "master";
            sha256 = "oFZJwHYDfK4f53lhcZg6PCw2AgHxFC0CRiqiinKZz8k=";
          };
        }
        {
          name = "zinit";
          src = pkgs.fetchFromGitHub {
            owner = "zdharma-continuum";
            repo = "zinit";
            rev = "master";
            sha256 = "WVolKlLL5FoD6sXBIbNOZtbbMdIcjbvzh5E2ad/74dI=";
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
            rev = "master";
            sha256 = "i/dGAx7HF1DQuAzUNdpjaf53nQPeSDBX/mpMcG+9+fQ=";
          };
        }
        {
          name = "zsh-terraform";
          src = pkgs.fetchFromGitHub {
            owner = "macunha1";
            repo = "zsh-terraform";
            rev = "master";
            sha256 = "65UWgMeW33fl2XJY1gkwZeGdzo+b1G6yI5bzXk17aD4=";
          };
        }
        {
          name = "zsh-vi-mode";
          src = pkgs.fetchFromGitHub {
            owner = "jeffreytse";
            repo = "zsh-vi-mode";
            rev = "master";
            sha256 = "xbchXJTFWeABTwq6h4KWLh+EvydDrDzcY9AQVK65RS8=";
          };
        }
      ];
      # plugins = [
      # ];
    };
  };

  home.file = {
    ".local/share/zsh/.keep".text = "";
    ".config/zsh/p10k.zsh".text = builtins.readFile ./p10k.zsh;
    ".config/zshrc.d" = {
      source = ./zshrc.d;
      recursive = true;
    };
  };
}


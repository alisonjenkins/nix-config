{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./tide.nix
  ];

  # Add completion packages
  home.packages = with pkgs; [
    grc  # Generic colorizer for command output
  ];

  programs = {
    fish = {
      enable = true;

      # Shell integrations
      interactiveShellInit = ''
        # Load Nix profile if it exists
        if test -e $HOME/.nix-profile/etc/profile.d/nix.fish
          source $HOME/.nix-profile/etc/profile.d/nix.fish
        end

        # Ghostty shell integration
        ${if pkgs.stdenv.isDarwin then ''
          if test -f /Applications/Ghostty.app/Contents/Resources/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
            source /Applications/Ghostty.app/Contents/Resources/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
          end
        '' else ""}

        # McFly history search
        if type -q mcfly
          mcfly init fish | source
        end
      '';

      plugins = [
        {
          name = "foreign-env";
          src = pkgs.fetchFromGitHub {
            owner = "oh-my-fish";
            repo = "plugin-foreign-env";
            rev = "7f0cf099ae1e1e4ab38f46350ed6757d54471de7";
            sha256 = "sha256-4+k5rSoxkTtYFh/lEjhRkVYa2S4KEzJ/IJbyJl+rJjQ=";
          };
        }
        {
          name = "autopair";
          src = pkgs.fetchFromGitHub {
            owner = "jorgebucaran";
            repo = "autopair.fish";
            rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
            sha256 = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
          };
        }
        {
          name = "done";
          src = pkgs.fetchFromGitHub {
            owner = "franciscolourenco";
            repo = "done";
            rev = "d6abb267bb3fb7e987a9352bc43dcdb67bac9f06";
            sha256 = "sha256-DMIRKRAVOn7YEnuAtz4hIxrU93ULxNoQhW6juxCoh4o=";
          };
        }
        {
          name = "fish-abbreviation-tips";
          src = pkgs.fetchFromGitHub {
            owner = "gazorby";
            repo = "fish-abbreviation-tips";
            rev = "8ed76a62bb044ba4ad8e3e6832640178880df485";
            sha256 = "sha256-F1t81VliD+v6WEWqj1c1ehFBXzqLyumx5vV46s/FZRU=";
          };
        }
        {
          name = "fzf.fish";
          src = pkgs.fetchFromGitHub {
            owner = "PatrickF1";
            repo = "fzf.fish";
            rev = "8920367cf85eee5218cc25a11e209d46e2591e7a";
            sha256 = "sha256-T8KYLA/r/gOKvAivKRoeqIwE2pINlxFQtZJHpOy9GMM=";
          };
        }
        {
          name = "puffer-fish";
          src = pkgs.fetchFromGitHub {
            owner = "nickeb96";
            repo = "puffer-fish";
            rev = "3cb17caa88270e1bd215d97fbd591155c976f083";
            sha256 = "sha256-NQa12L0zlEz2EJjMDhWUhw5cz/zcFokjuCK5ZofTn+Q=";
          };
        }
        {
          name = "grc";
          src = pkgs.fetchFromGitHub {
            owner = "oh-my-fish";
            repo = "plugin-grc";
            rev = "61de7a8a0d7bda3234f8703d6e07c671992eb079";
            sha256 = "sha256-NQa12L0zlEz2EJjMDhWUhw5cz/zcFokjuCK5ZofTn+Q=";
          };
        }
      ];
    };
  };

  # Copy Fish configuration files
  home.file = {
    ".config/fish/conf.d/environment_vars.fish".source = ./conf.d/environment_vars.fish;
    ".config/fish/conf.d/aliases.fish".source = ./conf.d/aliases.fish;
    ".config/fish/conf.d/fish_settings.fish".source = ./conf.d/fish_settings.fish;
    ".config/fish/conf.d/terraform_completions.fish".source = ./conf.d/terraform_completions.fish;
    ".config/fish/conf.d/carapace.fish".source = ./conf.d/carapace.fish;
    ".config/fish/conf.d/fzf_enhanced.fish".source = ./conf.d/fzf_enhanced.fish;
    ".config/fish/conf.d/abbreviations.fish".source = ./conf.d/abbreviations.fish;
    ".config/fish/functions/n.fish".source = ./functions/n.fish;
    ".config/fish/functions/aws.fish".source = ./functions/aws.fish;
    ".config/fish/functions/terraform.fish".source = ./functions/terraform.fish;
    ".config/fish/functions/kubectl.fish".source = ./functions/kubectl.fish;
    ".config/fish/completions/asp.fish".source = ./completions/asp.fish;
    ".config/fish/completions/asr.fish".source = ./completions/asr.fish;
  };
}

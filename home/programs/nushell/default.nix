{ pkgs
, system
, inputs
, ...
}:
let
  zoxide-config = pkgs.stdenv.mkDerivation {
    name = "nushell-zoxide-config";
    buildInputs = [ pkgs.zoxide ];
    dontUnpack = true;
    buildPhase = ''
      mkdir -p $out
      zoxide init nushell > $out/zoxide.nu
    '';
  };
  starship-config = pkgs.stdenv.mkDerivation {
    name = "nushell-starship-config";
    buildInputs = [ pkgs.starship ];
    dontUnpack = true;
    buildPhase = ''
      mkdir -p $out
      starship init nushell > $out/starship.nu
    '';
  };
in
{
  programs.nushell = {
    enable = true;

    extraConfig = ''
      source ${zoxide-config}/zoxide.nu
      source ${starship-config}/starship.nu
      source ${pkgs.nu_scripts}/share/nu_scripts/custom-completions/git/git-completions.nu
      source ~/.config/nushell/nnn-quitcd.nu
      # source ~/.config/nushell/ssh-agent.nu
      $env.config = {
        edit_mode: vi
        show_banner: false

        hooks: {
            pre_prompt: [{ ||
              if (which direnv | is-empty) {
                return
              }

              direnv export json | from json | default {} | load-env
            }]
        }
      }
    '';

    shellAliases = {
    };

    environmentVariables = {
      SSH_AUTH_SOCK = ''$"($env.XDG_RUNTIME_DIR)/ssh-agent"'';
    };
  };

  home.file = {
    ".config/nushell/nnn-quitcd.nu".text = builtins.readFile ./nnn-quitcd.nu;
    # ".config/nushell/ssh-agent.nu".text = builtins.readFile ./ssh-agent.nu;
  };
}

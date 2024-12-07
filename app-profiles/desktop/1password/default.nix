{ pkgs, username, ... }: {
  programs._1password-gui =
    if pkgs.stdenv.isLinux then {
      enable = true;
      polkitPolicyOwners = [ username ];
    } else {
      enable = false;
    };
  programs._1password.enable = if pkgs.stdenv.isLinux then true else false;
}

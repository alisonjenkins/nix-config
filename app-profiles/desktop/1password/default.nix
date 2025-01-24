{ pkgs, config, ... }: {
  programs._1password-gui =
    if pkgs.stdenv.isLinux then
      let
        op_polkit_owners = builtins.attrNames config.users;
      in
      {
        enable = true;
        polkitPolicyOwners = op_polkit_owners;
      } else {
      enable = false;
    };
  programs._1password.enable = if pkgs.stdenv.isLinux then true else false;
}

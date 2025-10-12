# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{pkgs, ...}: {
  # example = pkgs.callPackage ./example { };
  git-clean = pkgs.callPackage ./git-clean { inherit pkgs; };
  lock-session = pkgs.callPackage ./lock-session { inherit pkgs; };
  nix-flake-template-init = pkgs.callPackage ./nix-flake-template-init {} ;
  suspendScripts = pkgs.callPackage ./suspend-scripts {};
  wallpapers = pkgs.callPackage ./wallpapers {};
}

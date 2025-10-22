# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{pkgs, inputs, ...}: {
  # example = pkgs.callPackage ./example { };
  git-clean = pkgs.callPackage ./git-clean { inherit pkgs; };
  lock-session = pkgs.callPackage ./lock-session { inherit pkgs; };
  nix-flake-template-init = pkgs.callPackage ./nix-flake-template-init {} ;
  stasis = pkgs.callPackage ./stasis { stasisSrc = inputs.stasis; };
  suspendScripts = pkgs.callPackage ./suspend-scripts {};
  wallpapers = pkgs.callPackage ./wallpapers {};
}
